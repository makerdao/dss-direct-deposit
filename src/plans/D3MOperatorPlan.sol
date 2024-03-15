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

import "./ID3MPlan.sol";

/**
 *  @title D3M Operator Plan
 *  @notice An operator sets the desired target assets.
 */
contract D3MOperatorPlan is ID3MPlan {

    mapping (address => uint256) public wards;
    uint256                      public enabled;

    address public operator;
    uint256 public targetAssets;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, uint256 data);

    constructor() {
        enabled = 1;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MOperatorPlan/not-authorized");
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

    function file(bytes32 what, address data) external auth {
        if (what == "operator") {
            operator = data;
        } else revert("D3MOperatorPlan/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "enabled") {
            require(data <= 1, "D3MOperatorPlan/invalid-value");
            enabled = data;
        } else revert("D3MOperatorPlan/file-unrecognized-param");
        emit File(what, data);
    }

    function setTargetAssets(uint256 value) external {
        require(msg.sender == operator, "D3MOperatorPlan/not-authorized");

        targetAssets = value;
    }

    function getTargetAssets(uint256) external override view returns (uint256) {
        return targetAssets;
    }

    function active() public view override returns (bool) {
        return enabled == 1;
    }

    function disable() external override auth {
        enabled = 0;
        emit Disable();
    }
}
