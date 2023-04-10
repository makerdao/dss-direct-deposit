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

import { D3MCompoundV2TypeRateTargetPlan } from "../../plans/D3MCompoundV2TypeRateTargetPlan.sol";

interface CErc20Like {
    function borrowRatePerBlock() external view returns (uint256);
    function getCash() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function interestRateModel() external view returns (address);
    function implementation() external view returns (address);
    function accrueInterest() external returns (uint256);
}

interface InterestRateModelLike {
    function baseRatePerBlock() external view returns (uint256);
    function kink() external view returns (uint256);
    function multiplierPerBlock() external view returns (uint256);
    function jumpMultiplierPerBlock() external view returns (uint256);
    function blocksPerYear() external view returns (uint256);
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256);
    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) external pure returns (uint256);
}

contract D3MCompoundV2TypeRateTargetPlanWrapper is D3MCompoundV2TypeRateTargetPlan {
    constructor(address cdai_) D3MCompoundV2TypeRateTargetPlan(cdai_) {}

    function calculateTargetSupply(uint256 targetInterestRate) external view returns (uint256) {
        return _calculateTargetSupply(targetInterestRate, cDai.totalBorrows());
    }
}

contract D3MCompoundV2TypeRateTargetPlanTest is D3MPlanBaseTest {

    DaiAbstract dai;
    CErc20Like                             cDai;
    InterestRateModelLike                  model;
    address                                cDaiImplementation;
    D3MCompoundV2TypeRateTargetPlanWrapper plan;

    function _wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y / WAD;
    }
    function _wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * WAD / y;
    }

    function assertEqApproxBPS(uint256 _a, uint256 _b, uint256 _tolerance_bps) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > _b * _tolerance_bps / 10 ** 4) {
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

    function setUp() public {
        // TODO these should be mocked
        dai                = DaiAbstract(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        cDai               = CErc20Like(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        cDaiImplementation = cDai.implementation();
        model              = InterestRateModelLike(cDai.interestRateModel());

        plan = new D3MCompoundV2TypeRateTargetPlanWrapper(address(cDai));

        baseInit(plan, "D3MCompoundV2TypeRateTargetPlan");
    }

    function _targetRateForUtil(uint256 util) internal view returns (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) {
        borrows  = cDai.totalBorrows();
        reserves = cDai.totalReserves();

        // reverse calculation of https://github.com/compound-finance/compound-protocol/blob/master/contracts/BaseJumpRateModelV2.sol#L79
        cash = _wdiv(borrows, util) - borrows + reserves;
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

    function test_auth_modifiers() public override {
        plan.file("barb", 0.0005e16);
        assertEq(plan.active(), true);

        super.test_auth_modifiers();
    }

    function test_disable_makes_inactive() public override {
        plan.file("barb", 0.0005e16);

        super.test_disable_makes_inactive();
    }

    function test_sets_cdai() public {
        assertEq(address(cDai), address(plan.cDai()));
    }

    function test_sets_rateModel() public {
        assertEq(plan.tacks(address(model)), 1);
    }

    function test_sets_cdaiImplementation() public {
        assertEq(plan.delegates(cDaiImplementation), 1);
    }

    function test_can_file_barb() public {
        assertEq(plan.barb(), 0);

        plan.file("barb", 0.0005e16);

        assertEq(plan.barb(), 0.0005e16);
    }

    function test_sets_barb_too_high() public {
        assertRevert(address(plan), abi.encodeWithSignature("file(bytes32,uint256)", bytes32("barb"), uint256(0.0005e16 + 1)), "D3MCompoundV2TypeRateTargetPlan/barb-too-high");
    }

    function test_cannot_file_unknown_uint_param() public {
        assertRevert(address(plan), abi.encodeWithSignature("file(bytes32,uint256)", bytes32("bad"), uint256(1)), "D3MCompoundV2TypeRateTargetPlan/file-unrecognized-param");
    }

    function test_cannot_file_uint_without_auth() public {
        plan.deny(address(this));
        assertRevert(address(plan), abi.encodeWithSignature("file(bytes32,uint256)", bytes32("barb"), uint256(1)), "D3MCompoundV2TypeRateTargetPlan/not-authorized");
    }

    function test_can_file_tack() public {
        assertEq(plan.tacks(address(1)), 0);
        plan.file("tack", address(1), 1);
        assertEq(plan.tacks(address(1)), 1);
        plan.file("tack", address(1), 0);
        assertEq(plan.tacks(address(1)), 0);
    }

    function test_can_file_delegate() public {
        assertEq(plan.delegates(address(1)), 0);
        plan.file("delegate", address(1), 1);
        assertEq(plan.delegates(address(1)), 1);
        plan.file("delegate", address(1), 0);
        assertEq(plan.delegates(address(1)), 0);
    }

    function test_can_not_file_unknown_address_set() public {
        assertRevert(address(plan), abi.encodeWithSignature("file(bytes32,address,uint256)", bytes32("bad"), address(0), uint256(1)), "D3MCompoundV2TypeRateTargetPlan/file-unrecognized-param");
    }

    function test_can_not_file_illegal_uint_for_tack() public {
        assertRevert(address(plan), abi.encodeWithSignature("file(bytes32,address,uint256)", bytes32("tack"), address(0), uint256(2)), "D3MCompoundV2TypeRateTargetPlan/file-invalid-data");
    }

    function test_can_not_file_illegal_uint_for_delegate() public {
        assertRevert(address(plan), abi.encodeWithSignature("file(bytes32,address,uint256)", bytes32("delegate"), address(0), uint256(2)), "D3MCompoundV2TypeRateTargetPlan/file-invalid-data");
    }

    function test_can_not_file_tack_without_auth() public {
        plan.deny(address(this));
        assertRevert(address(plan), abi.encodeWithSignature("file(bytes32,address,uint256)", "tack", address(1), 1), "D3MCompoundV2TypeRateTargetPlan/not-authorized");
    }

    function test_can_not_file_deleagte_without_auth() public {
        plan.deny(address(this));
        assertRevert(address(plan), abi.encodeWithSignature("file(bytes32,address,uint256)", "delegate", address(1), 1), "D3MCompoundV2TypeRateTargetPlan/not-authorized");
    }

    function test_calculate_current_rate() public {
        uint256 borrowRatePerBlock = cDai.borrowRatePerBlock();
        uint256 targetSupply = plan.calculateTargetSupply(borrowRatePerBlock);

        uint256 cash = cDai.getCash();
        uint256 borrows = cDai.totalBorrows();
        uint256 reserves = cDai.totalReserves();
        assertEqApproxBPS(targetSupply, cash + borrows - reserves, 1);
    }

    function test_calculate_exactly_normal_rate() public {
        uint256 util = model.kink(); // example: current kink = 80% => util = 80%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, cash + borrows - reserves, 1);
    }

    function test_calculate_below_normal_rate() public {
        uint256 util = model.kink() / 2; // example: current kink = 80% => util = 40%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, cash + borrows - reserves, 1);
    }

    function test_calculate_above_normal_rate() public {
        uint256 util = model.kink() + (WAD - model.kink()) / 2; // example: current kink = 80% => util = 80% + 10%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, cash + borrows - reserves, 1);
    }

    function test_calculate_extremely_low_rate() public {
        uint256 util = model.kink() / 100; // example: current kink = 80% => util = 0.8%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, cash + borrows - reserves, 1);
    }

    function test_calculate_extremely_high_rate() public {
        uint256 util = model.kink() + (WAD - model.kink()) * 9 / 10; // example: current kink = 80% => util = 80% + 20% * 9 / 10 = 98%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, cash + borrows - reserves, 1);
    }

    function test_interest_rate_calc() public {
        // Confirm that the inverse function is correct by comparing all percentages
        for (uint256 i = 1; i <= 100 ; i++) {
            (uint256 targetRate, uint256 newCash, uint256 borrows, uint256 reserves) = _targetRateForRelativeUtil(i * 100);

            uint256 supply = plan.calculateTargetSupply(targetRate);
            assertEqApproxBPS(supply, newCash + borrows - reserves, 1);
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

    function test_very_high_utilization_supported() public {
        uint256 normalRate = _wmul(model.kink(), model.multiplierPerBlock()) + model.baseRatePerBlock();

        uint256 util = 1e36;
        uint256 rate = normalRate + model.jumpMultiplierPerBlock() * (util - model.kink()) / WAD;

        // Make sure utilization target supply is indeed less than borrows (i.e utilization > 100%)
        uint256 targetSupply = plan.calculateTargetSupply(rate);
        assertLt(targetSupply, cDai.totalBorrows());

        // Make sure targetSupply is indeed very small
        assertGt(targetSupply, 0);
        assertLt(targetSupply, WAD);
    }

    function test_getTargetAssets() public {
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
        // Set barb so we won't be inactive due to it
        plan.file("barb", 123);

        // Simulate Compound changing the rate model in the pool
        assertEq(plan.tacks(cDai.interestRateModel()), 1);
        assertTrue(plan.active());
        plan.file("tack", cDai.interestRateModel(), 0);
        plan.file("tack", address(456), 1);
        assertEq(plan.tacks(cDai.interestRateModel()), 0);
        assertTrue(plan.active() == false);
    }

    function test_delegate_changed_not_active() public {
        // Set barb so we won't be inactive due to it
        plan.file("barb", 123);

        // Simulate Compound changing the cDai implementation
        assertEq(plan.delegates(cDai.implementation()), 1);
        assertTrue(plan.active() == true);
        plan.file("delegate", cDai.implementation(), 0);
        plan.file("delegate", address(456), 1);

        assertEq(plan.delegates(cDai.implementation()), 0);
        assertTrue(plan.active() == false);
    }

    function test_barb_zero_not_active() public {
        assertEq(plan.barb(), 0);
        assertTrue(plan.active() == false);
    }

    function test_rate_model_not_changed_active() public {
        plan.file("barb", 123);
        assertEq(plan.tacks(address(model)), 1);
        assertTrue(plan.active());
    }

    function test_delegate_not_changed_active() public {
        plan.file("barb", 123);
        assertEq(plan.delegates(cDaiImplementation), 1);
        assertTrue(plan.active());
    }

    function test_implements_disable() public {
        // disable_sets_bar_to_zero
        plan.file("barb", 123);
        assertTrue(plan.barb() != 0);

        plan.disable();
        assertEq(plan.barb(), 0);
    }

    function test_disable_without_auth() public {
        plan.file("barb", 123);
        assertEq(plan.tacks(address(model)), 1);
        assertEq(plan.delegates(cDaiImplementation), 1);
        plan.deny(address(this));

        assertRevert(address(plan), abi.encodeWithSignature("disable()"), "D3MCompoundV2TypeRateTargetPlan/not-authorized");
    }

}

