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

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { NstDeploy, NstInstance } from "nst/deploy/NstDeploy.sol";
import { NstInit } from "nst/deploy/NstInit.sol";

import { D3MOperatorPlan } from "../../plans/D3MOperatorPlan.sol";
import { D3MAaveV3NSTNoSupplyCapTypePool } from "../../pools/D3MAaveV3NSTNoSupplyCapTypePool.sol";

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
}

interface PoolConfiguratorLike {

    struct InitReserveInput {
        address aTokenImpl;
        address stableDebtTokenImpl;
        address variableDebtTokenImpl;
        bool useVirtualBalance;
        address interestRateStrategyAddress;
        address underlyingAsset;
        address treasury;
        address incentivesController;
        string aTokenName;
        string aTokenSymbol;
        string variableDebtTokenName;
        string variableDebtTokenSymbol;
        string stableDebtTokenName;
        string stableDebtTokenSymbol;
        bytes params;
        bytes interestRateData;
    }

    struct InterestRateData {
        uint16 optimalUsageRatio;
        uint32 baseVariableBorrowRate;
        uint32 variableRateSlope1;
        uint32 variableRateSlope2;
    }

    function initReserves(
        InitReserveInput[] calldata input
    ) external;
    function setReserveBorrowing(address asset, bool enabled) external;
}

interface AaveOracleLike {
    function setAssetSources(address[] calldata assets, address[] calldata sources) external;
}

contract AaveV3LidoTest is IntegrationBaseTest {

    using stdJson for string;
    using MCD for *;
    using GodMode for *;
    using ScriptTools for *;

    address constant AAVE_EXECUTOR = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A;
    address constant AAVE_ATOKEN_IMPL = 0x7F8Fc14D462bdF93c681c1f2Fd615389bF969Fb2;
    address constant AAVE_VARIABLE_DEBT_IMPL = 0x3E59212c34588a63350142EFad594a20C88C2CEd;
    address constant AAVE_STABLE_DEBT_IMPL = 0x36284fED68f802c5733432c3306D8e92c504a243;
    address constant AAVE_IRM = 0x6642dcAaBc80807DD083c66a301d308568CBcA3D;
    address constant AAVE_TREASURY = 0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c;
    address constant AAVE_INCENTIVES = 0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb;
    address constant AAVE_ORACLE = 0xE3C061981870C0C7b1f3C4F4bB36B95f1F260BE6;

    address constant AAVE_POOL = 0x4e033931ad43597d96D6bcc25c280717730B58B1;
    address constant AAVE_CONFIGURATOR = 0x342631c6CeFC9cfbf97b2fe4aa242a236e1fd517;
    address constant OPERATOR = 0x298b375f24CeDb45e936D7e21d6Eb05e344adFb5;  // Gov. facilitator multisig

    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    PoolLike aavePool = PoolLike(AAVE_POOL);
    PoolConfiguratorLike aaveConfigurator = PoolConfiguratorLike(AAVE_CONFIGURATOR);
    NstInstance nstInstance;

    IERC20 nst;

    D3MOperatorPlan plan;
    D3MAaveV3NSTNoSupplyCapTypePool pool;

    function setUp() public {
        baseInit();

        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 20469508);  // Aug 6, 2024

        // Setup NST
        nstInstance = NstDeploy.deploy(address(this), admin, address(dss.daiJoin));
        nst = IERC20(nstInstance.nst);
        vm.startPrank(admin);
        NstInit.init(dss, nstInstance);
        vm.stopPrank();

        // Add NST as a reserve to the Aave Lido pool
        PoolConfiguratorLike.InitReserveInput[] memory reserves = new PoolConfiguratorLike.InitReserveInput[](1);
        reserves[0] = PoolConfiguratorLike.InitReserveInput({
            aTokenImpl: AAVE_ATOKEN_IMPL,
            stableDebtTokenImpl: AAVE_STABLE_DEBT_IMPL,
            variableDebtTokenImpl: AAVE_VARIABLE_DEBT_IMPL,
            useVirtualBalance: true,
            interestRateStrategyAddress: AAVE_IRM,
            underlyingAsset: address(nst),
            treasury: AAVE_TREASURY,
            incentivesController: AAVE_INCENTIVES,
            aTokenName: "Aave NST",
            aTokenSymbol: "aNST",
            variableDebtTokenName: "Aave NST Variable Debt",
            variableDebtTokenSymbol: "vNST",
            stableDebtTokenName: "Aave NST Stable Debt",
            stableDebtTokenSymbol: "sNST",
            params: "",
            interestRateData: abi.encode(PoolConfiguratorLike.InterestRateData({
                optimalUsageRatio: 90_00,
                baseVariableBorrowRate: 5_00,
                variableRateSlope1: 8_00,
                variableRateSlope2: 120_00
            }))
        });
        vm.startPrank(AAVE_EXECUTOR);
        aaveConfigurator.initReserves(reserves);
        address[] memory assets = new address[](1);
        address[] memory sources = new address[](1);
        assets[0] = address(nst);
        sources[0] = 0x42a03F81dd8A1cEcD746dc262e4d1CD9fD39F777;  // Hardcoded $1 oracle
        AaveOracleLike(AAVE_ORACLE).setAssetSources(assets, sources);
        aaveConfigurator.setReserveBorrowing(address(nst), true);
        vm.stopPrank();

        // Deploy
        d3m.oracle = D3MDeploy.deployOracle(
            address(this),
            admin,
            ilk,
            address(dss.vat)
        );
        d3m.pool = D3MDeploy.deployAaveV3NSTNoSupplyCapTypePool(
            address(this),
            admin,
            ilk,
            address(hub),
            address(nstInstance.nstJoin),
            address(daiJoin),
            address(aavePool)
        );
        pool = D3MAaveV3NSTNoSupplyCapTypePool(d3m.pool);
        d3m.plan = D3MDeploy.deployOperatorPlan(
            address(this),
            admin
        );
        plan = D3MOperatorPlan(d3m.plan);

        // Init
        vm.startPrank(admin);

        D3MCommonConfig memory cfg = D3MCommonConfig({
            hub: address(hub),
            mom: address(mom),
            ilk: ilk,
            existingIlk: false,
            maxLine: 100_000_000e45,
            gap: 100_000_000e45,
            ttl: 24 hours,
            tau: 7 days
        });
        D3MInit.initCommon(
            dss,
            d3m,
            cfg
        );
        D3MInit.initAaveNSTPool(
            dss,
            d3m,
            cfg,
            D3MAaveNSTPoolConfig({
                king: admin,
                anst: address(pool.anst()),
                nstJoin: nstInstance.nstJoin,
                nst: nstInstance.nst,
                stableDebt: address(pool.stableDebt()),
                variableDebt: address(pool.variableDebt())
            })
        );
        D3MInit.initOperatorPlan(
            d3m,
            D3MOperatorPlanConfig({
                operator: OPERATOR
            })
        );

        vm.stopPrank();

        // Give us some NST
        deal(address(nst), address(this), 100_000_000e18);

        // Deposit wstETH into the pool
        uint256 amt = 100_000 * WAD;
        IERC20 wstETH = IERC20(WSTETH);
        deal(address(wstETH), address(this), amt);
        wstETH.approve(address(aavePool), type(uint256).max);
        nst.approve(address(aavePool), type(uint256).max);
        aavePool.supply(address(wstETH), amt, address(this), 0);

        // We generate unbacked ERC20 NST -- ensure there is enough in the join adapter
        vm.prank(admin);
        dss.vat.suck(address(nstInstance.nstJoin), address(nstInstance.nstJoin), 100_000_000e45);

        assertGt(getDebtCeiling(), 0);

        basePostSetup();
    }

    // --- Overrides ---
    function adjustDebt(int256 deltaAmount) internal override {
        if (deltaAmount == 0) return;

        int256 newTargetAssets = int256(plan.targetAssets()) + deltaAmount;
        vm.prank(OPERATOR);
        plan.setTargetAssets(newTargetAssets >= 0 ? uint256(newTargetAssets) : 0);
        hub.exec(ilk);
    }

    function adjustLiquidity(int256 deltaAmount) internal override {
        if (deltaAmount == 0) return;

        if (deltaAmount > 0) {
            // Supply to increase liquidity
            uint256 amt = uint256(deltaAmount);
            deal(address(nst), address(this), nst.balanceOf(address(this)) + amt);
            aavePool.supply(address(nst), amt, address(0), 0);
        } else {
            // Borrow to decrease liquidity
            uint256 amt = uint256(-deltaAmount);
            aavePool.borrow(address(nst), amt, 2, 0, address(this));
        }
    }

    function generateInterest() internal override {
        // Generate interest by borrowing and repaying
        aavePool.supply(address(nst), 10_000_000e18, address(this), 0);
        aavePool.borrow(address(nst), 5_000_000e18, 2, 0, address(this));
        vm.warp(block.timestamp + 1 days);
        aavePool.repay(address(nst), 5_000_000e18, 2, address(this));
        aavePool.withdraw(address(nst), 10_000_000e18, address(this));
    }

    function getLiquidity() internal override view returns (uint256) {
        return nst.balanceOf(address(pool.anst()));
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

}
