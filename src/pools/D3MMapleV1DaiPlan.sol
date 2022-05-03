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

interface PoolLike {
    function intendToWithdraw() external;
}

interface MapleGlobalsLike {
    function getLpCooldownParams() external view returns (uint256, uint256);
}

contract D3MMapleV1DaiPlan is D3MPlanBase {

    PoolLike public immutable pool;

    uint256 public cap; // Target Loan Size
    bool    public cue; // If true then we intend to initiate a withdraw

    constructor(address dai_, address pool_) public D3MPlanBase(dai_) {
        pool = PoolLike(pool_);
    }

    // --- Admin ---
    function file(bytes32 what, uint256 data) public auth {
        if (what == "cap") {
            // TODO need to add a check that we are not already in some aspect of the withdraw phase
            // TODO also need to check that our current DAI position is greater than the new cap
            if (cap < data) {
                // Need to signal to the pool that we want to withdraw. We may be in the pre-cooldown
                // phase, so we signal to withdraw at the next available opportunity.
                cue = true;
            }

            cap = data;
        } else revert("D3MMapleV1DaiPlan/file-unrecognized-param");
    }

    // @dev A keeper needs to watch this and trigger when non-reverting
    function trip() external {
        require(cue, "D3MMapleV1DaiPlan/no-cue");
        pool.intendToWithdraw();
        cue = false;
    }

    // TODO Add override when available in base
    function getTargetAssets(uint256 curr) external view returns (uint256) {
        return cap;
    }

    function calcSupplies(uint256 availableLiquidity) external override view returns (uint256 supplyAmount, uint256 targetSupply) {
        // Allow for compile
        // TODO: Implement
        supplyAmount = 0;
        targetSupply = 0;
    }
}
