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

import { D3MALMDelegateControllerPlan } from "../../plans/D3MALMDelegateControllerPlan.sol";

contract D3MALMDelegateControllerPlanTest is D3MPlanBaseTest {

    D3MALMDelegateControllerPlan plan;

    event AddAllocator(address indexed allocator);
    event RemoveAllocator(address indexed allocator);
    event AddAllocatorDelegate(address indexed allocator, address indexed allocatorDelegate);
    event RemoveAllocatorDelegate(address indexed allocator, address indexed allocatorDelegate);

    function setUp() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        plan = new D3MALMDelegateControllerPlan();

        baseInit(plan, "D3MALMDelegateControllerPlan");
    }

    function test_auth_modifiers() public override {
        super.test_auth_modifiers();

        checkModifier(address(plan), string(abi.encodePacked(contractName, "/not-authorized")), [
            D3MALMDelegateControllerPlan.addAllocator.selector,
            D3MALMDelegateControllerPlan.removeAllocator.selector,
            bytes4(keccak256("setMaxAllocation(bytes32,uint256)")),
            bytes4(keccak256("setMaxAllocation(address,bytes32,uint256)"))
        ]);
    }

    function test_constructor() public {
        assertEq(plan.enabled(), 1);
    }

    function test_file() public {
        vm.expectRevert(abi.encodePacked(contractName, "/file-unrecognized-param"));
        plan.file("an invalid value", 1);
        assertEq(plan.enabled(), 1);
        vm.expectEmit(true, false, false, true);
        emit File("enabled", 0);
        plan.file("enabled", 0);
        assertEq(plan.enabled(), 0);
        vm.expectRevert(abi.encodePacked(contractName, "/invalid-value"));
        plan.file("enabled", 2);
        plan.deny(address(this));
        vm.expectRevert(abi.encodePacked(contractName, "/not-authorized"));
        plan.file("some value", 1);
    }

    function test_disable_unauthed() public {
        plan.deny(address(this));

        vm.expectRevert(abi.encodePacked(contractName, "/not-authorized"));
        plan.disable();
    }

    function test_addAllocator() public {
        assertEq(plan.allocators(TEST_ADDRESS), 0);
        vm.expectEmit(true, true, true, true);
        emit AddAllocator(TEST_ADDRESS);
        plan.addAllocator(TEST_ADDRESS);
        assertEq(plan.allocators(TEST_ADDRESS), 1);
    }

    function test_removeAllocator() public {
        plan.addAllocator(TEST_ADDRESS);

        assertEq(plan.allocators(TEST_ADDRESS), 1);
        vm.expectEmit(true, true, true, true);
        emit RemoveAllocator(TEST_ADDRESS);
        plan.removeAllocator(TEST_ADDRESS);
        assertEq(plan.allocators(TEST_ADDRESS), 0);
    }

    function test_setMaxAllocation() public {

    }

    function test_active_enabled_set() public {
        assertEq(plan.enabled(), 1);
        assertTrue(plan.active());
        plan.file("enabled", 0);
        assertEq(plan.enabled(), 0);
        assertTrue(!plan.active());
        plan.file("enabled", 1);
        assertEq(plan.enabled(), 1);
        assertTrue(plan.active());
    }

    function test_disable() public {
        assertEq(plan.enabled(), 1);
        assertTrue(plan.active());
        vm.expectEmit(true, true, true, true);
        emit Disable();
        plan.disable();
        assertTrue(!plan.active());
        assertEq(plan.enabled(), 0);
    }
    
}
