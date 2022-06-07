// SPDX-FileCopyrightText: © 2021-2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021-2022 Dai Foundation
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

import { Hevm, D3MPlanBaseTest } from "./D3MPlanBase.t.sol";
import { DaiLike, TokenLike } from "../tests/interfaces/interfaces.sol";

import { D3MAavePlan, LendingPoolLike } from "./D3MAavePlan.sol";

interface InterestRateStrategyLike {
    function baseVariableBorrowRate() external view returns (uint256);
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

contract D3MAavePlanWrapper is D3MAavePlan {

    constructor(address dai_, address pool_) D3MAavePlan(dai_, pool_) {}

    function calculateTargetSupply(uint256 targetInterestRate) external view returns (uint256) {
        uint256 totalDebt = stableDebt.totalSupply() + variableDebt.totalSupply();
        return _calculateTargetSupply(targetInterestRate, totalDebt);
    }
}

contract D3MAavePlanTest is D3MPlanBaseTest {
    uint256 constant RAY = 10 ** 27;

    LendingPoolLike aavePool;
    InterestRateStrategyLike interestStrategy;
    TokenLike adai;

    // Allow for a 1 BPS margin of error on interest rates
    uint256 constant INTEREST_RATE_TOLERANCE = RAY / 10000;

    function setUp() override public {
        hevm = Hevm(
            address(bytes20(uint160(uint256(keccak256("hevm cheat code")))))
        );

        dai = DaiLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        aavePool = LendingPoolLike(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        adai = TokenLike(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
        interestStrategy = InterestRateStrategyLike(0xfffE32106A68aA3eD39CcCE673B646423EEaB62a);

        d3mTestPlan = address(new D3MAavePlanWrapper(address(dai), address(aavePool)));
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

    function test_sets_adai() public {
        assertEq(address(adai), D3MAavePlan(d3mTestPlan).adai());
    }

    function test_sets_dai_value() public {
        assertEq(address(D3MAavePlan(d3mTestPlan).dai()), address(dai));
    }

    function test_sets_stableDebt() public {
        (,,,,,,,, address stableDebt,,,) = LendingPoolLike(aavePool).getReserveData(address(dai));

        assertEq(stableDebt, address(D3MAavePlan(d3mTestPlan).stableDebt()));
    }

    function test_sets_variableDebt() public {
        (,,,,,,,,, address variableDebt,,) = LendingPoolLike(aavePool).getReserveData(address(dai));

        assertEq(variableDebt, address(D3MAavePlan(d3mTestPlan).variableDebt()));
    }

    function test_sets_InterestStrategy() public {
        assertEq(address(interestStrategy), address(D3MAavePlan(d3mTestPlan).tack()));
    }

    function test_can_file_bar() public {
        assertEq(D3MAavePlan(d3mTestPlan).bar(), 0);

        D3MAavePlan(d3mTestPlan).file("bar", 1);

        assertEq(D3MAavePlan(d3mTestPlan).bar(), 1);
    }

    function testFail_cannot_file_unknown_uint_param() public {
        D3MAavePlan(d3mTestPlan).file("bad", 1);
    }

    function test_can_file_interestStratgey() public {
        assertEq(address(D3MAavePlan(d3mTestPlan).tack()), address(interestStrategy));

        D3MAavePlan(d3mTestPlan).file("tack", address(1));

        assertEq(address(D3MAavePlan(d3mTestPlan).tack()), address(1));
    }

    function testFail_cannot_file_unknown_address_param() public {
        D3MAavePlan(d3mTestPlan).file("bad", address(1));
    }

    function testFail_cannot_file_without_auth() public {
        D3MAavePlan(d3mTestPlan).deny(address(this));

        D3MAavePlan(d3mTestPlan).file("bar", 1);
    }

    function test_set_bar_too_high_unwinds() public {
        D3MAavePlan(d3mTestPlan).file("bar", interestStrategy.getMaxVariableBorrowRate() + 1);
        assertEq(D3MAavePlan(d3mTestPlan).getTargetAssets(1), 0);
    }

    function test_set_bar_too_low_unwinds() public {
        D3MAavePlan(d3mTestPlan).file("bar", interestStrategy.baseVariableBorrowRate());
        assertEq(D3MAavePlan(d3mTestPlan).getTargetAssets(1), 0);
    }

    function test_interest_rate_calc() public {
        // Confirm that the inverse function is correct by comparing all percentages
        for (uint256 i = 1; i <= 100 * interestStrategy.getMaxVariableBorrowRate() / RAY; i++) {
            uint256 targetSupply = D3MAavePlanWrapper(d3mTestPlan).calculateTargetSupply(i * RAY / 100);
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

    function test_implements_getTargetAssets() public override {
        D3MAavePlan(d3mTestPlan).file("bar", interestStrategy.baseVariableBorrowRate() + 2 * RAY / 100);

        uint256 initialTargetAssets = D3MAavePlan(d3mTestPlan).getTargetAssets(0);
        assertGt(initialTargetAssets, 0);

        // Reduce target rate (increase needed number of target Assets)
        D3MAavePlan(d3mTestPlan).file("bar", interestStrategy.baseVariableBorrowRate() + 1 * RAY / 100);

        uint256 newTargetAssets = D3MAavePlan(d3mTestPlan).getTargetAssets(0);
        assertGt(newTargetAssets, initialTargetAssets);
    }

    function test_getTargetAssets_bar_zero() public {
        assertEq(D3MAavePlan(d3mTestPlan).bar(), 0);
        assertEq(D3MAavePlan(d3mTestPlan).getTargetAssets(0), 0);
    }

    function test_interestStrategy_changed_not_active() public {
        D3MAavePlan(d3mTestPlan).file("bar", interestStrategy.baseVariableBorrowRate() + 1 * RAY / 100);

        // Simulate AAVE changing the strategy in the pool
        D3MAavePlan(d3mTestPlan).file("tack", address(456));
        (,,,,,,,,,, address poolStrategy,) = aavePool.getReserveData(address(dai));

        assertTrue(address(D3MAavePlan(d3mTestPlan).tack()) != poolStrategy);

        assertTrue(D3MAavePlan(d3mTestPlan).active() == false);
    }

    function test_bar_zero_not_active() public {
        assertEq(D3MAavePlan(d3mTestPlan).bar(), 0);
        assertTrue(D3MAavePlan(d3mTestPlan).active() == false);
    }

    function test_interestStrategy_not_changed_active() public {
        D3MAavePlan(d3mTestPlan).file("bar", interestStrategy.baseVariableBorrowRate() + 1 * RAY / 100);
        (,,,,,,,,,, address poolStrategy,) = aavePool.getReserveData(address(dai));
        assertEq(address(D3MAavePlan(d3mTestPlan).tack()), poolStrategy);

        assertTrue(D3MAavePlan(d3mTestPlan).active());
    }

    function test_implements_disable() public override {
        // disable_sets_bar_to_zero
        D3MAavePlan(d3mTestPlan).file("bar", interestStrategy.baseVariableBorrowRate() + 1 * RAY / 100);

        assertTrue(D3MAavePlan(d3mTestPlan).bar() != 0);

        D3MAavePlan(d3mTestPlan).disable();

        assertEq(D3MAavePlan(d3mTestPlan).bar(), 0);
    }

    function testFail_disable_without_auth() public {
        D3MAavePlan(d3mTestPlan).file("bar", interestStrategy.baseVariableBorrowRate() + 1 * RAY / 100);
        (,,,,,,,,,, address poolStrategy,) = aavePool.getReserveData(address(dai));
        assertEq(address(D3MAavePlan(d3mTestPlan).tack()), poolStrategy);
        D3MAavePlan(d3mTestPlan).deny(address(this));

        D3MAavePlan(d3mTestPlan).disable();
    }
}
