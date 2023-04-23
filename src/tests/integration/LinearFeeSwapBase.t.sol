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
    using ScriptTools for *;

    GemAbstract gem;
    DSValueAbstract pip;
    DSValueAbstract swapGemForDaiPip;
    DSValueAbstract swapDaiForGemPip;
    uint256 gemConversionFactor;

    D3MALMDelegateControllerPlan plan;
    D3MLinearFeeSwapPool pool;

    function setUp() public virtual {
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
    function getGem() internal virtual view returns (address);
    function getPip() internal virtual view returns (address);
    function getSwapGemForDaiPip() internal virtual view returns (address);
    function getSwapDaiForGemPip() internal virtual view returns (address);

    // --- Overrides ---
    function setDebt(uint256 amount) internal override {
        plan.setAllocation(address(this), ilk, uint128(amount));
        hub.exec(ilk);
    }

    function setLiquidity(uint256 amount) internal override {
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
            pool.swapDaiForGem(address(this), delta, 0);
        } else {
            // Decrease DAI liquidity by swapping gems for dai
            uint256 delta = prev - amount;
            uint256 gemAmount = daiToGem(delta);
            deal(address(gem), address(this), gemAmount);
            pool.swapGemForDai(address(this), gemAmount, 0);
        }
    }

    function generateInterest() internal override {
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

        assertApproxEqAbs(dai.balanceOf(address(pool)), 0, 1);
        assertRoundingEq(gem.balanceOf(address(pool)), daiToGem(standardDebtCeiling));
        pool.swapDaiForGem(address(this), standardDebtCeiling / 2, 0);
        assertRoundingEq(dai.balanceOf(address(pool)), standardDebtCeiling / 2);
        assertRoundingEq(gem.balanceOf(address(pool)), daiToGem(standardDebtCeiling / 2));
    }

}

contract USDCSwapTest is LinearFeeSwapBaseTest {
    
    function getGem() internal override pure returns (address) {
        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function getPip() internal override pure returns (address) {
        return 0x77b68899b99b686F415d074278a9a16b336085A0;  // Hardcoded $1 pip
    }

    function getSwapGemForDaiPip() internal override pure returns (address) {
        return 0x77b68899b99b686F415d074278a9a16b336085A0;
    }

    function getSwapDaiForGemPip() internal override pure returns (address) {
        return 0x77b68899b99b686F415d074278a9a16b336085A0;
    }

}

contract GUSDSwapTest is LinearFeeSwapBaseTest {

    using stdStorage for StdStorage;
    
    function getGem() internal override pure returns (address) {
        return 0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd;
    }

    function getPip() internal override pure returns (address) {
        return 0xf45Ae69CcA1b9B043dAE2C83A5B65Bc605BEc5F5;  // Hardcoded $1 pip
    }

    function getSwapGemForDaiPip() internal override pure returns (address) {
        return 0xf45Ae69CcA1b9B043dAE2C83A5B65Bc605BEc5F5;
    }

    function getSwapDaiForGemPip() internal override pure returns (address) {
        return 0xf45Ae69CcA1b9B043dAE2C83A5B65Bc605BEc5F5;
    }

    // GUSD has a separate storage contract so we need to override deal
    function deal(address token, address to, uint256 give) internal override {
        if (token == getGem()) {
            // Target the storage contract for GUSD
            stdstore.target(0xc42B14e49744538e3C239f8ae48A1Eaaf35e68a0).sig(bytes4(abi.encodeWithSignature("balances(address)"))).with_key(to).checked_write(give);
        } else {
            super.deal(token, to, give);
        }
    }

}

contract USDPSwapTest is LinearFeeSwapBaseTest {
    
    function getGem() internal override pure returns (address) {
        return 0x8E870D67F660D95d5be530380D0eC0bd388289E1;
    }

    function getPip() internal override pure returns (address) {
        return 0x043B963E1B2214eC90046167Ea29C2c8bDD7c0eC;  // Hardcoded $1 pip
    }

    function getSwapGemForDaiPip() internal override pure returns (address) {
        return 0x043B963E1B2214eC90046167Ea29C2c8bDD7c0eC;
    }

    function getSwapDaiForGemPip() internal override pure returns (address) {
        return 0x043B963E1B2214eC90046167Ea29C2c8bDD7c0eC;
    }

}

contract BackedIB01SwapTest is LinearFeeSwapBaseTest {

    PipMock private _pip;

    function setUp() public override {
        // Setup an oracle
        _pip = new PipMock();
        _pip.poke(1.2 ether);   // Set to some non-$1 value
        
        super.setUp();
    }
    
    function getGem() internal override pure returns (address) {
        return 0xCA30c93B02514f86d5C86a6e375E3A330B435Fb5;
    }

    function getPip() internal override view returns (address) {
        return address(_pip);
    }

    function getSwapGemForDaiPip() internal override view returns (address) {
        return address(_pip);
    }

    function getSwapDaiForGemPip() internal override view returns (address) {
        return address(_pip);
    }

}
