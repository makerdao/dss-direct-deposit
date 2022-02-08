// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
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

interface TargetTokenLike {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function scaledBalanceOf(address) external view returns (uint256);
}

interface LendingPoolLike {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external;
    function getReserveNormalizedIncome(address asset) external view returns (uint256);
    function getReserveData(address asset) external view returns (
        uint256,    // Configuration
        uint128,    // the liquidity index. Expressed in ray
        uint128,    // variable borrow index. Expressed in ray
        uint128,    // the current supply rate. Expressed in ray
        uint128,    // the current variable borrow rate. Expressed in ray
        uint128,    // the current stable borrow rate. Expressed in ray
        uint40,
        address,    // address of the adai interest bearing token
        address,    // address of the stable debt token
        address,    // address of the variable debt token
        address,    // address of the interest rate strategy
        uint8
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

contract DssDirectDepositAaveDai {

    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external auth {
        wards[usr] = 1;

        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;

        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "DssDirectDepositAaveDai/not-authorized");
        _;
    }

    LendingPoolLike public immutable pool;
    InterestRateStrategyLike public immutable interestStrategy;
    address public immutable rewardsClaimer;
    TargetTokenLike public immutable gem;
    TargetTokenLike public immutable adai;
    TargetTokenLike public immutable stableDebt;
    TargetTokenLike public immutable variableDebt;

    uint256 public live = 1;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Cage();

    constructor(address dai_, address pool_, address _rewardsClaimer) public {

        // Fetch the reserve data from Aave
        (,,,,,,, address adai_, address stableDebt_, address variableDebt_, address interestStrategy_,) = LendingPoolLike(pool_).getReserveData(address(dai_));
        require(adai_ != address(0), "DssDirectDepositAaveDai/invalid-adai");
        require(stableDebt_ != address(0), "DssDirectDepositAaveDai/invalid-stableDebt");
        require(variableDebt_ != address(0), "DssDirectDepositAaveDai/invalid-variableDebt");
        require(interestStrategy_ != address(0), "DssDirectDepositAaveDai/invalid-interestStrategy");

        pool = LendingPoolLike(pool_);
        gem = adai = TargetTokenLike(adai_);
        stableDebt = TargetTokenLike(stableDebt_);
        variableDebt = TargetTokenLike(variableDebt_);
        interestStrategy = InterestRateStrategyLike(interestStrategy_);
        rewardsClaimer = _rewardsClaimer;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        TargetTokenLike(adai_).approve(address(pool_), type(uint256).max);
        TargetTokenLike(dai_).approve(address(pool_), type(uint256).max);

    }

    // --- Math ---
    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "DssDirectDepositAaveDai/overflow");
    }
    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "DssDirectDepositAaveDai/underflow");
    }
    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "DssDirectDepositAaveDai/overflow");
    }
    uint256 constant RAY  = 10 ** 27;
    function _rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, y) / RAY;
    }
    function _rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, RAY) / y;
    }
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }

    function getMaxBar() public view returns (uint256) {
        return interestStrategy.getMaxVariableBorrowRate();
    }

    function validTarget(address wat) external view returns (bool) {
        (,,,,,,,,,, address strategy,) = pool.getReserveData(wat);
        return strategy == address(interestStrategy);
    }
    
    // --- Automated Rate targeting ---
    function calculateTargetSupply(uint256 targetInterestRate) public view returns (uint256) {
        uint256 base = interestStrategy.baseVariableBorrowRate();
        require(targetInterestRate > base, "DssDirectDepositAaveDai/target-interest-base");
        require(targetInterestRate <= getMaxBar(), "DssDirectDepositAaveDai/above-max-interest");

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
        return _rdiv(_add(stableDebt.totalSupply(), variableDebt.totalSupply()), targetUtil);
    }

    function calcSupplies(uint256 availableLiquidity, uint256 targetBar) external view returns(uint256 supplyAmount, uint256 targetSupply) {
        supplyAmount = _add(
                          availableLiquidity,
                            _add(
                                stableDebt.totalSupply(),
                                variableDebt.totalSupply()
                            )
                        );
        targetSupply = targetBar > 0 ? calculateTargetSupply(targetBar) : 0;
    }

    // Deposits Dai to Aave in exchange for adai which gets sent to the msg.sender
    // Aave: https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#deposit
    function supply(address wat, uint256 amt) external auth {
        // We need to pull the dai tokens to this address before calling deposit
        require(TargetTokenLike(wat).transferFrom(msg.sender, address(this), amt), "DssDirectDepositAaveDai/deposit-transfer-failed");
        // Then we can deposit and send the aDai to the msg.sender
        pool.deposit(wat, amt, msg.sender, 0);

    }

    // Withdraws Dai from Aave in exchange for adai
    // Aave: https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#withdraw
    function withdraw(address wat, uint256 amt) external auth {
        // We need to pull adai tokens in this address before calling withdraw
        require(adai.transferFrom(msg.sender, address(this), amt), "DssDirectDepositAaveDai/withdraw-transfer-failed");
        // Then we can withdraw and send the Dai to the msg.sender
        pool.withdraw(wat, amt, msg.sender);
    }

    function getCurrentRate(address wat) public view returns (uint256 currVarBorrow) {
        (,,,, currVarBorrow,,,,,,,) = pool.getReserveData(wat);
    }

    // --- Balance in standard ERC-20 denominations
    function getNormalizedBalanceOf(address who) external view returns (uint256) {
        return adai.scaledBalanceOf(who);
    }

    // --- Convert a standard ERC-20 amount to a the normalized amount 
    //     when added to the balance
    function getNormalizedAmount(address wat, uint256 amt) external view returns (uint256) {
        uint256 interestIndex = pool.getReserveNormalizedIncome(wat);
        return _rdiv(amt, interestIndex);
    }

    // --- Shutdown ---
    function cage() external auth {
        live = 0;
        emit Cage();
    }
}
