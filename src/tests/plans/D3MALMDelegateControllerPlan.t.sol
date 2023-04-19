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

    address constant ALLOCATOR1 = address(1);
    address constant ALLOCATOR2 = address(2);
    address constant ALLOCATOR3 = address(3);

    address constant ALLOCATORDELEGATE1 = address(4);
    address constant ALLOCATORDELEGATE2 = address(5);
    address constant ALLOCATORDELEGATE3 = address(6);

    bytes32 constant ILK1 = "ILK1";
    bytes32 constant ILK2 = "ILK2";
    bytes32 constant ILK3 = "ILK3";

    event AddAllocator(address indexed allocator);
    event RemoveAllocator(address indexed allocator);
    event SetMaxAllocation(address indexed allocator, bytes32 indexed ilk, uint128 max);
    event AddAllocatorDelegate(address indexed allocator, address indexed allocatorDelegate);
    event RemoveAllocatorDelegate(address indexed allocator, address indexed allocatorDelegate);
    event SetAllocation(address indexed allocator, bytes32 indexed ilk, uint128 previousAllocation, uint128 newAllocation);

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
            D3MALMDelegateControllerPlan.setMaxAllocation.selector
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
        assertEqAllocation(ALLOCATOR1, ILK1, 0, 0);
        plan.setMaxAllocation(ALLOCATOR1, ILK1, 100 ether);
        assertEqAllocation(ALLOCATOR1, ILK1, 0, 100 ether);
    }

    function test_setMaxAllocation_existing_allocator_under_new_limit() public {
        vm.expectEmit(true, true, true, true);
        emit SetMaxAllocation(ALLOCATOR1, ILK1, 100 ether);
        plan.setMaxAllocation(ALLOCATOR1, ILK1, 100 ether);
        assertEqAllocation(ALLOCATOR1, ILK1, 0, 100 ether);
        vm.expectEmit(true, true, true, true);
        emit SetAllocation(ALLOCATOR1, ILK1, 0, 75 ether);
        plan.setAllocation(ALLOCATOR1, ILK1, 75 ether);
        assertEqAllocation(ALLOCATOR1, ILK1, 75 ether, 100 ether);
        vm.expectEmit(true, true, true, true);
        emit SetAllocation(ALLOCATOR1, ILK1, 75 ether, 50 ether); // Note we are testing the set allocation event
        plan.setMaxAllocation(ALLOCATOR1, ILK1, 50 ether);
        assertEqAllocation(ALLOCATOR1, ILK1, 50 ether, 50 ether);
    }

    function _initAllocators() internal {
        plan.addAllocator(ALLOCATOR1);
        plan.addAllocator(ALLOCATOR2);
        plan.addAllocator(ALLOCATOR3);
    }

    function test_addAllocatorDelegate_ward_any() public {
        _initAllocators();
        
        assertEq(plan.allocatorDelegates(ALLOCATOR1, ALLOCATORDELEGATE1), 0);
        vm.expectEmit(true, true, true, true);
        emit AddAllocatorDelegate(ALLOCATOR1, ALLOCATORDELEGATE1);
        plan.addAllocatorDelegate(ALLOCATOR1, ALLOCATORDELEGATE1);
        assertEq(plan.allocatorDelegates(ALLOCATOR1, ALLOCATORDELEGATE1), 1);
    }

    function test_addAllocatorDelegate_allocator_self() public {
        _initAllocators();
        plan.deny(address(this));
        
        assertEq(plan.allocatorDelegates(ALLOCATOR1, ALLOCATORDELEGATE1), 0);
        vm.prank(ALLOCATOR1); plan.addAllocatorDelegate(ALLOCATOR1, ALLOCATORDELEGATE1);
        assertEq(plan.allocatorDelegates(ALLOCATOR1, ALLOCATORDELEGATE1), 1);
    }

    function test_addAllocatorDelegate_allocator_other() public {
        _initAllocators();
        plan.deny(address(this));
        
        vm.expectRevert(abi.encodePacked(contractName, "/not-authorized"));
        plan.addAllocatorDelegate(ALLOCATOR1, ALLOCATORDELEGATE1);
    }

    function test_removeAllocatorDelegate_ward_any() public {
        _initAllocators();
        plan.addAllocatorDelegate(ALLOCATOR1, ALLOCATORDELEGATE1);
        
        assertEq(plan.allocatorDelegates(ALLOCATOR1, ALLOCATORDELEGATE1), 1);
        vm.expectEmit(true, true, true, true);
        emit RemoveAllocatorDelegate(ALLOCATOR1, ALLOCATORDELEGATE1);
        plan.removeAllocatorDelegate(ALLOCATOR1, ALLOCATORDELEGATE1);
        assertEq(plan.allocatorDelegates(ALLOCATOR1, ALLOCATORDELEGATE1), 0);
    }

    function test_removeAllocatorDelegate_allocator_self() public {
        _initAllocators();
        plan.addAllocatorDelegate(ALLOCATOR1, ALLOCATORDELEGATE1);
        plan.deny(address(this));
        
        assertEq(plan.allocatorDelegates(ALLOCATOR1, ALLOCATORDELEGATE1), 1);
        vm.prank(ALLOCATOR1); plan.removeAllocatorDelegate(ALLOCATOR1, ALLOCATORDELEGATE1);
        assertEq(plan.allocatorDelegates(ALLOCATOR1, ALLOCATORDELEGATE1), 0);
    }

    function test_removeAllocatorDelegate_allocator_other() public {
        _initAllocators();
        plan.addAllocatorDelegate(ALLOCATOR1, ALLOCATORDELEGATE1);
        plan.deny(address(this));
        
        vm.expectRevert(abi.encodePacked(contractName, "/not-authorized"));
        plan.removeAllocatorDelegate(ALLOCATOR1, ALLOCATORDELEGATE1);
    }

    function test_setAllocation() public {
        _initAllocators();
        plan.setMaxAllocation(ALLOCATOR1, ILK1, 100 ether);
        plan.setMaxAllocation(ALLOCATOR2, ILK1, 150 ether);

        assertEqAllocation(ALLOCATOR1, ILK1, 0, 100 ether);
        assertEqAllocation(ALLOCATOR2, ILK1, 0, 150 ether);
        assertEq(plan.totalAllocated(ILK1), 0);
        assertEq(plan.numAllocations(ILK1), 0);
        assertEq(plan.hasAllocator(ILK1, ALLOCATOR1), false);
        assertEq(plan.hasAllocator(ILK1, ALLOCATOR2), false);

        plan.setAllocation(ALLOCATOR1, ILK1, 50 ether);

        assertEqAllocation(ALLOCATOR1, ILK1, 50 ether, 100 ether);
        assertEqAllocation(ALLOCATOR2, ILK1, 0, 150 ether);
        assertEq(plan.totalAllocated(ILK1), 50 ether);
        assertEq(plan.numAllocations(ILK1), 1);
        assertEq(plan.allocatorAt(ILK1, 0), ALLOCATOR1);
        assertEq(plan.hasAllocator(ILK1, ALLOCATOR1), true);
        assertEq(plan.hasAllocator(ILK1, ALLOCATOR2), false);

        plan.setAllocation(ALLOCATOR2, ILK1, 75 ether);

        assertEqAllocation(ALLOCATOR1, ILK1, 50 ether, 100 ether);
        assertEqAllocation(ALLOCATOR2, ILK1, 75 ether, 150 ether);
        assertEq(plan.totalAllocated(ILK1), 125 ether);
        assertEq(plan.numAllocations(ILK1), 2);
        assertEq(plan.allocatorAt(ILK1, 0), ALLOCATOR1);
        assertEq(plan.allocatorAt(ILK1, 1), ALLOCATOR2);
        assertEq(plan.hasAllocator(ILK1, ALLOCATOR1), true);
        assertEq(plan.hasAllocator(ILK1, ALLOCATOR2), true);

        plan.setAllocation(ALLOCATOR2, ILK1, 25 ether);

        assertEqAllocation(ALLOCATOR1, ILK1, 50 ether, 100 ether);
        assertEqAllocation(ALLOCATOR2, ILK1, 25 ether, 150 ether);
        assertEq(plan.totalAllocated(ILK1), 75 ether);
        assertEq(plan.numAllocations(ILK1), 2);
        assertEq(plan.allocatorAt(ILK1, 0), ALLOCATOR1);
        assertEq(plan.allocatorAt(ILK1, 1), ALLOCATOR2);
        assertEq(plan.hasAllocator(ILK1, ALLOCATOR1), true);
        assertEq(plan.hasAllocator(ILK1, ALLOCATOR2), true);

        plan.setAllocation(ALLOCATOR1, ILK1, 0);

        assertEqAllocation(ALLOCATOR1, ILK1, 0, 100 ether);
        assertEqAllocation(ALLOCATOR2, ILK1, 25 ether, 150 ether);
        assertEq(plan.totalAllocated(ILK1), 25 ether);
        assertEq(plan.numAllocations(ILK1), 1);
        assertEq(plan.allocatorAt(ILK1, 0), ALLOCATOR2);
        assertEq(plan.hasAllocator(ILK1, ALLOCATOR1), false);
        assertEq(plan.hasAllocator(ILK1, ALLOCATOR2), true);
    }

    function test_setAllocation_ward_any() public {
        _initAllocators();
        plan.setMaxAllocation(ALLOCATOR1, ILK1, 100 ether);
        
        assertEqAllocation(ALLOCATOR1, ILK1, 0, 100 ether);
        vm.expectEmit(true, true, true, true);
        emit SetAllocation(ALLOCATOR1, ILK1, 0, 75 ether);
        plan.setAllocation(ALLOCATOR1, ILK1, 75 ether);
        assertEqAllocation(ALLOCATOR1, ILK1, 75 ether, 100 ether);
    }

    function test_setAllocation_allocator_self() public {
        _initAllocators();
        plan.setMaxAllocation(ALLOCATOR1, ILK1, 100 ether);
        plan.deny(address(this));
        
        assertEqAllocation(ALLOCATOR1, ILK1, 0, 100 ether);
        vm.prank(ALLOCATOR1); plan.setAllocation(ALLOCATOR1, ILK1, 75 ether);
        assertEqAllocation(ALLOCATOR1, ILK1, 75 ether, 100 ether);
    }

    function test_setAllocation_allocator_other() public {
        _initAllocators();
        plan.setMaxAllocation(ALLOCATOR1, ILK1, 100 ether);
        plan.deny(address(this));
        
        vm.expectRevert(abi.encodePacked(contractName, "/not-authorized"));
        vm.prank(ALLOCATOR2); plan.setAllocation(ALLOCATOR1, ILK1, 75 ether);
    }

    function test_setAllocation_allocator_delegate_approved() public {
        _initAllocators();
        plan.setMaxAllocation(ALLOCATOR1, ILK1, 100 ether);
        plan.addAllocatorDelegate(ALLOCATOR1, ALLOCATORDELEGATE1);
        plan.deny(address(this));
        
        assertEqAllocation(ALLOCATOR1, ILK1, 0, 100 ether);
        vm.prank(ALLOCATORDELEGATE1); plan.setAllocation(ALLOCATOR1, ILK1, 75 ether);
        assertEqAllocation(ALLOCATOR1, ILK1, 75 ether, 100 ether);
    }

    function test_setAllocation_allocator_delegate_not_approved() public {
        _initAllocators();
        plan.setMaxAllocation(ALLOCATOR1, ILK1, 100 ether);
        plan.deny(address(this));
        
        vm.expectRevert(abi.encodePacked(contractName, "/not-authorized"));
        vm.prank(ALLOCATORDELEGATE1); plan.setAllocation(ALLOCATOR1, ILK1, 75 ether);
    }

    function test_setAllocation_above_max() public {
        _initAllocators();
        plan.setMaxAllocation(ALLOCATOR1, ILK1, 100 ether);
        
        vm.expectRevert(abi.encodePacked(contractName, "/amount-exceeds-max"));
        plan.setAllocation(ALLOCATOR1, ILK1, 100 ether + 1);
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

    function assertEqAllocation(address allocator, bytes32 ilk, uint256 current, uint256 max) internal {
        (uint128 _current, uint128 _max) = plan.allocations(allocator, ilk);
        assertEq(_current, current, "current does not match");
        assertEq(_max, max, "max does not match");
    }
    
}
