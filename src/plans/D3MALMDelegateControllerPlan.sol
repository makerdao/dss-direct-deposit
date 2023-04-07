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

    struct TotalAllocation {
        uint256 current;
        uint256 max;
        EnumerableSet.AddressSet allocators;
    }

    struct Allocation {
        uint256 current;
        uint256 max;
    }

    mapping (address => uint256) public wards;
    mapping (address => uint256) public allocators;                             // Allocators can set debt ceilings for target ilks
    mapping (address => address) public allocatorDelegates;                     // Allocators can delegate authority to custom logic
    mapping (bytes32 => TotalAllocation) private _totalAllocations;             // current = total of allocators current, max = default per-allocator limit [wad]
    mapping (address => mapping (bytes32 => Allocation)) public allocations;    // current = allocator current, max = per-allocator limit override [wad]

    uint256 public enabled = 1;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event AddAllocator(address indexed allocator);
    event RemoveAllocator(address indexed allocator);
    event AddAllocatorDelegate(address indexed allocator, address indexed allocatorDelegate);
    event RemoveAllocatorDelegate(address indexed allocator, address indexed allocatorDelegate);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed ilk, bytes32 indexed what, uint256 data);
    event File(bytes32 indexed ilk, bytes32 indexed what, address data);

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

    function addAllocator(address allocator) external auth {
        allocators[allocator] = 1;
        emit AddAllocator(allocator);
    }

    function removeAllocator(address allocator) external auth {
        allocators[allocator] = 0;
        emit RemoveAllocator(allocator);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "enabled") {
            require(data <= 1, "D3MALMDelegateControllerPlan/invalid-value");
            enabled = data;
        } else revert("D3MALMDelegateControllerPlan/file-unrecognized-param");
        emit File(what, data);
    }

    function setMaxAllocation(bytes32 ilk, uint256 max) external auth {
        _totalAllocations[ilk].max = max;
        uint256 length = _totalAllocations[ilk].allocators.length();
        for (uint256 i = 0; i < length; i++) {
            address allocator = _totalAllocations[ilk].allocators.at(i);
            if (max < allocations[allocator][ilk].current) {
                _setAllocation(allocator, ilk, max);
            }
        }
    }

    function setMaxAllocation(address allocator, bytes32 ilk, uint256 max) external auth {
        allocations[allocator][ilk].max = max;
        if (max < allocations[allocator][ilk].current) {
            _setAllocation(allocator, ilk, max);
        }
    }

    // --- Allocator Control ---
    function addAllocatorDelegate(address allocator, address allocatorDelegate) external {
        require((allocator == msg.sender && allocators[msg.sender] == 1) || wards[msg.sender] == 1, "D3MALMDelegateControllerPlan/not-authorized");

        allocatorDelegates[allocatorDelegate] = allocator;
        emit AddAllocatorDelegate(allocator, allocatorDelegate);
    }

    function removeAllocatorDelegate(address allocator, address allocatorDelegate) external {
        require((allocator == msg.sender && allocators[msg.sender] == 1) || wards[msg.sender] == 1, "D3MALMDelegateControllerPlan/not-authorized");

        allocatorDelegates[allocatorDelegate] = address(0);
        emit RemoveAllocatorDelegate(allocator, allocatorDelegate);
    }

    function setAllocation(address allocator, bytes32 ilk, uint256 amount) external {
        require(
            (allocatorDelegates[msg.sender] == allocator && allocators[allocator] == 1) ||
            (allocator == msg.sender && allocators[msg.sender] == 1) ||
            wards[msg.sender] == 1
        , "D3MALMDelegateControllerPlan/not-authorized");

        _setAllocation(allocator, ilk, amount);
    }

    function _setAllocation(address allocator, bytes32 ilk, uint256 amount) internal {
        Allocation memory allocation = allocations[allocator][ilk];
        require(
            allocation.max != 0 ?
            amount <= allocation.max :              // Per-allocator limit override
            amount <= _totalAllocations[ilk].max     // Default per-allocator limit
        , "D3MALMDelegateControllerPlan/amount-exceeds-max");
        allocations[allocator][ilk].current = amount;
        _totalAllocations[ilk].current = _totalAllocations[ilk].current - allocation.current + amount;
    }

    // --- Getter Functions ---
    function totalAllocations(bytes32 ilk) external view returns (Allocation memory) {
        return Allocation(
            _totalAllocations[ilk].current,
            _totalAllocations[ilk].max
        );
    }

    function numAllocations(bytes32 ilk) external view returns (uint256) {
        return _totalAllocations[ilk].allocators.length();
    }

    function allocatorAt(bytes32 ilk, uint256 index) external view returns (address) {
        return _totalAllocations[ilk].allocators.at(index);
    }

    function hasAllocator(bytes32 ilk, address allocator) external view returns (bool) {
        return _totalAllocations[ilk].allocators.contains(allocator);
    }

    // --- IPlan Functions ---
    function getTargetAssets(bytes32 ilk, uint256 currentAssets) external override view returns (uint256) {
        if (enabled == 0) return 0;

        return _totalAllocations[ilk].current;
    }

    function active() public view override returns (bool) {
        return enabled == 1;
    }

    function disable() external override auth {
        enabled = 0;
        emit Disable();
    }

}
