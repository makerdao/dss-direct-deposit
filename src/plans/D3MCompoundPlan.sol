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
// https://github.com/compound-finance/compound-protocol/blob/a3214f67b73310d547e00fc578e8355911c9d376/contracts/BaseJumpRateModelV2.sol#L96
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
// https://github.com/compound-finance/compound-protocol/blob/a3214f67b73310d547e00fc578e8355911c9d376/contracts/BaseJumpRateModelV2.sol#L80
//
//         util = borrows * WAD / (cash + borrows - reserves);
// (3)     cash + borrows - reserves = borrows * WAD / util

pragma solidity ^0.8.14;

import "./ID3MPlan.sol";

// cDai - https://etherscan.io/address/0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643
interface CErc20Like {
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function interestRateModel() external view returns (address);
    function getCash() external view returns (uint256);
    function implementation() external view returns (address);
}

// JumpRateModelV2 - https://etherscan.io/address/0xfb564da37b41b2f6b6edcc3e56fbf523bd9f2012
interface InterestRateModelLike {
    function baseRatePerBlock() external view returns (uint256);
    function kink() external view returns (uint256);
    function multiplierPerBlock() external view returns (uint256);
    function jumpMultiplierPerBlock() external view returns (uint256);
}

contract D3MCompoundPlan is ID3MPlan {

    mapping (address => uint256) public wards;
    InterestRateModelLike        public tack;
    address                      public delegate; // cDai implementation
    uint256                      public barb;     // target Interest Rate Per Block [wad] (0)

    CErc20Like public immutable cDai;

    // https://github.com/compound-finance/compound-protocol/blob/a3214f67b73310d547e00fc578e8355911c9d376/contracts/CTokenInterfaces.sol#L31
    uint256 internal constant MAX_BORROW_RATE = 0.0005e16;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);

    constructor(address cDai_) {
        cDai = CErc20Like(cDai_);

        address rateModel_ = cDai.interestRateModel();
        address delegate_  = cDai.implementation();

        require(rateModel_ != address(0), "D3MCompoundPlan/invalid-rateModel");
        require(delegate_  != address(0), "D3MCompoundPlan/invalid-delegate");

        tack     = InterestRateModelLike(rateModel_);
        delegate = delegate_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MCompoundPlan/not-authorized");
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
            require(data <= MAX_BORROW_RATE, "D3MCompoundPlan/barb-too-high");
            barb = data;
        } else revert("D3MCompoundPlan/file-unrecognized-param");
        emit File(what, data);
    }
    function file(bytes32 what, address data) external auth {
        if (what == "tack") tack = InterestRateModelLike(data);
        else if (what == "delegate") delegate = data;
        else revert("D3MCompoundPlan/file-unrecognized-param");
        emit File(what, data);
    }

    function _calculateTargetSupply(uint256 targetInterestRate, uint256 borrows) internal view returns (uint256) {
        uint256 kink                   = tack.kink();
        uint256 multiplierPerBlock     = tack.multiplierPerBlock();
        uint256 baseRatePerBlock       = tack.baseRatePerBlock();
        uint256 jumpMultiplierPerBlock = tack.jumpMultiplierPerBlock();

        // The normal rate is a Compound term for the rate at kink utillization
        uint256 normalRate = _wmul(kink, multiplierPerBlock) + baseRatePerBlock;

        uint256 targetUtil;
        if (targetInterestRate > normalRate) {
            if (jumpMultiplierPerBlock == 0) return 0; // illegal rate, max is normal rate for this case
            targetUtil = kink + _wdiv(targetInterestRate - normalRate, jumpMultiplierPerBlock); // (1)
        } else if (targetInterestRate > baseRatePerBlock) {
            // multiplierPerBlock != 0, as otherwise normalRate == baseRatePerBlock, matching the first case
            targetUtil = _wdiv(targetInterestRate - baseRatePerBlock, multiplierPerBlock);      // (2)
        } else {
            // if (target == base) => (borrows == 0) => supply does not matter
            // if (target  < base) => illegal rate
            return 0;
        }

        return _wdiv(borrows, targetUtil);                                                      // (3)
    }

    // Note: This view function has no reentrancy protection. On chain integrations should consider verifying that
    //       `hub.locked()` is false before relying on it.
    function getTargetAssets(uint256 currentAssets) external override view returns (uint256) {
        uint256 targetInterestRate = barb;
        if (targetInterestRate == 0) return 0; // De-activated

        uint256 borrows = cDai.totalBorrows();
        uint256 targetTotalPoolSize = _calculateTargetSupply(targetInterestRate, borrows);
        uint256 totalPoolSize = cDai.getCash() + borrows - cDai.totalReserves();

        if (targetTotalPoolSize >= totalPoolSize) {
            // Increase debt (or same)
            return currentAssets + (targetTotalPoolSize - totalPoolSize);
        } else {
            // Decrease debt
            unchecked {
                uint256 decrease = totalPoolSize - targetTotalPoolSize;
                if (currentAssets >= decrease) {
                    return currentAssets - decrease;
                } else {
                    return 0;
                }
            }
        }
    }

    function active() public view override returns (bool) {
        if (barb == 0) return false;
        return cDai.interestRateModel() == address(tack) &&
               cDai.implementation()    == delegate;
    }

    function disable() external override {
        require(wards[msg.sender] == 1 || !active(), "D3MCompoundPlan/not-authorized");
        barb = 0; // ensure deactivation even if active conditions return later
        emit Disable();
    }
}
