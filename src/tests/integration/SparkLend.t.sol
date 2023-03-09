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
import { DSTokenAbstract } from "dss-interfaces/Interfaces.sol";

import { D3MHub } from "../../D3MHub.sol";
import { D3MMom } from "../../D3MMom.sol";

import { D3MOracle } from "../../D3MOracle.sol";
import { D3MAaveTypeBufferPlan } from "../../plans/D3MAaveTypeBufferPlan.sol";
import { D3MAaveV3TypePool, ATokenLike } from "../../pools/D3MAaveV3TypePool.sol";

import {
    D3MDeploy,
    D3MInstance
} from "../../deploy/D3MDeploy.sol";
import {
    D3MInit,
    D3MCommonConfig,
    D3MAavePoolConfig,
    D3MAaveBufferPlanConfig
} from "../../deploy/D3MInit.sol";

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

    function ADDRESSES_PROVIDER() external view returns (PoolAddressProviderLike);
    function getReserveData(address asset) external view returns (ReserveData memory);
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external;
    function withdraw(address asset, uint256 amount, address to) external;
}

interface PoolAddressProviderLike {
    function getPoolConfigurator() external view returns (PoolConfiguratorLike);
}

interface PoolConfiguratorLike {
    function setSupplyCap(address asset, uint256 newSupplyCap) external;
    function setReserveFlashLoaning(address asset, bool enabled) external;
}

contract SparkLendTest is DssTest {

    using stdJson for string;
    using MCD for *;
    using GodMode for *;
    using ScriptTools for *;

    string config;
    address admin;
    bytes32 ilk;
    DssInstance dss;
    D3MInstance d3m;

    PoolLike sparkPool;
    PoolConfiguratorLike configurator;
    address adai;
    uint256 buffer;

    D3MHub hub;
    D3MMom mom;

    D3MAaveTypeBufferPlan plan;
    D3MAaveV3TypePool pool;

    uint256 constant FLASHLOAN_ENABLED_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF7FFFFFFFFFFFFFFF;
    uint256 constant SUPPLY_CAP_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFF000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 constant SUPPLY_CAP_START_BIT_POSITION = 116;
    string constant SUPPLY_CAP_EXCEEDED = '51';  // SUPPLY_CAP_EXCEEDED error code 

    function setUp() public {
        config = ScriptTools.readInput("template-spark");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));
        admin = config.readAddress(".admin");
        ilk = config.readString(".ilk").stringToBytes32();
        hub = D3MHub(dss.chainlog.getAddress("DIRECT_HUB"));
        mom = D3MMom(dss.chainlog.getAddress("DIRECT_MOM"));

        assertEq(admin, dss.chainlog.getAddress("MCD_PAUSE_PROXY"), "admin should be pause proxy");

        sparkPool = PoolLike(config.readAddress(".lendingPool"));
        configurator = sparkPool.ADDRESSES_PROVIDER().getPoolConfigurator();
        adai = config.readAddress(".adai");
        buffer = config.readUint(".buffer") * WAD;
        assertGt(buffer, 0);

        // Deploy
        d3m.oracle = D3MDeploy.deployOracle(
            address(this),
            admin,
            ilk,
            address(dss.vat)
        );
        d3m.pool = D3MDeploy.deployAaveV3TypePool(
            address(this),
            admin,
            ilk,
            address(hub),
            address(dss.dai),
            address(sparkPool)
        );
        pool = D3MAaveV3TypePool(d3m.pool);
        d3m.plan = D3MDeploy.deployAaveBufferPlan(
            address(this),
            admin,
            adai
        );
        plan = D3MAaveTypeBufferPlan(d3m.plan);

        // Init
        vm.startPrank(admin);

        D3MCommonConfig memory cfg = D3MCommonConfig({
            hub: address(hub),
            mom: address(mom),
            ilk: ilk,
            existingIlk: config.readBool(".existingIlk"),
            maxLine: buffer * RAY * 1000,     // Set gap and max line to large number to avoid hitting limits
            gap: buffer * RAY * 1000,
            ttl: 0,
            tau: config.readUint(".tau")
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
                king: config.readAddress(".king"),
                adai: address(pool.adai()),
                stableDebt: address(pool.stableDebt()),
                variableDebt: address(pool.variableDebt())
            })
        );
        D3MInit.initAaveBufferPlan(
            d3m,
            D3MAaveBufferPlanConfig({
                buffer: buffer,
                adai: address(pool.adai()),
                adaiRevision: plan.adaiRevision()
            })
        );

        vm.stopPrank();
        
        // Give us some DAI
        dss.dai.setBalance(address(this), buffer * 100);

        // Deposit WETH into the pool
        uint256 amt = 1_000_000 * WAD;
        DSTokenAbstract weth = DSTokenAbstract(dss.getIlk("ETH", "A").gem);
        weth.setBalance(address(this), amt);
        weth.approve(address(sparkPool), type(uint256).max);
        dss.dai.approve(address(sparkPool), type(uint256).max);
        sparkPool.deposit(address(weth), amt, address(this), 0);
        
        // Set the liquidity of DAI to 0 to simplify things
        dss.dai.setBalance(address(adai), 0);

        assertGt(getDebtCeiling(), 0);
    }

    // Helper functions
    function getDebtCeiling() internal view returns (uint256) {
        (,,, uint256 line,) = dss.vat.ilks(ilk);
        return line;
    }
    function getDebt() internal view returns (uint256) {
        (, uint256 art) = dss.vat.urns(ilk, address(pool));
        return art;
    }
    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }
    function getSupplyUsed() internal view returns (uint256) {
        PoolLike.ReserveData memory data = sparkPool.getReserveData(address(dss.dai));
        return _divup((ATokenLike(adai).scaledTotalSupply() + uint256(data.accruedToTreasury)) * data.liquidityIndex, RAY);
    }

    function test_wind() public {
        assertEq(getDebt(), 0);

        hub.exec(ilk);

        assertEq(getDebt(), buffer, "should wind up to the buffer");
    }

    function test_wind_twice() public {
        hub.exec(ilk);

        // User borrows half the debt injected by the D3M
        sparkPool.borrow(address(dss.dai), buffer / 2, 2, 0, address(this));
        assertEq(getDebt(), buffer);

        hub.exec(ilk);

        assertEq(getDebt(), buffer + buffer / 2, "should have 1.5x the buffer in debt");
    }

    function test_wind_unwind() public {
        hub.exec(ilk);
        sparkPool.borrow(address(dss.dai), buffer / 2, 2, 0, address(this));
        hub.exec(ilk);

        // User repays half their debt
        assertEq(getDebt(), buffer + buffer / 2);
        sparkPool.repay(address(dss.dai), buffer / 4, 2, address(this));
        assertEq(getDebt(), buffer + buffer / 2);

        hub.exec(ilk);

        assertEq(getDebt(), buffer + buffer / 2 - buffer / 4, "should be back down to 1.25x the buffer");
    }

    function test_supplyCap_hit() public {
        // Supply and borrow some DAI to ensure interest is being generated
        sparkPool.deposit(address(dss.dai), buffer / 4, address(this), 0);
        sparkPool.borrow(address(dss.dai), buffer / 8, 2, 0, address(this));

        // Spark doesn't have a supply cap, but let's make sure the maxDeposit() works if it it's turned on
        uint256 currentSupply = getSupplyUsed();
        vm.prank(admin);
        configurator.setSupplyCap(address(dss.dai), (currentSupply + buffer / 2) / WAD);    // Set the supply cap well within the buffer

        PoolLike.ReserveData memory data = sparkPool.getReserveData(address(dss.dai));
        uint256 supplyCap = ((data.configuration & ~SUPPLY_CAP_MASK) >> SUPPLY_CAP_START_BIT_POSITION) * (1 ether);
        bool flashLoansEnabled = (data.configuration & ~FLASHLOAN_ENABLED_MASK) != 0;

        // Pre-requisites for executing the flash loan to correct liquidity index and accrued treasury amounts
        assertEq(flashLoansEnabled, true, "flash loans should be enabled");
        assertGt(dss.dai.balanceOf(adai), 0, "adai should have dai balance");

        // Warp so we gaurantee there is new interest
        vm.warp(block.timestamp + 1 days);

        uint256 prevMaxDeposit = supplyCap - _divup((ATokenLike(adai).scaledTotalSupply() + uint256(data.accruedToTreasury)) * data.liquidityIndex, RAY);
        assertEq(pool.maxDeposit(), prevMaxDeposit, "max deposit should be equal to validation logic");

        // Exec should run and mint right up to the supply cap
        hub.exec(ilk);

        uint256 amountMinted = ATokenLike(adai).balanceOf(address(pool));
        assertGt(amountMinted, 0, "amount minted should be greater than 0");
        assertLt(amountMinted, prevMaxDeposit, "amounted minted should be less than previous max deposit"); // This number should be less due to interest collection being deductated after flash loan
        assertLt(pool.maxDeposit(), 1, "max deposit should be ~0");
    }

    function test_supplyCap_hit_no_flashloans() public {
        // Supply and borrow some DAI to ensure interest is being generated
        sparkPool.deposit(address(dss.dai), buffer / 4, address(this), 0);
        sparkPool.borrow(address(dss.dai), buffer / 8, 2, 0, address(this));

        // Spark doesn't have a supply cap, but let's make sure the maxDeposit() works if it it's turned on
        uint256 currentSupply = getSupplyUsed();
        vm.prank(admin);
        configurator.setSupplyCap(address(dss.dai), (currentSupply + buffer / 2) / WAD);    // Set the supply cap well within the buffer
        vm.prank(admin);
        configurator.setReserveFlashLoaning(address(dss.dai), false);

        PoolLike.ReserveData memory data = sparkPool.getReserveData(address(dss.dai));
        uint256 supplyCap = ((data.configuration & ~SUPPLY_CAP_MASK) >> SUPPLY_CAP_START_BIT_POSITION) * (1 ether);
        bool flashLoansEnabled = (data.configuration & ~FLASHLOAN_ENABLED_MASK) != 0;

        // Pre-requisites for executing the flash loan to correct liquidity index and accrued treasury amounts
        assertEq(flashLoansEnabled, false, "flash loans should be disabled");
        assertGt(dss.dai.balanceOf(adai), 0, "adai should have dai balance");

        // Warp so we gaurantee there is new interest
        vm.warp(block.timestamp + 1 days);

        uint256 prevMaxDeposit = supplyCap - _divup((ATokenLike(adai).scaledTotalSupply() + uint256(data.accruedToTreasury)) * data.liquidityIndex, RAY);
        assertEq(pool.maxDeposit(), prevMaxDeposit, "max deposit should be equal to validation logic");

        // This should revert now because maxDeposit() is using stale values and overestimating
        vm.expectRevert(bytes(SUPPLY_CAP_EXCEEDED));
        hub.exec(ilk);
    }
}