// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
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

import "./IntegrationBase.t.sol";
import { PipMock } from "../mocks/PipMock.sol";

import { D3MALMDelegateControllerPlan } from "../../plans/D3MALMDelegateControllerPlan.sol";
import { D3MSwapPool } from "../../pools/D3MSwapPool.sol";

abstract contract SwapPoolBaseTest is IntegrationBaseTest {

    using stdJson for string;
    using MCD for *;
    using ScriptTools for *;

    GemAbstract gem;
    DSValueAbstract pip;
    DSValueAbstract swapGemForDaiPip;
    DSValueAbstract swapDaiForGemPip;
    uint256 gemConversionFactor;

    D3MALMDelegateControllerPlan plan;
    D3MSwapPool private pool;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        baseInit();

        gem = GemAbstract(getGem());
        gemConversionFactor = 10 ** (18 - gem.decimals());
        pip = DSValueAbstract(getPip());
        swapGemForDaiPip = DSValueAbstract(getSwapGemForDaiPip());
        swapDaiForGemPip = DSValueAbstract(getSwapDaiForGemPip());

        // Deploy
        d3m.oracle = D3MDeploy.deployOracle(
            address(this),
            admin,
            ilk,
            address(dss.vat)
        );
        d3m.pool = deployPool();
        pool = D3MSwapPool(d3m.pool);
        d3m.plan = D3MDeploy.deployALMDelegateControllerPlan(
            address(this),
            admin
        );
        plan = D3MALMDelegateControllerPlan(d3m.plan);
        d3m.fees = D3MDeploy.deployForwardFees(
            address(vat),
            address(vow)
        );

        // Init
        vm.startPrank(admin);

        D3MCommonConfig memory cfg = D3MCommonConfig({
            hub: address(hub),
            mom: address(mom),
            ilk: ilk,
            existingIlk: false,
            maxLine: standardDebtCeiling * RAY,
            gap: standardDebtCeiling * RAY,
            ttl: 0,
            tau: 7 days
        });
        D3MInit.initCommon(
            dss,
            d3m,
            cfg
        );
        D3MInit.initSwapPool(
            dss,
            d3m,
            cfg,
            D3MSwapPoolConfig({
                gem: address(gem),
                pip: address(pip),
                swapGemForDaiPip: address(swapGemForDaiPip),
                swapDaiForGemPip: address(swapDaiForGemPip)
            })
        );

        // Add ourselves to the plan
        plan.addAllocator(address(this));
        plan.setMaxAllocation(address(this), ilk, uint128(standardDebtCeiling));

        vm.stopPrank();
        
        // Give infinite approval to the pools
        dai.approve(address(pool), type(uint256).max);
        gem.approve(address(pool), type(uint256).max);

        basePostSetup();
    }

    // --- To Override ---
    function deployPool() internal virtual returns (address);
    function getGem() internal virtual view returns (address);
    function getPip() internal virtual view returns (address);
    function getSwapGemForDaiPip() internal virtual view returns (address);
    function getSwapDaiForGemPip() internal virtual view returns (address);

    // --- Overrides ---
    function setDebt(uint256 amount) internal override virtual {
        plan.setAllocation(address(this), ilk, uint128(amount));
        hub.exec(ilk);
    }

    function setLiquidity(uint256 amount) internal override virtual {
        (uint128 currentAllocation, uint128 max) = plan.allocations(address(this), ilk);
        uint256 prev = dai.balanceOf(address(pool));
        if (amount >= prev) {
            // Increase dai liquidity by swapping dai for gems (or just adding it if there isn't enough gems)
            uint256 delta = amount - prev;
            uint256 gemBalance = gem.balanceOf(address(pool));
            uint256 gemAmount = daiToGemRoundUp(delta);
            if (gemBalance < gemAmount) {
                // Ensure there is enough gems to swap
                deal(address(gem), address(pool), gemAmount);
            }
            deal(address(dai), address(this), delta);
            plan.setAllocation(address(this), ilk, 0);
            pool.swapDaiForGem(address(this), delta, 0);
        } else {
            // Decrease DAI liquidity by swapping gems for dai
            uint256 delta = prev - amount;
            uint256 gemAmount = daiToGem(delta);
            deal(address(gem), address(this), gemAmount);
            plan.setAllocation(address(this), ilk, max);
            pool.swapGemForDai(address(this), gemAmount, 0);
        }
        plan.setAllocation(address(this), ilk, currentAllocation);
    }

    function generateInterest() internal override virtual {
        // Generate interest by adding more gems to the pool
        deal(address(gem), address(pool), gem.balanceOf(address(pool)) + daiToGem(standardDebtSize / 100));
    }

    function getTokenBalanceInAssets(address a) internal view override returns (uint256) {
        return gemToDai(gem.balanceOf(a));
    }

    // --- Helper functions ---
    function daiToGem(uint256 daiAmount) internal view returns (uint256) {
        return daiAmount * WAD / (gemConversionFactor * uint256(pip.read()));
    }

    function daiToGemRoundUp(uint256 daiAmount) internal view returns (uint256) {
        return _divup(daiAmount * WAD, gemConversionFactor * uint256(pip.read()));
    }

    function gemToDai(uint256 gemAmount) internal view returns (uint256) {
        return gemAmount * (gemConversionFactor * uint256(pip.read())) / WAD;
    }

    function gemToDaiRoundUp(uint256 gemAmount) internal view returns (uint256) {
        return _divup(gemAmount * gemConversionFactor * uint256(pip.read()), WAD);
    }

    function initSwaps() internal {
        plan.setAllocation(address(this), ilk, uint128(standardDebtCeiling));
        hub.exec(ilk);
        deal(address(gem), address(this), daiToGem(standardDebtCeiling));
        deal(address(dai), address(this), standardDebtCeiling);
    }
    
    // --- Tests ---
    function test_swapGemForDai() public {
        initSwaps();

        assertEq(dai.balanceOf(address(pool)), standardDebtCeiling);
        assertEq(gem.balanceOf(address(pool)), 0);
        pool.swapGemForDai(address(this), daiToGem(standardDebtCeiling / 2), 0);
        assertRoundingEq(dai.balanceOf(address(pool)), standardDebtCeiling / 2);
        assertRoundingEq(gem.balanceOf(address(pool)), daiToGem(standardDebtCeiling / 2));
    }

    function test_swapDaiForGem() public {
        initSwaps();
        pool.swapGemForDai(address(this), daiToGem(standardDebtCeiling), 0);

        assertApproxEqAbs(dai.balanceOf(address(pool)), 0, 1 ether);
        assertRoundingEq(gem.balanceOf(address(pool)), daiToGem(standardDebtCeiling));
        plan.setAllocation(address(this), ilk, 0);
        pool.swapDaiForGem(address(this), standardDebtCeiling / 2, 0);
        assertRoundingEq(dai.balanceOf(address(pool)), standardDebtCeiling / 2);
        assertRoundingEq(gem.balanceOf(address(pool)), daiToGem(standardDebtCeiling / 2));
    }

}
