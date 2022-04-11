// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021-2022 Dai Foundation
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

pragma solidity 0.6.12;

import "../../plans/D3MPlanBase.sol";

contract D3MTestPlan is D3MPlanBase {
    // test helper variables
    uint256 maxBar_;
    uint256 targetAssets;
    uint256 currentRate;

    uint256 public bar;  // Target Interest Rate [ray]

    constructor(address dai_) public D3MPlanBase(dai_) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Admin ---
    function file(bytes32 what, uint256 data) external auth {
        if (what == "maxBar_") {
            maxBar_ = data;
        } else if (what == "targetAssets") {
            targetAssets = data;
        } else if (what == "currentRate") {
            currentRate = data;
        } else if (what == "bar") {
            require(data <= maxBar(), "D3MTestPlan/above-max-interest");

            bar = data;
        } else revert("D3MTestPlan/file-unrecognized-param");
    }

    function maxBar() public view returns (uint256) {
        return maxBar_;
    }

    function getTargetAssets(uint256 currentAssets) external override view returns (uint256) {
        currentAssets;

        return bar > 0 ? targetAssets : 0;
    }

    function disable() external auth {
        bar = 0;
    }
}