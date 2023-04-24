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

pragma solidity ^0.8.14;

import "./D3MPoolBase.t.sol";

import { D3MAaveV3NoSupplyCapTypePool, PoolLike } from "../../pools/D3MAaveV3NoSupplyCapTypePool.sol";

interface RewardsClaimerLike {
    function getRewardsBalance(address[] calldata assets, address user) external view returns (uint256);
}

contract AToken is TokenMock {
    address public rewardsClaimer;

    constructor(uint256 decimals_) TokenMock(decimals_) {
        rewardsClaimer = address(new FakeRewardsClaimer());
    }

    function scaledBalanceOf(address who) external view returns (uint256) {
        return balanceOf[who];
    }

    function getIncentivesController() external view returns (address) {
        return rewardsClaimer;
    }
}

contract FakeRewardsClaimer {
    struct ClaimCall {
        address[] assets;
        uint256 amt;
        address dst;
        address reward;
    }
    ClaimCall public lastClaim;

    function claimRewards(address[] calldata assets, uint256 amt, address dst, address reward) external returns (uint256) {
        lastClaim = ClaimCall(
            assets,
            amt,
            dst,
            reward
        );
        return amt;
    }

    function getAssetsFromClaim() external view returns (address[] memory) {
        return lastClaim.assets;
    }
}

contract FakeLendingPool {

    // Need to use a struct as too many variables to return on the stack
    struct ReserveData {
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

    address public adai;
    address public variableDebtToken;
    address public stableDebtToken;
    address public dai;

    struct DepositCall {
        address asset;
        uint256 amt;
        address forWhom;
        uint16 code;
    }
    DepositCall public lastDeposit;

    struct WithdrawCall {
        address asset;
        uint256 amt;
        address dst;
    }
    WithdrawCall public lastWithdraw;

    constructor(address adai_, address variableDebtToken_, address stableDebtToken_, address dai_) {
        adai = adai_;
        variableDebtToken = variableDebtToken_;
        stableDebtToken = stableDebtToken_;
        dai = dai_;
    }

    function getReserveData(address) external view returns(
        ReserveData memory result
    ) {
        result.aTokenAddress = adai;
        result.stableDebtTokenAddress = stableDebtToken;
        result.variableDebtTokenAddress = variableDebtToken;
        result.interestRateStrategyAddress = address(4);
    }

    function supply(address asset, uint256 amt, address forWhom, uint16 code) external {
        lastDeposit = DepositCall(
            asset,
            amt,
            forWhom,
            code
        );
        TokenMock(dai).transferFrom(msg.sender, address(adai), amt);
        TokenMock(adai).mint(forWhom, amt);
    }

    function withdraw(address asset, uint256 amt, address dst) external {
        lastWithdraw = WithdrawCall(
            asset,
            amt,
            dst
        );
        TokenMock(asset).transferFrom(address(adai), dst, amt);
    }

    function getReserveNormalizedIncome(address asset) external pure returns (uint256) {
        asset;
        return 10 ** 27;
    }
}

contract D3MAaveV3NoSupplyCapTypePoolTest is D3MPoolBaseTest {

    AToken adai;
    TokenMock variableDebtToken;
    TokenMock stableDebtToken;
    FakeLendingPool aavePool;
    
    D3MAaveV3NoSupplyCapTypePool pool;

    function setUp() public {
        baseInit("D3MAaveV3NoSupplyCapTypePool");

        adai = new AToken(18);
        adai.mint(address(this), 1_000_000 ether);
        variableDebtToken = new TokenMock(18);
        stableDebtToken = new TokenMock(18);
        aavePool = new FakeLendingPool(address(adai), address(variableDebtToken), address(stableDebtToken), address(dai));
        adai.rely(address(aavePool));
        vm.prank(address(adai)); dai.approve(address(aavePool), type(uint256).max);

        setPoolContract(address(pool = new D3MAaveV3NoSupplyCapTypePool("", address(hub), address(dai), address(aavePool))));
    }

    function test_sets_dai_value() public {
        assertEq(address(pool.dai()), address(dai));
    }

    function test_can_file_king() public {
        assertEq(pool.king(), address(0));

        pool.file("king", address(123));

        assertEq(pool.king(), address(123));
    }

    function test_cannot_file_king_no_auth() public {
        pool.deny(address(this));
        assertRevert(address(pool), abi.encodeWithSignature("file(bytes32,address)", bytes32("king"), address(123)), "D3MAaveV3NoSupplyCapTypePool/not-authorized");
    }

    function test_cannot_file_king_vat_caged() public {
        vat.cage();
        assertRevert(address(pool), abi.encodeWithSignature("file(bytes32,address)", bytes32("king"), address(123)), "D3MAaveV3NoSupplyCapTypePool/no-file-during-shutdown");
    }

    function test_deposit_calls_lending_pool_deposit() public {
        dai.mint(address(pool), 1);
        vm.prank(address(hub)); pool.deposit(1);
        (address asset, uint256 amt, address dst, uint256 code) = FakeLendingPool(address(aavePool)).lastDeposit();
        assertEq(asset, address(dai));
        assertEq(amt, 1);
        assertEq(dst, address(pool));
        assertEq(code, 0);
    }

    function test_withdraw_calls_lending_pool_withdraw() public {
        // make sure we have Dai to withdraw
        TokenMock(address(dai)).mint(address(adai), 1);

        vm.prank(address(hub)); pool.withdraw(1);
        (address asset, uint256 amt, address dst) = FakeLendingPool(address(aavePool)).lastWithdraw();
        assertEq(asset, address(dai));
        assertEq(amt, 1);
        assertEq(dst, address(hub));
    }

    function test_withdraw_calls_lending_pool_withdraw_vat_caged() public {
        // make sure we have Dai to withdraw
        TokenMock(address(dai)).mint(address(adai), 1);

        vat.cage();
        vm.prank(address(hub)); pool.withdraw(1);
        (address asset, uint256 amt, address dst) = FakeLendingPool(address(aavePool)).lastWithdraw();
        assertEq(asset, address(dai));
        assertEq(amt, 1);
        assertEq(dst, address(hub));
    }

    function test_collect_claims_for_king() public {
        address king = address(123);
        address rewardsClaimer = adai.getIncentivesController();
        pool.file("king", king);

        pool.collect(address(456));

        (uint256 amt, address dst, address reward) = FakeRewardsClaimer(rewardsClaimer).lastClaim();
        address[] memory assets = FakeRewardsClaimer(rewardsClaimer).getAssetsFromClaim();

        assertEq(address(adai), assets[0]);
        assertEq(amt, type(uint256).max);
        assertEq(dst, king);
        assertEq(reward, address(456));
    }

    function test_collect_no_king() public {
        assertEq(pool.king(), address(0));
        assertRevert(address(pool), abi.encodeWithSignature("collect(address)", address(0)), "D3MAaveV3NoSupplyCapTypePool/king-not-set");
    }

    function test_redeemable_returns_adai() public {
        assertEq(pool.redeemable(), address(adai));
    }

    function test_exit_adai() public {
        uint256 tokens = adai.totalSupply();
        adai.transfer(address(pool), tokens);
        assertEq(adai.balanceOf(address(this)), 0);
        assertEq(adai.balanceOf(address(pool)), tokens);

        end.setArt(tokens);
        vm.prank(address(hub)); pool.exit(address(this), tokens);

        assertEq(adai.balanceOf(address(this)), tokens);
        assertEq(adai.balanceOf(address(pool)), 0);
    }

    function test_quit_moves_balance() public {
        uint256 tokens = adai.totalSupply();
        adai.transfer(address(pool), tokens);
        assertEq(adai.balanceOf(address(this)), 0);
        assertEq(adai.balanceOf(address(pool)), tokens);

        pool.quit(address(this));

        assertEq(adai.balanceOf(address(this)), tokens);
        assertEq(adai.balanceOf(address(pool)), 0);
    }

    function test_assetBalance_gets_adai_balanceOf_pool() public {
        uint256 tokens = adai.totalSupply();
        assertEq(pool.assetBalance(), 0);
        assertEq(adai.balanceOf(address(pool)), 0);

        adai.transfer(address(pool), tokens);

        assertEq(pool.assetBalance(), tokens);
        assertEq(adai.balanceOf(address(pool)), tokens);
    }

    function test_maxWithdraw_gets_available_assets_assetBal() public {
        uint256 tokens = dai.totalSupply();
        dai.transfer(address(adai), tokens);
        assertEq(dai.balanceOf(address(adai)), tokens);
        assertEq(adai.balanceOf(address(pool)), 0);

        assertEq(pool.maxWithdraw(), 0);
    }

    function test_maxWithdraw_gets_available_assets_daiBal() public {
        uint256 tokens = adai.totalSupply();
        adai.transfer(address(pool), tokens);
        assertEq(dai.balanceOf(address(adai)), 0);
        assertEq(adai.balanceOf(address(pool)), tokens);

        assertEq(pool.maxWithdraw(), 0);
    }

    function test_maxDeposit_returns_max_uint() public {
        assertEq(pool.maxDeposit(), type(uint256).max);
    }

    function test_liquidityAvailable() public {
        dai.mint(address(adai), 100 ether);
        assertEq(dai.balanceOf(address(adai)), 100 ether);
        assertEq(pool.liquidityAvailable(), 100 ether);
    }

    function test_idleLiquidity() public {
        dai.mint(address(pool), 100 ether);
        vm.prank(address(hub)); pool.deposit(100 ether);
        assertEq(pool.idleLiquidity(), 100 ether);

        // Simulate a variable borrow
        aavePool.withdraw(address(dai), 50 ether, address(this));
        variableDebtToken.mint(address(this), 50 ether);

        assertEq(pool.idleLiquidity(), 50 ether);

        // Simulate a stable borrow
        aavePool.withdraw(address(dai), 25 ether, address(this));
        stableDebtToken.mint(address(this), 25 ether);

        assertEq(pool.idleLiquidity(), 25 ether);
    }
}
