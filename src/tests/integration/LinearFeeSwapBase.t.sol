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

import "./IntegrationBase.t.sol";
import { PipMock } from "../mocks/PipMock.sol";

import { D3MALMDelegateControllerPlan } from "../../plans/D3MALMDelegateControllerPlan.sol";
import { D3MLinearFeeSwapPool } from "../../pools/D3MLinearFeeSwapPool.sol";

abstract contract LinearFeeSwapBaseTest is IntegrationBaseTest {

    using stdJson for string;
    using MCD for *;
    using GodMode for *;
    using ScriptTools for *;

    GemAbstract gem;
    DSValueAbstract pip;
    DSValueAbstract sellGemPip;
    DSValueAbstract buyGemPip;
    uint256 gemConversionFactor;

    D3MALMDelegateControllerPlan plan;
    D3MLinearFeeSwapPool pool;

    function setUp() public {
        baseInit();

        uint256 debtCeiling = uint256(standardDebtSize) * 100;

        gem = GemAbstract(getGem());
        gemConversionFactor = 10 ** (18 - gem.decimals());
        pip = DSValueAbstract(getPip());
        sellGemPip = DSValueAbstract(getSellGemPip());
        buyGemPip = DSValueAbstract(getBuyGemPip());

        // Deploy
        d3m.oracle = D3MDeploy.deployOracle(
            address(this),
            admin,
            ilk,
            address(dss.vat)
        );
        d3m.pool = D3MDeploy.deployLinearFeeSwapPool(
            address(this),
            admin,
            ilk,
            address(hub),
            address(dai),
            address(gem)
        );
        pool = D3MLinearFeeSwapPool(d3m.pool);
        d3m.plan = D3MDeploy.deployALMDelegateControllerPlan(
            address(this),
            admin
        );
        plan = D3MALMDelegateControllerPlan(d3m.plan);

        // Init
        vm.startPrank(admin);

        D3MCommonConfig memory cfg = D3MCommonConfig({
            hub: address(hub),
            mom: address(mom),
            ilk: ilk,
            existingIlk: false,
            maxLine: debtCeiling * RAY,
            gap: debtCeiling * RAY,
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
                sellGemPip: address(sellGemPip),
                buyGemPip: address(buyGemPip)
            })
        );

        // Add ourselves to the plan
        plan.addAllocator(address(this));
        plan.setMaxAllocation(address(this), ilk, uint128(debtCeiling));

        vm.stopPrank();
        
        // Give us some dai and gems and infinite approval
        dai.setBalance(address(this), debtCeiling);
        address(gem).setBalance(address(this), daiToGem(debtCeiling));
        dai.approve(address(pool), type(uint256).max);
        gem.approve(address(pool), type(uint256).max);

        basePostSetup();
    }

    // --- To Override ---
    function getGem() internal virtual view returns (address);
    function getPip() internal virtual view returns (address);
    function getSellGemPip() internal virtual view returns (address);
    function getBuyGemPip() internal virtual view returns (address);

    // --- Overrides ---
    function adjustDebt(int256 deltaAmount) internal override {
        if (deltaAmount == 0) return;
        
        (uint128 current,) = plan.allocations(address(this), ilk);
        int256 newValue = int256(uint256(current)) + deltaAmount;
        plan.setAllocation(address(this), ilk, newValue > 0 ? uint128(uint256(newValue)) : 0);
        hub.exec(ilk);
    }

    function adjustLiquidity(int256 deltaAmount) internal override {
        if (deltaAmount == 0) return;

        if (deltaAmount > 0) {
            uint256 amt = uint256(deltaAmount);
            dai.setBalance(address(pool), dai.balanceOf(address(pool)) + amt);
        } else {
            uint256 amt = uint256(-deltaAmount);
            dai.setBalance(address(pool), dai.balanceOf(address(pool)) - amt);
        }
    }

    function generateInterest() internal override {
        // Generate interest by adding more gems to the pool
        gem.transfer(address(pool), daiToGem(standardDebtSize / 10));
    }

    function getLiquidity() internal override view returns (uint256) {
        return dai.balanceOf(address(pool));
    }

    // --- Helper functions ---
    function daiToGem(uint256 daiAmount) internal view returns (uint256) {
        return daiAmount * WAD / (gemConversionFactor * uint256(pip.read()));
    }

    function gemToDai(uint256 gemAmount) internal view returns (uint256) {
        return gemAmount * (gemConversionFactor * uint256(pip.read())) / WAD;
    }
    
    // --- Tests ---
    function test_swap() public {
        
    }

}

contract USDCSwapTest is LinearFeeSwapBaseTest {
    
    function getGem() internal override pure returns (address) {
        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function getPip() internal override pure returns (address) {
        return 0x77b68899b99b686F415d074278a9a16b336085A0;  // Hardcoded $1 pip
    }

    function getSellGemPip() internal override pure returns (address) {
        return 0x77b68899b99b686F415d074278a9a16b336085A0;
    }

    function getBuyGemPip() internal override pure returns (address) {
        return 0x77b68899b99b686F415d074278a9a16b336085A0;
    }

}
