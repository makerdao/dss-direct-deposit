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

/**
 *  @title D3M ALM Controller V1
 *  @notice Allocates/liquidates debt to multiple investment vehicles. Supports fixed and relative debt targets.
 */
contract D3MALMControllerV1Plan is ID3MPlan {

    struct AllocatorAllotment {
        address allocator;
        uint256 amount;
    }

    struct InvestmentTarget {
        bytes32 ilk;
        address owner;                      // Owner of the D3M
        uint256 fee;                        // Fee that goes to the owner [BPS]
        uint256 totalAllocated;             // Total amount of debt ceiling allocated to this target [WAD]
        AllocatorAllotment[] allotments;    // Breakdown of which allocator owns what portion of the debt ceiling [WAD]
    }

    mapping (address => uint256) public wards;
    mapping (address => uint256) public allocators;
    mapping (address => address) public allocatorDelegates;     // Allocators can delegate authority to other allocators
    mapping (bytes32 => InvestmentTarget) public targets;

    uint256 public enabled = 1;

    uint256 internal constant BPS = 10 ** 4;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event AddAllocator(address indexed allocator);
    event RemoveAllocator(address indexed allocator);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed ilk, bytes32 indexed what, uint256 data);
    event File(bytes32 indexed ilk, bytes32 indexed what, address data);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MALMControllerV1Plan/not-authorized");
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

    function addAllocatorDelegate(address allocator, address allocatorDelegate) external {
        require((allocator == msg.sender && allocators[msg.sender] == 1) || wards[msg.sender] == 1, "D3MALMControllerV1Plan/not-authorized");

        allocatorDelegates[allocatorDelegate] = allocator;
        emit AddAllocatorDelegate(allocator);
    }

    function removeAllocatorDelegate(address allocator, address allocatorDelegate) external {
        require((allocator == msg.sender && allocators[msg.sender] == 1) || wards[msg.sender] == 1, "D3MALMControllerV1Plan/not-authorized");

        allocatorDelegates[allocatorDelegate] = address(0);
        emit RemoveAllocatorDelegate(allocator);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "enabled") {
            require(data <= 1, "D3MALMControllerV1Plan/invalid-value");
            enabled = data;
        } else revert("D3MALMControllerV1Plan/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 ilk, bytes32 what, address data) external auth {
        if (what == "owner") targets[ilk].owner = data;
        else revert("D3MALMControllerV1Plan/file-unrecognized-param");
        emit File(ilk, what, data);
    }

    function setFee(bytes32 ilk, uint256 fee) external {
        require(msg.sender == targets[ilk].owner || wards[msg.sender] == 1, "D3MALMControllerV1Plan/not-authorized");

        targets[ilk].fee = fee;
    }

    function setAllocation(bytes32 ilk, address allocator, uint256 amount) external {
        require(
            (allocatorDelegates[msg.sender] == allocator && allocators[allocator] == 1) ||
            (allocator == msg.sender && allocators[msg.sender] == 1) ||
            wards[msg.sender] == 1
        , "D3MALMControllerV1Plan/not-authorized");

        InvestmentTarget memory target = targets[ilk];
        AllocatorAllotment[] memory allotments = target.allotments;

        uint256 previousAmount;
        for (uint256 i = 0; i < allotments.length; i++) {
            AllocatorAllotment memory allotment = allotments[i];
            if (allotment.allocator == allocator) {
                // Already exists, update
                previousAmount = allotments[i].amount;
                targets[ilk].allotments[i].amount = amount;
            }
        }
        targets[ilk].totalAllocated = target.totalAllocated - previousAmount + amount;
    }

    // --- IPlan Functions ---
    function getTargetAssets(bytes32 ilk, uint256 currentAssets) external override view returns (uint256) {
        if (enabled == 0) return 0;

        return targets[ilk].totalAllocated;
    }

    function active() public view override returns (bool) {
        return enabled == 1;
    }

    function disable() external override auth {
        enabled = 0;
        emit Disable();
    }

}
