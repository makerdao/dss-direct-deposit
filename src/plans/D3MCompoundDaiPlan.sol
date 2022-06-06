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

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//    Methodology for Calculating Target Supply from Target Rate Per Block    //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

// apy to rate per block off-chain conversion info:
//         apy = ((1 + (borrowRatePerBlock / WAD) * blocksPerDay) ^ 365 - 1) * 100
// (0)     borrowRatePerBlock = ((((apy / 100) + 1) ^ (1 / 365) - 1) / blocksPerDay) * WAD
//         ATTOW the formula matches the borrow apy on (https://compound.finance/markets/DAI) using blocksPerDay = 6570
//
// https://github.com/compound-finance/compound-protocol/blob/master/contracts/BaseJumpRateModelV2.sol#L95
//
// util > kink:
//         normalRate = kink * multiplierPerBlock / WAD + baseRatePerBlock;
//         targetInterestRate = normalRate + jumpMultiplierPerBlock * (util - kink) / WAD
//         util * jumpMultiplierPerBlock = (targetInterestRate - normalRate) * WAD + kink * jumpMultiplierPerBlock
// (1)     util = kink + (targetInterestRate - normalRate) * WAD / jumpMultiplierPerBlock
//
// util <= kink:
//         targetInterestRate = util * multiplierPerBlock / WAD + baseRatePerBlock
// (2)     util = (targetInterestRate - baseRatePerBlock) * WAD / multiplierPerBlock
//
// https://github.com/compound-finance/compound-protocol/blob/master/contracts/BaseJumpRateModelV2.sol#L79
//
//         util = borrows * WAD / (cash + borrows - reserves);
// (3)     cash + borrows - reserves = borrows * WAD / util

pragma solidity ^0.8.14;

import "./ID3MPlan.sol";

// https://github.com/compound-finance/compound-protocol/blob/3affca87636eecd901eb43f81a4813186393905d/contracts/CErc20.sol#L14
interface CErc20Like {
    function totalBorrows()           external view returns (uint256);
    function totalReserves()          external view returns (uint256);
    function interestRateModel()      external view returns (address);
    function getCash()                external view returns (uint256);
    function underlying()             external view returns (address);
}

// https://github.com/compound-finance/compound-protocol/blob/3affca87636eecd901eb43f81a4813186393905d/contracts/BaseJumpRateModelV2.sol#L10
interface InterestRateModelLike {
    function baseRatePerBlock()       external view returns (uint256);
    function kink()                   external view returns (uint256);
    function multiplierPerBlock()     external view returns (uint256);
    function jumpMultiplierPerBlock() external view returns (uint256);
}

contract D3MCompoundDaiPlan is ID3MPlan {

    mapping (address => uint256) public wards;
    InterestRateModelLike        public tack;
    uint256                      public barb; // target Interest Rate Per Block [wad] (0)

    CErc20Like public immutable cDai;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);

    constructor(address cDai_) {
        address rateModel_ = CErc20Like(cDai_).interestRateModel();
        require(rateModel_ != address(0), "D3MCompoundDaiPlan/invalid-rateModel");

        cDai = CErc20Like(cDai_);
        tack = InterestRateModelLike(rateModel_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MCompoundDaiPlan/not-authorized");
        _;
    }

    // --- Math ---
    uint256 internal constant WAD = 10 ** 18;
    function _wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * y) / WAD;
    }
    function _wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * WAD) / y;
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

    function file(bytes32 what, uint256 data) external auth {
        if (what == "barb") {
            barb = data;
        } else revert("D3MCompoundDaiPlan/file-unrecognized-param");
        emit File(what, data);
    }
    function file(bytes32 what, address data) external auth {
        if (what == "rateModel") tack = InterestRateModelLike(data); // TODO: change "rateModel" to "tack" once changed on aave plan
        else revert("D3MCompoundDaiPlan/file-unrecognized-param");
        emit File(what, data);
    }

    function getTargetAssets(uint256 currentAssets) external override view returns (uint256) {
        uint256 targetInterestRate = barb;
        if (targetInterestRate == 0) return 0; // De-activated

        uint256 borrows = cDai.totalBorrows();
        uint256 targetTotalPoolSize = _calculateTargetSupply(targetInterestRate, borrows);
        uint256 totalPoolSize = cDai.getCash() + borrows - cDai.totalReserves();

        if (targetTotalPoolSize >= totalPoolSize) {
            // Increase debt (or same)
            return currentAssets + targetTotalPoolSize - totalPoolSize;
        } else {
            // Decrease debt
            uint256 decrease;
            unchecked { decrease = totalPoolSize - targetTotalPoolSize; }
            if (currentAssets >= decrease) {
                unchecked { return currentAssets - decrease; }
            } else {
                return 0;
            }
        }
    }

    function _calculateTargetSupply(uint256 targetInterestRate, uint256 borrows) internal view returns (uint256) {
        uint256 kink                   = tack.kink();
        uint256 multiplierPerBlock     = tack.multiplierPerBlock();
        uint256 baseRatePerBlock       = tack.baseRatePerBlock();
        uint256 jumpMultiplierPerBlock = tack.jumpMultiplierPerBlock();

        uint256 normalRate = _wmul(kink, multiplierPerBlock) + baseRatePerBlock;

        uint256 targetUtil;
        if (targetInterestRate > normalRate) {
            if (jumpMultiplierPerBlock == 0) return 0; // illegal rate, max is normal rate for this case
            targetUtil = kink + _wdiv(targetInterestRate - normalRate, jumpMultiplierPerBlock); // (1)
        } else if (targetInterestRate > baseRatePerBlock) {
            targetUtil = _wdiv(targetInterestRate - baseRatePerBlock, multiplierPerBlock);      // (2)
        } else {
            // if (target == base) => (borrows == 0) => supply does not matter
            // if (target  < base) => illegal rate
            return 0;
        }

        if (targetUtil > WAD) return 0; // illegal rate (unacheivable utilization)

        return _wdiv(borrows, targetUtil);                                                      // (3)
    }

    function active() public view override returns (bool) {
        if (barb == 0) return false;
        return CErc20Like(cDai).interestRateModel() == address(tack);
    }

    function disable() external override {
        require(wards[msg.sender] == 1 || !active(), "D3MCompoundDaiPlan/not-authorized");
        barb = 0;
        emit Disable();
    }
}
