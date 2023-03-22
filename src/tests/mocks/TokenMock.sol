// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
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

pragma solidity ^0.8.14;

contract TokenMock {
    mapping (address => uint256) public wards;

    uint256 public totalSupply;
    uint256 public immutable decimals;
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping(address => uint256)) public allowance;

    event Rely(address indexed usr);
    event Deny(address indexed usr);

    constructor(uint256 decimals_) {
        decimals = decimals_;

        wards[msg.sender] = 1;
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
        require(wards[msg.sender] == 1, "TokenMock/not-authorized");
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
        require(balanceOf[src] >= amt, "TokenMock/insufficient-balance");
        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= amt, "TokenMock/insufficient-allowance");
            allowance[src][msg.sender] = allowance[src][msg.sender] - amt;
        }
        balanceOf[src] -= amt;
        balanceOf[dst] += amt;
        return true;
    }

    function mint(address usr, uint wad) external auth {
        balanceOf[usr] += wad;
        totalSupply    += wad;
    }

    function burn(address usr, uint wad) external {
        require(balanceOf[usr] >= wad, "TokenMock/insufficient-balance");
        if (usr != msg.sender && allowance[usr][msg.sender] != type(uint256).max) {
            require(allowance[usr][msg.sender] >= wad, "TokenMock/insufficient-allowance");
            allowance[usr][msg.sender] -= wad;
        }
        balanceOf[usr] -= wad;
        totalSupply    -= wad;
    }
}
