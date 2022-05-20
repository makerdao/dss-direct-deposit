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

import "./ID3MPlan.sol";

interface PoolLike {
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function deposit(uint256 amount) external;
    function intendToWithdraw() external;
}

interface MapleGlobalsLike {
    function getLpCooldownParams() external view returns (uint256, uint256);
}

contract D3MMapleV1DaiPlan is ID3MPlan {

    PoolLike public immutable pool;

    uint256 public cap; // Target Loan Size
    bool    public cue; // If true then we intend to initiate a withdraw

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "D3MMapleV1DaiPlan/not-authorized");
        _;
    }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    constructor(address dai_, address pool_) public {
        pool = PoolLike(pool_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
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

    function active() external view override returns (bool) {
        return true;
    }

    // @dev A keeper needs to watch this and trigger when non-reverting
    function trip() external {
        require(cue, "D3MMapleV1DaiPlan/no-cue");
        pool.intendToWithdraw();
        cue = false;
    }

    // TODO Add override when available in base
    function getTargetAssets(uint256) external override view returns (uint256) {
        return cap;
    }

    function disable() external override auth {
        cap = 0;
        emit Disable();
    }
}
