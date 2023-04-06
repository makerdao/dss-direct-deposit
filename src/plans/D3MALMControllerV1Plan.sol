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

    struct SubDAO {
        address proxy;
        uint256 totalRelativeAssets;
    }

    enum AllotmentType {
        FIXED,
        RELATIVE
    }

    struct AllocatorAllotment {
        uint256 allocatorId;
        AllotmentType allotmentType;
        uint256 amount;
        uint256 amountCached;   // A cached calculation for relative allotments
    }

    struct InvestmentTarget {
        bytes32 ilk;
        uint256 ownerId;
        uint256 revShare;
        AllocatorAllotment[] allotments;
    }

    mapping (address => uint256) public wards;
    mapping (bytes32 => InvestmentTarget) public targets;

    uint256 public enabled = 1;
    SubDAO[] public subdaos;

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
            require(data <= 1, "D3MDebtCeilingPlan/invalid-value");
            enabled = data;
        } else revert("D3MDebtCeilingPlan/file-unrecognized-param");
        emit File(what, data);
    }

    function getTargetAssets(bytes32 ilk, uint256 daiLiquidity, uint256 currentAssets) external override view returns (uint256 targetAssets) {
        if (enabled == 0) return 0;

        InvestmentTarget memory target = targets[ilk];
        AllocatorAllotment[] memory allotments = target.allotments;

        // Calculate targetAssets
        for (uint256 i = 0; i < allotments.length; i++) {
            AllocatorAllotment memory allotment = allotments[i];
            if (allotment.allotmentType == AllotmentType.FIXED) {
                targetAssets += allotment.amount;
            } else if (allotment.allotmentType == AllotmentType.RELATIVE) {
                targetAssets += subdaos[allotment.allocatorId].totalRelativeAssets * allotment.amount / BPS;
            } else {
                revert("Invalid allotment type");
            }
        }

        // Refresh the relative allotment
        for (uint256 i = 0; i < subdaos.length; i++) {
            
        }
    }

    function active() public view override returns (bool) {
        return enabled == 1;
    }

    function disable() external override auth {
        enabled = 0;
        emit Disable();
    }
}
