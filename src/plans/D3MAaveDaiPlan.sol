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

import "./D3MPlanBase.sol";

interface TokenLike {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
}

interface LendingPoolLike {
    function getReserveData(address asset) external view returns (
        uint256,    // Configuration
        uint128,    // the liquidity index. Expressed in ray
        uint128,    // variable borrow index. Expressed in ray
        uint128,    // the current supply rate. Expressed in ray
        uint128,    // the current variable borrow rate. Expressed in ray
        uint128,    // the current stable borrow rate. Expressed in ray
        uint40,     // last updated timestamp
        address,    // address of the adai interest bearing token
        address,    // address of the stable debt token
        address,    // address of the variable debt token
        address,    // address of the interest rate strategy
        uint8       // the id of the reserve
    );
}

interface InterestRateStrategyLike {
    function OPTIMAL_UTILIZATION_RATE() external view returns (uint256);
    function EXCESS_UTILIZATION_RATE() external view returns (uint256);
    function variableRateSlope1() external view returns (uint256);
    function variableRateSlope2() external view returns (uint256);
    function baseVariableBorrowRate() external view returns (uint256);
    function getMaxVariableBorrowRate() external view returns (uint256);
}

contract D3MAaveDaiPlan is D3MPlanBase {

    InterestRateStrategyLike public immutable interestStrategy;
    TokenLike                public immutable stableDebt;
    TokenLike                public immutable variableDebt;
    address                  public immutable adai;

    uint256 public bar;  // Target Interest Rate [ray]

    constructor(address dai_, address pool_) public D3MPlanBase(dai_) {

        // Fetch the reserve data from Aave
        (,,,,,,, address adai_, address stableDebt_, address variableDebt_, address interestStrategy_,) = LendingPoolLike(pool_).getReserveData(dai_);
        require(adai_ != address(0), "D3MAaveDaiPool/invalid-adai");
        require(stableDebt_ != address(0), "D3MAaveDaiPlan/invalid-stableDebt");
        require(variableDebt_ != address(0), "D3MAaveDaiPlan/invalid-variableDebt");
        require(interestStrategy_ != address(0), "D3MAaveDaiPlan/invalid-interestStrategy");

        adai = adai_;
        stableDebt = TokenLike(stableDebt_);
        variableDebt = TokenLike(variableDebt_);
        interestStrategy = InterestRateStrategyLike(interestStrategy_);
    }

    // --- Math ---
    uint256 constant RAY  = 10 ** 27;

    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "D3MAaveDaiPlan/overflow");
    }
    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "D3MAaveDaiPlan/underflow");
    }
    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "D3MAaveDaiPlan/overflow");
    }
    function _rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, y) / RAY;
    }
    function _rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, RAY) / y;
    }

    // --- Admin ---
    function file(bytes32 what, uint256 data) public auth {
        if (what == "bar") {
            require(data <= maxBar(), "D3MAaveDaiPlan/above-max-interest");

            bar = data;
        } else revert("D3MAaveDaiPlan/file-unrecognized-param");
    }

    function maxBar() public view returns (uint256) {
        return interestStrategy.getMaxVariableBorrowRate();
    }

    // --- Automated Rate targeting ---
    function calculateTargetSupply(uint256 targetInterestRate) external view returns (uint256) {
        uint256 stableDebtTotal = stableDebt.totalSupply();
        uint256 variableDebtTotal = variableDebt.totalSupply();
        return _calculateTargetSupply(targetInterestRate, stableDebtTotal, variableDebtTotal);
    }

    function _calculateTargetSupply(uint256 targetInterestRate, uint256 stableDebtTotal, uint256 variableDebtTotal) internal view returns (uint256) {
        uint256 base = interestStrategy.baseVariableBorrowRate();
        require(targetInterestRate > base, "DssDirectDepositAaveDai/target-interest-base");
        require(targetInterestRate <= interestStrategy.getMaxVariableBorrowRate(), "DssDirectDepositAaveDai/above-max-interest");

        // Do inverse calculation of interestStrategy
        uint256 variableRateSlope1 = interestStrategy.variableRateSlope1();
        uint256 targetUtil;
        if (targetInterestRate > _add(base, variableRateSlope1)) {
            // Excess interest rate
            uint256 r = targetInterestRate - base - variableRateSlope1;
            targetUtil = _add(_rdiv(_rmul(interestStrategy.EXCESS_UTILIZATION_RATE(), r), interestStrategy.variableRateSlope2()), interestStrategy.OPTIMAL_UTILIZATION_RATE());
        } else {
            // Optimal interest rate
            targetUtil = _rdiv(_rmul(_sub(targetInterestRate, base), interestStrategy.OPTIMAL_UTILIZATION_RATE()), variableRateSlope1);
        }
        return _rdiv(_add(stableDebtTotal, variableDebtTotal), targetUtil);
    }

    function getTargetAssets(uint256 currentAssets) external override view returns (uint256) {
        uint256 targetInterestRate = bar;
        if (targetInterestRate == 0) return 0;     // De-activated

        uint256 totalPoolSize = _add(
                TokenLike(dai).balanceOf(address(adai)),
                _add(
                    stableDebt.totalSupply(),
                    variableDebt.totalSupply()
                )
            );

        uint256 stableDebtTotal = stableDebt.totalSupply();
        uint256 variableDebtTotal = variableDebt.totalSupply();

        uint256 targetTotalPoolSize = _calculateTargetSupply(targetInterestRate, stableDebtTotal, variableDebtTotal);
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
}
