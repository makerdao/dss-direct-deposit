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
import { ID3MFees } from "../../fees/ID3MFees.sol";

import { D3MHub } from "../../D3MHub.sol";
import { D3MMom } from "../../D3MMom.sol";
import { D3MOracle } from "../../D3MOracle.sol";

import "../../deploy/D3MDeploy.sol";
import "../../deploy/D3MInit.sol";

abstract contract IntegrationBaseTest is DssTest {

    using stdJson for string;
    using MCD for *;
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

    uint256 internal standardDebtSize = 1_000_000 * WAD;        // Override if necessary
    uint256 internal standardDebtCeiling = 100_000_000 * WAD;   // Override if necessary
    uint256 internal roundingTolerance = WAD / 10000;           // Override if necessary [1bps by default]
    bytes32 internal ilk = "EXAMPLE-ILK";                       // Override if necessary

    D3MHub internal hub;
    D3MMom internal mom;

    // These are private as inheriting contract should use a more specific type
    ID3MPool private pool;
    ID3MPlan private plan;
    ID3MFees private fees;

    function baseInit() internal {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        dss = MCD.loadFromChainlog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
        admin = dss.chainlog.getAddress("MCD_PAUSE_PROXY");

        // The Hub needs an upgrade so deactivate and replace the old one
        address _hub = D3MDeploy.deployHub(
            address(this),
            admin,
            address(dss.daiJoin)
        );

        vm.startPrank(admin);

        D3MInit.deactivateHub(
            dss,
            dss.chainlog.getAddress("DIRECT_HUB")
        );
        D3MInit.initHub(
            dss,
            _hub
        );

        vm.stopPrank();

        hub = D3MHub(_hub);
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
        fees = ID3MFees(d3m.fees);
    }

    // --- Helper functions ---
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }
    function assertRoundingEq(uint256 a, uint256 b) internal {
        assertApproxEqRel(a, b, roundingTolerance);
    }
    function assertRoundingEq(uint256 a, uint256 b, string memory err) internal {
        assertApproxEqRel(a, b, roundingTolerance, err);
    }

    // --- Manage D3M Debt ---
    function getDebt() internal virtual view returns (uint256) {
        (, uint256 art) = vat.urns(ilk, address(pool));
        return art;
    }

    function setDebt(uint256 amount) internal virtual;

    function setDebtToMaximum() internal virtual {
        (,,, uint256 line,) = vat.ilks(ilk);
        setDebt(line / RAY);
    }

    // --- Manage Pool Liquidity ---
    function getLiquidity() internal virtual view returns (uint256) {
        return pool.liquidityAvailable();
    }

    function setLiquidity(uint256 amount) internal virtual;

    // --- Other Overridable Functions ---
    function getTokenBalanceInAssets(address a) internal view virtual returns (uint256) {
        DSTokenAbstract token = DSTokenAbstract(pool.redeemable());
        return token.balanceOf(a) * 10 ** (18 - token.decimals());
    }

    function generateInterest() internal virtual {
        vm.warp(block.timestamp + 1 days);
    }

    // --- Tests ---
    function test_target_zero() public {
        setDebt(standardDebtSize);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, standardDebtSize);
        assertRoundingEq(art, standardDebtSize);

        setDebt(0);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function test_cage_temp_insufficient_liquidity() public {
        setDebt(standardDebtSize);
        setLiquidity(standardDebtSize / 2);

        // Cage the system and start unwinding
        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        vm.prank(admin); hub.cage(ilk);
        hub.exec(ilk);

        // Should be no dai liquidity remaining as we attempt to fully unwind
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertGt(ink, 0);
        assertGt(art, 0);
        assertRoundingEq(pink - ink, standardDebtSize / 2);
        assertRoundingEq(part - art, standardDebtSize / 2);
        assertEq(getLiquidity(), 0);

        // Liquidity returns so we can remove the rest of the debt
        setLiquidity(standardDebtSize / 2);

        hub.exec(ilk);
        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function test_cage_perm_insufficient_liquidity() public {
        setDebt(standardDebtSize);
        setLiquidity(standardDebtSize / 2);

        // Cage the system and start unwinding
        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        vm.prank(admin); hub.cage(ilk);
        hub.exec(ilk);

        // Should be no dai liquidity remaining as we attempt to fully unwind
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertGt(ink, 0);
        assertGt(art, 0);
        assertRoundingEq(pink - ink, standardDebtSize / 2);
        assertRoundingEq(part - art, standardDebtSize / 2);
        assertEq(getLiquidity(), 0);

        // In this case no DAI liquidity returns so we have to write off the bad debt
        vm.warp(block.timestamp + hub.tau(ilk));

        uint256 sin = vat.sin(address(vow));
        uint256 vowDai = vat.dai(address(vow));
        hub.cull(ilk);
        (uint256 ink2, uint256 art2) = vat.urns(ilk, address(pool));
        (, , , , uint256 culled, ) = hub.ilks(ilk);
        assertEq(culled, 1);
        assertEq(ink2, 0);
        assertEq(art2, 0);
        assertEq(vat.gem(ilk, address(pool)), ink);
        assertEq(vat.sin(address(vow)), sin + art * RAY);
        assertEq(vat.dai(address(vow)), vowDai);

        // Some time later DAI liquidity returns
        setLiquidity(standardDebtSize / 2);

        // Close out the remainder of the position
        uint256 balance = pool.assetBalance();
        assertGe(balance, art);
        hub.exec(ilk);
        assertEq(pool.assetBalance(), 0);
        assertEq(vat.sin(address(vow)), sin + art * RAY);
        assertEq(vat.dai(address(vow)), vowDai + balance * RAY);
        assertEq(vat.gem(ilk, address(pool)), 0);
    }

    function test_hit_debt_ceiling() public {
        // Lower the debt ceiling to a small number
        uint256 debtCeiling = standardDebtSize / 2;
        vm.prank(admin); vat.file(ilk, "line", debtCeiling * RAY);

        // Max out the debt ceiling
        setDebtToMaximum();
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, debtCeiling);
        assertRoundingEq(art, debtCeiling);

        // Should be a no-op
        hub.exec(ilk);
        (ink, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, debtCeiling);
        assertRoundingEq(art, debtCeiling);

        // Raise it by a bit
        debtCeiling = standardDebtSize * 2;
        vm.prank(admin); vat.file(ilk, "line", debtCeiling * RAY);
        setDebtToMaximum();
        (ink, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, debtCeiling);
        assertRoundingEq(art, debtCeiling);
    }

    function test_collect_interest() public {
        setDebt(standardDebtSize);

        generateInterest();
        
        // Make sure we can collect the interest
        setLiquidity(pool.assetBalance());

        uint256 vowDai = vat.dai(address(vow));
        hub.exec(ilk);

        assertGt(vat.dai(address(vow)), vowDai);
    }

    function test_insufficient_liquidity_for_unwind_fees() public {
        uint256 vowDai = vat.dai(address(vow));

        setDebt(standardDebtSize);

        uint256 pAssets = pool.assetBalance();
        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertEq(pink, part);
        assertRoundingEq(pink, pAssets);

        // Liquidity all goes away
        setLiquidity(0);

        // Accumulate interest
        generateInterest();

        uint256 feesAccrued = pool.assetBalance() - pAssets;
        setLiquidity(feesAccrued);
        uint256 debt = getDebt();

        assertGt(feesAccrued, 0);
        assertEq(pink, debt);
        assertGt(pink + feesAccrued, debt);

        // Cage the system to trigger only unwinds
        vm.prank(admin); hub.cage(ilk);
        hub.exec(ilk);

        uint256 assets = pool.assetBalance();
        // All the fees are accrued but what can't be withdrawn is added up to the original ink and art debt
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, art);
        assertRoundingEq(ink, assets);
        assertGt(assets, 0);
        assertRoundingEq(vat.dai(address(vow)), vowDai + feesAccrued * RAY);

        // Liquidity returns
        setLiquidity(assets);
        hub.exec(ilk);

        // Now the CDP completely unwinds and surplus buffer doesn't change
        (ink, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, 0);
        assertRoundingEq(art, 0);
        assertEq(pool.assetBalance(), 0);
        assertRoundingEq(vat.dai(address(vow)), vowDai + feesAccrued * RAY);
    }

    function test_insufficient_liquidity_for_exec_fees() public {
        setDebt(standardDebtSize);

        uint256 pAssets = pool.assetBalance();
        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertEq(pink, part);
        assertRoundingEq(pink, pAssets);

        // Accumulate interest
        generateInterest();

        // Almost all the liquidity goes away
        setLiquidity(standardDebtSize / 100);
        assertRoundingEq(getLiquidity(), standardDebtSize / 100);

        uint256 feesAccrued = pool.assetBalance() - pAssets;
        assertGt(feesAccrued, 0);

        // Accrue fees
        uint256 vowDai = vat.dai(address(vow));
        vm.prank(admin); plan.disable(); // So we make sure to unwind after rebalancing
        hub.exec(ilk);

        uint256 assets = pool.assetBalance();
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, art);
        assertRoundingEq(ink, assets);
        assertRoundingEq(ink, pink + feesAccrued - standardDebtSize / 100);
        assertRoundingEq(vat.dai(address(vow)), vowDai + feesAccrued * RAY);
    }

    function test_unwind_mcd_caged_not_skimmed() public {
        setDebt(standardDebtSize);
        setLiquidity(standardDebtSize / 2);

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

        // We try to unwind what is possible
        hub.exec(ilk);
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));

        // exec() moved the remaining urn debt to the end
        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertRoundingEq(vat.gem(ilk, address(end)), standardDebtSize / 2); // Automatically skimmed when unwinding
        if (prevSin + (standardDebtSize / 2) * RAY >= prevDai) {
            assertRoundingEq(vat.sin(address(vow)), prevSin + (standardDebtSize / 2) * RAY - prevDai);
            assertEq(vat.dai(address(vow)), 0);
        } else {
            assertRoundingEq(vat.dai(address(vow)), prevDai - prevSin - (standardDebtSize / 2) * RAY);
            assertEq(vat.sin(address(vow)), 0);
        }

        // Some time later the pool gets some liquidity
        setLiquidity(standardDebtSize / 2);

        // Rest of the liquidity can be withdrawn
        hub.exec(ilk);
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(vat.sin(address(vow)), 0);
        assertGe(vat.dai(address(vow)), prevDai); // As also probably accrues interest
    }

    function test_unwind_mcd_caged_skimmed() public {
        setDebt(standardDebtSize);
        setLiquidity(standardDebtSize / 2);

        (uint256 pink,) = vat.urns(ilk, address(pool));

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

        // Position is taken by the End module
        end.skim(ilk, address(pool));
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));
        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(end)), pink);
        if (prevSin + standardDebtSize * RAY >= prevDai) {
            assertRoundingEq(vat.sin(address(vow)), prevSin + standardDebtSize * RAY - prevDai);
            assertEq(vat.dai(address(vow)), 0);
        } else {
            assertRoundingEq(vat.dai(address(vow)), prevDai - prevSin - standardDebtSize * RAY);
            assertEq(vat.sin(address(vow)), 0);
        }

        // We try to unwind what is possible
        hub.exec(ilk);
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));

        // Part can't be done yet
        assertRoundingEq(vat.gem(ilk, address(end)), standardDebtSize / 2);
        if (prevSin + (standardDebtSize / 2) * RAY >= prevDai) {
            assertRoundingEq(vat.sin(address(vow)), prevSin + (standardDebtSize / 2) * RAY - prevDai);
            assertEq(vat.dai(address(vow)), 0);
        } else {
            assertRoundingEq(vat.dai(address(vow)), prevDai - prevSin - (standardDebtSize / 2) * RAY);
            assertEq(vat.sin(address(vow)), 0);
        }

        // Some time later the pool gets some liquidity
        setLiquidity(standardDebtSize / 2);

        // Rest of the liquidity can be withdrawn
        hub.exec(ilk);
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(vat.sin(address(vow)), 0);
        assertGe(vat.dai(address(vow)), prevDai); // As also probably accrues interest
    }

    function test_unwind_mcd_caged_wait_done() public {
        setDebt(standardDebtSize);
        setLiquidity(standardDebtSize / 2);

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
        setDebt(standardDebtSize);
        setLiquidity(standardDebtSize / 2);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));

        vm.prank(admin); hub.cage(ilk);

        (, , , uint256 tau, , ) = hub.ilks(ilk);

        vm.warp(block.timestamp + tau);

        uint256 daiEarned = pool.assetBalance() - pink;

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
        assertGe(pool.assetBalance(), pink);

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
        assertGe(pool.assetBalance(), pink);
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
        assertGe(pool.assetBalance(), pink);
        if (originalSin + part * RAY >= originalDai) {
            assertRoundingEq(vat.sin(address(vow)), originalSin + part * RAY - originalDai);
            assertEq(vat.dai(address(vow)), 0);
        } else {
            assertRoundingEq(vat.dai(address(vow)), originalDai - originalSin - part * RAY);
            assertEq(vat.sin(address(vow)), 0);
        }

        // We try to unwind what is possible
        hub.exec(ilk);
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));

        // A part can't be unwind yet
        assertRoundingEq(vat.gem(ilk, address(end)), standardDebtSize / 2);
        assertRoundingEq(pool.assetBalance(), standardDebtSize / 2);
        if (originalSin + part * RAY >= originalDai + (standardDebtSize / 2) * RAY) {
            // rounding may affect twice, and multiplied by RAY to be compared with sin
            assertRoundingEq(vat.sin(address(vow)), originalSin + part * RAY - originalDai - (standardDebtSize / 2) * RAY);
            assertEq(vat.dai(address(vow)), 0);
        } else {
            // rounding may affect twice, and multiplied by RAY to be compared with sin
            assertRoundingEq(vat.dai(address(vow)), originalDai + (standardDebtSize / 2) * RAY - originalSin - part * RAY);
            assertEq(vat.sin(address(vow)), 0);
        }

        // Then pool gets some liquidity
        setLiquidity(standardDebtSize / 2);

        // Rest of the liquidity can be withdrawn
        hub.exec(ilk);
        vow.heal(_min(vat.sin(address(vow)), vat.dai(address(vow))));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(pool.assetBalance(), 0);
        assertEq(vat.sin(address(vow)), 0);
        assertRoundingEq(vat.dai(address(vow)), originalDai - originalSin + daiEarned * RAY);
    }

    function test_uncull_not_culled() public {
        setDebt(standardDebtSize);
        vm.prank(admin); hub.cage(ilk);

        // MCD shutdowns
        vm.prank(admin); end.cage();

        assertRevert(address(hub), abi.encodeWithSignature("uncull(bytes32)", ilk), "D3MHub/not-prev-culled");
    }

    function test_uncull_not_shutdown() public {
        setDebt(standardDebtSize);
        vm.prank(admin); hub.cage(ilk);

        (, , , uint256 tau, , ) = hub.ilks(ilk);
        vm.warp(block.timestamp + tau);

        hub.cull(ilk);

        assertRevert(address(hub), abi.encodeWithSignature("uncull(bytes32)", ilk), "D3MHub/no-uncull-normal-operation");
    }

    function test_cage_exit() public {
        setDebt(standardDebtSize);
        setLiquidity(0);

        // Vat is caged for global settlement
        vm.prank(admin); end.cage();
        end.cage(ilk);
        end.skim(ilk, address(pool));

        // Simulate DAI holder gets some gems from GS
        uint256 takeAmount = standardDebtSize / 2;
        vm.prank(address(end)); vat.flux(ilk, address(end), address(this), takeAmount);

        uint256 totalArt = end.Art(ilk);

        assertEq(getTokenBalanceInAssets(address(this)), 0);

        // User can exit and get the Token
        uint256 expected = takeAmount * pool.assetBalance() / totalArt;
        hub.exit(ilk, address(this), takeAmount);
        assertRoundingEq(expected, takeAmount);
        assertRoundingEq(getTokenBalanceInAssets(address(this)), expected);
    }

    function test_cage_exit_multiple() public {
        setDebt(standardDebtSize);
        setLiquidity(0);

        // Vat is caged for global settlement
        vm.prank(admin); end.cage();
        end.cage(ilk);
        end.skim(ilk, address(pool));

        uint256 totalArt = end.Art(ilk);

        // Simulate DAI holder gets some gems from GS
        vm.prank(address(end)); vat.flux(ilk, address(end), address(this), totalArt);

        assertEq(getTokenBalanceInAssets(address(this)), 0);

        // User can exit and get the Token
        uint256 takeAmount = standardDebtSize / 8;
        uint256 expectedToken = takeAmount * pool.assetBalance() / totalArt;
        hub.exit(ilk, address(this), takeAmount);
        assertRoundingEq(expectedToken, takeAmount);
        assertRoundingEq(getTokenBalanceInAssets(address(this)), expectedToken);

        generateInterest();

        uint256 expectedToken2 = takeAmount * pool.assetBalance() / (totalArt - takeAmount);
        assertGt(expectedToken2, expectedToken);
        hub.exit(ilk, address(this), takeAmount);
        assertRoundingEq(getTokenBalanceInAssets(address(this)), expectedToken + expectedToken2);

        generateInterest();

        takeAmount = uint256(standardDebtSize / 4);
        uint256 expectedToken3 = takeAmount * pool.assetBalance() / (totalArt - takeAmount);
        assertGt(expectedToken3, expectedToken + expectedToken2);
        hub.exit(ilk, address(this), takeAmount);
        assertRoundingEq(getTokenBalanceInAssets(address(this)), expectedToken + expectedToken2 + expectedToken3);

        generateInterest();

        takeAmount = uint256(standardDebtSize / 2);
        uint256 expectedToken4 = (totalArt - takeAmount) * pool.assetBalance() / (totalArt - takeAmount);
        hub.exit(ilk, address(this), (totalArt - takeAmount));
        assertRoundingEq(getTokenBalanceInAssets(address(this)), expectedToken + expectedToken2 + expectedToken3 + expectedToken4);
        assertEq(pool.assetBalance(), 0);
    }

    function test_shutdown_cant_cull() public {
        setDebt(standardDebtSize);

        vm.prank(admin); hub.cage(ilk);

        // Vat is caged for global settlement
        vm.prank(admin); vat.cage();

        (, , , uint256 tau, , ) = hub.ilks(ilk);
        vm.warp(block.timestamp + tau);

        assertRevert(address(hub), abi.encodeWithSignature("cull(bytes32)", ilk), "D3MHub/no-cull-during-shutdown");
    }

    function test_quit_no_cull() public {
        setDebt(standardDebtSize);
        setLiquidity(standardDebtSize / 2);

        vm.prank(admin); hub.cage(ilk);

        // Test that we can extract the whole position in emergency situations
        // Token should be sitting in the deposit contract, urn should be owned by deposit contract
        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        uint256 pbal = pool.assetBalance();
        assertGt(pink, 0);
        assertGt(part, 0);
        assertGt(pbal, 0);

        address receiver = address(123);

        vm.prank(admin); pool.quit(address(receiver));
        vm.prank(admin); vat.grab(ilk, address(pool), address(receiver), address(receiver), -int256(pink), -int256(part));
        vm.prank(admin); vat.grab(ilk, address(receiver), address(receiver), address(receiver), int256(pink), int256(part));

        (uint256 nink, uint256 nart) = vat.urns(ilk, address(pool));
        uint256 nbal = pool.assetBalance();
        assertEq(nink, 0);
        assertEq(nart, 0);
        assertEq(nbal, 0);

        (uint256 ink, uint256 art) = vat.urns(ilk, receiver);
        uint256 bal = getTokenBalanceInAssets(receiver) + dai.balanceOf(receiver);
        assertEq(ink, pink);
        assertEq(art, part);
        assertEq(bal, pbal);
    }

    function test_quit_cull() public {
        setDebt(standardDebtSize);
        setLiquidity(standardDebtSize / 2);

        vm.prank(admin); hub.cage(ilk);

        (, , , uint256 tau, , ) = hub.ilks(ilk);
        vm.warp(block.timestamp + tau);

        hub.cull(ilk);

        // Test that we can extract the token in emergency situations
        // Token should be sitting in the deposit contract, gems should be owned by deposit contract
        uint256 pgem = vat.gem(ilk, address(pool));
        uint256 pbal = pool.assetBalance();
        assertGt(pgem, 0);
        assertGt(pbal, 0);

        address receiver = address(123);

        vm.prank(admin); pool.quit(address(receiver));
        vm.prank(admin); vat.slip(ilk, address(pool), -int256(pgem));

        uint256 ngem = vat.gem(ilk, address(pool));
        uint256 nbal = pool.assetBalance();
        assertEq(ngem, 0);
        assertEq(nbal, 0);

        uint256 gem = vat.gem(ilk, receiver);
        uint256 bal = getTokenBalanceInAssets(receiver) + dai.balanceOf(receiver);
        assertEq(gem, 0);
        assertEq(bal, pbal);
    }

    function test_direct_deposit_mom() public {
        setDebt(standardDebtSize);

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
        (, , , uint256 tau, , ) = hub.ilks(ilk);
        assertEq(tau, 7 days);
        vm.prank(admin); hub.file(ilk, "tau", 1 days);
        (, , , tau, , ) = hub.ilks(ilk);
        assertEq(tau, 1 days);
    }

    function test_fully_unwind_debt_paid_back() public {
        uint256 liquidityBalanceInitial = getLiquidity();

        setDebt(standardDebtSize);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        uint256 gemBefore = vat.gem(ilk, address(pool));
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(address(vow));
        uint256 vowDaiBefore = vat.dai(address(vow));
        uint256 liquidityBalanceBefore = getLiquidity();
        uint256 assetsBalanceBefore = pool.assetBalance();

        // Someone pays back our debt
        deal(address(dai), address(this), 10 * WAD);
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
        assertEq(pool.assetBalance(), assetsBalanceBefore);

        // We should be able to close out the vault completely even though ink and art do not match
        vm.prank(admin); plan.disable();

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, 0);
        assertRoundingEq(art, 0);
        assertEq(vat.gem(ilk, address(pool)), 0);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(address(vow)), sinBefore);
        assertRoundingEq(vat.dai(address(vow)), vowDaiBefore + 10 * RAD);
        assertRoundingEq(getLiquidity(), liquidityBalanceInitial);
        assertEq(pool.assetBalance(), 0);
    }

    function test_wind_partial_unwind_wind_debt_paid_back() public {
        setDebt(standardDebtSize);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        uint256 gemBefore = vat.gem(ilk, address(pool));
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(address(vow));
        uint256 vowDaiBefore = vat.dai(address(vow));
        uint256 liquidityBalanceBefore = getLiquidity();

        // Someone pays back our debt
        deal(address(dai), address(this), 10 * WAD);
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

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, pink);
        assertRoundingEq(art, part);
        assertEq(ink, art);
        assertEq(vat.gem(ilk, address(pool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(address(vow)), sinBefore);
        assertRoundingEq(vat.dai(address(vow)), vowDaiBefore + 10 * RAD);
        assertEq(getLiquidity(), liquidityBalanceBefore);

        // Decrease debt
        setDebt(standardDebtSize / 2);

        (ink, art) = vat.urns(ilk, address(pool));
        assertLt(ink, pink);
        assertLt(art, part);
        assertEq(ink, art);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(address(vow)), sinBefore);
        assertRoundingEq(vat.dai(address(vow)), vowDaiBefore + 10 * RAD);
        assertEq(vat.gem(ilk, address(pool)), gemBefore);
        assertLt(getLiquidity(), liquidityBalanceBefore);

        // can re-wind and have the correct amount of debt
        setDebt(standardDebtSize);

        (ink, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(ink, pink);
        assertRoundingEq(art, part);
        assertEq(ink, art);
        assertEq(vat.gem(ilk, address(pool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(address(vow)), sinBefore);
        assertRoundingEq(vat.dai(address(vow)), vowDaiBefore + 10 * RAD);
        assertRoundingEq(getLiquidity(), liquidityBalanceBefore);
    }
}
