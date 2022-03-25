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

import "../bases/D3MPlanBase.sol";

contract D3MTestPlan is D3MPlanBase {
    // test helper variables
    uint256 maxBar_;
    uint256 totalAssets;
    uint256 targetAssets;
    uint256 currentRate;

    constructor(address dai_, address pool_) public D3MPlanBase(dai_, pool_) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Testing Admin ---
    function file(bytes32 what, uint256 data) public override auth {
        if (what == "maxBar_") {
            maxBar_ = data;
        } else if (what == "totalAssets") {
            totalAssets = data;
        } else if (what == "targetAssets") {
            targetAssets = data;
        } else if (what == "currentRate") {
            currentRate = data;
        } else super.file(what, data);
    }

    function maxBar() public override view returns (uint256) {
        return maxBar_;
    }

    function calcSupplies(uint256 availableAssets) external override view returns (uint256, uint256) {
        availableAssets;

        return (totalAssets, bar > 0 ? targetAssets : 0);
    }
}
