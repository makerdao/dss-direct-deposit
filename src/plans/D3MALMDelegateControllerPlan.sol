// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
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

import "./ID3MPlan.sol";
import "../utils/EnumerableSet.sol";

/**
 *  @title D3M ALM Delegate Controller
 *  @notice Allocators can set debt ceilings for target ilks. Delegate addresses can be added for custom logic.
 */
contract D3MALMDelegateControllerPlan is ID3MPlan {

    using EnumerableSet for EnumerableSet.AddressSet;

    struct IlkAllocation {
        uint256 total;                          // The total allocated to this ilk [wad]
        EnumerableSet.AddressSet allocators;    // The list of allocators that have allocated to this ilk
    }

    struct Allocation {
        uint128 current;    // The current allocation for this allocator [wad]
        uint128 max;        // The maximum allocation for this allocator [wad]
    }

    mapping (address => uint256) public wards;
    mapping (address => uint256) public allocators;                                 // Allocators can set debt ceilings for target ilks
    mapping (address => mapping (address => uint256)) public allocatorDelegates;    // Allocators can delegate authority to custom logic / wallets
    mapping (bytes32 => IlkAllocation) private _ilkAllocations;
    mapping (address => mapping (bytes32 => Allocation)) public allocations;

    uint256 public enabled = 1;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event AddAllocator(address indexed allocator);
    event RemoveAllocator(address indexed allocator);
    event SetMaxAllocation(address indexed allocator, bytes32 indexed ilk, uint128 max);
    event AddAllocatorDelegate(address indexed allocator, address indexed allocatorDelegate);
    event RemoveAllocatorDelegate(address indexed allocator, address indexed allocatorDelegate);
    event SetAllocation(address indexed allocator, bytes32 indexed ilk, uint128 previousAllocation, uint128 newAllocation);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MALMDelegateControllerPlan/not-authorized");
        _;
    }

    // --- Admin ---
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "enabled") {
            require(data <= 1, "D3MALMDelegateControllerPlan/invalid-value");
            enabled = data;
        } else revert("D3MALMDelegateControllerPlan/file-unrecognized-param");
        emit File(what, data);
    }

    function addAllocator(address allocator) external auth {
        allocators[allocator] = 1;
        emit AddAllocator(allocator);
    }

    function removeAllocator(address allocator) external auth {
        allocators[allocator] = 0;
        emit RemoveAllocator(allocator);
    }

    function setMaxAllocation(address allocator, bytes32 ilk, uint128 max) external auth {
        allocations[allocator][ilk].max = max;
        emit SetMaxAllocation(allocator, ilk, max);

        uint128 currentAllocation = allocations[allocator][ilk].current;
        if (max < currentAllocation) {
            _setAllocation(allocator, ilk, currentAllocation, max);
        }
    }

    // --- Allocator Control ---
    function addAllocatorDelegate(address allocator, address allocatorDelegate) external {
        require((allocator == msg.sender && allocators[allocator] == 1) || wards[msg.sender] == 1, "D3MALMDelegateControllerPlan/not-authorized");

        allocatorDelegates[allocator][allocatorDelegate] = 1;
        emit AddAllocatorDelegate(allocator, allocatorDelegate);
    }

    function removeAllocatorDelegate(address allocator, address allocatorDelegate) external {
        require((allocator == msg.sender && allocators[allocator] == 1) || wards[msg.sender] == 1, "D3MALMDelegateControllerPlan/not-authorized");

        allocatorDelegates[allocator][allocatorDelegate] = 0;
        emit RemoveAllocatorDelegate(allocator, allocatorDelegate);
    }

    function setAllocation(address allocator, bytes32 ilk, uint128 amount) external {
        require(
            (
                allocators[allocator] == 1 && 
                (allocatorDelegates[allocator][msg.sender] == 1 || allocator == msg.sender)
            ) ||
            wards[msg.sender] == 1
        , "D3MALMDelegateControllerPlan/not-authorized");
        Allocation memory allocation = allocations[allocator][ilk];
        require(amount <= allocation.max, "D3MALMDelegateControllerPlan/amount-exceeds-max");

        _setAllocation(allocator, ilk, allocation.current, amount);
    }

    function _setAllocation(address allocator, bytes32 ilk, uint128 currentAllocation, uint128 newAllocation) internal {
        allocations[allocator][ilk].current = newAllocation;
        _ilkAllocations[ilk].total = _ilkAllocations[ilk].total - currentAllocation + newAllocation;
        if (newAllocation > 0 && !_ilkAllocations[ilk].allocators.contains(allocator)) {
            _ilkAllocations[ilk].allocators.add(allocator);
        } else if (newAllocation == 0 && _ilkAllocations[ilk].allocators.contains(allocator)) {
            _ilkAllocations[ilk].allocators.remove(allocator);
        }
        emit SetAllocation(allocator, ilk, currentAllocation, newAllocation);
    }

    // --- Getter Functions ---
    function totalAllocations(bytes32 ilk) external view returns (uint256) {
        return  _ilkAllocations[ilk].total;
    }

    function numAllocations(bytes32 ilk) external view returns (uint256) {
        return _ilkAllocations[ilk].allocators.length();
    }

    function allocatorAt(bytes32 ilk, uint256 index) external view returns (address) {
        return _ilkAllocations[ilk].allocators.at(index);
    }

    function hasAllocator(bytes32 ilk, address allocator) external view returns (bool) {
        return _ilkAllocations[ilk].allocators.contains(allocator);
    }

    // --- IPlan Functions ---
    function getTargetAssets(bytes32 ilk, uint256) external override view returns (uint256) {
        if (enabled == 0) return 0;

        return _ilkAllocations[ilk].total;
    }

    function active() public view override returns (bool) {
        return enabled == 1;
    }

    function disable() external override auth {
        enabled = 0;
        emit Disable();
    }

}
