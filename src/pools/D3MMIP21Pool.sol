// SPDX-FileCopyrightText: © 2021-2022 Dai Foundation <www.daifoundation.org>
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

pragma solidity ^0.8.14;

import "./ID3MPool.sol";

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

interface D3mHubLike {
    function vat() external view returns (address);
}

contract D3MMIP21Pool is ID3MPool {

    mapping (address => uint256) public wards;
    uint256                      public totalSize;

    TokenLike          public immutable asset; // Dai

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    constructor(address hub_, address dai_, address plan_) {
        asset = TokenLike(dai_);

        CanLike(D3mHubLike(hub_).vat()).hope(hub_);
        asset.approve(plan_, type(uint256).max);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MMIP21Pool/not-authorized");
        _;
    }

    // --- Math ---
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }

    // --- Admin ---
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function hope(address hub) external override auth {
        CanLike(D3mHubLike(hub).vat()).hope(hub);
    }

    function nope(address hub) external override auth {
        CanLike(D3mHubLike(hub).vat()).nope(hub);
    }

    // Does nothing - DAI sits in this contract until it is ready to be pulled by operator
    function deposit(uint256 wad) external override auth {
        totalSize += wad;
    }

    // Send DAI back to hub
    function withdraw(uint256 wad) external override auth {
        totalSize -= wad;
        asset.transfer(msg.sender, wad);
    }

    function transfer(address dst, uint256 wad) external override auth returns (bool) {
        return asset.transfer(dst, wad);
    }

    function transferAll(address dst) external override auth returns (bool) {
        return asset.transfer(dst, asset.balanceOf(address(this)));
    }

    function preDebtChange(bytes32) external override {}

    function postDebtChange(bytes32) external override {}

    // --- Balance of the underlying asset (Dai)
    function assetBalance() public view override returns (uint256) {
        return totalSize;
    }

    function maxDeposit() external pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw() external view override returns (uint256) {
        return _min(asset.balanceOf(address(asset)), assetBalance());
    }

    function active() external pure override returns (bool) {
        return true;
    }

    function redeemable() external view override returns (address) {
        return address(asset);
    }
}
