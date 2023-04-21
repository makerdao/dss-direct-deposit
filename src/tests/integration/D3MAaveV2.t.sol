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

import "dss-test/DssTest.sol";
import "dss-interfaces/Interfaces.sol";

import { D3MHub } from "../../D3MHub.sol";
import { D3MMom } from "../../D3MMom.sol";
import { D3MOracle } from "../../D3MOracle.sol";
import { D3MForwardFees } from "../../fees/D3MForwardFees.sol";

import { D3MAaveV2TypeRateTargetPlan } from "../../plans/D3MAaveV2TypeRateTargetPlan.sol";
import { D3MAaveV2TypePool } from "../../pools/D3MAaveV2TypePool.sol";

interface LendingPoolLike {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external;
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
    function getMaxVariableBorrowRate() external view returns (uint256);
    function calculateInterestRates(
        address reserve,
        uint256 availableLiquidity,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 averageStableBorrowRate,
        uint256 reserveFactor
    ) external returns (
        uint256,
        uint256,
        uint256
    );
}

interface AGemAbstract is GemAbstract {
    function scaledBalanceOf(address) external view returns (uint256);
}

interface RewardsClaimerLike {
    function getRewardsBalance(address[] calldata assets, address user) external view returns (uint256);
}

contract D3MAaveV2IntegrationTest is DssTest {

    using GodMode for *;

    VatAbstract vat;
    EndAbstract end;
    LendingPoolLike aavePool;
    InterestRateStrategyLike interestStrategy;
    RewardsClaimerLike rewardsClaimer;
    DaiAbstract dai;
    DaiJoinAbstract daiJoin;
    AGemAbstract adai;
    GemAbstract stkAave;
    SpotAbstract spot;
    GemAbstract weth;
    address vow;
    address pauseProxy;

    bytes32 constant ilk = "DD-DAI-A";
    D3MHub d3mHub;
    D3MAaveV2TypePool d3mAavePool;
    D3MAaveV2TypeRateTargetPlan d3mAavePlan;
    D3MMom d3mMom;
    D3MOracle pip;

    // Allow for a 1 BPS margin of error on interest rates
    uint256 constant INTEREST_RATE_TOLERANCE = RAY / 10000;
    uint256 constant EPSILON_TOLERANCE = 4;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        vat = VatAbstract(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        end = EndAbstract(0x0e2e8F1D1326A4B9633D96222Ce399c708B19c28);
        aavePool = LendingPoolLike(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        adai = AGemAbstract(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
        stkAave = GemAbstract(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
        dai = DaiAbstract(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        daiJoin = DaiJoinAbstract(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
        interestStrategy = InterestRateStrategyLike(0xfffE32106A68aA3eD39CcCE673B646423EEaB62a);
        rewardsClaimer = RewardsClaimerLike(0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5);
        spot = SpotAbstract(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);
        weth = GemAbstract(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        vow = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;
        pauseProxy = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

        // Force give admin access to these contracts via vm magic
        address(vat).setWard(address(this), 1);
        address(end).setWard(address(this), 1);
        address(spot).setWard(address(this), 1);

        d3mHub = new D3MHub(address(daiJoin));
        d3mAavePool = new D3MAaveV2TypePool(ilk, address(d3mHub), address(dai), address(aavePool));
        d3mAavePool.rely(address(d3mHub));
        d3mAavePlan = new D3MAaveV2TypeRateTargetPlan(address(dai), address(aavePool));

        d3mHub.file(ilk, "pool", address(d3mAavePool));
        d3mHub.file(ilk, "plan", address(d3mAavePlan));
        d3mHub.file(ilk, "fees", address(new D3MForwardFees(address(vat), address(vow))));
        d3mHub.file(ilk, "tau", 7 days);

        d3mHub.file("vow", vow);
        d3mHub.file("end", address(end));

        // d3mAavePool.rely(address(d3mHub));

        d3mMom = new D3MMom();
        d3mAavePlan.rely(address(d3mMom));

        // Init new collateral
        pip = new D3MOracle(address(vat), ilk);
        pip.file("hub", address(d3mHub));
        spot.file(ilk, "pip", address(pip));
        spot.file(ilk, "mat", RAY);
        spot.poke(ilk);

        vat.rely(address(d3mHub));
        vat.init(ilk);
        vat.file(ilk, "line", 5_000_000_000 * RAD);
        vat.file("Line", vat.Line() + 5_000_000_000 * RAD);

        // Give us a bunch of WETH and deposit into Aave
        uint256 amt = 1_000_000 * WAD;
        address(weth).setBalance(address(this), amt);
        weth.approve(address(aavePool), type(uint256).max);
        dai.approve(address(aavePool), type(uint256).max);
        aavePool.deposit(address(weth), amt, address(this), 0);
    }

    // --- Math ---
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }

    function assertEqApprox(uint256 _a, uint256 _b, uint256 _tolerance) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > _tolerance) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function assertEqInterest(uint256 _a, uint256 _b) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > INTEREST_RATE_TOLERANCE) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_decimal_uint("  Expected", _b, 27);
            emit log_named_decimal_uint("    Actual", _a, 27);
            fail();
        }
    }

    // aTOKENs round against the depositor - we allow a rounding error of 1
    function assertEqRoundingAgainst(uint256 _a, uint256 _b) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > 1) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_decimal_uint("  Expected", _b, 27);
            emit log_named_decimal_uint("    Actual", _a, 27);
            fail();
        }
    }

    function getBorrowRate() public view returns (uint256 borrowRate) {
        (,,,, borrowRate,,,,,,,) = aavePool.getReserveData(address(dai));
    }

    // Set the borrow rate to a relative percent to what it currently is
    function _setRelBorrowTarget(uint256 deltaBPS) internal returns (uint256 targetBorrowRate) {
        targetBorrowRate = getBorrowRate() * deltaBPS / 10000;
        d3mAavePlan.file("bar", targetBorrowRate);
        d3mHub.exec(ilk);
    }

    function test_target_decrease() public {
        uint256 targetBorrowRate = _setRelBorrowTarget(7500);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        uint256 amountMinted = adai.balanceOf(address(d3mAavePool));
        assertTrue(amountMinted > 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertEqRoundingAgainst(ink, amountMinted);    // We allow a rounding error of 1 because aTOKENs round against the user
        assertEqRoundingAgainst(art, amountMinted);
        assertEq(vat.gem(ilk, address(d3mAavePool)), 0);
        assertEq(vat.dai(address(d3mHub)), 0);
    }

    function test_target_increase() public {
        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Raise by 25%
        targetBorrowRate = _setRelBorrowTarget(12500);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        uint256 amountMinted = adai.balanceOf(address(d3mAavePool));
        assertTrue(amountMinted > 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertEqRoundingAgainst(ink, amountMinted);    // We allow a rounding error of 1 because aTOKENs round against the user
        assertEqRoundingAgainst(art, amountMinted);
        assertEq(vat.gem(ilk, address(d3mAavePool)), 0);
        assertEq(vat.dai(address(d3mAavePool)), 0);
    }

    function test_bar_zero() public {
        uint256 targetBorrowRate = _setRelBorrowTarget(7500);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertGt(ink, 0);
        assertGt(art, 0);

        // Temporarily disable the module
        d3mAavePlan.file("bar", 0);
        d3mHub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(d3mAavePool));
        assertEqRoundingAgainst(ink, 0);
        assertEqRoundingAgainst(art, 0);
    }

    function test_target_increase_insufficient_liquidity() public {
        uint256 currBorrowRate = getBorrowRate();

        // Attempt to increase by 25% (you can't)
        _setRelBorrowTarget(12500);
        assertEqInterest(getBorrowRate(), currBorrowRate);  // Unchanged

        assertEq(adai.balanceOf(address(d3mAavePool)), 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(d3mAavePool)), 0);
        assertEq(vat.dai(address(d3mHub)), 0);
    }

    function test_cage_temp_insufficient_liquidity() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(d3mAavePool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        aavePool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // Cage the system and start unwinding
        currentLiquidity = dai.balanceOf(address(adai));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mAavePool));
        d3mHub.cage(ilk);
        d3mHub.exec(ilk);

        // Should be no dai liquidity remaining as we attempt to fully unwind
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertTrue(ink > 0);
        assertTrue(art > 0);
        assertEqApprox(pink - ink, currentLiquidity, 1);
        assertEqApprox(part - art, currentLiquidity, 1);
        assertEq(dai.balanceOf(address(adai)), 0);
        assertEq(getBorrowRate(), interestStrategy.getMaxVariableBorrowRate());

        // Someone else repays some Dai so we can unwind the rest
        vm.warp(block.timestamp + 1 days);
        aavePool.repay(address(dai), amountToBorrow, 2, address(this));

        d3mHub.exec(ilk);
        assertEq(adai.balanceOf(address(d3mAavePool)), 0);
        assertTrue(dai.balanceOf(address(adai)) > 0);
        (ink, art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function test_cage_perm_insufficient_liquidity() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(d3mAavePool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        aavePool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // Cage the system and start unwinding
        currentLiquidity = dai.balanceOf(address(adai));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mAavePool));
        d3mHub.cage(ilk);
        d3mHub.exec(ilk);

        // Should be no dai liquidity remaining as we attempt to fully unwind
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertTrue(ink > 0);
        assertTrue(art > 0);
        assertEqApprox(pink - ink, currentLiquidity, 1);
        assertEqApprox(part - art, currentLiquidity, 1);
        assertEq(dai.balanceOf(address(adai)), 0);
        assertEq(getBorrowRate(), interestStrategy.getMaxVariableBorrowRate());

        // In this case nobody deposits more DAI so we have to write off the bad debt
        vm.warp(block.timestamp + 7 days);

        uint256 sin = vat.sin(vow);
        uint256 vowDai = vat.dai(vow);
        d3mHub.cull(ilk);
        (uint256 ink2, uint256 art2) = vat.urns(ilk, address(d3mAavePool));
        (, , , , uint256 culled, ) = d3mHub.ilks(ilk);
        assertEq(culled, 1);
        assertEq(ink2, 0);
        assertEq(art2, 0);
        assertEq(vat.gem(ilk, address(d3mAavePool)), ink);
        assertEq(vat.sin(vow), sin + art * RAY);
        assertEq(vat.dai(vow), vowDai);

        // Some time later the pool gets some liquidity
        vm.warp(block.timestamp + 180 days);
        aavePool.repay(address(dai), amountToBorrow, 2, address(this));

        // Close out the remainder of the position
        uint256 adaiBalance = adai.balanceOf(address(d3mAavePool));
        assertTrue(adaiBalance >= art);
        d3mHub.exec(ilk);
        assertEq(adai.balanceOf(address(d3mAavePool)), 0);
        assertTrue(dai.balanceOf(address(adai)) > 0);
        assertEq(vat.sin(vow), sin + art * RAY);
        assertEq(vat.dai(vow), vowDai + adaiBalance * RAY);
        assertEq(vat.gem(ilk, address(d3mAavePool)), 0);
    }

    function test_hit_debt_ceiling() public {
        // Lower the debt ceiling to 100k
        uint256 debtCeiling = 100_000 * WAD;
        vat.file(ilk, "line", debtCeiling * RAY);

        uint256 currBorrowRate = getBorrowRate();

        // Set a super low target interest rate
        uint256 targetBorrowRate = _setRelBorrowTarget(1);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertTrue(getBorrowRate() > targetBorrowRate && getBorrowRate() < currBorrowRate);
        assertEqRoundingAgainst(adai.balanceOf(address(d3mAavePool)), debtCeiling);    // We allow a rounding error of 1 because aTOKENs round against the user

        // Should be a no-op
        d3mHub.exec(ilk);
        (ink, art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertEqRoundingAgainst(adai.balanceOf(address(d3mAavePool)), debtCeiling);

        // Raise it by a bit
        currBorrowRate = getBorrowRate();
        debtCeiling = 125_000 * WAD;
        vat.file(ilk, "line", debtCeiling * RAY);
        d3mHub.exec(ilk);
        (ink, art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertTrue(getBorrowRate() > targetBorrowRate && getBorrowRate() < currBorrowRate);
        assertEqRoundingAgainst(adai.balanceOf(address(d3mAavePool)), debtCeiling);    // We allow a rounding error of 1 because aTOKENs round against the user
    }

    function test_collect_interest() public {
        _setRelBorrowTarget(7500);

        vm.warp(block.timestamp + 1 days);     // Collect one day of interest

        uint256 vowDai = vat.dai(vow);
        d3mHub.exec(ilk);

        assertGt(vat.dai(vow) - vowDai, 0);
    }

    function test_insufficient_liquidity_for_unwind_fees() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));
        uint256 vowDai = vat.dai(vow);

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        uint256 pAssets = adai.balanceOf(address(d3mAavePool));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mAavePool));
        assertEq(pink, part);
        assertEqApprox(pink, pAssets, 1);

        // Someone else borrows the exact amount previously available
        (uint256 amountSupplied,) = vat.urns(ilk, address(d3mAavePool));
        uint256 amountToBorrow = currentLiquidity;
        aavePool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // Accumulate a bunch of interest
        vm.warp(block.timestamp + 180 days);

        uint256 feesAccrued = adai.balanceOf(address(d3mAavePool)) - pAssets;

        currentLiquidity = dai.balanceOf(address(adai));
        assertGt(feesAccrued, 0);
        assertEq(amountSupplied, currentLiquidity);
        assertGt(amountSupplied + feesAccrued, currentLiquidity);

        // Cage the system to trigger only unwinds
        d3mHub.cage(ilk);
        d3mHub.exec(ilk);

        uint256 assets = adai.balanceOf(address(d3mAavePool));
        // All the fees are accrued but what can't be withdrawn is added up to the original ink and art debt
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, art);
        assertEqApprox(ink, assets, 1);
        assertGt(adai.balanceOf(address(d3mAavePool)), 0);
        assertEqApprox(ink, pink + feesAccrued - currentLiquidity, 1);
        assertEqApprox(vat.dai(vow), vowDai + feesAccrued * RAY, RAY);

        // Someone repays
        aavePool.repay(address(dai), amountToBorrow, 2, address(this));
        d3mHub.exec(ilk);

        // Now the CDP completely unwinds and surplus buffer doesn't change
        (ink, art) = vat.urns(ilk, address(d3mAavePool));
        assertEqApprox(ink, 0, 1);
        assertEqApprox(art, 0, 1);
        assertEq(adai.balanceOf(address(d3mAavePool)), 0);
        assertEqApprox(vat.dai(vow), vowDai + feesAccrued * RAY, 2 * RAY); // rounding may affect twice
    }

    function test_insufficient_liquidity_for_exec_fees() public {
        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        uint256 pAssets = adai.balanceOf(address(d3mAavePool));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mAavePool));
        assertEq(pink, part);
        assertEqApprox(pink, pAssets, 1);

        // Accumulate a bunch of interest
        vm.warp(block.timestamp + 180 days);

        // Someone else borrows almost all the liquidity
        aavePool.borrow(address(dai), dai.balanceOf(address(adai)) - 100 * WAD, 2, 0, address(this));
        assertEq(dai.balanceOf(address(adai)), 100 * WAD);

        uint256 feesAccrued = adai.balanceOf(address(d3mAavePool)) - pAssets;
        assertGt(feesAccrued, 100 * WAD);

        // Accrue fees
        uint256 vowDai = vat.dai(vow);
        d3mAavePlan.file("bar", 0); // So we make sure to unwind after rebalancing
        d3mHub.exec(ilk);

        uint256 assets = adai.balanceOf(address(d3mAavePool));
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, art);
        assertEqApprox(ink, assets, 1);
        assertEqApprox(ink, pink + feesAccrued - 100 * WAD, 1);
        assertEqApprox(vat.dai(vow), vowDai + feesAccrued * RAY, RAY);
    }

    function test_unwind_mcd_caged_not_skimmed() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mAavePool));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(d3mAavePool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        aavePool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        // CDP still has the position built
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertGt(ink, 0);
        assertGt(art, 0);
        assertEq(vat.gem(ilk, address(end)), 0);

        uint256 prevSin = vat.sin(vow);
        uint256 prevDai = vat.dai(vow);
        assertEq(prevSin, 0);
        assertGt(prevDai, 0);

        // We try to unwind what is possible
        d3mHub.exec(ilk);
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        // exec() moved the remaining urn debt to the end
        (ink, art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(end)), amountSupplied / 2); // Automatically skimmed when unwinding
        if (prevSin + (amountSupplied / 2) * RAY >= prevDai) {
            assertEqApprox(vat.sin(vow), prevSin + (amountSupplied / 2) * RAY - prevDai, RAY);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqApprox(vat.dai(vow), prevDai - prevSin - (amountSupplied / 2) * RAY, RAY);
            assertEq(vat.sin(vow), 0);
        }

        // Some time later the pool gets some liquidity
        vm.warp(block.timestamp + 180 days);
        aavePool.repay(address(dai), amountToBorrow, 2, address(this));

        // Rest of the liquidity can be withdrawn
        d3mHub.exec(ilk);
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(vat.sin(vow), 0);
        assertGe(vat.dai(vow), prevDai); // As also probably accrues interest from aDai
    }

    function test_unwind_mcd_caged_skimmed() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mAavePool));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(d3mAavePool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        aavePool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        // CDP still has the position built
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertGt(ink, 0);
        assertGt(art, 0);
        assertEq(vat.gem(ilk, address(end)), 0);

        uint256 prevSin = vat.sin(vow);
        uint256 prevDai = vat.dai(vow);
        assertEq(prevSin, 0);
        assertGt(prevDai, 0);

        // Position is taken by the End module
        end.skim(ilk, address(d3mAavePool));
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));
        (ink, art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(end)), pink);
        if (prevSin + amountSupplied * RAY >= prevDai) {
            assertEqApprox(vat.sin(vow), prevSin + amountSupplied * RAY - prevDai, RAY);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqApprox(vat.dai(vow), prevDai - prevSin - amountSupplied * RAY, RAY);
            assertEq(vat.sin(vow), 0);
        }

        // We try to unwind what is possible
        d3mHub.exec(ilk);
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        // Part can't be done yet
        assertEq(vat.gem(ilk, address(end)), amountSupplied / 2);
        if (prevSin + (amountSupplied / 2) * RAY >= prevDai) {
            assertEqApprox(vat.sin(vow), prevSin + (amountSupplied / 2) * RAY - prevDai, RAY);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqApprox(vat.dai(vow), prevDai - prevSin - (amountSupplied / 2) * RAY, RAY);
            assertEq(vat.sin(vow), 0);
        }

        // Some time later the pool gets some liquidity
        vm.warp(block.timestamp + 180 days);
        aavePool.repay(address(dai), amountToBorrow, 2, address(this));

        // Rest of the liquidity can be withdrawn
        d3mHub.exec(ilk);
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(vat.sin(vow), 0);
        assertGe(vat.dai(vow), prevDai); // As also probably accrues interest from aDai
    }

    function test_unwind_mcd_caged_wait_done() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mAavePool));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(d3mAavePool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        aavePool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        vm.warp(block.timestamp + end.wait());

        // Force remove all the dai from vow so it can call end.thaw()
        vm.store(
            address(vat),
            keccak256(abi.encode(address(vow), uint256(5))),
            bytes32(0)
        );

        end.thaw();

        assertRevert(address(d3mHub), abi.encodeWithSignature("exec(bytes32)", ilk), "D3MHub/end-debt-already-set");
    }

    function test_unwind_culled_then_mcd_caged() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mAavePool));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(d3mAavePool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        aavePool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        d3mHub.cage(ilk);

        (, , , uint256 tau, , ) = d3mHub.ilks(ilk);

        vm.warp(block.timestamp + tau);

        uint256 daiEarned = adai.balanceOf(address(d3mAavePool)) - pink;

        VowAbstract(vow).heal(
            _min(
                vat.sin(vow) - VowAbstract(vow).Sin() - VowAbstract(vow).Ash(),
                vat.dai(vow)
            )
        );
        uint256 originalSin = vat.sin(vow);
        uint256 originalDai = vat.dai(vow);
        // If the whole Sin queue would be cleant by someone,
        // originalSin should be 0 as there is more profit than debt registered
        assertGt(originalDai, originalSin);
        assertGt(originalSin, 0);

        d3mHub.cull(ilk);

        // After cull, the debt of the position is converted to bad debt
        assertEq(vat.sin(vow), originalSin + part * RAY);

        // CDP grabbed and ink moved as free collateral to the deposit contract
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(d3mAavePool)), pink);
        assertGe(adai.balanceOf(address(d3mAavePool)), pink);

        // MCD shutdowns
        originalDai = originalDai + vat.dai(VowAbstract(vow).flapper());
        end.cage();

        if (originalSin + part * RAY >= originalDai) {
            assertEq(vat.sin(vow), originalSin + part * RAY - originalDai);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEq(vat.dai(vow), originalDai - originalSin - part * RAY);
            assertEq(vat.sin(vow), 0);
        }

        d3mHub.uncull(ilk);
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        end.cage(ilk);

        // So the position is restablished
        (ink, art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, pink);
        assertEq(art, part);
        assertEq(vat.gem(ilk, address(d3mAavePool)), 0);
        assertGe(adai.balanceOf(address(d3mAavePool)), pink);
        assertEq(vat.sin(vow), 0);

        // Call skim manually (will be done through deposit anyway)
        // Position is again taken but this time the collateral goes to the End module
        end.skim(ilk, address(d3mAavePool));
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        (ink, art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(d3mAavePool)), 0);
        assertEq(vat.gem(ilk, address(end)), pink);
        assertGe(adai.balanceOf(address(d3mAavePool)), pink);
        if (originalSin + part * RAY >= originalDai) {
            assertEqApprox(vat.sin(vow), originalSin + part * RAY - originalDai, RAY);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqApprox(vat.dai(vow), originalDai - originalSin - part * RAY, RAY);
            assertEq(vat.sin(vow), 0);
        }

        // We try to unwind what is possible
        d3mHub.exec(ilk);
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        // A part can't be unwind yet
        assertEq(vat.gem(ilk, address(end)), amountSupplied / 2);
        assertGt(adai.balanceOf(address(d3mAavePool)), amountSupplied / 2);
        if (originalSin + part * RAY >= originalDai + (amountSupplied / 2) * RAY) {
            // rounding may affect twice, and multiplied by RAY to be compared with sin
            assertEqApprox(vat.sin(vow), originalSin + part * RAY - originalDai - (amountSupplied / 2) * RAY, (2 * RAY));
            assertEq(vat.dai(vow), 0);
        } else {
            // rounding may affect twice, and multiplied by RAY to be compared with sin
            assertEqApprox(vat.dai(vow), originalDai + (amountSupplied / 2) * RAY - originalSin - part * RAY, (2 * RAY));
            assertEq(vat.sin(vow), 0);
        }

        // Then pool gets some liquidity
        aavePool.repay(address(dai), amountToBorrow, 2, address(this));

        // Rest of the liquidity can be withdrawn
        d3mHub.exec(ilk);
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(adai.balanceOf(address(d3mAavePool)), 0);
        assertEq(vat.sin(vow), 0);
        assertEqApprox(vat.dai(vow), originalDai - originalSin + daiEarned * RAY, RAY);
    }

    function test_uncull_not_culled() public {
        // Lower by 50%
        _setRelBorrowTarget(5000);
        d3mHub.cage(ilk);

        // MCD shutdowns
        end.cage();

        assertRevert(address(d3mHub), abi.encodeWithSignature("uncull(bytes32)", ilk), "D3MHub/not-prev-culled");
    }

    function test_uncull_not_shutdown() public {
        // Lower by 50%
        _setRelBorrowTarget(5000);
        d3mHub.cage(ilk);

        (, , , uint256 tau, , ) = d3mHub.ilks(ilk);
        vm.warp(block.timestamp + tau);

        d3mHub.cull(ilk);

        assertRevert(address(d3mHub), abi.encodeWithSignature("uncull(bytes32)", ilk), "D3MHub/no-uncull-normal-operation");
    }

    function test_collect_stkaave() public {
        _setRelBorrowTarget(7500);

        vm.warp(block.timestamp + 1 days);

        // Set the king
        d3mAavePool.file("king", address(pauseProxy));

        // Collect some stake rewards into the pause proxy
        address[] memory tokens = new address[](1);
        tokens[0] = address(adai);
        uint256 amountToClaim = rewardsClaimer.getRewardsBalance(tokens, address(d3mHub));
        if (amountToClaim == 0) return;     // Rewards are turned off - this is still an acceptable state
        uint256 amountClaimed = d3mAavePool.collect();
        assertEq(amountClaimed, amountToClaim);
        assertEq(stkAave.balanceOf(address(pauseProxy)), amountClaimed);
        assertEq(rewardsClaimer.getRewardsBalance(tokens, address(d3mHub)), 0);

        vm.warp(block.timestamp + 1 days);

        // Collect some more rewards
        uint256 amountToClaim2 = rewardsClaimer.getRewardsBalance(tokens, address(d3mHub));
        assertGt(amountToClaim2, 0);
        uint256 amountClaimed2 = d3mAavePool.collect();
        assertEq(amountClaimed2, amountToClaim2);
        assertEq(stkAave.balanceOf(address(pauseProxy)), amountClaimed + amountClaimed2);
        assertEq(rewardsClaimer.getRewardsBalance(tokens, address(d3mHub)), 0);
    }

    function test_collect_stkaave_king_not_set() public {
        _setRelBorrowTarget(7500);

        vm.warp(block.timestamp + 1 days);

        // Collect some stake rewards into the pause proxy
        address[] memory tokens = new address[](1);
        tokens[0] = address(adai);
        rewardsClaimer.getRewardsBalance(tokens, address(d3mAavePool));

        assertEq(d3mAavePool.king(), address(0));

        assertRevert(address(d3mAavePool), abi.encodeWithSignature("collect()"), "D3MAaveV2TypePool/king-not-set");
    }

    function test_cage_exit() public {
        _setRelBorrowTarget(7500);

        // Vat is caged for global settlement
        end.cage();
        end.cage(ilk);
        end.skim(ilk, address(d3mAavePool));

        // Simulate DAI holder gets some gems from GS
        vm.prank(address(end));
        vat.flux(ilk, address(end), address(this), 100 ether);

        uint256 totalArt = end.Art(ilk);

        assertEq(adai.balanceOf(address(this)), 0);

        // User can exit and get the aDAI
        uint256 expectedAdai = 100 ether * adai.balanceOf(address(d3mAavePool)) / totalArt;
        d3mHub.exit(ilk, address(this), 100 ether);
        assertEqApprox(expectedAdai, 100 ether, 1);
        assertEqApprox(adai.balanceOf(address(this)), expectedAdai, 1); // As the whole thing happened in a block (no fees)
    }

    function test_cage_exit_multiple() public {
        _setRelBorrowTarget(7500);

        // Vat is caged for global settlement
        end.cage();
        end.cage(ilk);
        end.skim(ilk, address(d3mAavePool));

        uint256 totalArt = end.Art(ilk);

        // Simulate DAI holder gets some gems from GS
        vm.prank(address(end));
        vat.flux(ilk, address(end), address(this), totalArt);

        assertEq(adai.balanceOf(address(this)), 0);

        // User can exit and get the aDAI
        uint256 expectedAdai = 25 ether * adai.balanceOf(address(d3mAavePool)) / totalArt;
        d3mHub.exit(ilk, address(this), 25 ether);
        assertEqApprox(expectedAdai, 25 ether, 1);
        assertEqApprox(adai.balanceOf(address(this)), expectedAdai, 1); // As the whole thing happened in a block (no fees)

        vm.warp(block.timestamp + 3600);

        uint256 expectedAdai2 = 25 ether * adai.balanceOf(address(d3mAavePool)) / (totalArt - 25 ether);
        assertGt(expectedAdai2, expectedAdai);
        d3mHub.exit(ilk, address(this), 25 ether);
        assertGt(adai.balanceOf(address(this)), expectedAdai + expectedAdai2); // As fees were accrued

        vm.warp(block.timestamp + 3600);

        uint256 expectedAdai3 = 50 ether * adai.balanceOf(address(d3mAavePool)) / (totalArt - 50 ether);
        assertGt(expectedAdai3, expectedAdai + expectedAdai2);
        d3mHub.exit(ilk, address(this), 50 ether);
        assertGt(adai.balanceOf(address(this)), expectedAdai + expectedAdai2 + expectedAdai3); // As fees were accrued

        vm.warp(block.timestamp + 3600);

        uint256 expectedAdai4 = (totalArt - 100 ether) * adai.balanceOf(address(d3mAavePool)) / (totalArt - 100 ether);
        d3mHub.exit(ilk, address(this), (totalArt - 100 ether));
        assertGt(adai.balanceOf(address(this)), expectedAdai + expectedAdai2 + expectedAdai3 + expectedAdai4); // As fees were accrued
        assertEq(adai.balanceOf(address(d3mAavePool)), 0);
    }

    function test_shutdown_cant_cull() public {
        _setRelBorrowTarget(7500);

        d3mHub.cage(ilk);

        // Vat is caged for global settlement
        vat.cage();

        (, , , uint256 tau, , ) = d3mHub.ilks(ilk);
        vm.warp(block.timestamp + tau);

        assertRevert(address(d3mHub), abi.encodeWithSignature("cull(bytes32)", ilk), "D3MHub/no-cull-during-shutdown");
    }

    function test_quit_no_cull() public {
        _setRelBorrowTarget(7500);

        d3mHub.cage(ilk);

        // Test that we can extract the whole position in emergency situations
        // aDAI should be sitting in the deposit contract, urn should be owned by deposit contract
        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mAavePool));
        uint256 pbal = adai.balanceOf(address(d3mAavePool));
        assertGt(pink, 0);
        assertGt(part, 0);
        assertGt(pbal, 0);

        address receiver = address(123);

        d3mAavePool.quit(address(receiver));
        vat.grab(ilk, address(d3mAavePool), address(receiver), address(receiver), -int256(pink), -int256(part));
        vat.grab(ilk, address(receiver), address(receiver), address(receiver), int256(pink), int256(part));

        (uint256 nink, uint256 nart) = vat.urns(ilk, address(d3mAavePool));
        uint256 nbal = adai.balanceOf(address(d3mAavePool));
        assertEq(nink, 0);
        assertEq(nart, 0);
        assertEq(nbal, 0);

        (uint256 ink, uint256 art) = vat.urns(ilk, receiver);
        uint256 bal = adai.balanceOf(receiver);
        assertEq(ink, pink);
        assertEq(art, part);
        assertEq(bal, pbal);
    }

    function test_quit_cull() public {
        _setRelBorrowTarget(7500);

        d3mHub.cage(ilk);

        (, , , uint256 tau, , ) = d3mHub.ilks(ilk);
        vm.warp(block.timestamp + tau);

        d3mHub.cull(ilk);

        // Test that we can extract the adai in emergency situations
        // aDAI should be sitting in the deposit contract, gems should be owned by deposit contract
        uint256 pgem = vat.gem(ilk, address(d3mAavePool));
        uint256 pbal = adai.balanceOf(address(d3mAavePool));
        assertGt(pgem, 0);
        assertGt(pbal, 0);

        address receiver = address(123);

        d3mAavePool.quit(address(receiver));
        vat.slip(ilk, address(d3mAavePool), -int256(pgem));

        uint256 ngem = vat.gem(ilk, address(d3mAavePool));
        uint256 nbal = adai.balanceOf(address(d3mAavePool));
        assertEq(ngem, 0);
        assertEq(nbal, 0);

        uint256 gem = vat.gem(ilk, receiver);
        uint256 bal = adai.balanceOf(receiver);
        assertEq(gem, 0);
        assertEq(bal, pbal);
    }

    function test_direct_deposit_mom() public {
        _setRelBorrowTarget(7500);

        (uint256 ink, ) = vat.urns(ilk, address(d3mAavePool));
        assertGt(ink, 0);
        assertGt(d3mAavePlan.bar(), 0);

        // Something bad happens on Aave - we need to bypass gov delay
        d3mMom.disable(address(d3mAavePlan));

        assertEq(d3mAavePlan.bar(), 0);

        // Close out our position
        d3mHub.exec(ilk);

        (ink, ) = vat.urns(ilk, address(d3mAavePool));
        assertEqRoundingAgainst(ink, 0);
    }

    function test_set_tau_not_caged() public {
        (, , , uint256 tau, , ) = d3mHub.ilks(ilk);
        assertEq(tau, 7 days);
        d3mHub.file(ilk, "tau", 1 days);
        (, , , tau, , ) = d3mHub.ilks(ilk);
        assertEq(tau, 1 days);
    }

    function test_fully_unwind_debt_paid_back() public {
        uint256 adaiDaiBalanceInitial = dai.balanceOf(address(adai));

        _setRelBorrowTarget(7500);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mAavePool));
        uint256 gemBefore = vat.gem(ilk, address(d3mAavePool));
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(vow);
        uint256 vowDaiBefore = vat.dai(vow);
        uint256 adaiDaiBalanceBefore = dai.balanceOf(address(adai));
        uint256 poolAdaiBalanceBefore = adai.balanceOf(address(d3mAavePool));

        // Someone pays back our debt
        dai.setBalance(address(this), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(d3mAavePool),
            address(d3mAavePool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, pink);
        assertEq(art, part - 10 * WAD);
        assertEq(ink - art, 10 * WAD);
        assertEq(vat.gem(ilk, address(d3mAavePool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEq(vat.dai(vow), vowDaiBefore);
        assertEqRoundingAgainst(dai.balanceOf(address(adai)), adaiDaiBalanceBefore);
        assertEqApprox(adai.balanceOf(address(d3mAavePool)), poolAdaiBalanceBefore, 2); // rounding may affect twice

        // We should be able to close out the vault completely even though ink and art do not match
        // _setRelBorrowTarget(0);
        d3mAavePlan.file("bar", 0);

        d3mHub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(d3mAavePool));
        assertEqRoundingAgainst(ink, 0);
        assertEqRoundingAgainst(art, 0);
        assertEq(vat.gem(ilk, address(d3mAavePool)), 0);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEqApprox(vat.dai(vow), vowDaiBefore + 10 * RAD, RAY);
        assertEqRoundingAgainst(dai.balanceOf(address(adai)), adaiDaiBalanceInitial);
        assertEq(adai.balanceOf(address(d3mAavePool)), 0);
    }

    function test_wind_partial_unwind_wind_debt_paid_back() public {
        uint256 initialRate = _setRelBorrowTarget(5000);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mAavePool));
        uint256 gemBefore = vat.gem(ilk, address(d3mAavePool));
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(vow);
        uint256 vowDaiBefore = vat.dai(vow);
        uint256 adaiDaiBalanceBefore = dai.balanceOf(address(adai));
        uint256 poolAdaiBalanceBefore = adai.balanceOf(address(d3mAavePool));

        // Someone pays back our debt
        dai.setBalance(address(this), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(d3mAavePool),
            address(d3mAavePool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mAavePool));
        assertEq(ink, pink);
        assertEq(art, part - 10 * WAD);
        assertEq(ink - art, 10 * WAD);
        assertEq(vat.gem(ilk, address(d3mAavePool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEq(vat.dai(vow), vowDaiBefore);
        assertEqRoundingAgainst(dai.balanceOf(address(adai)), adaiDaiBalanceBefore);
        assertEqRoundingAgainst(adai.balanceOf(address(d3mAavePool)), poolAdaiBalanceBefore);

        d3mHub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(d3mAavePool));
        assertEqRoundingAgainst(ink, pink);
        assertEqRoundingAgainst(art, part);
        assertEq(ink, art);
        assertEq(vat.gem(ilk, address(d3mAavePool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEqApprox(vat.dai(vow), vowDaiBefore + 10 * RAD, RAY);
        assertEqRoundingAgainst(dai.balanceOf(address(adai)), adaiDaiBalanceBefore);
        assertEqApprox(adai.balanceOf(address(d3mAavePool)), poolAdaiBalanceBefore, 2); // rounding may affect twice

        // Raise target a little to trigger unwind
        //_setRelBorrowTarget(12500);
        d3mAavePlan.file("bar", getBorrowRate() * 12500 / 10000);

        d3mHub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(d3mAavePool));
        assertLt(ink, pink);
        assertLt(art, part);
        assertEq(ink, art);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEqApprox(vat.dai(vow), vowDaiBefore + 10 * RAD, RAY);
        assertEq(vat.gem(ilk, address(d3mAavePool)), gemBefore);
        assertLt(dai.balanceOf(address(adai)), adaiDaiBalanceBefore);
        assertLt(adai.balanceOf(address(d3mAavePool)), poolAdaiBalanceBefore);

        // can re-wind and have the correct amount of debt
        d3mAavePlan.file("bar", initialRate);
        d3mHub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(d3mAavePool));
        assertEqRoundingAgainst(ink, pink);
        assertEqRoundingAgainst(art, part);
        assertEq(ink, art);
        assertEq(vat.gem(ilk, address(d3mAavePool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEqApprox(vat.dai(vow), vowDaiBefore + 10 * RAD, RAY);
        assertEqRoundingAgainst(dai.balanceOf(address(adai)), adaiDaiBalanceBefore);
        assertEqApprox(adai.balanceOf(address(d3mAavePool)), poolAdaiBalanceBefore, 2); // rounding may affect twice
    }
}
