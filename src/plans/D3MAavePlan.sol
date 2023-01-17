// SPDX-FileCopyrightText: © 2021 Dai Foundation <www.daifoundation.org>
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

pragma solidity ^0.8.14;

import "./ID3MPlan.sol";

interface TokenLike {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
}

interface ATokenLike {
    function ATOKEN_REVISION() external view returns (uint256);
}

interface LendingPoolLike {
    function getReserveData(address asset) external view returns (
        uint256, // configuration
        uint128, // the liquidity index. Expressed in ray
        uint128, // variable borrow index. Expressed in ray
        uint128, // the current supply rate. Expressed in ray
        uint128, // the current variable borrow rate. Expressed in ray
        uint128, // the current stable borrow rate. Expressed in ray
        uint40,  // last updated timestamp
        address, // address of the adai interest bearing token
        address, // address of the stable debt token
        address, // address of the variable debt token
        address, // address of the interest rate strategy
        uint8    // the id of the reserve
    );
}

// Need to use a struct as too many variables to return on the stack
struct ReserveDataV3 {
    //stores the reserve configuration
    uint256 configuration;
    //the liquidity index. Expressed in ray
    uint128 liquidityIndex;
    //the current supply rate. Expressed in ray
    uint128 currentLiquidityRate;
    //variable borrow index. Expressed in ray
    uint128 variableBorrowIndex;
    //the current variable borrow rate. Expressed in ray
    uint128 currentVariableBorrowRate;
    //the current stable borrow rate. Expressed in ray
    uint128 currentStableBorrowRate;
    //timestamp of last update
    uint40 lastUpdateTimestamp;
    //the id of the reserve. Represents the position in the list of the active reserves
    uint16 id;
    //aToken address
    address aTokenAddress;
    //stableDebtToken address
    address stableDebtTokenAddress;
    //variableDebtToken address
    address variableDebtTokenAddress;
    //address of the interest rate strategy
    address interestRateStrategyAddress;
    //the current treasury balance, scaled
    uint128 accruedToTreasury;
    //the outstanding unbacked aTokens minted through the bridging feature
    uint128 unbacked;
    //the outstanding debt borrowed against this asset in isolation mode
    uint128 isolationModeTotalDebt;
}

// Aave Lending Pool v3
// Interface changed slightly from v2 to v3
interface LendingPoolReserveDataV3Like {
    function getReserveData(address asset) external view returns (ReserveDataV3 memory);
}

interface InterestRateStrategyLike {
    // V2
    function OPTIMAL_UTILIZATION_RATE() external view returns (uint256);
    function EXCESS_UTILIZATION_RATE() external view returns (uint256);
    function variableRateSlope1() external view returns (uint256);
    function variableRateSlope2() external view returns (uint256);
    function baseVariableBorrowRate() external view returns (uint256);
    function getMaxVariableBorrowRate() external view returns (uint256);

    // V3
    function OPTIMAL_USAGE_RATIO() external view returns (uint256);
    function MAX_EXCESS_USAGE_RATIO() external view returns (uint256);
    function getVariableRateSlope1() external view returns (uint256);
    function getVariableRateSlope2() external view returns (uint256);
    function getBaseVariableBorrowRate() external view returns (uint256);
}

contract D3MAavePlan is ID3MPlan {

    enum AaveVersion {
        V2,
        V3
    }

    mapping (address => uint256) public wards;
    InterestRateStrategyLike     public tack;
    uint256                      public bar; // Target Interest Rate [ray]

    AaveVersion     public immutable version;
    LendingPoolLike public immutable pool;
    TokenLike       public immutable stableDebt;
    TokenLike       public immutable variableDebt;
    TokenLike       public immutable dai;
    address         public immutable adai;
    uint256         public immutable adaiRevision;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);

    constructor(AaveVersion version_, address dai_, address pool_) {
        version = version_;
        dai = TokenLike(dai_);
        pool = LendingPoolLike(pool_);

        // Fetch the reserve data from Aave
        (address adai_, address stableDebt_, address variableDebt_, address interestStrategy_) = getReserveDataAddresses();
        require(adai_             != address(0), "D3MAavePlan/invalid-adai");
        require(stableDebt_       != address(0), "D3MAavePlan/invalid-stableDebt");
        require(variableDebt_     != address(0), "D3MAavePlan/invalid-variableDebt");
        require(interestStrategy_ != address(0), "D3MAavePlan/invalid-interestStrategy");

        adai         = adai_;
        adaiRevision = ATokenLike(adai_).ATOKEN_REVISION();
        stableDebt   = TokenLike(stableDebt_);
        variableDebt = TokenLike(variableDebt_);
        tack         = InterestRateStrategyLike(interestStrategy_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function getReserveDataAddresses() internal view returns (address adai_, address stableDebt_, address variableDebt_, address interestStrategy_) {
         if (version == AaveVersion.V3) {
            ReserveDataV3 memory data = LendingPoolReserveDataV3Like(address(pool)).getReserveData(address(dai));
            adai_ = data.aTokenAddress;
            stableDebt_ = data.stableDebtTokenAddress;
            variableDebt_ = data.variableDebtTokenAddress;
            interestStrategy_ = data.interestRateStrategyAddress;
        } else {
            (,,,,,,, adai_, stableDebt_, variableDebt_, interestStrategy_,) = pool.getReserveData(address(dai));
        }
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MAavePlan/not-authorized");
        _;
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
    function _rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * y) / RAY;
    }
    function _rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * RAY) / y;
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
        if (what == "bar") bar = data;
        else revert("D3MAavePlan/file-unrecognized-param");
        emit File(what, data);
    }
    function file(bytes32 what, address data) external auth {
        if (what == "tack") tack = InterestRateStrategyLike(data);
        else revert("D3MAavePlan/file-unrecognized-param");
        emit File(what, data);
    }

    function getInterestRateVariables() public view returns (uint256 base, uint256 slope1, uint256 slope2, uint256 max, uint256 optimal, uint256 excess) {
        if (version == AaveVersion.V3) {
            base    = tack.getBaseVariableBorrowRate();
            slope1  = tack.getVariableRateSlope1();
            slope2  = tack.getVariableRateSlope2();
            max     = tack.getMaxVariableBorrowRate();
            optimal = tack.OPTIMAL_USAGE_RATIO();
            excess  = tack.MAX_EXCESS_USAGE_RATIO();
        } else {
            base    = tack.baseVariableBorrowRate();
            slope1  = tack.variableRateSlope1();
            slope2  = tack.variableRateSlope2();
            max     = tack.getMaxVariableBorrowRate();
            optimal = tack.OPTIMAL_UTILIZATION_RATE();
            excess  = tack.EXCESS_UTILIZATION_RATE();
        }
    }

    // --- Automated Rate targeting ---
    function _calculateTargetSupply(uint256 targetInterestRate, uint256 totalDebt) internal view returns (uint256) {
        (uint256 base, uint256 slope1, uint256 slope2, uint256 max, uint256 optimal, uint256 excess) = getInterestRateVariables();
        if (targetInterestRate <= base || targetInterestRate > max) {
            return 0;
        }

        // Do inverse calculation of interestStrategy
        uint256 targetUtil;
        if (targetInterestRate > base + slope1) {
            // Excess interest rate
            uint256 r;
            unchecked {
                r = targetInterestRate - base - slope1;
            }
            targetUtil = _rdiv(
                            _rmul(
                                excess,
                                r
                            ),
                            slope2
                         ) + optimal;
        } else {
            // Optimal interest rate
            unchecked {
                targetUtil = _rdiv(
                                _rmul(
                                    targetInterestRate - base,
                                    optimal
                                ),
                                slope1
                             );
            }
        }

        return _rdiv(totalDebt, targetUtil);
    }

    // Note: This view function has no reentrancy protection.
    //       On chain integrations should consider verifying `hub.locked()` is zero before relying on it.
    function getTargetAssets(uint256 currentAssets) external override view returns (uint256) {
        uint256 targetInterestRate = bar;
        if (targetInterestRate == 0) return 0; // De-activated

        uint256 totalDebt = stableDebt.totalSupply() + variableDebt.totalSupply();
        uint256 totalPoolSize = dai.balanceOf(adai) + totalDebt;
        uint256 targetTotalPoolSize = _calculateTargetSupply(targetInterestRate, totalDebt);

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
        if (bar == 0) return false;
        (address adai_, address stableDebt_, address variableDebt_, address strategy) = getReserveDataAddresses();
        uint256 adaiRevision_ = ATokenLike(adai_).ATOKEN_REVISION();
        return strategy      == address(tack)          &&
               adai_         == address(adai)          &&
               adaiRevision_ == adaiRevision           &&
               stableDebt_   == address(stableDebt)    &&
               variableDebt_ == address(variableDebt);
    }

    function disable() external override {
        require(wards[msg.sender] == 1 || !active(), "D3MAavePlan/not-authorized");
        bar = 0; // ensure deactivation even if active conditions return later
        emit Disable();
    }
}
