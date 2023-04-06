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
import "../pools/ID3MPool.sol";
import "../utils/EnumerableSet.sol";

interface BaseRateProviderLike {
    function getBaseRate() external view returns (uint256);
}

/**
 *  @title D3M ALM Controller V1
 *  @notice Allocates/liquidates debt to multiple investment vehicles. Supports fixed and relative debt targets.
 */
contract D3MALMControllerV1Plan is ID3MPlan {

    using EnumerableSet for EnumerableSet.AddressSet;

    struct Allocator {
        address owner;
        uint256 dai;
        uint256 sin;
    }

    struct AllocatorAllotment {
        address allocator;
        uint256 amount;
    }

    struct InvestmentTarget {
        bytes32 ilk;
        ID3MPool pool;
        address owner;
        uint256 fee;                        // Fee that goes to the owner [WAD]
        uint256 totalAllocated;             // Total amount of debt ceiling allocated to this target [WAD]
        AllocatorAllotment[] allotments;    // Breakdown of which allocator owns what portion of the debt ceiling [WAD]
    }

    mapping (address => uint256) public wards;
    mapping (bytes32 => InvestmentTarget) public targets;
    mapping (address => Allocator) public allocators;

    uint256 public enabled = 1;
    BaseRateProviderLike public baseRateProvider;
    EnumerableSet.AddressSet private activeAllocators;

    uint256 internal constant WAD = 10 ** 18;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);

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

    function file(bytes32 what, uint256 data) external auth {
        if (what == "enabled") {
            require(data <= 1, "D3MALMControllerV1Plan/invalid-value");
            enabled = data;
        } else revert("D3MALMControllerV1Plan/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 ilk, bytes32 what, uint256 data) external auth {
        require(data <= WAD, "D3MALMControllerV1Plan/invalid-value");

        if (what == "fee") targets[ilk].fee = data;
        else revert("D3MALMControllerV1Plan/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 ilk, bytes32 what, address data) external auth {
        if (what == "pool") targets[ilk].pool = data;
        else if (what == "owner") targets[ilk].owner = data;
        else revert("D3MALMControllerV1Plan/file-unrecognized-param");
        emit File(what, data);
    }

    function setAllocation(bytes32 ilk, address allocator, uint256 amount) external auth {
        InvestmentTarget memory target = targets[ilk];
        AllocatorAllotment[] memory allotments = target.allotments;

        for (uint256 i = 0; i < allotments.length; i++) {
            if (allotments[i].allocator == allocator) {
                allotments[i].amount = amount;
                return;
            }
        }

        targets[ilk] = target;
    }

    // --- Accessors ---
    function numAllocators() external view returns (uint256) {
        return activeAllocators.length();
    }
    function allocatorAt(uint256 index) external view returns (address) {
        return activeAllocators.at(index);
    }
    function hasAllocator(address allocator) external view returns (bool) {
        return activeAllocators.contains(allocator);
    }

    // --- Collect Maker Fees ---
    function collect() external {
        // TODO this should execute once per ttl
        uint256 baseRate = baseRateProvider.getBaseRate();

        uint256 l = activeAllocators.length();
        for (uint256 i = 0; i < l; i++) {
            address allocator = activeAllocators.at(i);
            uint256 idleDai = pool.maxWithdraw();

            // TODO charge the allocator for all the active DAI they have
        }
    }

    // --- IFees Functions ---
    function fees(bytes32 ilk, uint256 fees) external override returns (uint256 amountToVow) {
        InvestmentTarget memory target = targets[ilk];
        allocators[target.owner].dai += fees * target.fee / WAD;
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
