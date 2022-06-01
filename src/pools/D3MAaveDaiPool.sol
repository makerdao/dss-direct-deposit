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

pragma solidity ^0.8.14;

import "./ID3MPool.sol";

interface TokenLike {
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface CanLike {
    function hope(address) external;
    function nope(address) external;
}

interface D3mHubLike {
    function vat() external view returns (address);
}

interface ATokenLike is TokenLike {
    function scaledBalanceOf(address) external view returns (uint256);
}

interface LendingPoolLike {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external;
    function getReserveNormalizedIncome(address asset) external view returns (uint256);
    function getReserveData(address asset) external view returns (
        uint256,    // configuration
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

contract D3MAaveDaiPool is ID3MPool {

    mapping (address => uint256) public wards;

    LendingPoolLike          public immutable pool;
    RewardsClaimerLike       public immutable rewardsClaimer;
    ATokenLike               public immutable stableDebt;
    ATokenLike               public immutable variableDebt;
    ATokenLike               public immutable adai;
    TokenLike                public immutable asset; // Dai
    address                  public           king;  // Who gets the rewards

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event Collect(address indexed king, address[] assets, uint256 amt);

    constructor(address hub_, address dai_, address pool_, address _rewardsClaimer) {
        pool = LendingPoolLike(pool_);
        asset = TokenLike(dai_);

        // Fetch the reserve data from Aave
        (,,,,,,, address adai_, address stableDebt_, address variableDebt_, ,) = LendingPoolLike(pool_).getReserveData(dai_);
        require(stableDebt_ != address(0), "D3MAaveDaiPool/invalid-stableDebt");
        require(variableDebt_ != address(0), "D3MAaveDaiPool/invalid-variableDebt");

        adai = ATokenLike(adai_);
        stableDebt = ATokenLike(stableDebt_);
        variableDebt = ATokenLike(variableDebt_);
        rewardsClaimer = RewardsClaimerLike(_rewardsClaimer);

        TokenLike(dai_).approve(pool_, type(uint256).max);

        CanLike(D3mHubLike(hub_).vat()).hope(hub_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MAaveDaiPool/not-authorized");
        _;
    }

    // --- Math ---
    uint256 internal constant RAY  = 10 ** 27;
    function _rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * RAY) / y;
    }
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
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

    function file(bytes32 what, address data) external auth {
        if (what == "king") king = data;
        else revert("D3MAaveDaiPool/file-unrecognized-param");
        emit File(what, data);
    }

    function hope(address hub) external override auth{
        CanLike(D3mHubLike(hub).vat()).hope(hub);
    }

    function nope(address hub) external override auth{
        CanLike(D3mHubLike(hub).vat()).nope(hub);
    }

    // Deposits Dai to Aave in exchange for adai which gets sent to the msg.sender
    // Aave: https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#deposit
    function deposit(uint256 wad) external override auth returns (bool) {
        uint256 scaledPrev = adai.scaledBalanceOf(address(this));

        pool.deposit(address(asset), wad, address(this), 0);

        // Verify the correct amount of adai shows up
        uint256 interestIndex = pool.getReserveNormalizedIncome(address(asset));
        uint256 scaledAmount = _rdiv(wad, interestIndex);
        return adai.scaledBalanceOf(address(this)) >= (scaledPrev + scaledAmount);
    }

    // Withdraws Dai from Aave in exchange for adai
    // Aave: https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#withdraw
    function withdraw(uint256 wad) external override auth returns (bool) {
        pool.withdraw(address(asset), wad, address(msg.sender));
        return true;
    }

    function transfer(address dst, uint256 wad) external override auth returns (bool) {
        return adai.transfer(dst, wad);
    }

    function transferAll(address dst) external override auth returns (bool) {
        return adai.transfer(dst, adai.balanceOf(address(this)));
    }

    function preDebtChange() external override {}

    function postDebtChange() external override {}

    // --- Balance of the underlying asset (Dai)
    function assetBalance() public view override returns (uint256) {
        return adai.balanceOf(address(this));
    }

    function maxDeposit() external pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw() external view override returns (uint256) {
        return _min(asset.balanceOf(address(adai)), assetBalance());
    }

    function recoverDai(address dst, uint256 wad) external override auth returns (bool) {
        return TokenLike(asset).transfer(dst, wad);
    }

    function active() external pure override returns (bool) {
        return true;
    }

    // --- Collect any rewards ---
    function collect() external returns (uint256 amt) {
        require(king != address(0), "D3MAaveDaiPool/king-not-set");

        address[] memory assets = new address[](1);
        assets[0] = address(adai);

        amt = rewardsClaimer.claimRewards(assets, type(uint256).max, king);
        emit Collect(king, assets, amt);
    }
}
