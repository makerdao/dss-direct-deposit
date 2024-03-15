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

import { D3MPlanBaseTest } from "./D3MPlanBase.t.sol";
import { D3MOperatorPlan } from "../../plans/D3MOperatorPlan.sol";

contract D3MOperatorPlanTest is D3MPlanBaseTest {

    bytes32 ilk = "DIRECT-PROTOCOL-A";

    D3MOperatorPlan plan;

    address operator = makeAddr("operator");
    address randomAddress = makeAddr("randomAddress");

    event Disable();

    function setUp() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        plan = new D3MOperatorPlan();

        baseInit(plan, "D3MOperatorPlan");
    }

    function test_constructor() public {
        assertEq(plan.enabled(), 1);
        assertEq(plan.targetAssets(), 0);
    }

    function test_file() public {
        // File checks will increment the current value by 1 so
        // just set it to 0 to start with so there is no revert.
        plan.file("enabled", 0);
        checkFileUint(address(plan), contractName, ["enabled"]);
        checkFileAddress(address(plan), contractName, ["operator"]);
    }

    function test_file_bad_value() public {
        vm.expectRevert("D3MOperatorPlan/invalid-value");
        plan.file("enabled", 2);
    }

    function _setupOperatorAndTargetAssets() internal {
        plan.file("operator", operator);
        vm.prank(operator);
        plan.setTargetAssets(100e18);
    }

    function test_setTargetAssets() public {
        _setupOperatorAndTargetAssets();

        assertEq(plan.targetAssets(), 100e18);

        vm.prank(operator);
        plan.setTargetAssets(200e18);

        assertEq(plan.targetAssets(), 200e18);
    }

    function test_setTargetAssets_onlyOperator() public {
        _setupOperatorAndTargetAssets();

        vm.prank(randomAddress);
        vm.expectRevert("D3MOperatorPlan/not-authorized");
        plan.setTargetAssets(200e18);
    }

    function test_implements_getTargetAssets() public {
        _setupOperatorAndTargetAssets();
        
        uint256 result = plan.getTargetAssets(123e18);

        assertEq(result, 100e18);
    }

    function test_disable() public {
        _setupOperatorAndTargetAssets();

        assertEq(plan.enabled(), 1);
        assertTrue(plan.active());
        vm.expectEmit(true, true, true, true);
        emit Disable();
        plan.disable();
        assertTrue(!plan.active());
        assertEq(plan.enabled(), 0);
    }

}