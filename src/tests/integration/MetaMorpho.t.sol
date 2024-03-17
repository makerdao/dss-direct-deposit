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

import "forge-std/Test.sol";
import "./IntegrationBase.t.sol";
import "morpho-blue/src/interfaces/IMorpho.sol";

contract MetaMorphoTest is IntegrationBaseTest {
    address constant spDai = 0xB8C7F2a4B3bF76CC04bd55Ebc259b33a67b3b36d;
    address constant sUsde = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    IMorpho constant morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    D3MOperatorPlan plan;
    D3M4626TypePool pool;

    // sUSDe/USDC (91.5%).
    Id constant id = Id.wrap(0x1247f1c237eceae0602eab1470a5061a6dd8f734ba88c7cdc5d6109fb0026b28);
    MarketParams public marketParams = MarketParams({
        loanToken: 0x6B175474E89094C44Da98b954EedeAC495271d0F,
        collateralToken: 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497,
        oracle: 0x5D916980D5Ae1737a8330Bf24dF812b2911Aae25,
        irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
        lltv: 915000000000000000
    });

    address operator = makeAddr("operator");

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 19440000);

        baseInit();

        // Give us some DAI.
        deal(address(dai), address(this), type(uint256).max);
        dai.approve(address(morpho), type(uint256).max);
        // Give us some sUSDe.
        deal(address(sUsde), address(this), type(uint256).max);
        DaiAbstract(sUsde).approve(address(morpho), type(uint256).max);
        // Supply huge collat.
        morpho.supplyCollateral(marketParams, type(uint128).max, address(this), "");

        // Deploy.
        d3m.oracle = D3MDeploy.deployOracle(address(this), admin, ilk, address(dss.vat));
        d3m.pool = D3MDeploy.deploy4626TypePool(address(this), admin, ilk, address(hub), address(dai), address(spDai));
        pool = D3M4626TypePool(d3m.pool);
        d3m.plan = D3MDeploy.deployOperatorPlan(address(this), admin);
        plan = D3MOperatorPlan(d3m.plan);
        
        // Init.
        vm.startPrank(admin);
        uint256 buffer = 5_000_000 * WAD;
        D3MCommonConfig memory cfg = D3MCommonConfig({
            hub: address(hub),
            mom: address(mom),
            ilk: ilk,
            existingIlk: false,
            maxLine: buffer * RAY * 100000,     // Set gap and max line to large number to avoid hitting limits
            gap: buffer * RAY * 100000,
            ttl: 0,
            tau: 7 days
        });
        D3MInit.initCommon(dss, d3m, cfg);
        D3MInit.init4626Pool(dss, d3m, cfg, D3M4626PoolConfig({vault: spDai}));
        D3MInit.initOperatorPlan(d3m, D3MOperatorPlanConfig({operator: operator}));
        vm.stopPrank();

        basePostSetup();
    }

    // --- Overrides ---
    function adjustDebt(int256 deltaAmount) internal override {
        if (deltaAmount == 0) return;

        uint256 newTargetAssets = uint256(int256(plan.targetAssets()) + deltaAmount);
        vm.prank(operator);
        plan.setTargetAssets(newTargetAssets);
        hub.exec(ilk);
    }

    function adjustLiquidity(int256 deltaAmount) internal override {
        if (deltaAmount == 0) return;

        if (deltaAmount > 0) {
            // Supply to increase liquidity
            uint256 amt = uint256(deltaAmount);
            morpho.supply(marketParams, amt, 0, address(this), "");
        } else {
            // Borrow to decrease liquidity
            uint256 amt = uint256(-deltaAmount);
            morpho.borrow(marketParams, amt, 0, address(this), address(this));
        }
    }

    function generateInterest() internal override {
        vm.warp(block.timestamp + 1 days);
        morpho.accrueInterest(marketParams);
    }

    function getLiquidity() internal view override returns (uint256) {
        return morpho.market(id).totalSupplyAssets - morpho.market(id).totalBorrowAssets;
    }

    // --- Helper functions ---
    function getDebtCeiling() internal view returns (uint256) {
        (,,, uint256 line,) = dss.vat.ilks(ilk);
        return line;
    }

    function getDebt() internal view returns (uint256) {
        (, uint256 art) = dss.vat.urns(ilk, address(pool));
        return art;
    }

    // // --- Tests ---
    // function test_simple_wind_unwind() public {
    //     setLiquidityToZero();

    //     assertEq(getDebt(), 0);

    //     hub.exec(ilk);
    //     assertEq(getDebt(), buffer, "should wind up to the buffer");

    //     // User borrows half the debt injected by the D3M
    //     sparkPool.borrow(address(dai), buffer / 2, 2, 0, address(this));
    //     assertEq(getDebt(), buffer);

    //     hub.exec(ilk);
    //     assertEq(getDebt(), buffer + buffer / 2, "should have 1.5x the buffer in debt");

    //     // User repays half their debt
    //     sparkPool.repay(address(dai), buffer / 4, 2, address(this));
    //     assertEq(getDebt(), buffer + buffer / 2);

    //     hub.exec(ilk);
    //     assertEq(getDebt(), buffer + buffer / 2 - buffer / 4, "should be back down to 1.25x the buffer");
    // }
}
