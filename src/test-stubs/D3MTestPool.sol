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

import { D3MTestGem } from "./D3MTestGem.sol";
import "../bases/D3MPoolBase.sol";

interface RewardsClaimerLike {
    function claimRewards(address[] memory assets, uint256 amount, address to) external returns (uint256);
}

contract D3MTestPool is D3MPoolBase {

    RewardsClaimerLike public immutable rewardsClaimer;
    address            public           king; // Who gets the rewards

    // test helper variables
    uint256 supplyAmount;
    uint256 targetSupply;
    bool    isValidTarget;

    event Collect(address indexed king, address[] assets, uint256 amt);

    constructor(address hub_, address daiJoin_, address pool_, address _rewardsClaimer)
        public
        D3MPoolBase(hub_, daiJoin_, pool_)
    {
        rewardsClaimer = RewardsClaimerLike(_rewardsClaimer);
    }

    // --- Testing Admin ---
    function file(bytes32 what, bool data) external auth {
        if (what == "isValidTarget") {
            isValidTarget = data;
        }
    }

    // --- Admin ---
    function file(bytes32 what, address data) public override auth {
        require(live == 1, "D3MTestPool/no-file-not-live");

        if (what == "king") king = data;
        else super.file(what, data);
    }

    function validTarget() external view override returns (bool) {
        return isValidTarget;
    }

    function deposit(uint256 amt) external override {
        D3MTestGem(share).mint(address(this), amt);
        TokenLike(asset).transfer(share, amt);
        Deposit(msg.sender, address(this), amt, amt);
    }

    function withdraw(uint256 amt) external override {
        D3MTestGem(share).burn(address(this), amt);
        TokenLike(asset).transferFrom(share, address(hub), amt);
        Withdraw(msg.sender, address(this), address(this), amt, amt);
    }

    function collect(address[] memory assets, uint256 amount) external auth returns (uint256 amt) {
        require(king != address(0), "D3MPool/king-not-set");

        amt = rewardsClaimer.claimRewards(assets, amount, king);
        emit Collect(king, assets, amt);
    }

    function transferShares(address dst, uint256 amt) external override returns (bool) {
        return TokenLike(share).transfer(dst, amt);
    }

    function assetBalance() external view override returns (uint256) {
        return convertToAssets(shareBalance());
    }

    function maxWithdraw() external view override returns (uint256) {
        return TokenLike(asset).balanceOf(share);
    }

    function shareBalance() public view override returns (uint256) {
        return TokenLike(share).balanceOf(address(this));
    }

    function convertToShares(uint256 amt) external view override returns (uint256) {
        return amt;
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return shares;
    }
}
