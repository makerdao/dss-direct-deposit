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
import "morpho-blue/src/libraries/MarketParamsLib.sol";
import "morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import "metamorpho/libraries/PendingLib.sol";
import "forge-std/interfaces/IERC4626.sol";

// Versioning issues with import, so it's inline
interface IMetaMorpho is IERC4626 {
    function owner() external view returns (address);
    function timelock() external view returns (uint256);
    function withdrawQueue(uint256) external view returns (Id);
    function withdrawQueueLength() external view returns (uint256);
    function config(Id) external view returns (MarketConfig memory);
    function setSupplyQueue(Id[] calldata newSupplyQueue) external;
    function submitCap(MarketParams memory marketParams, uint256 newSupplyCap) external;
    function acceptCap(MarketParams memory marketParams) external;
}

contract MetaMorphoTest is IntegrationBaseTest {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    IMetaMorpho constant spDai = IMetaMorpho(0x73e65DBD630f90604062f6E02fAb9138e713edD9);
    address constant sUsde = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    IMorpho constant morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    D3MOperatorPlan plan;
    D3M4626TypePool pool;

    // sUSDe/USDC (91.5%).
    MarketParams public marketParams = MarketParams({
        loanToken: 0x6B175474E89094C44Da98b954EedeAC495271d0F,
        collateralToken: 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497,
        oracle: 0x5D916980D5Ae1737a8330Bf24dF812b2911Aae25,
        irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
        lltv: 915000000000000000
    });
    // sUSDe/USDC (94.5%).
    MarketParams public marketParamsHighLltv = MarketParams({
        loanToken: 0x6B175474E89094C44Da98b954EedeAC495271d0F,
        collateralToken: 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497,
        oracle: 0x5D916980D5Ae1737a8330Bf24dF812b2911Aae25,
        irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
        lltv: 945000000000000000
    });

    address operator = makeAddr("operator");
    uint256 constant startingAmount = 5_000_000 * WAD;

    function setUp() public {
        baseInit();

        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 19456934);

        // Need to increase to 3
        roundingTolerance = 3;

        // Deploy.
        d3m.oracle = D3MDeploy.deployOracle(address(this), admin, ilk, address(dss.vat));
        d3m.pool = D3MDeploy.deploy4626TypePool(address(this), admin, ilk, address(hub), address(dai), address(spDai));
        pool = D3M4626TypePool(d3m.pool);
        d3m.plan = D3MDeploy.deployOperatorPlan(address(this), admin);
        plan = D3MOperatorPlan(d3m.plan);

        // Init.
        vm.startPrank(admin);
        D3MCommonConfig memory cfg = D3MCommonConfig({
            hub: address(hub),
            mom: address(mom),
            ilk: ilk,
            existingIlk: false,
            maxLine: startingAmount * RAY * 100000, // Set gap and max line to large number to avoid hitting limits
            gap: startingAmount * RAY * 100000,
            ttl: 0,
            tau: 7 days
        });
        D3MInit.initCommon(dss, d3m, cfg);
        D3MInit.init4626Pool(dss, d3m, cfg, D3M4626PoolConfig({vault: address(spDai)}));
        D3MInit.initOperatorPlan(d3m, D3MOperatorPlanConfig({operator: operator}));
        vm.stopPrank();

        // Give us some DAI.
        deal(address(dai), address(this), startingAmount * 100000000);
        dai.approve(address(morpho), type(uint256).max);
        // Give us some sUSDe.
        deal(address(sUsde), address(this), startingAmount * 100000000);
        DaiAbstract(sUsde).approve(address(morpho), type(uint256).max);
        // Supply huge collat.
        morpho.supplyCollateral(marketParams, startingAmount * 10000, address(this), "");

        // Set sUSDe/USDC (91.5%) in the supply queue.
        Id[] memory newSupplyQueue = new Id[](1);
        newSupplyQueue[0] = marketParams.id();
        vm.prank(IMetaMorpho(spDai).owner());
        IMetaMorpho(spDai).setSupplyQueue(newSupplyQueue);

        // Set 0 cap for all listed markets.
        for (uint256 i; i < spDai.withdrawQueueLength(); i++) {
            setCap(morpho.idToMarketParams(spDai.withdrawQueue(i)), 0);
        }
        // Set max cap for sUSDe/USDC (91.5%).
        setCap(marketParams, type(uint184).max);

        basePostSetup();
    }

    // --- Overrides ---
    function adjustDebt(int256 deltaAmount) internal override {
        if (deltaAmount == 0) return;

        int256 newTargetAssets = int256(plan.targetAssets()) + deltaAmount;
        vm.prank(operator);
        plan.setTargetAssets(newTargetAssets >= 0 ? uint256(newTargetAssets) : 0);
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
        return morpho.market(marketParams.id()).totalSupplyAssets - morpho.market(marketParams.id()).totalBorrowAssets;
    }

    function getLPTokenBalanceInAssets(address a) internal view override returns (uint256) {
        return spDai.convertToAssets(spDai.balanceOf(a));
    }

    // --- Helpers ---
    function setCap(MarketParams memory mp, uint256 newCap) internal {
        uint256 previousCap = spDai.config(mp.id()).cap;
        if (previousCap != newCap) {
            vm.prank(IMetaMorpho(spDai).owner());
            spDai.submitCap(mp, newCap);
            if (previousCap < newCap) {
                vm.warp(block.timestamp + spDai.timelock());
                spDai.acceptCap(mp);
            }
        }
    }

    // --- Tests ---
    function testDepositInOneMarket(uint256 d3mDeposit) public {
        uint256 marketSupplyBefore = morpho.market(marketParams.id()).totalSupplyAssets;
        uint256 spDaiTotalSupplyBefore = spDai.totalSupply();
        uint256 spDaiTotalAssetsBefore = spDai.totalAssets();
        uint256 spDaiMaxDepositBefore = spDai.maxDeposit(address(pool));
        uint256 morphoBalanceBefore = dai.balanceOf(address(morpho));
        uint256 daiTotalSupplyBefore = dai.totalSupply();

        assertEq(spDai.totalSupply(), 0);
        assertEq(spDai.totalAssets(), 0);
        assertEq(plan.targetAssets(), 0);
        assertEq(spDai.maxDeposit(address(pool)), type(uint184).max);

        // Set target assets at `d3mDeposit` and exec.
        vm.prank(operator);
        plan.setTargetAssets(d3mDeposit);
        hub.exec(ilk);

        (,,, uint256 line,) = VatAbstract(vat).ilks(ilk);
        uint256 depositedAssets = UtilsLib.min(d3mDeposit, line * 1e18 / 1e45);
        
        assertEq(plan.targetAssets(), d3mDeposit);
        
        assertEq(morpho.market(marketParams.id()).totalSupplyAssets, marketSupplyBefore + depositedAssets);
        
        assertEq(spDai.balanceOf(address(pool)), depositedAssets);
        assertEq(spDai.totalSupply(), spDaiTotalSupplyBefore + depositedAssets);
        assertEq(spDai.totalAssets(), spDaiTotalAssetsBefore + morpho.expectedSupplyAssets(marketParams, address(spDai)));
        assertEq(spDai.maxDeposit(address(pool)), spDaiMaxDepositBefore - depositedAssets);
        
        assertEq(dai.balanceOf(address(morpho)), morphoBalanceBefore + depositedAssets);
        assertEq(dai.totalSupply(), daiTotalSupplyBefore + depositedAssets);
    }
}
