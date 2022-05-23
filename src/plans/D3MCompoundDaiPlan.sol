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

pragma solidity 0.6.12;

import "./ID3MPlan.sol";

interface CErc20Like {
    function totalBorrows()           external view returns (uint256);
    function totalReserves()          external view returns (uint256);
    function interestRateModel()      external view returns (address);
    function getCash()                external view returns (uint256);
    function underlying()             external view returns (address);
}

interface InterestRateModelLike {
    function baseRatePerBlock()       external view returns (uint256);
    function kink()                   external view returns (uint256);
    function multiplierPerBlock()     external view returns (uint256);
    function jumpMultiplierPerBlock() external view returns (uint256);
}

contract D3MCompoundDaiPlan is ID3MPlan {

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
        require(wards[msg.sender] == 1, "D3MCompoundDaiPlan/not-authorized");
        _;
    }

    // --- Data ---
    CErc20Like public immutable cDai;

    InterestRateModelLike public rateModel;
    uint256               public barb; // target Interest Rate Per Block [wad] (0)

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);

    constructor(address cDai_) public {
        address rateModel_ = CErc20Like(cDai_).interestRateModel();
        require(rateModel_ != address(0), "D3MCompoundDaiPlan/invalid-rateModel");

        cDai = CErc20Like(cDai_);
        rateModel = InterestRateModelLike(rateModel_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Math ---
    uint256 internal constant WAD = 10 ** 18;

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

    // --- Administration ---
    function file(bytes32 what, uint256 data) external auth {
        if (what == "barb") {
            barb = data;
        } else revert("D3MCompoundDaiPlan/file-unrecognized-param");
        emit File(what, data);
    }
    function file(bytes32 what, address data) external auth {
        if (what == "rateModel") rateModel = InterestRateModelLike(data);
        else revert("D3MCompoundDaiPlan/file-unrecognized-param");
        emit File(what, data);
    }

    function getTargetAssets(uint256 currentAssets) external override view returns (uint256) {
        uint256 targetInterestRate = barb;
        if (targetInterestRate == 0) return 0; // De-activated

        uint256 borrows = cDai.totalBorrows();
        uint256 totalPoolSize = _sub(_add(cDai.getCash(), borrows), cDai.totalReserves());

        uint256 targetTotalPoolSize = _calculateTargetSupply(targetInterestRate, borrows);

        if (targetTotalPoolSize >= totalPoolSize) {
            // Increase debt (or same)
            return _add(currentAssets, targetTotalPoolSize - totalPoolSize);
        } else {
            // Decrease debt
            uint256 decrease = totalPoolSize - targetTotalPoolSize;
            if (currentAssets >= decrease) {
                return currentAssets - decrease;
            } else {
                return 0;
            }
        }
    }

    // TODO: this function seems unneeded, remove once it's removed from the interface and AAVE
    // targetSupply = cash + borrows - reserves
    function calculateTargetSupply(uint256 targetInterestRate) external view returns (uint256) {
        return _calculateTargetSupply(targetInterestRate, cDai.totalBorrows());
    }

    function _calculateTargetSupply(uint256 targetInterestRate, uint256 borrows) internal view returns (uint256) {
        uint256 kink                   = rateModel.kink();
        uint256 multiplierPerBlock     = rateModel.multiplierPerBlock();
        uint256 baseRatePerBlock       = rateModel.baseRatePerBlock();
        uint256 jumpMultiplierPerBlock = rateModel.jumpMultiplierPerBlock();

        uint256 normalRate = _add(_wmul(kink, multiplierPerBlock), baseRatePerBlock);

        uint256 targetUtil;
        if (targetInterestRate > normalRate) {
            if (jumpMultiplierPerBlock == 0) return 0; // illegal rate, max is normal rate for this case
            targetUtil = _add(kink, _wdiv(targetInterestRate - normalRate, jumpMultiplierPerBlock));             // (1)
        } else if (targetInterestRate > baseRatePerBlock) {
            targetUtil = _wdiv(targetInterestRate - baseRatePerBlock, multiplierPerBlock);                       // (2)
        } else {
            // if (target == base) => (borrows == 0) => supply does not matter
            // if (target  < base) => illegal rate
            return 0;
        }

        if (targetUtil > WAD) return 0; // illegal rate (unacheivable utilization)

        return _wdiv(borrows, targetUtil);                                                                       // (3)
    }

    function active() public view override returns (bool) {
        return CErc20Like(cDai).interestRateModel() == address(rateModel);
    }

    // TODO: align to aave's plan disable() once finalized
    function disable() external override {
        require(wards[msg.sender] == 1 || !active(), "D3MCompoundDaiPlan/not-authorized");
        barb = 0;
        emit Disable();
    }
}
