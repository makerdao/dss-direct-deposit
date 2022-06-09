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

import { D3MTestGem } from "./D3MTestGem.sol";
import "../../pools/ID3MPool.sol";
import { TokenLike, D3mHubLike } from "../interfaces/interfaces.sol";

interface RewardsClaimerLike {
    function claimRewards(address[] memory assets, uint256 amount, address to) external returns (uint256);
}

interface VatLike {
    function hope(address) external;
    function nope(address) external;
}

contract D3MTestPool is ID3MPool {

    mapping (address => uint256) public wards;

    address public hub;

    VatLike            public immutable vat;
    RewardsClaimerLike public immutable rewardsClaimer;
    address            public immutable share; // Token representing a share of the asset pool
    TokenLike          public immutable asset; // Dai
    address            public           king;  // Who gets the rewards

    // test helper variables
    uint256        maxDepositAmount = type(uint256).max;
    bool    public preDebt          = false;
    bool    public postDebt         = false;
    bool    public active_          = true;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Collect(address indexed king, address[] assets, uint256 amt);

    constructor(address hub_, address dai_, address share_, address _rewardsClaimer) {
        asset = TokenLike(dai_);
        share = share_;

        rewardsClaimer = RewardsClaimerLike(_rewardsClaimer);

        hub = hub_;
        vat = VatLike(D3mHubLike(hub_).vat());
        VatLike(D3mHubLike(hub_).vat()).hope(hub_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MTestPool/not-authorized");
        _;
    }

    modifier onlyHub {
        require(msg.sender == hub, "D3MAavePool/only-hub");
        _;
    }

    // --- Testing Admin ---
    function file(bytes32 what, bool data) external auth {
        if (what == "preDebt") preDebt = data;
        else if (what == "postDebt") postDebt = data;
        else if (what == "active_") active_ = data;
        else revert("D3MTestPool/file-unrecognized-param");
    }
    function file(bytes32 what, uint256 data) external auth {
        if (what == "maxDepositAmount") maxDepositAmount = data;
        else revert("D3MTestPool/file-unrecognized-param");
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

    function file(bytes32 what, address data) external auth {
        if (what == "hub") {
            vat.nope(hub);
            hub = data;
            vat.hope(data);
        }
        else if (what == "king") king = data;
        else revert("D3MTestPool/file-unrecognized-param");
    }

    function deposit(uint256 wad) external override onlyHub {
        D3MTestGem(share).mint(address(this), wad);
        TokenLike(asset).transfer(share, wad);
    }

    function withdraw(uint256 wad) external override onlyHub {
        D3MTestGem(share).burn(address(this), wad);
        TokenLike(asset).transferFrom(share, address(msg.sender), wad);
    }

    function transfer(address dst, uint256 wad) public override onlyHub returns (bool) {
        return TokenLike(share).transfer(dst, wad);
    }

    function transferAll(address dst) external override auth returns (bool) {
        return TokenLike(share).transfer(dst, shareBalance());
    }

    function preDebtChange(bytes32 what) external override {
        what;
        preDebt = true;
    }

    function postDebtChange(bytes32 what) external override {
        what;
        postDebt = true;
    }

    function assetBalance() external view override returns (uint256) {
        return convertToAssets(shareBalance());
    }

    function maxDeposit() external view override returns (uint256) {
        return maxDepositAmount;
    }

    function maxWithdraw() external view override returns (uint256) {
        return TokenLike(asset).balanceOf(share);
    }

    function shareBalance() public view returns (uint256) {
        return TokenLike(share).balanceOf(address(this));
    }

    function convertToAssets(uint256 shares) public pure returns (uint256) {
        return shares;
    }

    function active() external view override returns (bool) {
        return active_;
    }

    function redeemable() external view override returns (address) {
        return address(share);
    }

    function collect() external auth returns (uint256 amt) {
        require(king != address(0), "D3MTestPool/king-not-set");

        address[] memory assets = new address[](1);
        assets[0] = address(share);

        amt = rewardsClaimer.claimRewards(assets, type(uint256).max, king);
        emit Collect(king, assets, amt);
    }
}
