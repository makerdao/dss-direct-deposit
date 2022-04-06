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

pragma solidity 0.6.12;

import "../bases/D3MPlanBase.sol";

interface CErc20 {
    function totalBorrows()           external view returns (uint256);
    function totalReserves()          external view returns (uint256);
    function interestRateModel()      external view returns (address);
}

interface InterestRateModel {
    function baseRatePerBlock()       external view returns (uint256);
    function multiplierPerBlock()     external view returns (uint256);
    function jumpMultiplierPerBlock() external view returns (uint256);
    function kink()                   external view returns (uint256);
}

contract D3MCompoundDaiPlan is D3MPlanBase {

    CErc20            public immutable cDai;
    InterestRateModel public immutable rateModel;

    // Target Interest Rate Per Block [wad]
    uint256 public barb; // (0)

    constructor(address dai_, address cDai_) public D3MPlanBase(dai_) {

        address rateModel_ = CErc20(cDai_).interestRateModel();
        require(rateModel_ != address(0), "D3MCompoundDaiPlan/invalid-rateModel");

        rateModel = InterestRateModel(rateModel_);
        cDai = CErc20(cDai_);
    }

    // --- Math ---
    uint256 constant WAD  = 10 ** 18;

    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "D3MCompoundDaiPlan/overflow");
    }
    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "D3MCompoundDaiPlan/underflow");
    }
    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "D3MCompoundDaiPlan/overflow");
    }
    function _wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, y) / WAD;
    }
    function _wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, WAD) / y;
    }

    // --- Admin ---
    function file(bytes32 what, uint256 data) external auth {
        if (what == "barb") {
            barb = data;
        } else revert("D3MCompoundDaiPlan/file-unrecognized-param");
    }

    // --- Automated Rate targeting ---
    function _calculateTargetSupply(uint256 targetInterestRate, uint256 borrows) internal view returns (uint256) {
        uint256 kink               = rateModel.kink();
        uint256 multiplierPerBlock = rateModel.multiplierPerBlock();
        uint256 baseRatePerBlock   = rateModel.baseRatePerBlock();

        uint256 normalRate = _add(_wmul(kink, multiplierPerBlock), baseRatePerBlock);

        uint256 targetUtil;
        if (targetInterestRate > normalRate) {
            targetUtil = _add(kink, _wdiv(targetInterestRate - normalRate, rateModel.jumpMultiplierPerBlock())); // (1)
        } else if (targetInterestRate > baseRatePerBlock) {
            targetUtil = _wdiv(targetInterestRate - baseRatePerBlock, multiplierPerBlock);                       // (2)
        } else {
            return 0;
        }

        return _wdiv(borrows, targetUtil);                                                                       // (3)
    }

    function calculateTargetSupply(uint256 targetInterestRate) external view returns (uint256) {
        return _calculateTargetSupply(targetInterestRate, cDai.totalBorrows());
    }

    function calcSupplies(uint256 availableAssets) external override view returns (uint256 totalAssets, uint256 targetAssets) {
        uint256 borrows = cDai.totalBorrows();

        totalAssets = _sub(
            _add(
                availableAssets, // cash
                borrows
            ),
            cDai.totalReserves()
        );

        targetAssets = _calculateTargetSupply(barb, borrows);
    }
}
