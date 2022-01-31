// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
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

pragma solidity 0.6.12;

import "ds-test/test.sol";
import "dss-interfaces/Interfaces.sol";
import "ds-value/value.sol";

import {DssDirectDepositAaveDai} from "./DssDirectDepositAaveDai.sol";
import {DirectDepositMom} from "./DirectDepositMom.sol";
import {DirectHelper} from "./helper/DirectHelper.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external view returns (bytes32);
}

interface AuthLike {
    function wards(address) external returns (uint256);
}

interface LendingPoolLike {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external;
    function getReserveNormalizedIncome(address asset) external view returns (uint256);
    function getReserveData(address asset) external view returns (
        uint256,    // Configuration
        uint128,    // the liquidity index. Expressed in ray
        uint128,    // variable borrow index. Expressed in ray
        uint128,    // the current supply rate. Expressed in ray
        uint128,    // the current variable borrow rate. Expressed in ray
        uint128,    // the current stable borrow rate. Expressed in ray
        uint40,
        address,    // address of the adai interest bearing token
        address,    // address of the stable debt token
        address,    // address of the variable debt token
        address,    // address of the interest rate strategy
        uint8
    );
}

interface InterestRateStrategyLike {
    function getMaxVariableBorrowRate() external view returns (uint256);
    function calculateInterestRates(
        address reserve,
        uint256 availableLiquidity,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 averageStableBorrowRate,
        uint256 reserveFactor
    ) external returns (
        uint256,
        uint256,
        uint256
    );
}

interface RewardsClaimerLike {
    function getRewardsBalance(address[] calldata assets, address user) external view returns (uint256);
}

contract DssDirectDepositAaveDaiTest is DSTest {

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    Hevm hevm;

    ChainlogAbstract chainlog;
    VatAbstract vat;
    EndAbstract end;
    LendingPoolLike pool;
    InterestRateStrategyLike interestStrategy;
    RewardsClaimerLike rewardsClaimer;
    DaiAbstract dai;
    DaiJoinAbstract daiJoin;
    DSTokenAbstract adai;
    DSTokenAbstract stkAave;
    SpotAbstract spot;
    DSTokenAbstract weth;
    address vow;
    address pauseProxy;

    bytes32 constant ilk = "DD-DAI-A";
    DssDirectDepositAaveDai deposit;
    DirectDepositMom directDepositMom;
    DirectHelper helper;
    DSValue pip;

    // Allow for a 1 BPS margin of error on interest rates
    uint256 constant INTEREST_RATE_TOLERANCE = RAY / 10000;
    uint256 constant EPSILON_TOLERANCE = 4;

    function setUp() public {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

        chainlog = ChainlogAbstract(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
        vat = VatAbstract(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        end = EndAbstract(0xBB856d1742fD182a90239D7AE85706C2FE4e5922);
        pool = LendingPoolLike(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        adai = DSTokenAbstract(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
        stkAave = DSTokenAbstract(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
        dai = DaiAbstract(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        daiJoin = DaiJoinAbstract(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
        interestStrategy = InterestRateStrategyLike(0xfffE32106A68aA3eD39CcCE673B646423EEaB62a);
        rewardsClaimer = RewardsClaimerLike(0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5);
        spot = SpotAbstract(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);
        weth = DSTokenAbstract(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        vow = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;
        pauseProxy = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

        // Force give admin access to these contracts via hevm magic
        _giveAuthAccess(address(vat), address(this));
        _giveAuthAccess(address(end), address(this));
        _giveAuthAccess(address(spot), address(this));
        
        deposit = new DssDirectDepositAaveDai(address(chainlog), ilk, address(pool), address(rewardsClaimer));
        deposit.file("tau", 7 days);
        directDepositMom = new DirectDepositMom();
        deposit.rely(address(directDepositMom));
        helper = new DirectHelper();

        // Init new collateral
        pip = new DSValue();
        pip.poke(bytes32(WAD));
        spot.file(ilk, "pip", address(pip));
        spot.file(ilk, "mat", RAY);
        spot.poke(ilk);

        vat.rely(address(deposit));
        vat.init(ilk);
        vat.file(ilk, "line", 5_000_000_000 * RAD);
        vat.file("Line", vat.Line() + 5_000_000_000 * RAD);

        // Give us a bunch of WETH and deposit into Aave
        uint256 amt = 1_000_000 * WAD;
        _giveTokens(weth, amt);
        weth.approve(address(pool), uint256(-1));
        dai.approve(address(pool), uint256(-1));
        pool.deposit(address(weth), amt, address(this), 0);
    }

    // --- Math ---
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }

    function _giveAuthAccess(address _base, address target) internal {
        AuthLike base = AuthLike(_base);

        // Edge case - ward is already set
        if (base.wards(target) == 1) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the ward storage slot
            bytes32 prevValue = hevm.load(
                address(base),
                keccak256(abi.encode(target, uint256(i)))
            );
            hevm.store(
                address(base),
                keccak256(abi.encode(target, uint256(i))),
                bytes32(uint256(1))
            );
            if (base.wards(target) == 1) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(base),
                    keccak256(abi.encode(target, uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function _giveTokens(DSTokenAbstract token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (token.balanceOf(address(this)) == amount) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                address(token),
                keccak256(abi.encode(address(this), uint256(i)))
            );
            hevm.store(
                address(token),
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (token.balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function assertEqApprox(uint256 _a, uint256 _b, uint256 _tolerance) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > _tolerance) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function assertEqInterest(uint256 _a, uint256 _b) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > INTEREST_RATE_TOLERANCE) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_decimal_uint("  Expected", _b, 27);
            emit log_named_decimal_uint("    Actual", _a, 27);
            fail();
        }
    }

    // aTOKENs round against the depositor - we allow a rounding error of 1
    function assertEqRoundingAgainst(uint256 _a, uint256 _b) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > 1) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_decimal_uint("  Expected", _b, 27);
            emit log_named_decimal_uint("    Actual", _a, 27);
            fail();
        }
    }

    function getBorrowRate() public view returns (uint256 borrowRate) {
        (,,,, borrowRate,,,,,,,) = pool.getReserveData(address(dai));
    }

    // Set the borrow rate to a relative percent to what it currently is
    function _setRelBorrowTarget(uint256 deltaBPS) internal returns (uint256 targetBorrowRate) {
        targetBorrowRate = getBorrowRate() * deltaBPS / 10000;
        deposit.file("bar", targetBorrowRate);
        deposit.exec();
    }

    function test_interest_rate_calc() public {
        // Confirm that the inverse function is correct by comparing all percentages
        for (uint256 i = 1; i <= 100 * interestStrategy.getMaxVariableBorrowRate() / RAY; i++) {
            uint256 targetSupply = deposit.calculateTargetSupply(i * RAY / 100);
            (,, uint256 varBorrow) = interestStrategy.calculateInterestRates(
                address(adai),
                targetSupply - (adai.totalSupply() - dai.balanceOf(address(adai))),
                0,
                adai.totalSupply() - dai.balanceOf(address(adai)),
                0,
                0
            );
            assertEqInterest(varBorrow, i * RAY / 100);
        }
    }

    function test_target_decrease() public {
        uint256 targetBorrowRate = _setRelBorrowTarget(7500);
        deposit.reap();     // Clear out interest to get rid of rounding errors
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        uint256 amountMinted = adai.balanceOf(address(deposit));
        assertTrue(amountMinted > 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertEqRoundingAgainst(ink, amountMinted);    // We allow a rounding error of 1 because aTOKENs round against the user
        assertEqRoundingAgainst(art, amountMinted);
        assertEq(vat.gem(ilk, address(deposit)), 0);
        assertEq(vat.dai(address(deposit)), 0);
    }

    function test_target_increase() public {
        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Raise by 25%
        targetBorrowRate = _setRelBorrowTarget(12500);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        uint256 amountMinted = adai.balanceOf(address(deposit));
        assertTrue(amountMinted > 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertEqRoundingAgainst(ink, amountMinted);    // We allow a rounding error of 1 because aTOKENs round against the user
        assertEqRoundingAgainst(art, amountMinted);
        assertEq(vat.gem(ilk, address(deposit)), 0);
        assertEq(vat.dai(address(deposit)), 0);
    }

    function test_bar_zero() public {
        uint256 targetBorrowRate = _setRelBorrowTarget(7500);
        deposit.reap();     // Clear out interest to get rid of rounding errors
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertGt(ink, 0);
        assertGt(art, 0);

        // Temporarily disable the module
        deposit.file("bar", 0);
        deposit.exec();

        (ink, art) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function test_target_increase_insufficient_liquidity() public {
        uint256 currBorrowRate = getBorrowRate();

        // Attempt to increase by 25% (you can't)
        _setRelBorrowTarget(12500);
        assertEqInterest(getBorrowRate(), currBorrowRate);  // Unchanged

        assertEq(adai.balanceOf(address(deposit)), 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(deposit)), 0);
        assertEq(vat.dai(address(deposit)), 0);
    }

    function test_cage_temp_insufficient_liquidity() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);
        
        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(deposit));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        pool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // Cage the system and start unwinding
        currentLiquidity = dai.balanceOf(address(adai));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(deposit));
        deposit.cage();
        assertEq(deposit.live(), 0);
        deposit.exec();

        // Should be no dai liquidity remaining as we attempt to fully unwind
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertTrue(ink > 0);
        assertTrue(art > 0);
        assertEq(pink - ink, currentLiquidity);
        assertEq(part - art, currentLiquidity);
        assertEq(dai.balanceOf(address(adai)), 0);
        assertEq(getBorrowRate(), interestStrategy.getMaxVariableBorrowRate());

        // Someone else repays some Dai so we can unwind the rest
        hevm.warp(block.timestamp + 1 days);
        pool.repay(address(dai), amountToBorrow, 2, address(this));

        deposit.exec();
        assertEq(adai.balanceOf(address(deposit)), 0);
        assertTrue(dai.balanceOf(address(adai)) > 0);
        (ink, art) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function test_cage_perm_insufficient_liquidity() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);
        
        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(deposit));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        pool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // Cage the system and start unwinding
        currentLiquidity = dai.balanceOf(address(adai));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(deposit));
        deposit.cage();
        assertEq(deposit.live(), 0);
        deposit.exec();

        // Should be no dai liquidity remaining as we attempt to fully unwind
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertTrue(ink > 0);
        assertTrue(art > 0);
        assertEq(pink - ink, currentLiquidity);
        assertEq(part - art, currentLiquidity);
        assertEq(dai.balanceOf(address(adai)), 0);
        assertEq(getBorrowRate(), interestStrategy.getMaxVariableBorrowRate());

        // In this case nobody deposits more DAI so we have to write off the bad debt
        hevm.warp(block.timestamp + 7 days);

        uint256 sin = vat.sin(vow);
        uint256 vowDai = vat.dai(vow);
        deposit.cull();
        (uint256 ink2, uint256 art2) = vat.urns(ilk, address(deposit));
        assertEq(deposit.culled(), 1);
        assertEq(ink2, 0);
        assertEq(art2, 0);
        assertEq(vat.gem(ilk, address(deposit)), ink);
        assertEq(vat.sin(vow), sin + art * RAY);
        assertEq(vat.dai(vow), vowDai);

        // Some time later the pool gets some liquidity
        hevm.warp(block.timestamp + 180 days);
        pool.repay(address(dai), amountToBorrow, 2, address(this));

        // Close out the remainder of the position
        uint256 adaiBalance = adai.balanceOf(address(deposit));
        assertTrue(adaiBalance >= art);
        deposit.exec();
        assertEq(adai.balanceOf(address(deposit)), 0);
        assertTrue(dai.balanceOf(address(adai)) > 0);
        assertEq(vat.sin(vow), sin + art * RAY);
        assertEq(vat.dai(vow), vowDai + adaiBalance * RAY);
        assertEq(vat.gem(ilk, address(deposit)), 0);
    }

    function test_hit_debt_ceiling() public {
        // Lower the debt ceiling to 100k
        uint256 debtCeiling = 100_000 * WAD;
        vat.file(ilk, "line", debtCeiling * RAY);

        uint256 currBorrowRate = getBorrowRate();

        // Set a super low target interest rate
        uint256 targetBorrowRate = _setRelBorrowTarget(1);
        deposit.reap();
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertTrue(getBorrowRate() > targetBorrowRate && getBorrowRate() < currBorrowRate);
        assertEqRoundingAgainst(adai.balanceOf(address(deposit)), debtCeiling);    // We allow a rounding error of 1 because aTOKENs round against the user

        // Should be a no-op
        deposit.exec();
        (ink, art) = vat.urns(ilk, address(deposit));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertEqRoundingAgainst(adai.balanceOf(address(deposit)), debtCeiling);

        // Raise it by a bit
        currBorrowRate = getBorrowRate();
        debtCeiling = 125_000 * WAD;
        vat.file(ilk, "line", debtCeiling * RAY);
        deposit.exec();
        deposit.reap();
        (ink, art) = vat.urns(ilk, address(deposit));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertTrue(getBorrowRate() > targetBorrowRate && getBorrowRate() < currBorrowRate);
        assertEqRoundingAgainst(adai.balanceOf(address(deposit)), debtCeiling);    // We allow a rounding error of 1 because aTOKENs round against the user
    }

    function test_collect_interest() public {
        _setRelBorrowTarget(7500);

        hevm.warp(block.timestamp + 1 days);     // Collect one day of interest

        uint256 vowDai = vat.dai(vow);
        deposit.reap();

        log_named_decimal_uint("dai", vat.dai(vow) - vowDai, 18);

        assertTrue(vat.dai(vow) - vowDai > 0);
    }

    function test_insufficient_liquidity_for_unwind_fees() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));
        uint256 vowDai = vat.dai(vow);

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Someone else borrows the exact amount previously available
        (uint256 amountSupplied,) = vat.urns(ilk, address(deposit));
        uint256 amountToBorrow = currentLiquidity;
        pool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // Accumulate a bunch of interest
        hevm.warp(block.timestamp + 180 days);
        uint256 feesAccrued = adai.balanceOf(address(deposit)) - amountSupplied;
        currentLiquidity = dai.balanceOf(address(adai));
        assertGt(feesAccrued, 0);
        assertEq(amountSupplied, currentLiquidity);
        assertGt(amountSupplied + feesAccrued, currentLiquidity);

        // Cage the system to trigger only unwinds
        deposit.cage();
        deposit.exec();

        // The full debt should be paid off, but we are still owed fees
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertGt(adai.balanceOf(address(deposit)), 0);
        assertEq(vat.dai(vow), vowDai);

        // Someone repays
        pool.repay(address(dai), amountToBorrow, 2, address(this));
        deposit.exec();

        (ink, art) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(adai.balanceOf(address(deposit)), 0);
        assertEqApprox(vat.dai(vow), vowDai + feesAccrued * RAY, RAY);
    }

    function test_insufficient_liquidity_for_reap_fees() public {
        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Accumulate a bunch of interest
        hevm.warp(block.timestamp + 180 days);

        // Someone else borrows almost all the liquidity
        pool.borrow(address(dai), dai.balanceOf(address(adai)) - 100 * WAD, 2, 0, address(this));

        // Reap the partial fees
        uint256 vowDai = vat.dai(vow);
        deposit.reap();
        assertEq(vat.dai(vow), vowDai + 100 * RAD);
    }

    function test_unwind_mcd_caged_not_skimmed() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(deposit));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(deposit));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        pool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        // CDP still has the position built
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertGt(ink, 0);
        assertGt(art, 0);
        assertEq(vat.gem(ilk, address(end)), 0);

        uint256 prevSin = vat.sin(vow);
        uint256 prevDai = vat.dai(vow);
        assertEq(prevSin, 0);
        assertGt(prevDai, 0);

        // We try to unwind what is possible
        deposit.exec();
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        // exec() moved the remaining urn debt to the end
        (ink, art) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(end)), amountSupplied / 2); // Automatically skimmed when unwinding
        if (prevSin + (amountSupplied / 2) * RAY >= prevDai) {
            assertEqApprox(vat.sin(vow), prevSin + (amountSupplied / 2) * RAY - prevDai, RAY);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqApprox(vat.dai(vow), prevDai - prevSin - (amountSupplied / 2) * RAY, RAY);
            assertEq(vat.sin(vow), 0);
        }

        // Some time later the pool gets some liquidity
        hevm.warp(block.timestamp + 180 days);
        pool.repay(address(dai), amountToBorrow, 2, address(this));

        // Rest of the liquidity can be withdrawn
        deposit.exec();
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(vat.sin(vow), 0);
        assertGe(vat.dai(vow), prevDai); // As also probably accrues interest from aDai
    }

    function test_unwind_mcd_caged_skimmed() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(deposit));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(deposit));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        pool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        // CDP still has the position built
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertGt(ink, 0);
        assertGt(art, 0);
        assertEq(vat.gem(ilk, address(end)), 0);

        uint256 prevSin = vat.sin(vow);
        uint256 prevDai = vat.dai(vow);
        assertEq(prevSin, 0);
        assertGt(prevDai, 0);

        // Position is taken by the End module
        end.skim(ilk, address(deposit));
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));
        (ink, art) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(end)), pink);
        if (prevSin + amountSupplied * RAY >= prevDai) {
            assertEqApprox(vat.sin(vow), prevSin + amountSupplied * RAY - prevDai, RAY);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqApprox(vat.dai(vow), prevDai - prevSin - amountSupplied * RAY, RAY);
            assertEq(vat.sin(vow), 0);
        }

        // We try to unwind what is possible
        deposit.exec();
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        // Part can't be done yet
        assertEq(vat.gem(ilk, address(end)), amountSupplied / 2);
        if (prevSin + (amountSupplied / 2) * RAY >= prevDai) {
            assertEqApprox(vat.sin(vow), prevSin + (amountSupplied / 2) * RAY - prevDai, RAY);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqApprox(vat.dai(vow), prevDai - prevSin - (amountSupplied / 2) * RAY, RAY);
            assertEq(vat.sin(vow), 0);
        }

        // Some time later the pool gets some liquidity
        hevm.warp(block.timestamp + 180 days);
        pool.repay(address(dai), amountToBorrow, 2, address(this));

        // Rest of the liquidity can be withdrawn
        deposit.exec();
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(vat.sin(vow), 0);
        assertGe(vat.dai(vow), prevDai); // As also probably accrues interest from aDai
    }

    function testFail_unwind_mcd_caged_wait_done() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(deposit));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(deposit));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        pool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        hevm.warp(block.timestamp + end.wait());

        // Force remove all the dai from vow so it can call end.thaw()
        hevm.store(
            address(vat),
            keccak256(abi.encode(address(vow), uint256(5))),
            bytes32(0)
        );

        end.thaw();

        // Unwind via exec should fail with error "DssDirectDepositAaveDai/end-debt-already-set"
        deposit.exec();
    }

    function test_unwind_culled_then_mcd_caged() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(deposit));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(deposit));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        pool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        deposit.cage();

        hevm.warp(block.timestamp + deposit.tau());

        uint256 daiEarned = adai.balanceOf(address(deposit)) - pink;

        VowAbstract(vow).heal(
            _min(
                vat.sin(vow) - VowAbstract(vow).Sin() - VowAbstract(vow).Ash(),
                vat.dai(vow)
            )
        );
        uint256 originalSin = vat.sin(vow);
        uint256 originalDai = vat.dai(vow);
        // If the whole Sin queue would be cleant by someone,
        // originalSin should be 0 as there is more profit than debt registered
        assertGt(originalDai, originalSin);
        assertGt(originalSin, 0);

        deposit.cull();

        // After cull, the debt of the position is converted to bad debt
        assertEq(vat.sin(vow), originalSin + part * RAY);

        // CDP grabbed and ink moved as free collateral to the deposit contract
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(deposit)), pink);
        assertGe(adai.balanceOf(address(deposit)), pink);

        // MCD shutdowns
        originalDai = originalDai + vat.dai(VowAbstract(vow).flapper());
        end.cage();
        end.cage(ilk);

        if (originalSin + part * RAY >= originalDai) {
            assertEq(vat.sin(vow), originalSin + part * RAY - originalDai);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEq(vat.dai(vow), originalDai - originalSin - part * RAY);
            assertEq(vat.sin(vow), 0);
        }

        deposit.uncull();
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        // So the position is restablished
        (ink, art) = vat.urns(ilk, address(deposit));
        assertEq(ink, pink);
        assertEq(art, part);
        assertEq(vat.gem(ilk, address(deposit)), 0);
        assertGe(adai.balanceOf(address(deposit)), pink);
        assertEq(vat.sin(vow), 0);

        // Call skim manually (will be done through deposit anyway)
        // Position is again taken but this time the collateral goes to the End module
        end.skim(ilk, address(deposit));
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        (ink, art) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(deposit)), 0);
        assertEq(vat.gem(ilk, address(end)), pink);
        assertGe(adai.balanceOf(address(deposit)), pink);
        if (originalSin + part * RAY >= originalDai) {
            assertEqApprox(vat.sin(vow), originalSin + part * RAY - originalDai, RAY);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqApprox(vat.dai(vow), originalDai - originalSin - part * RAY, RAY);
            assertEq(vat.sin(vow), 0);
        }

        // We try to unwind what is possible
        deposit.exec();
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        // A part can't be unwind yet
        assertEq(vat.gem(ilk, address(end)), amountSupplied / 2);
        assertGt(adai.balanceOf(address(deposit)), amountSupplied / 2);
        if (originalSin + part * RAY >= originalDai + (amountSupplied / 2) * RAY) {
            assertEqApprox(vat.sin(vow), originalSin + part * RAY - originalDai - (amountSupplied / 2) * RAY, RAY);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqApprox(vat.dai(vow), originalDai + (amountSupplied / 2) * RAY - originalSin - part * RAY, RAY);
            assertEq(vat.sin(vow), 0);
        }

        // Then pool gets some liquidity
        pool.repay(address(dai), amountToBorrow, 2, address(this));

        // Rest of the liquidity can be withdrawn
        deposit.exec();
        VowAbstract(vow).heal(_min(vat.sin(vow), vat.dai(vow)));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(adai.balanceOf(address(deposit)), 0);
        assertEq(vat.sin(vow), 0);
        assertEqApprox(vat.dai(vow), originalDai - originalSin + daiEarned * RAY, RAY);
    }

    function testFail_uncull_not_culled() public {
        // Lower by 50%
        _setRelBorrowTarget(5000);
        deposit.cage();

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        // uncull should fail with error "DssDirectDepositAaveDai/not-prev-culled"
        deposit.uncull();
    }

    function testFail_uncull_not_shutdown() public {
        // Lower by 50%
        _setRelBorrowTarget(5000);
        deposit.cage();

        hevm.warp(block.timestamp + deposit.tau());

        deposit.cull();

        // uncull should fail with error "DssDirectDepositAaveDai/no-uncull-normal-operation"
        deposit.uncull();
    }

    function test_collect_stkaave() public {
        _setRelBorrowTarget(7500);
        
        hevm.warp(block.timestamp + 1 days);

        // Set the king
        deposit.file("king", address(pauseProxy));

        // Collect some stake rewards into the pause proxy
        address[] memory tokens = new address[](1);
        tokens[0] = address(adai);
        uint256 amountToClaim = rewardsClaimer.getRewardsBalance(tokens, address(deposit));
        if (amountToClaim == 0) return;     // Rewards are turned off - this is still an acceptable state
        uint256 amountClaimed = deposit.collect(tokens, uint256(-1));
        assertEq(amountClaimed, amountToClaim);
        assertEq(stkAave.balanceOf(address(pauseProxy)), amountClaimed);
        assertEq(rewardsClaimer.getRewardsBalance(tokens, address(deposit)), 0);
        
        hevm.warp(block.timestamp + 1 days);

        // Collect some more rewards
        uint256 amountToClaim2 = rewardsClaimer.getRewardsBalance(tokens, address(deposit));
        assertGt(amountToClaim2, 0);
        uint256 amountClaimed2 = deposit.collect(tokens, uint256(-1));
        assertEq(amountClaimed2, amountToClaim2);
        assertEq(stkAave.balanceOf(address(pauseProxy)), amountClaimed + amountClaimed2);
        assertEq(rewardsClaimer.getRewardsBalance(tokens, address(deposit)), 0);
    }

    function testFail_collect_stkaave_king_not_set() public {
        _setRelBorrowTarget(7500);
        
        hevm.warp(block.timestamp + 1 days);

        // Collect some stake rewards into the pause proxy
        address[] memory tokens = new address[](1);
        tokens[0] = address(adai);
        uint256 amountToClaim = rewardsClaimer.getRewardsBalance(tokens, address(deposit));
        assertTrue(amountToClaim > 0);
        deposit.collect(tokens, uint256(-1));
    }
    
    function test_cage_exit() public {
        _setRelBorrowTarget(7500);

        // Vat is caged for global settlement
        vat.cage();

        // Simulate DAI holder gets some gems from GS
        vat.grab(ilk, address(deposit), address(this), address(this), -int256(100 ether), -int256(0));

        // User can exit and get the aDAI
        deposit.exit(address(this), 100 ether);
        assertEqApprox(adai.balanceOf(address(this)), 100 ether, 1);     // Slight rounding error may occur
    }
    
    function testFail_shutdown_cant_cage() public {
        _setRelBorrowTarget(7500);

        // Vat is caged for global settlement
        vat.cage();
        deposit.cage();
    }

    function testFail_shutdown_cant_cull() public {
        _setRelBorrowTarget(7500);

        deposit.cage();

        // Vat is caged for global settlement
        vat.cage();

        hevm.warp(block.timestamp + deposit.tau());

        deposit.cull();
    }
    
    function test_quit_no_cull() public {
        _setRelBorrowTarget(7500);

        deposit.cage();

        // Test that we can extract the whole position in emergency situations
        // aDAI should be sitting in the deposit contract, urn should be owned by deposit contract
        (uint256 pink, uint256 part) = vat.urns(ilk, address(deposit));
        uint256 pbal = adai.balanceOf(address(deposit));
        assertGt(pink, 0);
        assertGt(part, 0);
        assertGt(pbal, 0);

        vat.hope(address(deposit));     // Need to approve urn transfer
        deposit.quit(address(this));

        (uint256 nink, uint256 nart) = vat.urns(ilk, address(deposit));
        uint256 nbal = adai.balanceOf(address(deposit));
        assertEq(nink, 0);
        assertEq(nart, 0);
        assertEq(nbal, 0);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(this));
        uint256 bal = adai.balanceOf(address(this));
        assertEq(ink, pink);
        assertEq(art, part);
        assertEq(bal, pbal);
    }
    
    function test_quit_cull() public {
        _setRelBorrowTarget(7500);

        deposit.cage();

        hevm.warp(block.timestamp + deposit.tau());

        deposit.cull();

        // Test that we can extract the adai in emergency situations
        // aDAI should be sitting in the deposit contract, gems should be owned by deposit contract
        uint256 pgem = vat.gem(ilk, address(deposit));
        uint256 pbal = adai.balanceOf(address(deposit));
        assertGt(pgem, 0);
        assertGt(pbal, 0);

        deposit.quit(address(this));

        uint256 ngem = vat.gem(ilk, address(deposit));
        uint256 nbal = adai.balanceOf(address(deposit));
        assertEq(ngem, 0);
        assertEq(nbal, 0);

        uint256 gem = vat.gem(ilk, address(this));
        uint256 bal = adai.balanceOf(address(this));
        assertEq(gem, 0);
        assertEq(bal, pbal);
    }
    
    function testFail_quit_mcd_caged() public {
        _setRelBorrowTarget(7500);

        vat.cage();

        deposit.quit(address(this));
    }
    
    function testFail_reap_caged() public {
        _setRelBorrowTarget(7500);

        deposit.cage();
        
        hevm.warp(block.timestamp + 1 days);    // Accrue some interest

        // reap should fail with error "DssDirectDepositAaveDai/no-reap-during-cage"
        deposit.reap();
    }

    function test_direct_deposit_mom() public {
        _setRelBorrowTarget(7500);

        (uint256 ink, ) = vat.urns(ilk, address(deposit));
        assertGt(ink, 0);
        assertGt(deposit.bar(), 0);

        // Something bad happens on Aave - we need to bypass gov delay
        directDepositMom.disable(address(deposit));

        assertEq(deposit.bar(), 0);

        // Close out our position
        deposit.exec();

        (ink, ) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
    }

    function test_set_tau_not_caged() public {
        assertEq(deposit.tau(), 7 days);
        deposit.file("tau", 1 days);
        assertEq(deposit.tau(), 1 days);
    }

    function testFail_set_tau_caged() public {
        assertEq(deposit.tau(), 7 days);

        deposit.cage();
        assertEq(deposit.live(), 0);

        // file should fail with error "DssDirectDepositAaveDai/live"
        deposit.file("tau", 1 days);
    }

    // Make sure the module works correctly even when someone permissionlessly repays the urn
    function test_permissionless_repay() public {
        _setRelBorrowTarget(7500);

        // Permissionlessly repay the urn
        _giveTokens(DSTokenAbstract(address(dai)), 100);
        dai.approve(address(daiJoin), 100);
        daiJoin.join(address(this), 100);
        vat.frob(ilk, address(address(deposit)), address(this), address(this), 0, -100); // Some small amount of dai repaid

        // We should be able to close out the vault completely even though ink and art do not match
        _setRelBorrowTarget(0);
    }

    function test_shouldExec() public {
        // Move down by 25%
        deposit.file("bar", getBorrowRate() * 7500 / 10000);

        assertTrue(helper.shouldExec(address(deposit), 1 * RAY / 100), "1: 1% dev.");       // Definitely over a 1% deviation and winding room
        assertTrue(!helper.shouldExec(address(deposit), 40 * RAY / 100), "1: 40% dev.");    // Definitely not over a 40% deviation

        deposit.exec();

        // Should be within tolerance for both now
        assertTrue(!helper.shouldExec(address(deposit), 1 * RAY / 100), "2: 1% dev.");
        assertTrue(!helper.shouldExec(address(deposit), 40 * RAY / 100), "2: 40% dev.");

        // Target 2% up
        deposit.file("bar", getBorrowRate() * 10200 / 10000);

        // Should be outside of tolerance for 1% in the unwind direction
        assertTrue(helper.shouldExec(address(deposit), 1 * RAY / 100), "3: 1% dev.");
        assertTrue(!helper.shouldExec(address(deposit), 40 * RAY / 100), "3: 40% dev.");

        deposit.exec();

        assertTrue(!helper.shouldExec(address(deposit), 1 * RAY / 100), "4: 1% dev.");
        assertTrue(!helper.shouldExec(address(deposit), 40 * RAY / 100), "4: 40% dev.");

        // Unwind completely by disabling the module
        deposit.file("bar", 0);

        // Outside of both tolerance now
        assertTrue(helper.shouldExec(address(deposit), 1 * RAY / 100), "5: 1% dev.");
        
        helper.conditionalExec(address(deposit), 40 * RAY / 100); // Trigger the exec here

        // Should be outside of both tolerance, but debt is empty so should still return false
        (uint256 daiDebt,) = vat.urns(ilk, address(deposit));
        log_named_uint("daiDebt", daiDebt);
        assertTrue(!helper.shouldExec(address(deposit), 1 * RAY / 100), "6: 1% dev.");
        assertTrue(!helper.shouldExec(address(deposit), 40 * RAY / 100), "6: 40% dev.");

        // Set super low bar to force hitting the debt ceiling
        deposit.file("bar", 1 * RAY / 10000);
        deposit.exec();

        // Should be outside of both tolerance, but ceiling is hit so return false
        assertTrue(!helper.shouldExec(address(deposit), 1 * RAY / 100), "7: 1% dev.");
        assertTrue(!helper.shouldExec(address(deposit), 40 * RAY / 100), "7: 40% dev.");
    }
}
