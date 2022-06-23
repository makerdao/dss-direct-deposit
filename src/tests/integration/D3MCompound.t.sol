// SPDX-FileCopyrightText: © 2021-2022 Dai Foundation <www.daifoundation.org>
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

pragma solidity ^0.8.14;

import {DSSTest} from "dss-test/DSSTest.sol";
import "../interfaces/interfaces.sol";

import { D3MHub } from "../../D3MHub.sol";
import { D3MMom } from "../../D3MMom.sol";
import { D3MOracle } from "../../D3MOracle.sol";

import { D3MCompoundPlan } from "../../plans/D3MCompoundPlan.sol";
import { D3MCompoundPool } from "../../pools/D3MCompoundPool.sol";

interface Hevm {
    function warp(uint256) external;
    function roll(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external view returns (bytes32);
}

interface CErc20Like {
    function borrowRatePerBlock()     external view returns (uint256);
    function getCash()                external view returns (uint256);
    function totalBorrows()           external view returns (uint256);
    function totalReserves()          external view returns (uint256);
    function interestRateModel()      external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function comptroller()            external view returns (address);
    function borrow(uint256 borrowAmount)       external returns (uint256);
    function balanceOfUnderlying(address owner) external returns (uint256);
    function repayBorrow(uint256 repayAmount)   external returns (uint256);
    function exchangeRateCurrent()              external returns (uint256);
}

interface CEthLike {
    function mint() external payable;
}

interface ComptrollerLike {
    function enterMarkets(address[] memory cTokens) external returns (uint256[] memory);
    function compBorrowSpeeds(address cToken) external view returns (uint256);
}

interface WethLike {
    function withdraw(uint256 wad)    external;
    function balanceOf(address owner) external view returns (uint256);
}

interface InterestRateModelLike {
    function baseRatePerBlock() external view returns (uint256);
    function kink() external view returns (uint256);
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256);
    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) external pure returns (uint256);
}

contract D3MCompoundTest is DSSTest {
    Hevm hevm;

    VatLike vat;
    EndLike end;
    CErc20Like cDai;
    CEthLike   cEth;

    InterestRateModelLike rateModel;
    DaiLike dai;
    DaiJoinLike daiJoin;
    TokenLike comp;
    SpotLike spot;
    address vow;
    address pauseProxy;

    bytes32 constant ilk = "DD-DAI-A";
    D3MHub d3mHub;
    D3MCompoundPool d3mCompoundPool;
    D3MCompoundPlan d3mCompoundPlan;
    D3MMom d3mMom;
    D3MOracle pip;

    // Allow for a 1 BPS margin of error on interest rates
    // Note that here the rate is in WAD resolution
    uint256 constant INTEREST_RATE_TOLERANCE = WAD / 10000;

    function setUp() public override {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

        vat = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        end = EndLike(0x0e2e8F1D1326A4B9633D96222Ce399c708B19c28);
        cDai = CErc20Like(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        cEth = CEthLike(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
        comp = TokenLike(0xc00e94Cb662C3520282E6f5717214004A7f26888);
        dai = DaiLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        daiJoin = DaiJoinLike(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
        rateModel = InterestRateModelLike(0xFB564da37B41b2F6B6EDcc3e56FbF523bD9F2012);
        spot = SpotLike(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);
        vow = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;
        pauseProxy = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

        // Force give admin access to these contracts via hevm magic
        _giveAuthAccess(address(vat), address(this));
        _giveAuthAccess(address(end), address(this));
        _giveAuthAccess(address(spot), address(this));

        d3mHub = new D3MHub(address(daiJoin));
        d3mCompoundPool = new D3MCompoundPool(address(d3mHub), address(cDai));
        d3mCompoundPool.rely(address(d3mHub));
        d3mCompoundPlan = new D3MCompoundPlan(address(cDai));

        d3mHub.file(ilk, "pool", address(d3mCompoundPool));
        d3mHub.file(ilk, "plan", address(d3mCompoundPlan));
        d3mHub.file(ilk, "tau", 7 days);

        d3mHub.file("vow", vow);
        d3mHub.file("end", address(end));

        d3mMom = new D3MMom();
        d3mCompoundPlan.rely(address(d3mMom));

        // Init new collateral
        pip = new D3MOracle(address(vat), ilk);
        pip.file("hub", address(d3mHub));
        spot.file(ilk, "pip", address(pip));
        spot.file(ilk, "mat", RAY);
        spot.poke(ilk);

        vat.rely(address(d3mHub));
        vat.init(ilk);
        vat.file(ilk, "line", 5_000_000_000 * RAD);
        vat.file("Line", vat.Line() + 5_000_000_000 * RAD);

        // Deposit ETH into Compound to allow borrowing
        uint256 amt = 10_000_000_000 * WAD;
        cEth.mint{value: amt}();
        dai.approve(address(cDai), type(uint256).max);

        address[] memory cTokens = new address[](1);
        cTokens[0] = address(cEth);

        ComptrollerLike(cDai.comptroller()).enterMarkets(cTokens);
    }

    // --- Math ---
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }
    function _wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * WAD / y;
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

    function _giveTokens(TokenLike token, uint256 amount) internal {
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

    function assertEqRounding(uint256 _a, uint256 _b) internal {
        _assertEqApprox(_a, _b, 10 ** 10);
    }

    function assertEqCdai(uint256 _a, uint256 _b) internal {
        _assertEqApprox(_a, _b, 1);
    }

    function assertEqVatDai(uint256 _a, uint256 _b) internal {
        _assertEqApprox(_a, _b, (10 ** 10) * RAY);
    }

    function assertEqInterest(uint256 _a, uint256 _b) internal {
        _assertEqApprox(_a, _b, INTEREST_RATE_TOLERANCE);
    }

    function _assertEqApprox(uint256 _a, uint256 _b, uint256 _tolerance) internal {
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
        borrowRate = cDai.borrowRatePerBlock();
    }

    // Set the borrow rate to a relative percent to what it currently is
    function _setRelBorrowTarget(uint256 deltaBPS) internal returns (uint256 targetBorrowRate) {
        targetBorrowRate = getBorrowRate() * deltaBPS / 10000;
        d3mCompoundPlan.file("barb", targetBorrowRate);
        d3mHub.exec(ilk);
    }

    function test_target_decrease() public {
        uint256 targetBorrowRate = _setRelBorrowTarget(7500);
        d3mHub.reap(ilk);     // Clear out interest to get rid of rounding errors
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        uint256 amountSupplied = cDai.balanceOfUnderlying(address(d3mCompoundPool));

        assertTrue(amountSupplied > 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEqRounding(ink, amountSupplied);
        assertEqRounding(art, amountSupplied);

        assertEq(vat.gem(ilk, address(d3mCompoundPool)), 0);
        assertEq(vat.dai(address(d3mHub)), 0);
    }

    function test_target_increase() public {
        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        uint256 amountSuppliedInitial = cDai.balanceOfUnderlying(address(d3mCompoundPool));

        // Raise by 25%
        targetBorrowRate = _setRelBorrowTarget(12500);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        uint256 amountSupplied = cDai.balanceOfUnderlying(address(d3mCompoundPool));
        assertTrue(amountSupplied > 0);
        assertLt(amountSupplied, amountSuppliedInitial);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEqRounding(ink, amountSupplied);
        assertEqRounding(art, amountSupplied);

        assertEq(vat.gem(ilk, address(d3mCompoundPool)), 0);
        assertEq(vat.dai(address(d3mHub)), 0);
    }

    function test_barb_zero() public {

        uint256 targetBorrowRate = _setRelBorrowTarget(7500);

        d3mHub.reap(ilk);     // Clear out interest to get rid of rounding errors
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mCompoundPool));
        assertGt(ink, 0);
        assertGt(art, 0);

        // Temporarily disable the module
        d3mCompoundPlan.file("barb", 0);

        d3mHub.exec(ilk);
        assertEqRounding(cDai.balanceOfUnderlying(address(d3mCompoundPool)), 0);

        (ink, art) = vat.urns(ilk, address(d3mCompoundPool));

        assertEqRounding(ink, 0);
        assertEqRounding(art, 0);
    }

    function test_utilization_over_100_percent() public {

        // Borrow out all cash so we have high utilization
        assertEq(cDai.borrow(cDai.getCash()), 0);

        // Lower rate by 0.1% (inject dai)
        uint256 targetBorrowRate = _setRelBorrowTarget(9990);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Make sure the amount supplied is less than the reserves, which means utilization still > 100%
        uint256 initialSupply = cDai.balanceOfUnderlying(address(d3mCompoundPool));
        assertGt(initialSupply, 0);
        assertLt(initialSupply, cDai.totalReserves());

        // Assert that indeed current utilization > 100%
        assertGt(rateModel.utilizationRate(cDai.getCash(), cDai.totalBorrows(), cDai.totalReserves()), WAD);

        // File the current rate, make sure it is supported (does not cause unwind) although utilization is over 100%
        d3mCompoundPlan.file("barb", cDai.borrowRatePerBlock());
        d3mHub.exec(ilk);
        _assertEqApprox(initialSupply, cDai.balanceOfUnderlying(address(d3mCompoundPool)), WAD / 100);

        // File the maximum supported rate
        d3mCompoundPlan.file("barb", 0.0005e16);
        d3mHub.exec(ilk);

        // Assert that still current utilization > 100%
        assertGt(rateModel.utilizationRate(cDai.getCash(), cDai.totalBorrows(), cDai.totalReserves()), WAD);

        // Make sure it caused us to unwind
        assertEqRounding(cDai.balanceOfUnderlying(address(d3mCompoundPool)), 0);
    }

    function test_target_increase_insufficient_liquidity() public {
        uint256 currBorrowRate = getBorrowRate();

        // Attempt to increase by 25% (you can't since you have no cDai)
        _setRelBorrowTarget(12500);
        assertEqInterest(getBorrowRate(), currBorrowRate);  // Unchanged

        assertEq(cDai.balanceOf(address(d3mCompoundPool)), 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(d3mCompoundPool)), 0);
        assertEq(vat.dai(address(d3mHub)), 0);
    }

    function test_cage_temp_insufficient_liquidity() public {
        uint256 currentLiquidity = dai.balanceOf(address(cDai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Someone else borrows
        uint256 amountSupplied = cDai.balanceOfUnderlying(address(d3mCompoundPool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        assertEq(cDai.borrow(amountToBorrow), 0);

        // Cage the system and start unwinding
        currentLiquidity = dai.balanceOf(address(cDai));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mCompoundPool));
        d3mHub.cage(ilk);
        d3mHub.exec(ilk);

        // Should be no dai liquidity remaining as we attempt to fully unwind
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mCompoundPool));
        assertTrue(ink > 0);
        assertTrue(art > 0);
        assertEq(pink - ink, currentLiquidity);
        assertEq(part - art, currentLiquidity);
        assertEq(dai.balanceOf(address(cDai)), 0);

        // Someone else repays some Dai so we can unwind the rest
        hevm.warp(block.timestamp + 1 days);
        assertEq(cDai.repayBorrow(amountToBorrow), 0);

        d3mHub.exec(ilk);
        assertEqCdai(cDai.balanceOf(address(d3mCompoundPool)), 0);
        assertTrue(dai.balanceOf(address(cDai)) > 0);
        (ink, art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEqRounding(ink, 0);
        assertEqRounding(art, 0);
    }

    function test_cage_perm_insufficient_liquidity() public {
        uint256 currentLiquidity = dai.balanceOf(address(cDai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Someone else borrows
        uint256 amountSupplied = cDai.balanceOfUnderlying(address(d3mCompoundPool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        assertEq(cDai.borrow(amountToBorrow), 0);

        // Cage the system and start unwinding
        currentLiquidity = dai.balanceOf(address(cDai));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mCompoundPool));
        d3mHub.cage(ilk);
        d3mHub.exec(ilk);

        // Should be no dai liquidity remaining as we attempt to fully unwind
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mCompoundPool));
        assertTrue(ink > 0);
        assertTrue(art > 0);
        assertEq(pink - ink, currentLiquidity);
        assertEq(part - art, currentLiquidity);
        assertEq(dai.balanceOf(address(cDai)), 0);

        // In this case nobody deposits more DAI so we have to write off the bad debt
        hevm.warp(block.timestamp + 7 days);

        uint256 sin = vat.sin(vow);
        uint256 vowDai = vat.dai(vow);
        d3mHub.cull(ilk);
        (uint256 ink2, uint256 art2) = vat.urns(ilk, address(d3mCompoundPool));
        (, , , uint256 culled, ) = d3mHub.ilks(ilk);
        assertEq(culled, 1);
        assertEq(ink2, 0);
        assertEq(art2, 0);
        assertEq(vat.gem(ilk, address(d3mCompoundPool)), ink);
        assertEq(vat.sin(vow), sin + art * RAY);
        assertEq(vat.dai(vow), vowDai);

        // Some time later the pool gets some liquidity
        hevm.warp(block.timestamp + 180 days);
        assertEq(cDai.repayBorrow(amountToBorrow), 0);

        // Close out the remainder of the position
        uint256 assetBalance = cDai.balanceOfUnderlying(address(d3mCompoundPool));
        assertEqRounding(assetBalance, art);
        d3mHub.exec(ilk);
        assertEqCdai(cDai.balanceOf(address(d3mCompoundPool)), 0);
        assertTrue(dai.balanceOf(address(cDai)) > 0);
        assertEq(vat.sin(vow), sin + art * RAY);

        assertEq(vat.dai(vow), vowDai + assetBalance * RAY);
        assertEqRounding(vat.gem(ilk, address(d3mCompoundPool)), 0);
    }

    function test_hit_debt_ceiling() public {
        // Lower the debt ceiling to 100k
        uint256 debtCeiling = 100_000 * WAD;
        vat.file(ilk, "line", debtCeiling * RAY);

        uint256 currBorrowRate = getBorrowRate();

        // Set a super low target interest rate
        uint256 targetBorrowRate = _setRelBorrowTarget(1);
        d3mHub.reap(ilk);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertTrue(getBorrowRate() > targetBorrowRate && getBorrowRate() < currBorrowRate);
        uint256 assetBalance = cDai.balanceOfUnderlying(address(d3mCompoundPool));
        assertEqRounding(assetBalance, debtCeiling);

        // Should be a no-op
        d3mHub.exec(ilk);
        (ink, art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertEqRounding(assetBalance, debtCeiling);

        // Raise it by a bit
        currBorrowRate = getBorrowRate();
        debtCeiling = 125_000 * WAD;
        vat.file(ilk, "line", debtCeiling * RAY);
        d3mHub.exec(ilk);
        d3mHub.reap(ilk);
        (ink, art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertTrue(getBorrowRate() > targetBorrowRate && getBorrowRate() < currBorrowRate);
        assetBalance = cDai.balanceOfUnderlying(address(d3mCompoundPool));
        assertEqRounding(assetBalance, debtCeiling);
    }

    function test_collect_interest() public {
        _setRelBorrowTarget(7500);
        hevm.roll(block.number + 5760);     // Collect ~one day of interest

        uint256 vowDai = vat.dai(vow);
        d3mHub.reap(ilk);

        emit log_named_decimal_uint("dai", vat.dai(vow) - vowDai, 18);

        assertGt(vat.dai(vow) - vowDai, 0);
    }

    function test_insufficient_liquidity_for_unwind_fees() public {
        uint256 currentLiquidity = dai.balanceOf(address(cDai));
        uint256 vowDai = vat.dai(vow);

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Someone else borrows the exact amount previously available
        (uint256 amountSupplied,) = vat.urns(ilk, address(d3mCompoundPool));
        uint256 amountToBorrow = currentLiquidity;
        assertEq(cDai.borrow(amountToBorrow), 0);

        // Accumulate a bunch of interest
        hevm.roll(block.number + 180 * 5760);

        uint256 feesAccrued = cDai.balanceOfUnderlying(address(d3mCompoundPool)) - amountSupplied;
        currentLiquidity = dai.balanceOf(address(cDai));
        assertGt(feesAccrued, 0);
        assertEq(amountSupplied, currentLiquidity);
        assertGt(amountSupplied + feesAccrued, currentLiquidity);

        // Cage the system to trigger only unwinds
        d3mHub.cage(ilk);
        d3mHub.exec(ilk);

        // The full debt should be paid off, but we are still owed fees
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertGt(cDai.balanceOfUnderlying(address(d3mCompoundPool)), 0);
        assertEq(vat.dai(vow), vowDai);

        // Someone repays
        assertEq(cDai.repayBorrow(amountToBorrow), 0);
        d3mHub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEqRounding(cDai.balanceOfUnderlying(address(d3mCompoundPool)), 0);
        assertEqVatDai(vat.dai(vow), vowDai + feesAccrued * RAY);
    }

    function test_insufficient_liquidity_for_reap_fees() public {
        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Accumulate a bunch of interest
        hevm.roll(block.number + 180 * 5760);

        // Someone else borrows almost all the liquidity
        assertEq(cDai.borrow(dai.balanceOf(address(cDai)) - 100 * WAD), 0);

        // Show that 100 DAI is less than the amount of fees that have accrued
        uint256 assetBalance = d3mCompoundPool.assetBalance();
        (, uint256 daiDebt) = vat.urns(ilk, address(d3mCompoundPool));
        uint256 eligibleFees = assetBalance - daiDebt;
        assertLt(100 * WAD, eligibleFees);

        // Reap the partial fees
        uint256 vowDai = vat.dai(vow);
        d3mHub.reap(ilk);
        assertEq(vat.dai(vow), vowDai + 100 * RAD);
    }

    function test_unwind_mcd_caged_not_skimmed() public {
        uint256 currentLiquidity = dai.balanceOf(address(cDai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mCompoundPool));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        uint256 amountSupplied = cDai.balanceOfUnderlying(address(d3mCompoundPool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        assertEq(cDai.borrow(amountToBorrow), 0);

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        // CDP still has the position built
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mCompoundPool));
        assertGt(ink, 0);
        assertGt(art, 0);
        assertEq(vat.gem(ilk, address(end)), 0);

        uint256 prevSin = vat.sin(vow);
        uint256 prevDai = vat.dai(vow);
        assertEq(prevSin, 0);
        assertGt(prevDai, 0);

        // We try to unwind what is possible
        d3mHub.exec(ilk);
        VowLike(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        // exec() moved the remaining urn debt to the end
        (ink, art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(end)), amountSupplied / 2); // Automatically skimmed when unwinding
        if (prevSin + (amountSupplied / 2) * RAY >= prevDai) {
            assertEqVatDai(vat.sin(vow), prevSin + (amountSupplied / 2) * RAY - prevDai);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqVatDai(vat.dai(vow), prevDai - prevSin - (amountSupplied / 2) * RAY);
            assertEq(vat.sin(vow), 0);
        }

        // Some time later the pool gets some liquidity
        hevm.roll(block.number + 180 * 5760);
        //compoundPool.repay(address(dai), amountToBorrow, 2, address(this));
        assertEq(cDai.repayBorrow(amountToBorrow), 0);

        // Rest of the liquidity can be withdrawn
        d3mHub.exec(ilk);
        VowLike(vow).heal(_min(vat.sin(vow), vat.dai(vow)));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(vat.sin(vow), 0);
        assertGe(vat.dai(vow), prevDai); // As also probably accrues interest from cDai
    }

    function test_unwind_mcd_caged_skimmed() public {
        uint256 currentLiquidity = dai.balanceOf(address(cDai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mCompoundPool));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        //uint256 amountSupplied = cDai.balanceOf(address(d3mCompoundPool));
        uint256 amountSupplied = cDai.balanceOfUnderlying(address(d3mCompoundPool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        //compoundPool.borrow(address(dai), amountToBorrow, 2, 0, address(this));
        assertEq(cDai.borrow(amountToBorrow), 0);

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        // CDP still has the position built
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mCompoundPool));
        assertGt(ink, 0);
        assertGt(art, 0);
        assertEq(vat.gem(ilk, address(end)), 0);

        uint256 prevSin = vat.sin(vow);
        uint256 prevDai = vat.dai(vow);
        assertEq(prevSin, 0);
        assertGt(prevDai, 0);

        // Position is taken by the End module
        end.skim(ilk, address(d3mCompoundPool));
        VowLike(vow).heal(_min(vat.sin(vow), vat.dai(vow)));
        (ink, art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(end)), pink);
        if (prevSin + amountSupplied * RAY >= prevDai) {
            assertEqVatDai(vat.sin(vow), prevSin + amountSupplied * RAY - prevDai);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqVatDai(vat.dai(vow), prevDai - prevSin - amountSupplied * RAY);
            assertEq(vat.sin(vow), 0);
        }

        // We try to unwind what is possible
        d3mHub.exec(ilk);
        VowLike(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        // Part can't be done yet
        assertEq(vat.gem(ilk, address(end)), amountSupplied / 2);
        if (prevSin + (amountSupplied / 2) * RAY >= prevDai) {
            assertEqVatDai(vat.sin(vow), prevSin + (amountSupplied / 2) * RAY - prevDai);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqVatDai(vat.dai(vow), prevDai - prevSin - (amountSupplied / 2) * RAY);
            assertEq(vat.sin(vow), 0);
        }

        // Some time later the pool gets some liquidity
        hevm.roll(block.number + 180 * 5760);
        //compoundPool.repay(address(dai), amountToBorrow, 2, address(this));
        assertEq(cDai.repayBorrow(amountToBorrow), 0);

        // Rest of the liquidity can be withdrawn
        d3mHub.exec(ilk);
        VowLike(vow).heal(_min(vat.sin(vow), vat.dai(vow)));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(vat.sin(vow), 0);
        assertGe(vat.dai(vow), prevDai); // As also probably accrues interest from cDai
    }

    function test_unwind_mcd_caged_wait_done() public {
        uint256 currentLiquidity = dai.balanceOf(address(cDai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mCompoundPool));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        //uint256 amountSupplied = cDai.balanceOf(address(d3mCompoundPool));
        uint256 amountSupplied = cDai.balanceOfUnderlying(address(d3mCompoundPool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        //compoundPool.borrow(address(dai), amountToBorrow, 2, 0, address(this));
        assertEq(cDai.borrow(amountToBorrow), 0);

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

        assertRevert(address(d3mHub), abi.encodeWithSignature("exec(bytes32)", ilk), "D3MHub/end-debt-already-set");
    }

    function test_unwind_culled_then_mcd_caged() public {
        uint256 currentLiquidity = dai.balanceOf(address(cDai));

        // Lower by 50%
        uint256 targetBorrowRate = _setRelBorrowTarget(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mCompoundPool));
        assertGt(pink, 0);
        assertGt(part, 0);

        // Someone else borrows
        // Someone else borrows
        uint256 amountSupplied = cDai.balanceOfUnderlying(address(d3mCompoundPool));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        assertEq(cDai.borrow(amountToBorrow), 0);

        d3mHub.cage(ilk);

        (, , uint256 tau, , ) = d3mHub.ilks(ilk);

        hevm.warp(block.timestamp + tau);
        hevm.roll(block.number + tau / 15);

        uint256 daiEarned = cDai.balanceOfUnderlying(address(d3mCompoundPool)) - pink;

        VowLike(vow).heal(
            _min(
                vat.sin(vow) - VowLike(vow).Sin() - VowLike(vow).Ash(),
                vat.dai(vow)
            )
        );
        uint256 originalSin = vat.sin(vow);
        uint256 originalDai = vat.dai(vow);
        // If the whole Sin queue would be cleant by someone,
        // originalSin should be 0 as there is more profit than debt registered
        assertGt(originalDai, originalSin);
        assertGt(originalSin, 0);

        d3mHub.cull(ilk);

        // After cull, the debt of the position is converted to bad debt
        assertEq(vat.sin(vow), originalSin + part * RAY);

        // CDP grabbed and ink moved as free collateral to the deposit contract
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(d3mCompoundPool)), pink);
        assertGe(cDai.balanceOfUnderlying(address(d3mCompoundPool)), pink);

        // MCD shutdowns
        originalDai = originalDai + vat.dai(VowLike(vow).flapper());
        end.cage();

        if (originalSin + part * RAY >= originalDai) {
            assertEq(vat.sin(vow), originalSin + part * RAY - originalDai);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEq(vat.dai(vow), originalDai - originalSin - part * RAY);
            assertEq(vat.sin(vow), 0);
        }

        // Cannot cage the ilk before it is unculled
        assertRevert(address(end), abi.encodeWithSignature("cage(bytes32)", ilk), "D3MOracle/ilk-culled-in-shutdown");

        d3mHub.uncull(ilk);
        VowLike(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        end.cage(ilk);

        // So the position is restablished
        (ink, art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, pink);
        assertEq(art, part);
        assertEq(vat.gem(ilk, address(d3mCompoundPool)), 0);
        assertGe(cDai.balanceOfUnderlying(address(d3mCompoundPool)), pink);
        assertEq(vat.sin(vow), 0);

        // Call skim manually (will be done through deposit anyway)
        // Position is again taken but this time the collateral goes to the End module
        end.skim(ilk, address(d3mCompoundPool));
        VowLike(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        (ink, art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(d3mCompoundPool)), 0);
        assertEq(vat.gem(ilk, address(end)), pink);
        //assertGe(cDai.balanceOf(address(d3mCompoundPool)), pink);
        assertGe(cDai.balanceOfUnderlying(address(d3mCompoundPool)), pink);
        if (originalSin + part * RAY >= originalDai) {
            assertEqVatDai(vat.sin(vow), originalSin + part * RAY - originalDai);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqVatDai(vat.dai(vow), originalDai - originalSin - part * RAY);
            assertEq(vat.sin(vow), 0);
        }

        // We try to unwind what is possible
        d3mHub.exec(ilk);
        VowLike(vow).heal(_min(vat.sin(vow), vat.dai(vow)));

        // A part can't be unwind yet
        assertEq(vat.gem(ilk, address(end)), amountSupplied / 2);
        assertGt(cDai.balanceOfUnderlying(address(d3mCompoundPool)), amountSupplied / 2);
        if (originalSin + part * RAY >= originalDai + (amountSupplied / 2) * RAY) {
            assertEqVatDai(vat.sin(vow), originalSin + part * RAY - originalDai - (amountSupplied / 2) * RAY);
            assertEq(vat.dai(vow), 0);
        } else {
            assertEqVatDai(vat.dai(vow), originalDai + (amountSupplied / 2) * RAY - originalSin - part * RAY);
            assertEq(vat.sin(vow), 0);
        }

        // Then pool gets some liquidity
        assertEq(cDai.repayBorrow(amountToBorrow), 0);

        // Rest of the liquidity can be withdrawn
        d3mHub.exec(ilk);
        VowLike(vow).heal(_min(vat.sin(vow), vat.dai(vow)));
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEqCdai(cDai.balanceOf(address(d3mCompoundPool)), 0);
        assertEq(vat.sin(vow), 0);
        assertEqVatDai(vat.dai(vow), originalDai - originalSin + daiEarned * RAY);
    }

    function test_uncull_not_culled() public {
        // Lower by 50%
        _setRelBorrowTarget(5000);
        d3mHub.cage(ilk);

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        assertRevert(address(d3mHub), abi.encodeWithSignature("uncull(bytes32)", ilk), "D3MHub/not-prev-culled");
    }

    function test_uncull_not_shutdown() public {
        // Lower by 50%
        _setRelBorrowTarget(5000);
        d3mHub.cage(ilk);

        (, , uint256 tau, , ) = d3mHub.ilks(ilk);
        hevm.warp(block.timestamp + tau);

        d3mHub.cull(ilk);

        assertRevert(address(d3mHub), abi.encodeWithSignature("uncull(bytes32)", ilk), "D3MHub/no-uncull-normal-operation");
    }

    function test_collect_comp() public {
        _setRelBorrowTarget(7500);
        hevm.roll(block.number + 5760);

        // Set the king
        d3mCompoundPool.file("king", address(pauseProxy));

        // If rewards are turned off - this is still an acceptable state
        if (ComptrollerLike(cDai.comptroller()).compBorrowSpeeds(address(cDai)) == 0) return;

        uint256 compBefore = comp.balanceOf(address(pauseProxy));
        d3mCompoundPool.collect(true);
        assertGt(comp.balanceOf(address(pauseProxy)), compBefore);

        hevm.roll(block.number + 5760);

        // Collect some more rewards
        compBefore = comp.balanceOf(address(pauseProxy));
        d3mCompoundPool.collect(true);
        assertGt(comp.balanceOf(address(pauseProxy)), compBefore);
    }

    function test_collect_comp_king_not_set() public {
        _setRelBorrowTarget(7500);

        hevm.roll(block.number + 5760);
        if (ComptrollerLike(cDai.comptroller()).compBorrowSpeeds(address(cDai)) == 0) return; // Rewards are turned off

        assertRevert(address(d3mCompoundPool), abi.encodeWithSignature("collect(bool)", true), "D3MCompoundPool/king-not-set");
    }

    function test_cage_exit() public {
        _setRelBorrowTarget(7500);

        // Vat is caged for global settlement
        vat.cage();

        // Simulate DAI holder gets some gems from GS
        vat.grab(ilk, address(d3mCompoundPool), address(this), address(this), -int256(100 * 1e18), -int256(0));

        // User can exit and get the cDAI
        d3mHub.exit(ilk, address(this), 100 * 1e18);

        uint256 expectedCdai = _wdiv(100 * 1e18, cDai.exchangeRateCurrent());
        assertEq(cDai.balanceOf(address(this)), expectedCdai);
        assertEqRounding(100 * 1e18, cDai.balanceOfUnderlying(address(this)));
    }

    function test_shutdown_cant_cull() public {
        _setRelBorrowTarget(7500);

        d3mHub.cage(ilk);

        // Vat is caged for global settlement
        vat.cage();

        (, , uint256 tau, , ) = d3mHub.ilks(ilk);
        hevm.warp(block.timestamp + tau);

        assertRevert(address(d3mHub), abi.encodeWithSignature("cull(bytes32)", ilk), "D3MHub/no-cull-during-shutdown");
    }

    function test_quit_no_cull() public {
        _setRelBorrowTarget(7500);

        d3mHub.cage(ilk);

        // Test that we can extract the whole position in emergency situations
        // cDAI should be sitting in the deposit contract, urn should be owned by deposit contract
        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mCompoundPool));
        uint256 pbal = cDai.balanceOf(address(d3mCompoundPool));
        assertGt(pink, 0);
        assertGt(part, 0);
        assertGt(pbal, 0);

        address receiver = address(123);

        d3mCompoundPool.quit(address(receiver));
        vat.grab(ilk, address(d3mCompoundPool), address(receiver), address(receiver), -int256(pink), -int256(part));
        vat.grab(ilk, address(receiver), address(receiver), address(receiver), int256(pink), int256(part));


        (uint256 nink, uint256 nart) = vat.urns(ilk, address(d3mCompoundPool));
        uint256 nbal = cDai.balanceOf(address(d3mCompoundPool));
        assertEq(nink, 0);
        assertEq(nart, 0);
        assertEq(nbal, 0);

        (uint256 ink, uint256 art) = vat.urns(ilk, receiver);
        uint256 bal = cDai.balanceOf(receiver);
        assertEq(ink, pink);
        assertEq(art, part);
        assertEq(bal, pbal);
    }

    function test_quit_cull() public {
        _setRelBorrowTarget(7500);

        d3mHub.cage(ilk);

        (, , uint256 tau, , ) = d3mHub.ilks(ilk);
        hevm.warp(block.timestamp + tau);

        d3mHub.cull(ilk);

        // Test that we can extract the cDai in emergency situations
        // cDai should be sitting in the deposit contract, gems should be owned by deposit contract
        uint256 pgem = vat.gem(ilk, address(d3mCompoundPool));
        uint256 pbal = cDai.balanceOf(address(d3mCompoundPool));
        assertGt(pgem, 0);
        assertGt(pbal, 0);

        address receiver = address(123);

        d3mCompoundPool.quit(address(receiver));
        vat.slip(ilk, address(d3mCompoundPool), -int256(pgem));

        uint256 ngem = vat.gem(ilk, address(d3mCompoundPool));
        uint256 nbal = cDai.balanceOf(address(d3mCompoundPool));
        assertEq(ngem, 0);
        assertEq(nbal, 0);

        uint256 gem = vat.gem(ilk, receiver);
        uint256 bal = cDai.balanceOf(receiver);
        assertEq(gem, 0);
        assertEq(bal, pbal);
    }

    function test_reap_caged() public {
        _setRelBorrowTarget(7500);

        d3mHub.cage(ilk);

        hevm.warp(block.timestamp + 1 days);    // Accrue some interest

        assertRevert(address(d3mHub), abi.encodeWithSignature("reap(bytes32)", ilk), "D3MHub/pool-not-live");
    }

    function test_direct_deposit_mom() public {
        _setRelBorrowTarget(7500);

        (uint256 ink, ) = vat.urns(ilk, address(d3mCompoundPool));
        assertGt(ink, 0);
        assertGt(d3mCompoundPlan.barb(), 0);

        // Something bad happens on Compound - we need to bypass gov delay
        d3mMom.disable(address(d3mCompoundPlan));

        assertEq(d3mCompoundPlan.barb(), 0);

        // Close out our position
        d3mHub.exec(ilk);

        (ink, ) = vat.urns(ilk, address(d3mCompoundPool));
        assertEqRounding(ink, 0);
    }

    function test_set_tau_not_caged() public {
        (, , uint256 tau, , ) = d3mHub.ilks(ilk);
        assertEq(tau, 7 days);
        d3mHub.file(ilk, "tau", 1 days);
        (, , tau, , ) = d3mHub.ilks(ilk);
        assertEq(tau, 1 days);
    }

    function test_fully_unwind_debt_paid_back() public {
        uint256 cdaiDaiBalanceInitial = dai.balanceOf(address(cDai));

        _setRelBorrowTarget(7500);

        d3mHub.reap(ilk); // Clear out fees at the start

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mCompoundPool));
        uint256 gemBefore = vat.gem(ilk, address(d3mCompoundPool));
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(vow);
        uint256 vowDaiBefore = vat.dai(vow);
        uint256 cdaiDaiBalanceBefore = dai.balanceOf(address(cDai));
        uint256 poolCdaiBalanceBefore = cDai.balanceOf(address(d3mCompoundPool));

        // Someone pays back our debt
        _giveTokens(dai, 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(d3mCompoundPool),
            address(d3mCompoundPool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, pink);
        assertEq(art, part - 10 * WAD);
        assertEq(ink - art, 10 * WAD);
        assertEq(vat.gem(ilk, address(d3mCompoundPool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEq(vat.dai(vow), vowDaiBefore);
        assertEqRounding(dai.balanceOf(address(cDai)), cdaiDaiBalanceBefore);
        assertEqCdai(cDai.balanceOf(address(d3mCompoundPool)), poolCdaiBalanceBefore);

        // We should be able to close out the vault completely even though ink and art do not match
        // _setRelBorrowTarget(0);
        d3mCompoundPlan.file("barb", 0);

        d3mHub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEqRounding(ink, 0);
        assertEqRounding(art, 0);
        assertEq(ink, art);
        assertEq(vat.gem(ilk, address(d3mCompoundPool)), 0);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEq(vat.dai(vow), vowDaiBefore + 10 * RAD);
        assertEqRounding(dai.balanceOf(address(cDai)), cdaiDaiBalanceInitial);
        assertEqCdai(cDai.balanceOf(address(d3mCompoundPool)), 0);
    }

    function test_wind_partial_unwind_wind_debt_paid_back() public {
        uint256 initialRate = _setRelBorrowTarget(5000);
        d3mHub.reap(ilk); // Clear out fees at the start

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mCompoundPool));
        uint256 gemBefore = vat.gem(ilk, address(d3mCompoundPool));
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(vow);
        uint256 vowDaiBefore = vat.dai(vow);
        uint256 cdaiDaiBalanceBefore = dai.balanceOf(address(cDai));
        uint256 poolCdaiBalanceBefore = cDai.balanceOf(address(d3mCompoundPool));

        // Someone pays back our debt
        _giveTokens(dai, 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(d3mCompoundPool),
            address(d3mCompoundPool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, pink);
        assertEq(art, part - 10 * WAD);
        assertEq(ink - art, 10 * WAD);
        assertEq(vat.gem(ilk, address(d3mCompoundPool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEq(vat.dai(vow), vowDaiBefore);
        assertEqRounding(dai.balanceOf(address(cDai)), cdaiDaiBalanceBefore);
        assertEqCdai(cDai.balanceOf(address(d3mCompoundPool)), poolCdaiBalanceBefore);

        d3mHub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, pink);
        assertEq(art, part);
        assertEq(ink, art);
        assertEq(vat.gem(ilk, address(d3mCompoundPool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEq(vat.dai(vow), vowDaiBefore + 10 * RAD);
        assertEqRounding(dai.balanceOf(address(cDai)), cdaiDaiBalanceBefore);
        assertEqCdai(cDai.balanceOf(address(d3mCompoundPool)), poolCdaiBalanceBefore);

        // Raise target a little to trigger unwind
        //_setRelBorrowTarget(12500);
        d3mCompoundPlan.file("barb", getBorrowRate() * 12500 / 10000);

        d3mHub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(d3mCompoundPool));
        assertLt(ink, pink);
        assertLt(art, part);
        assertEq(ink, art);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEq(vat.dai(vow), vowDaiBefore + 10 * RAD);
        assertEq(vat.gem(ilk, address(d3mCompoundPool)), gemBefore);
        assertLt(dai.balanceOf(address(cDai)), cdaiDaiBalanceBefore);
        assertLt(cDai.balanceOf(address(d3mCompoundPool)), poolCdaiBalanceBefore);

        // can re-wind and have the correct amount of debt
        d3mCompoundPlan.file("barb", initialRate);
        d3mHub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(d3mCompoundPool));
        assertEq(ink, pink);
        assertEq(art, part);
        assertEq(ink, art);
        assertEq(vat.gem(ilk, address(d3mCompoundPool)), gemBefore);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEq(vat.dai(vow), vowDaiBefore + 10 * RAD);
        assertEqRounding(dai.balanceOf(address(cDai)), cdaiDaiBalanceBefore);
        assertEqCdai(cDai.balanceOf(address(d3mCompoundPool)), poolCdaiBalanceBefore);
    }
}
