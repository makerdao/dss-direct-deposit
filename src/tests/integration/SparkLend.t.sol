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
import { DSTokenAbstract } from "dss-interfaces/Interfaces.sol";
import { D3MForwardFees } from "../../fees/D3MForwardFees.sol";

import { D3MAaveTypeBufferPlan } from "../../plans/D3MAaveTypeBufferPlan.sol";
import { D3MAaveV3NoSupplyCapTypePool } from "../../pools/D3MAaveV3NoSupplyCapTypePool.sol";

interface PoolLike {

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

    function getReserveData(address asset) external view returns (ReserveData memory);
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external;
    function withdraw(address asset, uint256 amount, address to) external;
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
    function mintToTreasury(address[] calldata assets) external;
}

interface ATokenLike {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function decimals() external view returns (uint8);
    function RESERVE_TREASURY_ADDRESS() external view returns (address);
    function scaledBalanceOf(address) external view returns (uint256);
    function scaledTotalSupply() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function getIncentivesController() external view returns (address);
}

interface DaiInterestRateStrategyLike {
    function recompute() external;
    function performanceBonus() external view returns (uint256);
}

contract SparkLendTest is IntegrationBaseTest {

    using stdJson for string;
    using MCD for *;
    using ScriptTools for *;

    PoolLike sparkPool;
    DaiInterestRateStrategyLike daiInterestRateStrategy;
    ATokenLike adai;
    address someUser = address(0x1234);

    D3MAaveTypeBufferPlan plan;
    D3MAaveV3NoSupplyCapTypePool pool;

    function setUp() public {
        baseInit();

        // NOTE: Adding past block until fix to work against deployed protocol is introduced.
        // TODO: Update the test to work against deployed protocol with latest block.
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 17_200_000);

        sparkPool = PoolLike(0xC13e21B648A5Ee794902342038FF3aDAB66BE987);
        daiInterestRateStrategy = DaiInterestRateStrategyLike(getInterestRateStrategy(address(dai)));
        adai = ATokenLike(0x4DEDf26112B3Ec8eC46e7E31EA5e123490B05B8B);

        // Deploy
        d3m.oracle = D3MDeploy.deployOracle(
            address(this),
            admin,
            ilk,
            address(dss.vat)
        );
        d3m.pool = D3MDeploy.deployAaveV3NoSupplyCapTypePool(
            address(this),
            admin,
            ilk,
            address(hub),
            address(dai),
            address(sparkPool)
        );
        pool = D3MAaveV3NoSupplyCapTypePool(d3m.pool);
        d3m.plan = D3MDeploy.deployAaveBufferPlan(
            address(this),
            admin,
            address(adai)
        );
        plan = D3MAaveTypeBufferPlan(d3m.plan);
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
        D3MInit.initAavePool(
            dss,
            d3m,
            cfg,
            D3MAavePoolConfig({
                king: admin,
                adai: address(pool.adai()),
                stableDebt: address(pool.stableDebt()),
                variableDebt: address(pool.variableDebt())
            })
        );
        D3MInit.initAaveBufferPlan(
            d3m,
            D3MAaveBufferPlanConfig({
                buffer: standardDebtSize * 5,
                adai: address(pool.adai())
            })
        );

        vm.stopPrank();

        // Deposit WETH into the pool so we have effectively unlimited collateral to borrow against
        vm.startPrank(someUser);
        uint256 amt = 1_000_000 * WAD;
        DSTokenAbstract weth = DSTokenAbstract(dss.getIlk("ETH", "A").gem);
        deal(address(weth), someUser, amt);
        weth.approve(address(sparkPool), type(uint256).max);
        dai.approve(address(sparkPool), type(uint256).max);
        sparkPool.supply(address(weth), amt, someUser, 0);
        vm.stopPrank();

        // Recompute the dai interest rate strategy to ensure the new line is taken into account
        daiInterestRateStrategy.recompute();

        basePostSetup();
    }

    // --- Overrides ---
    function setDebt(uint256 amount) internal override {
        vm.prank(admin); plan.file("buffer", amount);
        hub.exec(ilk);
    }

    function setLiquidity(uint256 amount) internal override {
        vm.startPrank(someUser);
        uint256 currLiquidity = getLiquidity();
        if (amount >= currLiquidity) {
            // Supply to increase liquidity
            uint256 amt = amount - currLiquidity;
            deal(address(dai), someUser, dai.balanceOf(someUser) + amt);
            sparkPool.supply(address(dai), amt, someUser, 0);
        } else {
            // Borrow to decrease liquidity
            uint256 amt = currLiquidity - amount;
            sparkPool.borrow(address(dai), amt, 2, 0, someUser);
        }
        vm.stopPrank();
    }

    function generateInterest() internal override {
        // Generate interest by borrowing and repaying
        vm.startPrank(someUser);
        uint256 performanceBonus = daiInterestRateStrategy.performanceBonus();
        if (performanceBonus == 0) performanceBonus = standardDebtSize;
        deal(address(dai), someUser, dai.balanceOf(someUser) + performanceBonus * 4);
        sparkPool.supply(address(dai), performanceBonus * 4, someUser, 0);
        sparkPool.borrow(address(dai), performanceBonus * 2, 2, 0, someUser);
        vm.warp(block.timestamp + 1 days);
        sparkPool.repay(address(dai), performanceBonus * 2, 2, someUser);
        sparkPool.withdraw(address(dai), performanceBonus * 4, someUser);
        vm.stopPrank();
    }

    // --- Helper functions ---
    function getInterestRateStrategy(address asset) internal view returns (address) {
        PoolLike.ReserveData memory data = sparkPool.getReserveData(asset);
        return data.interestRateStrategyAddress;
    }

    // --- Tests ---
    function test_simple_wind_unwind() public {
        assertEq(getDebt(), 0);
        uint256 buffer = plan.buffer();

        hub.exec(ilk);
        assertRoundingEq(getDebt(), buffer, "should wind up to the buffer");

        // User borrows half the debt injected by the D3M
        vm.prank(someUser); sparkPool.borrow(address(dai), buffer / 2, 2, 0, someUser);
        assertRoundingEq(getDebt(), buffer);

        hub.exec(ilk);
        assertRoundingEq(getDebt(), buffer + buffer / 2, "should have 1.5x the buffer in debt");

        // User repays half their debt
        vm.prank(someUser); sparkPool.repay(address(dai), buffer / 4, 2, someUser);
        assertRoundingEq(getDebt(), buffer + buffer / 2);

        hub.exec(ilk);
        assertRoundingEq(getDebt(), buffer + buffer / 2 - buffer / 4, "should be back down to 1.25x the buffer");
    }
}
