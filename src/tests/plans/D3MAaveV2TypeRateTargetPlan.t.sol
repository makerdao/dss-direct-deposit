// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
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

import "./D3MPlanBase.t.sol";

import { D3MAaveV2TypeRateTargetPlan, LendingPoolLike } from "../../plans/D3MAaveV2TypeRateTargetPlan.sol";

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

contract D3MAaveV2TypeRateTargetPlanWrapper is D3MAaveV2TypeRateTargetPlan {

    constructor(address dai_, address pool_) D3MAaveV2TypeRateTargetPlan(dai_, pool_) {}

    function calculateTargetSupply(uint256 targetInterestRate) external view returns (uint256) {
        uint256 totalDebt = stableDebt.totalSupply() + variableDebt.totalSupply();
        return _calculateTargetSupply(targetInterestRate, totalDebt);
    }
}

contract D3MAaveV2TypeRateTargetPlanTest is D3MPlanBaseTest {

    DaiAbstract dai;
    LendingPoolLike aavePool;
    InterestRateStrategyLike interestStrategy;
    GemAbstract adai;

    D3MAaveV2TypeRateTargetPlanWrapper plan;

    // Allow for a 1 BPS margin of error on interest rates
    uint256 constant INTEREST_RATE_TOLERANCE = RAY / 10000;

    function setUp() public {
        // TODO these should be mocked
        dai = DaiAbstract(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        aavePool = LendingPoolLike(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        adai = GemAbstract(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
        interestStrategy = InterestRateStrategyLike(0xfffE32106A68aA3eD39CcCE673B646423EEaB62a);

        plan = new D3MAaveV2TypeRateTargetPlanWrapper(address(dai), address(aavePool));

        baseInit(plan, "D3MAaveV2TypeRateTargetPlan");
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
        assertEq(address(adai), plan.adai());
    }

    function test_sets_adaiRevision_value() public {
        assertEq(plan.adaiRevision(), 2);
    }

    function test_sets_dai_value() public {
        assertEq(address(plan.dai()), address(dai));
    }

    function test_sets_stableDebt() public {
        (,,,,,,,, address stableDebt,,,) = LendingPoolLike(aavePool).getReserveData(address(dai));

        assertEq(stableDebt, address(plan.stableDebt()));
    }

    function test_sets_variableDebt() public {
        (,,,,,,,,, address variableDebt,,) = LendingPoolLike(aavePool).getReserveData(address(dai));

        assertEq(variableDebt, address(plan.variableDebt()));
    }

    function test_sets_InterestStrategy() public {
        assertEq(address(interestStrategy), address(plan.tack()));
    }

    function test_can_file_bar() public {
        assertEq(plan.bar(), 0);

        plan.file("bar", 1);

        assertEq(plan.bar(), 1);
    }

    function test_cannot_file_unknown_uint_param() public {
        assertRevert(address(plan), abi.encodeWithSignature("file(bytes32,uint256)", bytes32("bad"), uint256(1)), "D3MAaveV2TypeRateTargetPlan/file-unrecognized-param");
    }

    function test_can_file_interestStratgey() public {
        assertEq(address(plan.tack()), address(interestStrategy));

        plan.file("tack", address(1));

        assertEq(address(plan.tack()), address(1));
    }

    function test_cannot_file_unknown_address_param() public {
        assertRevert(address(plan), abi.encodeWithSignature("file(bytes32,address)", bytes32("bad"), address(1)), "D3MAaveV2TypeRateTargetPlan/file-unrecognized-param");
    }

    function test_cannot_file_without_auth() public {
        plan.deny(address(this));
        assertRevert(address(plan), abi.encodeWithSignature("file(bytes32,uint256)", bytes32("bar"), uint256(1)), "D3MAaveV2TypeRateTargetPlan/not-authorized");
    }

    function test_set_bar_too_high_unwinds() public {
        plan.file("bar", interestStrategy.getMaxVariableBorrowRate() + 1);
        assertEq(plan.getTargetAssets(1), 0);
    }

    function test_set_bar_too_low_unwinds() public {
        plan.file("bar", interestStrategy.baseVariableBorrowRate());
        assertEq(plan.getTargetAssets(1), 0);
    }

    function test_interest_rate_calc() public {
        // Confirm that the inverse function is correct by comparing all percentages
        for (uint256 i = 1; i <= 100 * interestStrategy.getMaxVariableBorrowRate() / RAY; i++) {
            uint256 targetSupply = D3MAaveV2TypeRateTargetPlanWrapper(address(plan)).calculateTargetSupply(i * RAY / 100);
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

    function test_implements_getTargetAssets() public {
        plan.file("bar", interestStrategy.baseVariableBorrowRate() + 2 * RAY / 100);

        uint256 initialTargetAssets = plan.getTargetAssets(0);

        // Reduce target rate (increase needed number of target Assets)
        plan.file("bar", interestStrategy.baseVariableBorrowRate() + 1 * RAY / 100);

        uint256 newTargetAssets = plan.getTargetAssets(0);
        assertGt(newTargetAssets, initialTargetAssets);
    }

    function test_getTargetAssets_bar_zero() public {
        assertEq(plan.bar(), 0);
        assertEq(plan.getTargetAssets(0), 0);
    }

    function test_interestStrategy_changed_not_active() public {
        plan.file("bar", interestStrategy.baseVariableBorrowRate() + 1 * RAY / 100);

        // Simulate AAVE changing the strategy in the pool
        plan.file("tack", address(456));
        (,,,,,,,,,, address poolStrategy,) = aavePool.getReserveData(address(dai));

        assertTrue(address(plan.tack()) != poolStrategy);

        assertTrue(plan.active() == false);
    }

    function test_bar_zero_not_active() public {
        assertEq(plan.bar(), 0);
        assertTrue(plan.active() == false);
    }

    function test_interestStrategy_not_changed_active() public {
        plan.file("bar", interestStrategy.baseVariableBorrowRate() + 1 * RAY / 100);
        (,,,,,,,,,, address poolStrategy,) = aavePool.getReserveData(address(dai));
        assertEq(address(plan.tack()), poolStrategy);

        assertTrue(plan.active());
    }

    function test_implements_disable() public {
        // disable_sets_bar_to_zero
        plan.file("bar", interestStrategy.baseVariableBorrowRate() + 1 * RAY / 100);

        assertTrue(plan.bar() != 0);

        plan.disable();

        assertEq(plan.bar(), 0);
    }

    function test_disable_without_auth() public {
        plan.file("bar", interestStrategy.baseVariableBorrowRate() + 1 * RAY / 100);
        (,,,,,,,,,, address poolStrategy,) = aavePool.getReserveData(address(dai));
        assertEq(address(plan.tack()), poolStrategy);
        plan.deny(address(this));

        assertRevert(address(plan), abi.encodeWithSignature("disable()"), "D3MAaveV2TypeRateTargetPlan/not-authorized");
    }

}
