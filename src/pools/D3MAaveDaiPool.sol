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

import "../bases/D3MPoolBase.sol";

interface ShareTokenLike is TokenLike {
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

contract D3MAaveDaiPool is D3MPoolBase {

    InterestRateStrategyLike public immutable interestStrategy;
    RewardsClaimerLike       public immutable rewardsClaimer;
    ShareTokenLike           public immutable stableDebt;
    ShareTokenLike           public immutable variableDebt;

    address public king;     // Who gets the rewards
    uint256 public bar;      // Target Interest Rate [ray]

    constructor(address hub_, address daiJoin_, address pool_, address _rewardsClaimer) public D3MPoolBase(hub_, daiJoin_, pool_) {
        // address dai_, address pool_,

        address dai_ = DaiJoinLike(daiJoin_).dai();

        // Fetch the reserve data from Aave
        (,,,,,,, address adai_, address stableDebt_, address variableDebt_, address interestStrategy_,) = LendingPoolLike(pool_).getReserveData(address(dai_));
        require(adai_ != address(0), "D3MAaveDaiPool/invalid-adai");
        require(stableDebt_ != address(0), "D3MAaveDaiPool/invalid-stableDebt");
        require(variableDebt_ != address(0), "D3MAaveDaiPool/invalid-variableDebt");
        require(interestStrategy_ != address(0), "D3MAaveDaiPool/invalid-interestStrategy");

        stableDebt = ShareTokenLike(stableDebt_);
        variableDebt = ShareTokenLike(variableDebt_);
        interestStrategy = InterestRateStrategyLike(interestStrategy_);
        rewardsClaimer = RewardsClaimerLike(_rewardsClaimer);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        ShareTokenLike(adai_).approve(address(pool_), type(uint256).max);
        TokenLike(dai_).approve(address(pool_), type(uint256).max);

    }

    // --- Math ---
    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "D3MAaveDaiPool/overflow");
    }
    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "D3MAaveDaiPool/underflow");
    }
    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "D3MAaveDaiPool/overflow");
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
    function file(bytes32 what, address data) public override auth {
        require(live == 1, "D3MAaveDaiPoolPool/no-file-not-live");

        if (what == "king") king = data;
        else super.file(what, data);
    }

    function validTarget() external view override returns (bool) {
        (,,,,,,,,,, address strategy,) = LendingPoolLike(pool).getReserveData(address(asset));
        return strategy == address(interestStrategy);
    }

    function calcSupplies(uint256 availableAssets) external view override returns(uint256, uint256) {
        return D3MPlanLike(plan).calcSupplies(availableAssets);
    }

    // Deposits Dai to Aave in exchange for adai which gets sent to the msg.sender
    // Aave: https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#deposit
    function deposit(uint256 amt) external override auth {
        LendingPoolLike(pool).deposit(address(asset), amt, address(this), 0);

    }

    // Withdraws Dai from Aave in exchange for adai
    // Aave: https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#withdraw
    function withdraw(uint256 amt) external override auth {
        LendingPoolLike(pool).withdraw(address(asset), amt, address(this));
    }

    // --- Collect any rewards ---
    function collect(address[] memory assets, uint256 amount) external override auth returns (uint256 amt) {
        require(king != address(0), "D3MAaveDaiPool/king-not-set");

        amt = rewardsClaimer.claimRewards(assets, amount, king);
    }

    function transferShares(address dst, uint256 amt) external override returns(bool) {
        return ShareTokenLike(share).transfer(dst, amt);
    }

    // --- Balance in standard ERC-20 denominations
    function assetBalance() external view override returns (uint256) {
        return ShareTokenLike(share).scaledBalanceOf(address(this));
    }

    function shareBalance() public view override returns(uint256) {
        return ShareTokenLike(share).balanceOf(address(this));
    }

    function maxWithdraw() external view override returns(uint256) {
        // return TokenLike(asset).balanceOf(share);
    }

    // --- Convert a standard ERC-20 amount to a the normalized amount
    //     when added to the balance
    function convertToShares(uint256 amt) external view override returns (uint256) {
        uint256 interestIndex = LendingPoolLike(pool).getReserveNormalizedIncome(address(asset));
        return _rdiv(amt, interestIndex);
    }

    function convertToAssets(uint256 amt) public view override returns(uint256) {
        // return amt;
    }
}
