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

import "ds-test/test.sol";
import "../tests/interfaces/interfaces.sol";

import { D3MPlanBaseTest }            from "./D3MPlanBase.t.sol";
import { D3MCompoundPlan } from "./D3MCompoundPlan.sol";

interface CErc20Like {
    function borrowRatePerBlock()               external view returns (uint256);
    function getCash()                          external view returns (uint256);
    function totalBorrows()                     external view returns (uint256);
    function totalReserves()                    external view returns (uint256);
    function interestRateModel()                external view returns (address);
    function implementation()                   external view returns (address);
    function accrueInterest()                   external returns (uint256);
}

interface InterestRateModelLike {
    function baseRatePerBlock()       external view returns (uint256);
    function kink()                   external view returns (uint256);
    function multiplierPerBlock()     external view returns (uint256);
    function jumpMultiplierPerBlock() external view returns (uint256);
    function blocksPerYear()          external view returns (uint256);
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256);
    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) external pure returns (uint256);
}

contract D3MCompoundPlanWrapper is D3MCompoundPlan {
    constructor(address cdai_) D3MCompoundPlan(cdai_) {}

    function calculateTargetSupply(uint256 targetInterestRate) external view returns (uint256) {
        return _calculateTargetSupply(targetInterestRate, cDai.totalBorrows());
    }
}

contract D3MCompoundPlanTest is D3MPlanBaseTest {
    CErc20Like             cDai;
    InterestRateModelLike  model;
    D3MCompoundPlanWrapper plan;

    uint256 constant WAD = 10 ** 18;

    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "overflow");
    }
    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "underflow");
    }
    function _mul(uint256 x, uint256 y) public pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    function _wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, y) / WAD;
    }
    function _wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, WAD) / y;
    }

    function assertEqApproxBPS(uint256 _a, uint256 _b, uint256 _tolerance_bps) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > _mul(_b, _tolerance_bps) / 10 ** 4) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function assertEqAbsolute(uint256 _a, uint256 _b, uint256 _tolerance) internal {
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

    function setUp() public override {
        dai   = DaiLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        cDai  = CErc20Like(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        model = InterestRateModelLike(cDai.interestRateModel());

        d3mTestPlan = address(new D3MCompoundPlanWrapper(address(cDai)));
        plan = D3MCompoundPlanWrapper(d3mTestPlan);
    }

    function _targetRateForUtil(uint256 util) internal view returns (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) {
        borrows  = cDai.totalBorrows();
        reserves = cDai.totalReserves();

        // reverse calculation of https://github.com/compound-finance/compound-protocol/blob/master/contracts/BaseJumpRateModelV2.sol#L79
        cash = _add(_sub(_wdiv(borrows, util), borrows), reserves);
        targetRate = model.getBorrowRate(cash, borrows, reserves);
    }

    function _targetRateForRelativeUtil(uint256 deltaBPS) internal view returns (uint256 targetRate, uint256 newCash, uint256 borrows, uint256 reserves) {
        uint256 cash = cDai.getCash();
        borrows = cDai.totalBorrows();
        reserves = cDai.totalReserves();
        uint256 util = model.utilizationRate(cash, borrows, reserves);

        uint256 newUtil = util * deltaBPS / 10000;
        (targetRate, newCash, borrows, reserves) = _targetRateForUtil(newUtil);
    }

    function test_sets_cdai() public {
        assertEq(address(cDai), address(plan.cDai()));
    }

    function test_sets_rateModel() public {
        assertEq(address(model), address(plan.tack()));
    }

    function test_can_file_barb() public {
        assertEq(plan.barb(), 0);

        plan.file("barb", 0.0005e16);

        assertEq(plan.barb(), 0.0005e16);
    }

    function testFail_barb_too_high() public {
        plan.file("barb", 0.0005e16 + 1);
    }

    function testFail_cannot_file_unknown_uint_param() public {
        plan.file("bad", 1);
    }

    function test_can_file_rateModel() public {
        assertEq(address(plan.tack()), address(model));

        plan.file("tack", address(1));

        assertEq(address(plan.tack()), address(1));
    }

    function test_can_file_delegate() public {
        assert(plan.delegate() != address(1));

        plan.file("delegate", address(1));

        assertEq(plan.delegate(), address(1));
    }

    function testFail_cannot_file_unknown_address_param() public {
        plan.file("bad", address(1));
    }

    function testFail_cannot_file_without_auth() public {
        plan.deny(address(this));

        plan.file("bar", 1);
    }

    function test_calculate_current_rate() public {
        uint256 borrowRatePerBlock = cDai.borrowRatePerBlock();
        uint256 targetSupply = plan.calculateTargetSupply(borrowRatePerBlock);

        uint256 cash = cDai.getCash();
        uint256 borrows = cDai.totalBorrows();
        uint256 reserves = cDai.totalReserves();
        assertEqApproxBPS(targetSupply, _sub(_add(cash, borrows), reserves), 1);
    }

    function test_calculate_exactly_normal_rate() public {
        uint256 util = model.kink(); // example: current kink = 80% => util = 80%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, _sub(_add(cash, borrows), reserves), 1);
    }

    function test_calculate_below_normal_rate() public {
        uint256 util = model.kink() / 2; // example: current kink = 80% => util = 40%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, _sub(_add(cash, borrows), reserves), 1);
    }

    function test_calculate_above_normal_rate() public {
        uint256 util = _add(model.kink(), _sub(WAD, model.kink()) / 2); // example: current kink = 80% => util = 80% + 10%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, _sub(_add(cash, borrows), reserves), 1);
    }

    function test_calculate_extremely_low_rate() public {
        uint256 util = model.kink() / 100; // example: current kink = 80% => util = 0.8%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, _sub(_add(cash, borrows), reserves), 1);
    }

    function test_calculate_extremely_high_rate() public {
        uint256 util = _add(model.kink(), _mul(_sub(WAD, model.kink()), 9) / 10); // example: current kink = 80% => util = 80% + 20% * 9 / 10 = 98%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, _sub(_add(cash, borrows), reserves), 1);
    }

    function test_interest_rate_calc() public {
        // Confirm that the inverse function is correct by comparing all percentages
        for (uint256 i = 1; i <= 100 ; i++) {
            (uint256 targetRate, uint256 newCash, uint256 borrows, uint256 reserves) = _targetRateForRelativeUtil(i * 100);

            uint256 supply = plan.calculateTargetSupply(targetRate);
            assertEqApproxBPS(supply, _sub(_add(newCash, borrows), reserves), 1);
        }
    }

    function test_calculate_base_rate() public {
        uint256 supply = plan.calculateTargetSupply(model.baseRatePerBlock());
        assertEq(supply, 0);
    }

    function test_calculate_zero_rate() public {
        uint256 supply = plan.calculateTargetSupply(0);
        assertEq(supply, 0);
    }

    function test_top_utilization() public {
        uint256 topUtil = WAD;
        uint256 normalRate = _add(_wmul(model.kink(), model.multiplierPerBlock()), model.baseRatePerBlock());

        uint256 topRate = normalRate + model.jumpMultiplierPerBlock() * (topUtil - model.kink()) / WAD;
        assertGt(plan.calculateTargetSupply(topRate), 0);

        uint256 overTopRate = topRate * 101 / 100;
        assertEq(plan.calculateTargetSupply(overTopRate), 0);
    }

    function test_implements_getTargetAssets() public override {
        uint256 initialRatePerBlock = cDai.borrowRatePerBlock();

        plan.file("barb", initialRatePerBlock - (1 * WAD / 1000) / model.blocksPerYear()); // minus 0.1% from current yearly rate

        uint256 initialTargetAssets = plan.getTargetAssets(0);
        assertGt(initialTargetAssets, 0);

        // Reduce target rate (increase needed number of target Assets)
        plan.file("barb", initialRatePerBlock - (2 * WAD / 1000) / model.blocksPerYear()); // minus 0.2% from current yearly rate

        uint256 newTargetAssets = plan.getTargetAssets(0);
        assertGt(newTargetAssets, initialTargetAssets);
    }

    function test_getTargetAssets_barb_zero() public {
        assertEq(plan.barb(), 0);
        assertEq(plan.getTargetAssets(0), 0);
    }

    function test_getTargetAssets_current_rate() public {
        cDai.accrueInterest();
        uint256 borrowRatePerBlock = cDai.borrowRatePerBlock();
        plan.file("barb", borrowRatePerBlock);

        uint256 targetAssets = plan.getTargetAssets(0);
        assertEqAbsolute(targetAssets, 0, WAD);
    }

    function test_rate_model_changed_not_active() public {
        // Simulate Compound changing the rate model in the pool
        plan.file("tack", address(456));

        assertTrue(address(plan.tack()) != cDai.interestRateModel());
        assertTrue(plan.active() == false);
    }

    function test_delegate_changed_not_active() public {
        // Simulate Compound changing the cDai implementation
        assertTrue(address(plan.delegate()) == cDai.implementation());
        plan.file("delegate", address(456));

        assertTrue(address(plan.delegate()) != cDai.implementation());
        assertTrue(plan.active() == false);
    }

    function test_barb_zero_not_active() public {
        assertEq(plan.barb(), 0);
        assertTrue(plan.active() == false);
    }

    function test_rate_model_not_changed_active() public {
        plan.file("barb", 123);
        assertEq(address(plan.tack()), address(model));
        assertTrue(plan.active());
    }

    function test_implements_disable() public override {
        // disable_sets_bar_to_zero
        plan.file("barb", 123);
        assertTrue(plan.barb() != 0);

        plan.disable();
        assertEq(plan.barb(), 0);
    }

    function testFail_disable_without_auth() public {
        plan.file("barb", 123);
        assertEq(address(plan.tack()), address(model));
        plan.deny(address(this));

        plan.disable();
    }
}

