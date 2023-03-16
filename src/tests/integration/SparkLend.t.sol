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

interface DaiInterestRateStrategyLike {
    function recompute() external;
    function performanceBonus() external view returns (uint256);
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

interface TreasuryLike {
    function getFundsAdmin() external view returns (TreasuryAdminLike);
}

interface TreasuryAdminLike {
    function transfer(
        address collector,
        address token,
        address recipient,
        uint256 amount
    ) external;
}

contract SparkLendTest is IntegrationBaseTest {

    using stdJson for string;
    using MCD for *;
    using GodMode for *;
    using ScriptTools for *;

    PoolLike sparkPool;
    DaiInterestRateStrategyLike daiInterestRateStrategy;
    ATokenLike adai;
    TreasuryLike treasury;
    TreasuryAdminLike treasuryAdmin;
    uint256 buffer;

    D3MAaveTypeBufferPlan plan;
    D3MAaveV3NoSupplyCapTypePool pool;

    function setUp() public {
        baseInit();

        sparkPool = PoolLike(0xC13e21B648A5Ee794902342038FF3aDAB66BE987);
        daiInterestRateStrategy = DaiInterestRateStrategyLike(getInterestRateStrategy(address(dai)));
        adai = ATokenLike(0x4DEDf26112B3Ec8eC46e7E31EA5e123490B05B8B);
        treasury = TreasuryLike(adai.RESERVE_TREASURY_ADDRESS());
        treasuryAdmin = treasury.getFundsAdmin();
        buffer = 5_000_000 * WAD;
        assertGt(buffer, 0);

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

        // Init
        vm.startPrank(admin);

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
                buffer: buffer,
                adai: address(pool.adai())
            })
        );

        vm.stopPrank();
        
        // Give us some DAI
        dai.setBalance(address(this), buffer * 100000000);

        // Deposit WETH into the pool
        uint256 amt = 1_000_000 * WAD;
        DSTokenAbstract weth = DSTokenAbstract(dss.getIlk("ETH", "A").gem);
        weth.setBalance(address(this), amt);
        weth.approve(address(sparkPool), type(uint256).max);
        dai.approve(address(sparkPool), type(uint256).max);
        sparkPool.supply(address(weth), amt, address(this), 0);

        assertGt(getDebtCeiling(), 0);

        // Recompute the dai interest rate strategy to ensure the new line is taken into account
        daiInterestRateStrategy.recompute();

        basePostSetup();
    }

    // --- Overrides ---
    function adjustDebt(int256 deltaAmount) internal override {
        if (deltaAmount == 0) return;
        
        int256 newBuffer = int256(plan.buffer()) + deltaAmount;
        vm.prank(admin); plan.file("buffer", newBuffer >= 0 ? uint256(newBuffer) : 0);
        hub.exec(ilk);
    }

    function adjustLiquidity(int256 deltaAmount) internal override {
        if (deltaAmount == 0) return;

        if (deltaAmount > 0) {
            // Supply to increase liquidity
            uint256 amt = uint256(deltaAmount);
            dai.setBalance(address(this), dai.balanceOf(address(this)) + amt);
            sparkPool.supply(address(dai), amt, address(0), 0);
        } else {
            // Borrow to decrease liquidity
            uint256 amt = uint256(-deltaAmount);
            if (amt > getLiquidity()) {
                amt = getLiquidity();
            }
            sparkPool.borrow(address(dai), amt, 2, 0, address(this));
        }
    }

    function generateInterest() internal override {
        // Generate interest by borrowing and repaying
        uint256 performanceBonus = daiInterestRateStrategy.performanceBonus();
        sparkPool.supply(address(dai), performanceBonus * 4, address(this), 0);
        sparkPool.borrow(address(dai), performanceBonus * 2, 2, 0, address(this));
        vm.warp(block.timestamp + 1 days);
        sparkPool.repay(address(dai), performanceBonus * 2, 2, address(this));
        sparkPool.withdraw(address(dai), performanceBonus * 4, address(this));
    }

    function getLiquidity() internal override view returns (uint256) {
        return dai.balanceOf(address(adai));
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

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

    function getSupplyUsed(address asset) internal view returns (uint256) {
        PoolLike.ReserveData memory data = sparkPool.getReserveData(asset);
        return _divup((adai.scaledTotalSupply() + uint256(data.accruedToTreasury)) * data.liquidityIndex, RAY);
    }

    function getInterestRateStrategy(address asset) internal view returns (address) {
        PoolLike.ReserveData memory data = sparkPool.getReserveData(asset);
        return data.interestRateStrategyAddress;
    }

    function forceUpdateIndicies(address asset) internal {
        // Do the flashloan trick to force update indicies
        sparkPool.flashLoanSimple(address(this), asset, 1, "", 0);
    }

    function executeOperation(
        address,
        uint256,
        uint256,
        address,
        bytes calldata
    ) external pure returns (bool) {
        // Flashloan callback just immediately returns
        return true;
    }

    function getTotalAssets(address asset) internal view returns (uint256) {
        // Assets = DAI Liquidity + Total Debt
        PoolLike.ReserveData memory data = sparkPool.getReserveData(asset);
        return dai.balanceOf(address(adai)) + ATokenLike(data.variableDebtTokenAddress).totalSupply() + ATokenLike(data.stableDebtTokenAddress).totalSupply();
    }

    function getTotalLiabilities(address asset) internal view returns (uint256) {
        // Liabilities = spDAI Supply + Amount Accrued to Treasury
        return getSupplyUsed(asset);
    }

    function getAccruedToTreasury(address asset) internal view returns (uint256) {
        PoolLike.ReserveData memory data = sparkPool.getReserveData(asset);
        return data.accruedToTreasury;
    }

    // --- Tests ---
    function test_wind() public {
        setLiquidityToZero();

        assertEq(getDebt(), 0);

        hub.exec(ilk);

        assertEq(getDebt(), buffer, "should wind up to the buffer");
    }

    function test_wind_twice() public {
        setLiquidityToZero();

        hub.exec(ilk);

        // User borrows half the debt injected by the D3M
        sparkPool.borrow(address(dai), buffer / 2, 2, 0, address(this));
        assertEq(getDebt(), buffer);

        hub.exec(ilk);

        assertEq(getDebt(), buffer + buffer / 2, "should have 1.5x the buffer in debt");
    }

    function test_wind_unwind() public {
        setLiquidityToZero();

        hub.exec(ilk);
        sparkPool.borrow(address(dai), buffer / 2, 2, 0, address(this));
        hub.exec(ilk);

        // User repays half their debt
        assertEq(getDebt(), buffer + buffer / 2);
        sparkPool.repay(address(dai), buffer / 4, 2, address(this));
        assertEq(getDebt(), buffer + buffer / 2);

        hub.exec(ilk);

        assertEq(getDebt(), buffer + buffer / 2 - buffer / 4, "should be back down to 1.25x the buffer");
    }

    /** 
     * The DAI market is using a new interest model which over-allocates interest to the treasury.
     * This is due to the reserve factor not being flexible enough to account for this.
     * Confirm that we can later correct the discrepancy by donating the excess liabilities back to the DAI pool. (This can be automated later on)
     */
    function test_asset_liabilities_fix() public {
        uint256 assets = getTotalAssets(address(dai));
        uint256 liabilities = getTotalLiabilities(address(dai));
        if (assets >= liabilities) {
            // Force the assets to become less than the liabilities
            uint256 performanceBonus = daiInterestRateStrategy.performanceBonus();
            vm.prank(admin); plan.file("buffer", performanceBonus * 4);
            hub.exec(ilk);
            sparkPool.borrow(address(dai), performanceBonus * 2, 2, 0, address(this));  // Supply rate should now be above 0% (we are over-allocating)

            // Warp so we gaurantee there is new interest
            vm.warp(block.timestamp + 365 days);
            forceUpdateIndicies(address(dai));

            assets = getTotalAssets(address(dai));
            liabilities = getTotalLiabilities(address(dai));
            assertLe(assets, liabilities, "assets should be less than or equal to liabilities");
        }
        
        // Let's fix the accounting
        uint256 delta = liabilities - assets;

        // First trigger all spDAI owed to the treasury to be accrued
        assertGt(getAccruedToTreasury(address(dai)), 0, "accrued to treasury should be greater than 0");
        address[] memory toMint = new address[](1);
        toMint[0] = address(dai);
        sparkPool.mintToTreasury(toMint);
        assertEq(getAccruedToTreasury(address(dai)), 0, "accrued to treasury should be 0");
        assertGe(adai.balanceOf(address(treasury)), delta, "adai treasury should have more than the delta between liabilities and assets");

        // Donate the excess liabilities back to the pool
        // This will burn the liabilities while keeping the assets the same
        vm.prank(admin); treasuryAdmin.transfer(address(treasury), address(adai), address(this), delta);
        sparkPool.withdraw(address(dai), delta, address(adai));

        assets = getTotalAssets(address(dai)) + 1;  // In case of rounding error we +1
        liabilities = getTotalLiabilities(address(dai));
        assertGe(assets, liabilities, "assets should be greater than or equal to liabilities");
    }
}
