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

pragma solidity 0.6.12;

// import "ds-test/test.sol";
import { Hevm, D3MPlanBaseTest } from "./D3MPlanBase.t.sol";
import { DaiLike, TokenLike } from "../tests/interfaces/interfaces.sol";

import { D3MAaveDaiPlan, LendingPoolLike } from "./D3MAaveDaiPlan.sol";

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

contract D3MAaveDaiPlanTest is D3MPlanBaseTest {
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

        d3mTestPlan = address(new D3MAaveDaiPlan(address(dai), address(aavePool)));
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
        assertEq(address(adai), D3MAaveDaiPlan(d3mTestPlan).adai());
    }

    function test_sets_stableDebt() public {
        (,,,,,,,, address stableDebt,,,) = LendingPoolLike(aavePool).getReserveData(address(dai));

        assertEq(stableDebt, address(D3MAaveDaiPlan(d3mTestPlan).stableDebt()));
    }

    function test_sets_variableDebt() public {
        (,,,,,,,,, address variableDebt,,) = LendingPoolLike(aavePool).getReserveData(address(dai));

        assertEq(variableDebt, address(D3MAaveDaiPlan(d3mTestPlan).variableDebt()));
    }

    function test_sets_InterestStrategy() public {
        assertEq(address(interestStrategy), address(D3MAaveDaiPlan(d3mTestPlan).interestStrategy()));
    }

    function test_can_file_bar() public {
        assertEq(D3MAaveDaiPlan(d3mTestPlan).bar(), 0);

        D3MAaveDaiPlan(d3mTestPlan).file("bar", 1);

        assertEq(D3MAaveDaiPlan(d3mTestPlan).bar(), 1);
    }

    function testFail_cannot_file_unknown_param() public {
        D3MAaveDaiPlan(d3mTestPlan).file("bad", 1);
    }

    function testFail_cannot_file_without_auth() public {
        D3MAaveDaiPlan(d3mTestPlan).deny(address(this));

        D3MAaveDaiPlan(d3mTestPlan).file("bar", 1);
    }

    function testFail_cannot_file_too_high_bar() public {
        D3MAaveDaiPlan(d3mTestPlan).file("bar", D3MAaveDaiPlan(d3mTestPlan).maxBar() + 1);
    }

    function test_maxBar_is_MaxVarBorrowRate() internal {}

    function test_interest_rate_calc() public {
        // Confirm that the inverse function is correct by comparing all percentages
        for (uint256 i = 1; i <= 100 * interestStrategy.getMaxVariableBorrowRate() / RAY; i++) {
            uint256 targetSupply = D3MAaveDaiPlan(d3mTestPlan).calculateTargetSupply(i * RAY / 100);
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

    function test_implements_getTargetAssets() public override {}

}