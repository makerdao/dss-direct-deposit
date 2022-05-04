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

import "./D3MPoolBase.sol";

interface ATokenLike is TokenLike {
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
        uint40,     // last updated timestamp
        address,    // address of the adai interest bearing token
        address,    // address of the stable debt token
        address,    // address of the variable debt token
        address,    // address of the interest rate strategy
        uint8       // the id of the reserve
    );
}

interface RewardsClaimerLike {
    function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);
}

contract D3MAaveDaiPool is D3MPoolBase {

    uint256 constant RAY  = 10 ** 27;

    LendingPoolLike          public immutable pool;
    RewardsClaimerLike       public immutable rewardsClaimer;
    ATokenLike               public immutable stableDebt;
    ATokenLike               public immutable variableDebt;
    address                  public immutable interestStrategy;
    ATokenLike               public immutable adai;

    address public king;  // Who gets the rewards

    event Collect(address indexed king, address[] assets, uint256 amt);
    event File(bytes32 indexed what, address data);

    constructor(address hub_, address dai_, address pool_, address _rewardsClaimer) public D3MPoolBase(hub_, dai_) {
        pool = LendingPoolLike(pool_);

        // Fetch the reserve data from Aave
        (,,,,,,, address adai_, address stableDebt_, address variableDebt_, address interestStrategy_,) = LendingPoolLike(pool_).getReserveData(dai_);
        require(adai_ != address(0), "D3MAaveDaiPool/invalid-adai");
        require(stableDebt_ != address(0), "D3MAaveDaiPool/invalid-stableDebt");
        require(variableDebt_ != address(0), "D3MAaveDaiPool/invalid-variableDebt");
        require(interestStrategy_ != address(0), "D3MAaveDaiPool/invalid-interestStrategy");

        adai = ATokenLike(adai_);
        stableDebt = ATokenLike(stableDebt_);
        variableDebt = ATokenLike(variableDebt_);
        interestStrategy = interestStrategy_;
        rewardsClaimer = RewardsClaimerLike(_rewardsClaimer);

        ATokenLike(adai_).approve(pool_, type(uint256).max);
        TokenLike(dai_).approve(pool_, type(uint256).max);
    }

    // --- Math ---
    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "D3MAaveDaiPool/overflow");
    }
    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "D3MAaveDaiPool/overflow");
    }
    function _rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, RAY) / y;
    }
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }

    // --- Admin ---
    function file(bytes32 what, address data) external auth {
        if (what == "king") king = data;
        else revert("D3MAaveDaiPool/file-unrecognized-param");
        emit File(what, data);
    }

    function validTarget() external view override returns (bool) {
        (,,,,,,,,,, address strategy,) = pool.getReserveData(address(asset));
        return strategy == interestStrategy;
    }

    // Deposits Dai to Aave in exchange for adai which gets sent to the msg.sender
    // Aave: https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#deposit
    function deposit(uint256 amt) external override auth {
        uint256 scaledPrev = adai.scaledBalanceOf(address(this));

        pool.deposit(address(asset), amt, address(this), 0);

        // Verify the correct amount of adai shows up
        uint256 interestIndex = pool.getReserveNormalizedIncome(address(asset));
        uint256 scaledAmount = _rdiv(amt, interestIndex);
        require(adai.scaledBalanceOf(address(this)) >= _add(scaledPrev, scaledAmount), "D3MAaveDaiPool/incorrect-share-credit");
    }

    // Withdraws Dai from Aave in exchange for adai
    // Aave: https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#withdraw
    function withdraw(uint256 amt) external override auth {
        pool.withdraw(address(asset), amt, address(msg.sender));
    }

    // --- Collect any rewards ---
    function collect() external returns (uint256 amt) {
        require(king != address(0), "D3MAaveDaiPool/king-not-set");

        address[] memory assets = new address[](1);
        assets[0] = address(adai);

        uint256 amount = type(uint256).max;

        amt = rewardsClaimer.claimRewards(assets, amount, king);
        emit Collect(king, assets, amt);
    }

    function transfer(address dst, uint256 amt) external override auth returns (bool) {
        return adai.transfer(dst, amt);
    }

    function transferAll(address dst) external override auth returns (bool) {
        return adai.transfer(dst, adai.balanceOf(address(this)));
    }

    function accrueIfNeeded() external override {}

    // --- Balance of the underlying asset (Dai)
    function assetBalance() public view override returns (uint256) {
        return adai.balanceOf(address(this));
    }

    function maxWithdraw() external view override returns (uint256) {
        return _min(TokenLike(asset).balanceOf(address(adai)), assetBalance());
    }
}
