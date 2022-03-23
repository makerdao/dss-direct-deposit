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

import { DssDirectDepositTestGem } from "./DssDirectDepositTestGem.sol";
import "../bases/DssDirectDepositPoolBase.sol";

interface RewardsClaimerLike {
    function claimRewards(address[] memory assets, uint256 amount, address to) external returns (uint256);
}

contract DssDirectDepositTestPool is DssDirectDepositPoolBase {

    RewardsClaimerLike public immutable rewardsClaimer;
    address            public           king; // Who gets the rewards

    // test helper variables
    uint256 supplyAmount;
    uint256 targetSupply;
    bool    isValidTarget;

    constructor(address hub_, address daiJoin_, address pool_, address _rewardsClaimer)
        public
        DssDirectDepositPoolBase(hub_, daiJoin_, pool_)
    {
        rewardsClaimer = RewardsClaimerLike(_rewardsClaimer);
    }

    // --- Admin ---
    function file(bytes32 what, bool data) external auth {
        if (what == "isValidTarget") {
            isValidTarget = data;
        }
    }

    function file(bytes32 what, address data) public override auth {
        require(live == 1, "DssDirectDepositTestPool/no-file-not-live");

        if (what == "king") king = data;
        else super.file(what, data);
    }

    function validTarget() external view override returns (bool) {
        return isValidTarget;
    }

    function calcSupplies(uint256 availableAssets) external view override returns (uint256, uint256) {
        return DssDirectDepositPlanLike(plan).calcSupplies(availableAssets, bar);
    }

    function supply(uint256 amt) external override {
        daiJoin.exit(address(this), amt);
        DssDirectDepositTestGem(share).mint(address(this), amt);
        TokenLike(asset).transfer(share, amt);
        Deposit(msg.sender, address(this), amt, amt);
    }

    function withdraw(uint256 amt) external override {
        DssDirectDepositTestGem(share).burn(address(this), amt);
        TokenLike(asset).transferFrom(share, address(this), amt);
        daiJoin.join(address(this), amt);
        Withdraw(msg.sender, address(this), address(this), amt, amt);
    }

    function collect(address[] memory assets, uint256 amount) external override auth returns (uint256 amt) {
        require(king != address(0), "DssDirectDepositPool/king-not-set");

        amt = rewardsClaimer.claimRewards(assets, amount, king);
    }

    function transferShares(address dst, uint256 amt) external override returns(bool) {
        return TokenLike(share).transfer(dst, amt);
    }

    function assetBalance() external view override returns(uint256) {
        return TokenLike(asset).balanceOf(share);
    }

    function maxWithdraw() external view override returns(uint256) {
        return TokenLike(asset).balanceOf(share);
    }

    function shareBalance() external view override returns(uint256) {
        return TokenLike(share).balanceOf(address(this));
    }

    function convertToShares(uint256 amt) external override returns(uint256) {
        return amt;
    }

    function convertToAssets(uint256 amt) external override returns(uint256) {
        return amt;
    }
}
