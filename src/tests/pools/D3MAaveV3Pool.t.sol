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

import { Hevm, D3MPoolBaseTest, FakeHub, FakeVat, FakeEnd } from "./D3MPoolBase.t.sol";
import { DaiLike, TokenLike } from "../interfaces/interfaces.sol";
import { D3MTestGem } from "../stubs/D3MTestGem.sol";

import { D3MAaveV3Pool, PoolLike } from "../../pools/D3MAaveV3Pool.sol";

interface RewardsClaimerLike {
    function getRewardsBalance(address[] calldata assets, address user) external view returns (uint256);
}

contract AToken is D3MTestGem {
    address public rewardsClaimer;
    uint256 public scaledTotalSupply;

    constructor(uint256 decimals_) D3MTestGem(decimals_) {
        rewardsClaimer = address(new FakeRewardsClaimer());
    }

    function scaledBalanceOf(address who) external view returns (uint256) {
        return balanceOf[who];
    }

    function setScaledTotalSupply(uint256 amount) external {
        scaledTotalSupply = amount;
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

interface FlashLoanReceiverLike {
    function executeOperation(
        address,
        uint256,
        uint256,
        address,
        bytes calldata
    ) external returns (bool);
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
    address public dai;
    address public poolAdapter;
    uint256 public supplyCap;
    bool public flashLoanEnabled = true;
    uint256 public liquidityIndex = 10 ** 27;
    uint256 public accruedToTreasury;
    bool public flashLoanWasCalled;

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

    constructor(address adai_, address dai_) {
        adai = adai_;
        dai = dai_;
    }

    function getReserveData(address) external view returns(
        ReserveData memory result
    ) {
        result.configuration = supplyCap << 116 | uint256(flashLoanEnabled ? 1 : 0) << 63;
        result.aTokenAddress = adai;
        result.liquidityIndex = uint128(liquidityIndex);
        result.stableDebtTokenAddress = address(2);
        result.variableDebtTokenAddress = address(3);
        result.interestRateStrategyAddress = address(4);
        result.accruedToTreasury = uint128(accruedToTreasury);
    }

    function deposit(address asset, uint256 amt, address forWhom, uint16 code) external {
        lastDeposit = DepositCall(
            asset,
            amt,
            forWhom,
            code
        );
        D3MTestGem(adai).mint(forWhom, amt);
    }

    function withdraw(address asset, uint256 amt, address dst) external {
        lastWithdraw = WithdrawCall(
            asset,
            amt,
            dst
        );
        D3MTestGem(asset).transfer(dst, amt);
    }

    function getReserveNormalizedIncome(address asset) external pure returns (uint256) {
        asset;
        return 10 ** 27;
    }

    function setSupplyCap(uint256 cap) external {
        supplyCap = cap;
    }

    function setFlashLoanEnabled(bool on) external {
        flashLoanEnabled = on;
    }

    function setLiquidityIndex(uint256 index) external {
        liquidityIndex = index;
    }

    function setAccruedToTreasury(uint256 amt) external {
        accruedToTreasury = amt;
    }

    function setPoolAdapter(address a) external {
        poolAdapter = a;
    }

    function flashLoanSimple(address receiverAddress, address asset, uint256 amount, bytes calldata params, uint16 referralCode) external {
        flashLoanWasCalled = true;
        require(receiverAddress == poolAdapter, "receiverAddress");
        require(asset == dai, "asset");
        require(amount == 1, "amount");
        require(params.length == 0, "params");
        require(referralCode == 0, "referralCode");
        require(FlashLoanReceiverLike(receiverAddress).executeOperation(address(0), 0, 0, address(0), ""), "bad return");
    }
}

contract D3MAaveV3PoolTest is D3MPoolBaseTest {

    AToken adai;
    FakeLendingPool aavePool;
    FakeEnd end;

    function setUp() public override {
        contractName = "D3MAaveV3Pool";

        dai = DaiLike(address(new D3MTestGem(18)));
        adai = new AToken(18);
        aavePool = new FakeLendingPool(address(adai), address(dai));

        vat = address(new FakeVat());

        hub = address(new FakeHub(vat));
        end = FakeHub(hub).end();

        d3mTestPool = address(new D3MAaveV3Pool("", hub, address(dai), address(aavePool)));
        aavePool.setPoolAdapter(d3mTestPool);
    }

    function test_sets_dai_value() public {
        assertEq(address(D3MAaveV3Pool(d3mTestPool).dai()), address(dai));
    }

    function test_can_file_king() public {
        assertEq(D3MAaveV3Pool(d3mTestPool).king(), address(0));

        D3MAaveV3Pool(d3mTestPool).file("king", address(123));

        assertEq(D3MAaveV3Pool(d3mTestPool).king(), address(123));
    }

    function test_cannot_file_king_no_auth() public {
        D3MAaveV3Pool(d3mTestPool).deny(address(this));
        assertRevert(d3mTestPool, abi.encodeWithSignature("file(bytes32,address)", bytes32("king"), address(123)), "D3MAaveV3Pool/not-authorized");
    }

    function test_cannot_file_king_vat_caged() public {
        FakeVat(vat).cage();
        assertRevert(d3mTestPool, abi.encodeWithSignature("file(bytes32,address)", bytes32("king"), address(123)), "D3MAaveV3Pool/no-file-during-shutdown");
    }

    function test_deposit_calls_lending_pool_deposit() public {
        D3MTestGem(address(adai)).rely(address(aavePool));
        vm.prank(hub);
        D3MAaveV3Pool(d3mTestPool).deposit(1);
        (address asset, uint256 amt, address dst, uint256 code) = FakeLendingPool(address(aavePool)).lastDeposit();
        assertEq(asset, address(dai));
        assertEq(amt, 1);
        assertEq(dst, d3mTestPool);
        assertEq(code, 0);
    }

    function test_withdraw_calls_lending_pool_withdraw() public {
        // make sure we have Dai to withdraw
        D3MTestGem(address(dai)).mint(address(aavePool), 1);

        vm.prank(hub);
        D3MAaveV3Pool(d3mTestPool).withdraw(1);
        (address asset, uint256 amt, address dst) = FakeLendingPool(address(aavePool)).lastWithdraw();
        assertEq(asset, address(dai));
        assertEq(amt, 1);
        assertEq(dst, hub);
    }

    function test_withdraw_calls_lending_pool_withdraw_vat_caged() public {
        // make sure we have Dai to withdraw
        D3MTestGem(address(dai)).mint(address(aavePool), 1);

        FakeVat(vat).cage();
        vm.prank(hub);
        D3MAaveV3Pool(d3mTestPool).withdraw(1);
        (address asset, uint256 amt, address dst) = FakeLendingPool(address(aavePool)).lastWithdraw();
        assertEq(asset, address(dai));
        assertEq(amt, 1);
        assertEq(dst, hub);
    }

    function test_collect_claims_for_king() public {
        address king = address(123);
        address rewardsClaimer = adai.getIncentivesController();
        D3MAaveV3Pool(d3mTestPool).file("king", king);

        D3MAaveV3Pool(d3mTestPool).collect(address(123));

        (uint256 amt, address dst, address reward) = FakeRewardsClaimer(rewardsClaimer).lastClaim();
        address[] memory assets = FakeRewardsClaimer(rewardsClaimer).getAssetsFromClaim();

        assertEq(address(adai), assets[0]);
        assertEq(amt, type(uint256).max);
        assertEq(dst, king);
        assertEq(reward, address(123));
    }

    function test_collect_no_king() public {
        assertEq(D3MAaveV3Pool(d3mTestPool).king(), address(0));
        assertRevert(d3mTestPool, abi.encodeWithSignature("collect(address)", address(0)), "D3MAaveV3Pool/king-not-set");
    }

    function test_redeemable_returns_adai() public {
        assertEq(D3MAaveV3Pool(d3mTestPool).redeemable(), address(adai));
    }

    function test_exit_adai() public {
        uint256 tokens = adai.totalSupply();
        adai.transfer(d3mTestPool, tokens);
        assertEq(adai.balanceOf(address(this)), 0);
        assertEq(adai.balanceOf(d3mTestPool), tokens);

        end.setArt(tokens);
        vm.prank(hub);
        D3MAaveV3Pool(d3mTestPool).exit(address(this), tokens);

        assertEq(adai.balanceOf(address(this)), tokens);
        assertEq(adai.balanceOf(d3mTestPool), 0);
    }

    function test_quit_moves_balance() public {
        uint256 tokens = adai.totalSupply();
        adai.transfer(d3mTestPool, tokens);
        assertEq(adai.balanceOf(address(this)), 0);
        assertEq(adai.balanceOf(d3mTestPool), tokens);

        D3MAaveV3Pool(d3mTestPool).quit(address(this));

        assertEq(adai.balanceOf(address(this)), tokens);
        assertEq(adai.balanceOf(d3mTestPool), 0);
    }

    function test_assetBalance_gets_adai_balanceOf_pool() public {
        uint256 tokens = adai.totalSupply();
        assertEq(D3MAaveV3Pool(d3mTestPool).assetBalance(), 0);
        assertEq(adai.balanceOf(d3mTestPool), 0);

        adai.transfer(d3mTestPool, tokens);

        assertEq(D3MAaveV3Pool(d3mTestPool).assetBalance(), tokens);
        assertEq(adai.balanceOf(d3mTestPool), tokens);
    }

    function test_maxWithdraw_gets_available_assets_assetBal() public {
        uint256 tokens = dai.totalSupply();
        dai.transfer(address(adai), tokens);
        assertEq(dai.balanceOf(address(adai)), tokens);
        assertEq(adai.balanceOf(d3mTestPool), 0);

        assertEq(D3MAaveV3Pool(d3mTestPool).maxWithdraw(), 0);
    }

    function test_maxWithdraw_gets_available_assets_daiBal() public {
        uint256 tokens = adai.totalSupply();
        adai.transfer(d3mTestPool, tokens);
        assertEq(dai.balanceOf(address(adai)), 0);
        assertEq(adai.balanceOf(d3mTestPool), tokens);

        assertEq(D3MAaveV3Pool(d3mTestPool).maxWithdraw(), 0);
    }

    function test_maxDeposit_returns_max_uint() public {
        assertEq(D3MAaveV3Pool(d3mTestPool).maxDeposit(), type(uint256).max);
    }

    function test_maxDeposit_supply_cap_active() public {
        aavePool.setSupplyCap(100);
        assertEq(D3MAaveV3Pool(d3mTestPool).maxDeposit(), 100 ether);
    }

    function test_maxDeposit_supply_cap_adai_scaledTotalSupply() public {
        aavePool.setSupplyCap(100);
        adai.setScaledTotalSupply(50 ether);
        assertEq(D3MAaveV3Pool(d3mTestPool).maxDeposit(), 50 ether);
    }

    function test_maxDeposit_supply_cap_accruedToTreasury() public {
        aavePool.setSupplyCap(100);
        aavePool.setAccruedToTreasury(50 ether);
        assertEq(D3MAaveV3Pool(d3mTestPool).maxDeposit(), 50 ether);
    }

    function test_maxDeposit_supply_cap_liquidityIndex() public {
        aavePool.setSupplyCap(100);
        adai.setScaledTotalSupply(25 ether);
        aavePool.setLiquidityIndex(2 * RAY);    // 100% interest accrued
        assertEq(D3MAaveV3Pool(d3mTestPool).maxDeposit(), 50 ether);
    }

    function test_maxDeposit_supply_cap_over_limit() public {
        aavePool.setSupplyCap(100);
        adai.setScaledTotalSupply(150 ether);
        assertEq(D3MAaveV3Pool(d3mTestPool).maxDeposit(), 0);
    }

    function test_preDebtChange_flashLoanCalled() public {
        aavePool.setSupplyCap(100);
        _giveTokens(dai, 100 ether);
        dai.transfer(address(adai), 100 ether);
        assertEq(aavePool.flashLoanEnabled(), true);
        D3MAaveV3Pool(d3mTestPool).preDebtChange();
        assertEq(aavePool.flashLoanWasCalled(), true);
    }

    function test_preDebtChange_no_flashLoanCalled_supplyCap() public {
        aavePool.setSupplyCap(0);
        _giveTokens(dai, 100 ether);
        dai.transfer(address(adai), 100 ether);
        assertEq(aavePool.flashLoanEnabled(), true);
        D3MAaveV3Pool(d3mTestPool).preDebtChange();
        assertEq(aavePool.flashLoanWasCalled(), false);
    }

    function test_preDebtChange_no_flashLoanCalled_no_liquidity() public {
        aavePool.setSupplyCap(100);
        assertEq(dai.balanceOf(address(adai)), 0);
        assertEq(aavePool.flashLoanEnabled(), true);
        D3MAaveV3Pool(d3mTestPool).preDebtChange();
        assertEq(aavePool.flashLoanWasCalled(), false);
    }

    function test_preDebtChange_no_flashLoanCalled_flashloan_disabled() public {
        aavePool.setSupplyCap(100);
        _giveTokens(dai, 100 ether);
        dai.transfer(address(adai), 100 ether);
        aavePool.setFlashLoanEnabled(false);
        D3MAaveV3Pool(d3mTestPool).preDebtChange();
        assertEq(aavePool.flashLoanWasCalled(), false);
    }
}
