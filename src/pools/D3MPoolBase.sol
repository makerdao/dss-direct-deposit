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

pragma solidity 0.6.12;

interface TokenLike {
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface CanLike {
    function hope(address) external;
    function nope(address) external;
}

interface d3mHubLike {
    function vat() external view returns (address);
}

abstract contract D3MPoolBase {
    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "D3MPoolBase/not-authorized");
        _;
    }

    TokenLike   public immutable asset; // Dai
    address     public immutable hub;

    uint256     public           live = 1;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Cage();

    constructor(address hub_, address dai_) internal {
        asset = TokenLike(dai_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        hub = hub_;
        wards[hub_] = 1;
        emit Rely(hub_);
        CanLike(d3mHubLike(hub_).vat()).hope(hub_);
    }

    function validTarget() external view virtual returns (bool);

    function deposit(uint256 amt) external virtual;

    function withdraw(uint256 amt) external virtual;

    function transferShares(address dst, uint256 amt) external virtual returns (bool);

    function accrueIfNeeded() external virtual;

    function assetBalance() external view virtual returns (uint256);

    function shareBalance() external view virtual returns (uint256);

    function maxWithdraw() external view virtual returns (uint256);

    function convertToShares(uint256 amt) external view virtual returns (uint256);

    function recoverTokens(address token, address dst, uint256 amt) external auth returns (bool) {
        return TokenLike(token).transfer(dst, amt);
    }

    function cage() external virtual auth {
        live = 0;
        emit Cage();
    }
}
