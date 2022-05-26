// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021-2022 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.6.12;

interface TokenLike {
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract D3MTestGem {
    mapping (address => uint256) public wards;

    uint256 public totalSupply = 1_000_000 ether;
    uint256 public immutable decimals;
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping(address => uint256)) public allowance;

    event Rely(address indexed usr);
    event Deny(address indexed usr);

    constructor(uint256 decimals_) public {
        balanceOf[msg.sender] = totalSupply;
        decimals = decimals_;

        wards[msg.sender] = 1;
    }

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    // --- Auth ---
    function rely(address usr) external auth {
        wards[usr] = 1;

        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;

        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "DssDirectDepositTestGem/not-authorized");
        _;
    }

    function approve(address who, uint256 amt) external returns (bool) {
        allowance[msg.sender][who] = amt;
        return true;
    }

    function transfer(address dst, uint256 amt) external returns (bool) {
        return transferFrom(msg.sender, dst, amt);
    }

    function transferFrom(address src, address dst, uint256 amt) public returns (bool) {
        require(balanceOf[src] >= amt, "TestGem/insufficient-balance");
        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= amt, "TestGem/insufficient-allowance");
            allowance[src][msg.sender] = sub(allowance[src][msg.sender], amt);
        }
        balanceOf[src] = sub(balanceOf[src], amt);
        balanceOf[dst] = add(balanceOf[dst], amt);
        return true;
    }

    function mint(address usr, uint wad) external auth {
        balanceOf[usr] = add(balanceOf[usr], wad);
        totalSupply    = add(totalSupply, wad);
    }

    function burn(address usr, uint wad) external {
        require(balanceOf[usr] >= wad, "TestGem/insufficient-balance");
        if (usr != msg.sender && allowance[usr][msg.sender] != uint(-1)) {
            require(allowance[usr][msg.sender] >= wad, "TestGem/insufficient-allowance");
            allowance[usr][msg.sender] = sub(allowance[usr][msg.sender], wad);
        }
        balanceOf[usr] = sub(balanceOf[usr], wad);
        totalSupply    = sub(totalSupply, wad);
    }

    function giveAllowance(address token, address dst, uint amt) external auth {
        require(TokenLike(token).approve(dst, amt), "TestGem/give-allowance-failed");
    }
}
