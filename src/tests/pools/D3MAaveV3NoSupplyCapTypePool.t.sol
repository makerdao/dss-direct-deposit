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

import { D3MAaveV3NoSupplyCapTypePool, PoolLike } from "../../pools/D3MAaveV3NoSupplyCapTypePool.sol";

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
        result.aTokenAddress = adai;
        result.stableDebtTokenAddress = address(2);
        result.variableDebtTokenAddress = address(3);
        result.interestRateStrategyAddress = address(4);
    }

    function supply(address asset, uint256 amt, address forWhom, uint16 code) external {
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
}

contract D3MAaveV3NoSupplyCapTypePoolTest is D3MPoolBaseTest {

    AToken adai;
    FakeLendingPool aavePool;
    FakeEnd end;

    function setUp() public override {
        contractName = "D3MAaveV3NoSupplyCapTypePool";

        dai = DaiLike(address(new D3MTestGem(18)));
        adai = new AToken(18);
        aavePool = new FakeLendingPool(address(adai), address(dai));

        vat = address(new FakeVat());

        hub = address(new FakeHub(vat));
        end = FakeHub(hub).end();

        d3mTestPool = address(new D3MAaveV3NoSupplyCapTypePool("", hub, address(dai), address(aavePool)));
    }

    function test_sets_dai_value() public {
        assertEq(address(D3MAaveV3NoSupplyCapTypePool(d3mTestPool).dai()), address(dai));
    }

    function test_can_file_king() public {
        assertEq(D3MAaveV3NoSupplyCapTypePool(d3mTestPool).king(), address(0));

        D3MAaveV3NoSupplyCapTypePool(d3mTestPool).file("king", address(123));

        assertEq(D3MAaveV3NoSupplyCapTypePool(d3mTestPool).king(), address(123));
    }

    function test_cannot_file_king_no_auth() public {
        D3MAaveV3NoSupplyCapTypePool(d3mTestPool).deny(address(this));
        assertRevert(d3mTestPool, abi.encodeWithSignature("file(bytes32,address)", bytes32("king"), address(123)), "D3MAaveV3NoSupplyCapTypePool/not-authorized");
    }

    function test_cannot_file_king_vat_caged() public {
        FakeVat(vat).cage();
        assertRevert(d3mTestPool, abi.encodeWithSignature("file(bytes32,address)", bytes32("king"), address(123)), "D3MAaveV3NoSupplyCapTypePool/no-file-during-shutdown");
    }

    function test_deposit_calls_lending_pool_deposit() public {
        D3MTestGem(address(adai)).rely(address(aavePool));
        vm.prank(hub);
        D3MAaveV3NoSupplyCapTypePool(d3mTestPool).deposit(1);
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
        D3MAaveV3NoSupplyCapTypePool(d3mTestPool).withdraw(1);
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
        D3MAaveV3NoSupplyCapTypePool(d3mTestPool).withdraw(1);
        (address asset, uint256 amt, address dst) = FakeLendingPool(address(aavePool)).lastWithdraw();
        assertEq(asset, address(dai));
        assertEq(amt, 1);
        assertEq(dst, hub);
    }

    function test_collect_claims_for_king() public {
        address king = address(123);
        address rewardsClaimer = adai.getIncentivesController();
        D3MAaveV3NoSupplyCapTypePool(d3mTestPool).file("king", king);

        D3MAaveV3NoSupplyCapTypePool(d3mTestPool).collect(address(123));

        (uint256 amt, address dst, address reward) = FakeRewardsClaimer(rewardsClaimer).lastClaim();
        address[] memory assets = FakeRewardsClaimer(rewardsClaimer).getAssetsFromClaim();

        assertEq(address(adai), assets[0]);
        assertEq(amt, type(uint256).max);
        assertEq(dst, king);
        assertEq(reward, address(123));
    }

    function test_collect_no_king() public {
        assertEq(D3MAaveV3NoSupplyCapTypePool(d3mTestPool).king(), address(0));
        assertRevert(d3mTestPool, abi.encodeWithSignature("collect(address)", address(0)), "D3MAaveV3NoSupplyCapTypePool/king-not-set");
    }

    function test_redeemable_returns_adai() public {
        assertEq(D3MAaveV3NoSupplyCapTypePool(d3mTestPool).redeemable(), address(adai));
    }

    function test_exit_adai() public {
        uint256 tokens = adai.totalSupply();
        adai.transfer(d3mTestPool, tokens);
        assertEq(adai.balanceOf(address(this)), 0);
        assertEq(adai.balanceOf(d3mTestPool), tokens);

        end.setArt(tokens);
        vm.prank(hub);
        D3MAaveV3NoSupplyCapTypePool(d3mTestPool).exit(address(this), tokens);

        assertEq(adai.balanceOf(address(this)), tokens);
        assertEq(adai.balanceOf(d3mTestPool), 0);
    }

    function test_quit_moves_balance() public {
        uint256 tokens = adai.totalSupply();
        adai.transfer(d3mTestPool, tokens);
        assertEq(adai.balanceOf(address(this)), 0);
        assertEq(adai.balanceOf(d3mTestPool), tokens);

        D3MAaveV3NoSupplyCapTypePool(d3mTestPool).quit(address(this));

        assertEq(adai.balanceOf(address(this)), tokens);
        assertEq(adai.balanceOf(d3mTestPool), 0);
    }

    function test_assetBalance_gets_adai_balanceOf_pool() public {
        uint256 tokens = adai.totalSupply();
        assertEq(D3MAaveV3NoSupplyCapTypePool(d3mTestPool).assetBalance(), 0);
        assertEq(adai.balanceOf(d3mTestPool), 0);

        adai.transfer(d3mTestPool, tokens);

        assertEq(D3MAaveV3NoSupplyCapTypePool(d3mTestPool).assetBalance(), tokens);
        assertEq(adai.balanceOf(d3mTestPool), tokens);
    }

    function test_maxWithdraw_gets_available_assets_assetBal() public {
        uint256 tokens = dai.totalSupply();
        dai.transfer(address(adai), tokens);
        assertEq(dai.balanceOf(address(adai)), tokens);
        assertEq(adai.balanceOf(d3mTestPool), 0);

        assertEq(D3MAaveV3NoSupplyCapTypePool(d3mTestPool).maxWithdraw(), 0);
    }

    function test_maxWithdraw_gets_available_assets_daiBal() public {
        uint256 tokens = adai.totalSupply();
        adai.transfer(d3mTestPool, tokens);
        assertEq(dai.balanceOf(address(adai)), 0);
        assertEq(adai.balanceOf(d3mTestPool), tokens);

        assertEq(D3MAaveV3NoSupplyCapTypePool(d3mTestPool).maxWithdraw(), 0);
    }

    function test_maxDeposit_returns_max_uint() public {
        assertEq(D3MAaveV3NoSupplyCapTypePool(d3mTestPool).maxDeposit(), type(uint256).max);
    }
}
