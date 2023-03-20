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

import { ID3MPlan } from "../../plans/ID3MPlan.sol";
import { ID3MPool } from "../../pools/ID3MPool.sol";

import { D3MHub } from "../../D3MHub.sol";
import { D3MMom } from "../../D3MMom.sol";
import { D3MOracle } from "../../D3MOracle.sol";

import "../../deploy/D3MDeploy.sol";
import "../../deploy/D3MInit.sol";

abstract contract IntegrationBaseTest is DssTest {

    using stdJson for string;
    using MCD for *;
    using GodMode for *;
    using ScriptTools for *;

    address internal admin;
    DssInstance internal dss;
    D3MInstance internal d3m;

    // For easy access
    VatAbstract internal vat;
    DaiAbstract internal dai;
    DaiJoinAbstract internal daiJoin;
    EndAbstract internal end;
    VowAbstract internal vow;

    int256 internal standardDebtSize = int256(1_000_000 * WAD); // Override if necessary
    uint256 internal roundingTolerance = 1;                     // Override if necessary
    bytes32 internal ilk = "EXAMPLE-ILK";                       // Override if necessary

    D3MHub internal hub;
    D3MMom internal mom;
    
    // These are private as inheriting contract should use a more specific type
    ID3MPool private pool;
    ID3MPlan private plan;

    function baseInit() internal {
        dss = MCD.loadFromChainlog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
        admin = dss.chainlog.getAddress("MCD_PAUSE_PROXY");
        hub = D3MHub(dss.chainlog.getAddress("DIRECT_HUB"));
        mom = D3MMom(dss.chainlog.getAddress("DIRECT_MOM"));

        vat = dss.vat;
        dai = dss.dai;
        daiJoin = dss.daiJoin;
        end = dss.end;
        vow = dss.vow;
    }

    function basePostSetup() internal {
        pool = ID3MPool(d3m.pool);
        plan = ID3MPlan(d3m.plan);

        adjustLiquidity(standardDebtSize);  // Ensure there is some liquidty to start with
    }

    // --- Helper functions ---
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }
    function assertRoundingEq(uint256 a, uint256 b) internal {
        assertApproxEqAbs(a, b, roundingTolerance);
    }

    // --- Manage D3M Debt ---
    function adjustDebt(int256 deltaAmount) internal virtual;

    function setDebtToZero() internal virtual {
        adjustDebt(type(int256).min / int256(WAD));         // Just a really big number, but don't want to underflow
    }

    function setDebtToMaximum() internal virtual {
        adjustDebt(type(int256).max / int256(WAD));         // Just a really big number, but don't want to overflow
    }

    // --- Manage Pool Liquidity ---
    function getLiquidity() internal virtual view returns (uint256);

    function adjustLiquidity(int256 deltaAmount) internal virtual;

    function setLiquidityToZero() internal virtual {
        adjustLiquidity(type(int256).min / int256(WAD));    // Just a really big number, but don't want to underflow
    }

    // --- Other Overridable Functions ---
    function getLPTokenBalanceInAssets(address a) internal view virtual returns (uint256) {
        return DSTokenAbstract(pool.redeemable()).balanceOf(a);
    }

    function generateInterest() internal virtual {
        vm.warp(block.timestamp + 1 days);
    }

    // --- Tests ---
    function test_target_zero() public {
        adjustDebt(standardDebtSize);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertGt(ink, 0);
        assertGt(art, 0);

        setDebtToZero();

        (ink, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, 0);
        assertRoundingEq(art, 0);
    }

    function test_cage_temp_insufficient_liquidity() public {
        // Increase debt
        adjustDebt(standardDebtSize);

        // Someone else borrows
        int256 borrowAmount = standardDebtSize / 2 - int256(getLiquidity());
        adjustLiquidity(borrowAmount);

        // Cage the system and start unwinding
        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        vm.prank(admin); hub.cage(ilk);
        hub.exec(ilk);

        // Should be no dai liquidity remaining as we attempt to fully unwind
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertGt(ink, 0);
        assertGt(art, 0);
        assertRoundingEq(pink - ink, uint256(standardDebtSize / 2));
        assertRoundingEq(part - art, uint256(standardDebtSize / 2));

        // Someone else repays some Dai so we can unwind the rest
        adjustLiquidity(-borrowAmount);

        hub.exec(ilk);
        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function test_cage_perm_insufficient_liquidity() public {
        // Increase debt
        adjustDebt(standardDebtSize);

        // Someone else borrows
        int256 borrowAmount = standardDebtSize / 2 - int256(getLiquidity());
        adjustLiquidity(borrowAmount);

        // Cage the system and start unwinding
        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        vm.prank(admin); hub.cage(ilk);
        hub.exec(ilk);

        // Should be no dai liquidity remaining as we attempt to fully unwind
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertGt(ink, 0);
        assertGt(art, 0);
        assertRoundingEq(pink - ink, uint256(standardDebtSize / 2));
        assertRoundingEq(part - art, uint256(standardDebtSize / 2));

        // In this case nobody deposits more DAI so we have to write off the bad debt
        vm.warp(block.timestamp + hub.tau(ilk));

        uint256 sin = vat.sin(address(vow));
        uint256 vowDai = vat.dai(address(vow));
        hub.cull(ilk);
        (uint256 ink2, uint256 art2) = vat.urns(ilk, address(pool));
        (, , , uint256 culled, ) = hub.ilks(ilk);
        assertEq(culled, 1);
        assertEq(ink2, 0);
        assertEq(art2, 0);
        assertEq(vat.gem(ilk, address(pool)), ink);
        assertEq(vat.sin(address(vow)), sin + art * RAY);
        assertEq(vat.dai(address(vow)), vowDai);

        // Some time later the pool gets some liquidity
        adjustLiquidity(-borrowAmount);

        // Close out the remainder of the position
        uint256 balance = getLPTokenBalanceInAssets(address(pool));
        assertGe(balance, art);
        hub.exec(ilk);
        assertEq(getLPTokenBalanceInAssets(address(pool)), 0);
        assertEq(vat.sin(address(vow)), sin + art * RAY);
        assertEq(vat.dai(address(vow)), vowDai + balance * RAY);
        assertEq(vat.gem(ilk, address(pool)), 0);
    }

    function test_hit_debt_ceiling() public {
        // Lower the debt ceiling to a small number
        uint256 debtCeiling = uint256(standardDebtSize / 2);
        vm.prank(admin); vat.file(ilk, "line", debtCeiling * RAY);

        // Max out the debt ceiling
        setDebtToMaximum();
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertRoundingEq(getLPTokenBalanceInAssets(address(pool)), debtCeiling);

        // Should be a no-op
        hub.exec(ilk);
        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertRoundingEq(getLPTokenBalanceInAssets(address(pool)), debtCeiling);

        // Raise it by a bit
        debtCeiling = uint256(standardDebtSize * 2);
        vm.prank(admin); vat.file(ilk, "line", debtCeiling * RAY);
        hub.exec(ilk);
        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertRoundingEq(getLPTokenBalanceInAssets(address(pool)), debtCeiling);
    }

    function test_collect_interest() public {
        adjustDebt(standardDebtSize);

        generateInterest();

        uint256 vowDai = vat.dai(address(vow));
        hub.exec(ilk);

        assertGt(vat.dai(address(vow)), vowDai);
    }

    function test_insufficient_liquidity_for_unwind_fees() public {
        uint256 currentLiquidity = getLiquidity();
        uint256 vowDai = vat.dai(address(vow));

        // Increase debt
        adjustDebt(standardDebtSize);

        uint256 pAssets = getLPTokenBalanceInAssets(address(pool));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertEq(pink, part);
        assertRoundingEq(pink, pAssets);

        // Someone else borrows the exact amount previously available
        uint256 amountToBorrow = currentLiquidity;
        adjustLiquidity(-int256(amountToBorrow));

        // Accumulate interest
        generateInterest();

        uint256 feesAccrued = getLPTokenBalanceInAssets(address(pool)) - pAssets;
        currentLiquidity = getLiquidity();

        assertGt(feesAccrued, 0);
        assertEq(pink, currentLiquidity);
        assertGt(pink + feesAccrued, currentLiquidity);

        // Cage the system to trigger only unwinds
        vm.prank(admin); hub.cage(ilk);
        hub.exec(ilk);

        uint256 assets = getLPTokenBalanceInAssets(address(pool));
        // All the fees are accrued but what can't be withdrawn is added up to the original ink and art debt
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, art);
        assertRoundingEq(ink, assets);
        assertGt(assets, 0);
        assertRoundingEq(ink, feesAccrued);
        assertApproxEqAbs(vat.dai(address(vow)), vowDai + feesAccrued * RAY, RAY * roundingTolerance);

        // Someone repays
        adjustLiquidity(int256(amountToBorrow));
        hub.exec(ilk);

        // Now the CDP completely unwinds and surplus buffer doesn't change
        (ink, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, 0);
        assertRoundingEq(art, 0);
        assertEq(getLPTokenBalanceInAssets(address(pool)), 0);
        assertApproxEqAbs(vat.dai(address(vow)), vowDai + feesAccrued * RAY, 2 * RAY * roundingTolerance); // rounding may affect twice
    }

    function test_insufficient_liquidity_for_exec_fees() public {
        // Increase debt
        adjustDebt(standardDebtSize);

        uint256 pAssets = getLPTokenBalanceInAssets(address(pool));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertEq(pink, part);
        assertRoundingEq(pink, pAssets);

        // Accumulate interest
        generateInterest();

        // Someone else borrows almost all the liquidity
        uint256 currentLiquidity = getLiquidity();
        adjustLiquidity(-int256(currentLiquidity * 99 / 100));
        assertRoundingEq(getLiquidity(), currentLiquidity / 100);

        uint256 feesAccrued = getLPTokenBalanceInAssets(address(pool)) - pAssets;
        assertGt(feesAccrued, 0);

        // Accrue fees
        uint256 vowDai = vat.dai(address(vow));
        vm.prank(admin); plan.disable(); // So we make sure to unwind after rebalancing
        hub.exec(ilk);

        uint256 assets = getLPTokenBalanceInAssets(address(pool));
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, art);
        assertRoundingEq(ink, assets);
        assertRoundingEq(ink, pink + feesAccrued - currentLiquidity / 100);
        assertApproxEqAbs(vat.dai(address(vow)), vowDai + feesAccrued * RAY, RAY * roundingTolerance);
    }

    function test_unwind_mcd_caged_not_skimmed() public {
        uint256 currentLiquidity = getLiquidity();

        // Increase debt
        adjustDebt(standardDebtSize);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        uint256 amountSupplied = getLPTokenBalanceInAssets(address(pool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        adjustLiquidity(-int256(amountToBorrow));

        // MCD shutdowns
        vm.prank(admin); end.cage();
        end.cage(ilk);

        // CDP still has the position built
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertGt(ink, 0);
        assertGt(art, 0);
        assertEq(vat.gem(ilk, address(end)), 0);

        uint256 prevSin = vat.sin(address(vow));
        uint256 prevDai = vat.dai(address(vow));
        assertEq(prevSin, 0);
        assertGt(prevDai, 0);

        // We try to unwind what is possible
        hub.exec(ilk);
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));

        // exec() moved the remaining urn debt to the end
        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(end)), amountSupplied / 2); // Automatically skimmed when unwinding
        if (prevSin + (amountSupplied / 2) * RAY >= prevDai) {
            assertApproxEqAbs(vat.sin(address(vow)), prevSin + (amountSupplied / 2) * RAY - prevDai, RAY * roundingTolerance);
            assertEq(vat.dai(address(vow)), 0);
        } else {
            assertApproxEqAbs(vat.dai(address(vow)), prevDai - prevSin - (amountSupplied / 2) * RAY, RAY * roundingTolerance);
            assertEq(vat.sin(address(vow)), 0);
        }

        // Some time later the pool gets some liquidity
        adjustLiquidity(int256(amountToBorrow));

        // Rest of the liquidity can be withdrawn
        hub.exec(ilk);
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(vat.sin(address(vow)), 0);
        assertGe(vat.dai(address(vow)), prevDai); // As also probably accrues interest
    }

    function test_unwind_mcd_caged_skimmed() public {
        uint256 currentLiquidity = getLiquidity();

        // Inrease debt
        adjustDebt(standardDebtSize);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        uint256 amountSupplied = getLPTokenBalanceInAssets(address(pool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        adjustLiquidity(-int256(amountToBorrow));

        // MCD shutdowns
        vm.prank(admin); end.cage();
        end.cage(ilk);

        // CDP still has the position built
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertGt(ink, 0);
        assertGt(art, 0);
        assertEq(vat.gem(ilk, address(end)), 0);

        uint256 prevSin = vat.sin(address(vow));
        uint256 prevDai = vat.dai(address(vow));
        assertEq(prevSin, 0);
        assertGt(prevDai, 0);

        // Position is taken by the End module
        end.skim(ilk, address(pool));
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));
        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(end)), pink);
        if (prevSin + amountSupplied * RAY >= prevDai) {
            assertApproxEqAbs(vat.sin(address(vow)), prevSin + amountSupplied * RAY - prevDai, RAY * roundingTolerance);
            assertEq(vat.dai(address(vow)), 0);
        } else {
            assertApproxEqAbs(vat.dai(address(vow)), prevDai - prevSin - amountSupplied * RAY, RAY);
            assertEq(vat.sin(address(vow)), 0);
        }

        // We try to unwind what is possible
        hub.exec(ilk);
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));

        // Part can't be done yet
        assertEq(vat.gem(ilk, address(end)), amountSupplied / 2);
        if (prevSin + (amountSupplied / 2) * RAY >= prevDai) {
            assertApproxEqAbs(vat.sin(address(vow)), prevSin + (amountSupplied / 2) * RAY - prevDai, RAY * roundingTolerance);
            assertEq(vat.dai(address(vow)), 0);
        } else {
            assertApproxEqAbs(vat.dai(address(vow)), prevDai - prevSin - (amountSupplied / 2) * RAY, RAY * roundingTolerance);
            assertEq(vat.sin(address(vow)), 0);
        }

        // Some time later the pool gets some liquidity
        adjustLiquidity(int256(amountToBorrow));

        // Rest of the liquidity can be withdrawn
        hub.exec(ilk);
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(vat.sin(address(vow)), 0);
        assertGe(vat.dai(address(vow)), prevDai); // As also probably accrues interest 
    }

    function test_unwind_mcd_caged_wait_done() public {
        uint256 currentLiquidity = getLiquidity();

        // Inrease debt
        adjustDebt(standardDebtSize);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        uint256 amountSupplied = getLPTokenBalanceInAssets(address(pool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        adjustLiquidity(-int256(amountToBorrow));

        // MCD shutdowns
        vm.prank(admin); end.cage();
        end.cage(ilk);

        vm.warp(block.timestamp + end.wait());

        // Force remove all the dai from vow so it can call end.thaw()
        vm.store(
            address(vat),
            keccak256(abi.encode(address(vow), uint256(5))),
            bytes32(0)
        );

        end.thaw();

        assertRevert(address(hub), abi.encodeWithSignature("exec(bytes32)", ilk), "D3MHub/end-debt-already-set");
    }

    function test_unwind_culled_then_mcd_caged() public {
        uint256 currentLiquidity = getLiquidity();

        // Inrease debt
        adjustDebt(standardDebtSize);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        uint256 amountSupplied = getLPTokenBalanceInAssets(address(pool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        adjustLiquidity(-int256(amountToBorrow));

        vm.prank(admin); hub.cage(ilk);

        (, , uint256 tau, , ) = hub.ilks(ilk);

        vm.warp(block.timestamp + tau);

        uint256 daiEarned = getLPTokenBalanceInAssets(address(pool)) - pink;

        vow.heal(
            _min(
                vat.sin(address(vow)) - vow.Sin() - vow.Ash(),
                vat.dai(address(vow))
            )
        );
        uint256 originalSin = vat.sin(address(vow));
        uint256 originalDai = vat.dai(address(vow));
        // If the whole Sin queue would be cleant by someone,
        // originalSin should be 0 as there is more profit than debt registered
        assertGt(originalDai, originalSin);
        assertGt(originalSin, 0);

        hub.cull(ilk);

        // After cull, the debt of the position is converted to bad debt
        assertEq(vat.sin(address(vow)), originalSin + part * RAY);

        // CDP grabbed and ink moved as free collateral to the deposit contract
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(pool)), pink);
        assertGe(getLPTokenBalanceInAssets(address(pool)), pink);

        // MCD shutdowns
        originalDai = originalDai + vat.dai(vow.flapper());
        vm.prank(admin); end.cage();

        if (originalSin + part * RAY >= originalDai) {
            assertEq(vat.sin(address(vow)), originalSin + part * RAY - originalDai);
            assertEq(vat.dai(address(vow)), 0);
        } else {
            assertEq(vat.dai(address(vow)), originalDai - originalSin - part * RAY);
            assertEq(vat.sin(address(vow)), 0);
        }

        hub.uncull(ilk);
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));

        end.cage(ilk);

        // So the position is restablished
        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, pink);
        assertEq(art, part);
        assertEq(vat.gem(ilk, address(pool)), 0);
        assertGe(getLPTokenBalanceInAssets(address(pool)), pink);
        assertEq(vat.sin(address(vow)), 0);

        // Call skim manually (will be done through deposit anyway)
        // Position is again taken but this time the collateral goes to the End module
        end.skim(ilk, address(pool));
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(pool)), 0);
        assertEq(vat.gem(ilk, address(end)), pink);
        assertGe(getLPTokenBalanceInAssets(address(pool)), pink);
        if (originalSin + part * RAY >= originalDai) {
            assertApproxEqAbs(vat.sin(address(vow)), originalSin + part * RAY - originalDai, RAY * roundingTolerance);
            assertEq(vat.dai(address(vow)), 0);
        } else {
            assertApproxEqAbs(vat.dai(address(vow)), originalDai - originalSin - part * RAY, RAY * roundingTolerance);
            assertEq(vat.sin(address(vow)), 0);
        }

        // We try to unwind what is possible
        hub.exec(ilk);
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));

        // A part can't be unwind yet
        assertEq(vat.gem(ilk, address(end)), amountSupplied / 2);
        assertGe(getLPTokenBalanceInAssets(address(pool)), amountSupplied / 2);
        if (originalSin + part * RAY >= originalDai + (amountSupplied / 2) * RAY) {
            // rounding may affect twice, and multiplied by RAY to be compared with sin
            assertApproxEqAbs(vat.sin(address(vow)), originalSin + part * RAY - originalDai - (amountSupplied / 2) * RAY, 2 * RAY * roundingTolerance);
            assertEq(vat.dai(address(vow)), 0);
        } else {
            // rounding may affect twice, and multiplied by RAY to be compared with sin
            assertApproxEqAbs(vat.dai(address(vow)), originalDai + (amountSupplied / 2) * RAY - originalSin - part * RAY, 2 * RAY * roundingTolerance);
            assertEq(vat.sin(address(vow)), 0);
        }

        // Then pool gets some liquidity
        adjustLiquidity(int256(amountToBorrow));

        // Rest of the liquidity can be withdrawn
        hub.exec(ilk);
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(getLPTokenBalanceInAssets(address(pool)), 0);
        assertEq(vat.sin(address(vow)), 0);
        assertApproxEqAbs(vat.dai(address(vow)), originalDai - originalSin + daiEarned * RAY, RAY * roundingTolerance);
    }

    function test_uncull_not_culled() public {
        adjustDebt(standardDebtSize);
        vm.prank(admin); hub.cage(ilk);

        // MCD shutdowns
        vm.prank(admin); end.cage();

        assertRevert(address(hub), abi.encodeWithSignature("uncull(bytes32)", ilk), "D3MHub/not-prev-culled");
    }

    function test_uncull_not_shutdown() public {
        adjustDebt(standardDebtSize);
        vm.prank(admin); hub.cage(ilk);

        (, , uint256 tau, , ) = hub.ilks(ilk);
        vm.warp(block.timestamp + tau);

        hub.cull(ilk);

        assertRevert(address(hub), abi.encodeWithSignature("uncull(bytes32)", ilk), "D3MHub/no-uncull-normal-operation");
    }

    function test_cage_exit() public {
        adjustDebt(200 ether);

        // Vat is caged for global settlement
        vm.prank(admin); end.cage();
        end.cage(ilk);
        end.skim(ilk, address(pool));

        // Simulate DAI holder gets some gems from GS
        vm.prank(address(end)); vat.flux(ilk, address(end), address(this), 100 ether);

        uint256 totalArt = end.Art(ilk);

        assertEq(getLPTokenBalanceInAssets(address(this)), 0);

        // User can exit and get the LP token
        uint256 expected = 100 ether * getLPTokenBalanceInAssets(address(pool)) / totalArt;
        hub.exit(ilk, address(this), 100 ether);
        assertRoundingEq(expected, 100 ether);
        assertRoundingEq(getLPTokenBalanceInAssets(address(this)), expected); // As the whole thing happened in a block (no fees)
    }

    function test_cage_exit_multiple() public {
        adjustDebt(200 ether);

        // Vat is caged for global settlement
        vm.prank(admin); end.cage();
        end.cage(ilk);
        end.skim(ilk, address(pool));

        uint256 totalArt = end.Art(ilk);

        // Simulate DAI holder gets some gems from GS
        vm.prank(address(end)); vat.flux(ilk, address(end), address(this), totalArt);

        assertEq(getLPTokenBalanceInAssets(address(this)), 0);

        // User can exit and get the LP
        uint256 expectedLP = 25 ether * getLPTokenBalanceInAssets(address(pool)) / totalArt;
        hub.exit(ilk, address(this), 25 ether);
        assertRoundingEq(expectedLP, 25 ether);
        assertRoundingEq(getLPTokenBalanceInAssets(address(this)), expectedLP); // As the whole thing happened in a block (no fees)

        generateInterest();

        uint256 expectedLP2 = 25 ether * getLPTokenBalanceInAssets(address(pool)) / (totalArt - 25 ether);
        assertGt(expectedLP2, expectedLP);
        hub.exit(ilk, address(this), 25 ether);
        assertGt(getLPTokenBalanceInAssets(address(this)), expectedLP + expectedLP2); // As fees were accrued

        generateInterest();

        uint256 expectedLP3 = 50 ether * getLPTokenBalanceInAssets(address(pool)) / (totalArt - 50 ether);
        assertGt(expectedLP3, expectedLP + expectedLP2);
        hub.exit(ilk, address(this), 50 ether);
        assertGt(getLPTokenBalanceInAssets(address(this)), expectedLP + expectedLP2 + expectedLP3); // As fees were accrued

        generateInterest();

        uint256 expectedLP4 = (totalArt - 100 ether) * getLPTokenBalanceInAssets(address(pool)) / (totalArt - 100 ether);
        hub.exit(ilk, address(this), (totalArt - 100 ether));
        assertGt(getLPTokenBalanceInAssets(address(this)), expectedLP + expectedLP2 + expectedLP3 + expectedLP4); // As fees were accrued
        assertEq(getLPTokenBalanceInAssets(address(pool)), 0);
    }

    function test_shutdown_cant_cull() public {
        adjustDebt(standardDebtSize);

        vm.prank(admin); hub.cage(ilk);

        // Vat is caged for global settlement
        vm.prank(admin); vat.cage();

        (, , uint256 tau, , ) = hub.ilks(ilk);
        vm.warp(block.timestamp + tau);

        assertRevert(address(hub), abi.encodeWithSignature("cull(bytes32)", ilk), "D3MHub/no-cull-during-shutdown");
    }

    function test_quit_no_cull() public {
        adjustDebt(standardDebtSize);

        vm.prank(admin); hub.cage(ilk);

        // Test that we can extract the whole position in emergency situations
        // LP should be sitting in the deposit contract, urn should be owned by deposit contract
        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        uint256 pbal = getLPTokenBalanceInAssets(address(pool));
        assertGt(pink, 0);
        assertGt(part, 0);
        assertGt(pbal, 0);

        address receiver = address(123);

        vm.prank(admin); pool.quit(address(receiver));
        vm.prank(admin); vat.grab(ilk, address(pool), address(receiver), address(receiver), -int256(pink), -int256(part));
        vm.prank(admin); vat.grab(ilk, address(receiver), address(receiver), address(receiver), int256(pink), int256(part));

        (uint256 nink, uint256 nart) = vat.urns(ilk, address(pool));
        uint256 nbal = getLPTokenBalanceInAssets(address(pool));
        assertEq(nink, 0);
        assertEq(nart, 0);
        assertEq(nbal, 0);

        (uint256 ink, uint256 art) = vat.urns(ilk, receiver);
        uint256 bal = getLPTokenBalanceInAssets(receiver);
        assertEq(ink, pink);
        assertEq(art, part);
        assertEq(bal, pbal);
    }

    function test_quit_cull() public {
        adjustDebt(standardDebtSize);

        vm.prank(admin); hub.cage(ilk);

        (, , uint256 tau, , ) = hub.ilks(ilk);
        vm.warp(block.timestamp + tau);

        hub.cull(ilk);

        // Test that we can extract the lp token in emergency situations
        // LP token should be sitting in the deposit contract, gems should be owned by deposit contract
        uint256 pgem = vat.gem(ilk, address(pool));
        uint256 pbal = getLPTokenBalanceInAssets(address(pool));
        assertGt(pgem, 0);
        assertGt(pbal, 0);

        address receiver = address(123);

        vm.prank(admin); pool.quit(address(receiver));
        vm.prank(admin); vat.slip(ilk, address(pool), -int256(pgem));

        uint256 ngem = vat.gem(ilk, address(pool));
        uint256 nbal = getLPTokenBalanceInAssets(address(pool));
        assertEq(ngem, 0);
        assertEq(nbal, 0);

        uint256 gem = vat.gem(ilk, receiver);
        uint256 bal = getLPTokenBalanceInAssets(receiver);
        assertEq(gem, 0);
        assertEq(bal, pbal);
    }

    function test_direct_deposit_mom() public {
        adjustDebt(standardDebtSize);

        (uint256 ink, ) = vat.urns(ilk, address(pool));
        assertGt(ink, 0);
        assertEq(plan.active(), true);

        // Something bad happens - we need to bypass gov delay
        vm.prank(admin); mom.disable(address(plan));

        assertEq(plan.active(), false);

        // Close out our position
        hub.exec(ilk);

        (ink, ) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, 0);
    }

    function test_set_tau_not_caged() public {
        (, , uint256 tau, , ) = hub.ilks(ilk);
        assertEq(tau, 7 days);
        vm.prank(admin); hub.file(ilk, "tau", 1 days);
        (, , tau, , ) = hub.ilks(ilk);
        assertEq(tau, 1 days);
    }

    function test_fully_unwind_debt_paid_back() public {
        uint256 liquidityBalanceInitial = getLiquidity();

        adjustDebt(standardDebtSize);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        uint256 gemBefore = vat.gem(ilk, address(pool));
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(address(vow));
        uint256 vowDaiBefore = vat.dai(address(vow));
        uint256 liquidityBalanceBefore = getLiquidity();
        uint256 assetsBalanceBefore = getLPTokenBalanceInAssets(address(pool));

        // Someone pays back our debt
        dai.setBalance(address(this), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(pool),
            address(pool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, pink);
        assertEq(art, part - 10 * WAD);
        assertEq(ink - art, 10 * WAD);
        assertEq(vat.gem(ilk, address(pool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(address(vow)), sinBefore);
        assertEq(vat.dai(address(vow)), vowDaiBefore);
        assertEq(getLiquidity(), liquidityBalanceBefore);
        assertEq(getLPTokenBalanceInAssets(address(pool)), assetsBalanceBefore);

        // We should be able to close out the vault completely even though ink and art do not match
        vm.prank(admin); plan.disable();

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, 0);
        assertRoundingEq(art, 0);
        assertEq(vat.gem(ilk, address(pool)), 0);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(address(vow)), sinBefore);
        assertApproxEqAbs(vat.dai(address(vow)), vowDaiBefore + 10 * RAD, RAY * roundingTolerance);
        assertRoundingEq(getLiquidity(), liquidityBalanceInitial);
        assertEq(getLPTokenBalanceInAssets(address(pool)), 0);
    }

    function test_wind_partial_unwind_wind_debt_paid_back() public {
        adjustDebt(standardDebtSize);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        uint256 gemBefore = vat.gem(ilk, address(pool));
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(address(vow));
        uint256 vowDaiBefore = vat.dai(address(vow));
        uint256 liquidityBalanceBefore = getLiquidity();
        uint256 assetsBalanceBefore = getLPTokenBalanceInAssets(address(pool));

        // Someone pays back our debt
        dai.setBalance(address(this), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(pool),
            address(pool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, pink);
        assertEq(art, part - 10 * WAD);
        assertEq(ink - art, 10 * WAD);
        assertEq(vat.gem(ilk, address(pool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(address(vow)), sinBefore);
        assertEq(vat.dai(address(vow)), vowDaiBefore);
        assertEq(getLiquidity(), liquidityBalanceBefore);
        assertEq(getLPTokenBalanceInAssets(address(pool)), assetsBalanceBefore);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, pink);
        assertRoundingEq(art, part);
        assertEq(ink, art);
        assertEq(vat.gem(ilk, address(pool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(address(vow)), sinBefore);
        assertApproxEqAbs(vat.dai(address(vow)), vowDaiBefore + 10 * RAD, RAY * roundingTolerance);
        assertEq(getLiquidity(), liquidityBalanceBefore);
        assertEq(getLPTokenBalanceInAssets(address(pool)), assetsBalanceBefore);

        // Decrease debt
        adjustDebt(-standardDebtSize / 2);

        (ink, art) = vat.urns(ilk, address(pool));
        assertLt(ink, pink);
        assertLt(art, part);
        assertEq(ink, art);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(address(vow)), sinBefore);
        assertApproxEqAbs(vat.dai(address(vow)), vowDaiBefore + 10 * RAD, RAY * roundingTolerance);
        assertEq(vat.gem(ilk, address(pool)), gemBefore);
        assertLt(getLiquidity(), liquidityBalanceBefore);
        assertLt(getLPTokenBalanceInAssets(address(pool)), assetsBalanceBefore);

        // can re-wind and have the correct amount of debt
        adjustDebt(standardDebtSize / 2);

        (ink, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, pink);
        assertRoundingEq(art, part);
        assertEq(ink, art);
        assertEq(vat.gem(ilk, address(pool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(address(vow)), sinBefore);
        assertApproxEqAbs(vat.dai(address(vow)), vowDaiBefore + 10 * RAD, RAY * roundingTolerance);
        assertRoundingEq(getLiquidity(), liquidityBalanceBefore);
        assertApproxEqAbs(getLPTokenBalanceInAssets(address(pool)), assetsBalanceBefore, 2 * roundingTolerance); // rounding may affect twice
    }
}
