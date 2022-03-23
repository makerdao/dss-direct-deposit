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

interface RewardsClaimerLike {
    function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);
}

interface CanLike {
    function hope(address) external;
    function nope(address) external;
}

interface DssDirectDepositPlanLike {
    function calcSupplies(uint256, uint256) external view returns (uint256, uint256);
    function maxBar() external view returns (uint256);
}

contract DssDirectDepositAaveDaiPool {

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
        require(wards[msg.sender] == 1, "DssDirectDepositAaveDaiPool/not-authorized");
        _;
    }

    LendingPoolLike          public immutable pool;
    InterestRateStrategyLike public immutable interestStrategy;
    RewardsClaimerLike       public immutable rewardsClaimer;
    TargetTokenLike          public immutable gem;
    address                  public immutable dai;
    TargetTokenLike          public immutable adai;
    TargetTokenLike          public immutable stableDebt;
    TargetTokenLike          public immutable variableDebt;
    DssDirectDepositPlanLike public           plan;

    uint256 public live = 1;
    address public king;     // Who gets the rewards
    uint256 public bar;      // Target Interest Rate [ray]


    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Cage();

    constructor(address dai_, address pool_, address _rewardsClaimer) public {

        // Fetch the reserve data from Aave
        (,,,,,,, address adai_, address stableDebt_, address variableDebt_, address interestStrategy_,) = LendingPoolLike(pool_).getReserveData(address(dai_));
        require(adai_ != address(0), "DssDirectDepositAaveDaiPool/invalid-adai");
        require(stableDebt_ != address(0), "DssDirectDepositAaveDaiPool/invalid-stableDebt");
        require(variableDebt_ != address(0), "DssDirectDepositAaveDaiPool/invalid-variableDebt");
        require(interestStrategy_ != address(0), "DssDirectDepositAaveDaiPool/invalid-interestStrategy");

        pool = LendingPoolLike(pool_);
        dai = dai_;
        gem = adai = TargetTokenLike(adai_);
        stableDebt = TargetTokenLike(stableDebt_);
        variableDebt = TargetTokenLike(variableDebt_);
        interestStrategy = InterestRateStrategyLike(interestStrategy_);
        rewardsClaimer = RewardsClaimerLike(_rewardsClaimer);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        TargetTokenLike(adai_).approve(address(pool_), type(uint256).max);
        TargetTokenLike(dai_).approve(address(pool_), type(uint256).max);

    }

    // --- Math ---
    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "DssDirectDepositAaveDaiPool/overflow");
    }
    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "DssDirectDepositAaveDaiPool/underflow");
    }
    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "DssDirectDepositAaveDaiPool/overflow");
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

    // --- Admin ---
    function file(bytes32 what, uint256 data) external auth {
        if (what == "bar") {
            require(data <= plan.maxBar(), "DssDirectDepositAaveDaiPool/above-max-interest");

            bar = data;
        }
    }

    function file(bytes32 what, address data) external auth {
        require(live == 1, "DssDirectDepositAaveDaiPoolPool/no-file-not-live");

        if (what == "king") king = data;
        else if (what == "plan") plan = DssDirectDepositPlanLike(data);
    }

    function hope(address dst, address who) external auth {
        CanLike(dst).hope(who);
    }

    function nope(address dst, address who) external auth {
        CanLike(dst).nope(who);
    }

    function validTarget() external view returns (bool) {
        (,,,,,,,,,, address strategy,) = pool.getReserveData(dai);
        return strategy == address(interestStrategy);
    }

    function calcSupplies(uint256 availableAssets) external view returns(uint256, uint256) {
        return plan.calcSupplies(availableAssets, bar);
    }

    // Deposits Dai to Aave in exchange for adai which gets sent to the msg.sender
    // Aave: https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#deposit
    function supply(uint256 amt) external auth {
        pool.deposit(dai, amt, address(this), 0);

    }

    // Withdraws Dai from Aave in exchange for adai
    // Aave: https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#withdraw
    function withdraw(uint256 amt) external auth {
        pool.withdraw(dai, amt, address(this));
    }

    // --- Collect any rewards ---
    function collect(address[] memory assets, uint256 amount) external auth returns (uint256 amt) {
        require(king != address(0), "DssDirectDepositAaveDaiPool/king-not-set");

        amt = rewardsClaimer.claimRewards(assets, amount, king);
    }

    // --- Balance in standard ERC-20 denominations
    function getNormalizedBalanceOf() external view returns (uint256) {
        return adai.scaledBalanceOf(address(this));
    }

    // --- Convert a standard ERC-20 amount to a the normalized amount
    //     when added to the balance
    function getNormalizedAmount(uint256 amt) external view returns (uint256) {
        uint256 interestIndex = pool.getReserveNormalizedIncome(dai);
        return _rdiv(amt, interestIndex);
    }

    // --- Shutdown ---
    function cage() external auth {
        live = 0;
        emit Cage();
    }
}