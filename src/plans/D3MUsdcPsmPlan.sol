// SPDX-FileCopyrightText: © 2021 Dai Foundation <www.daifoundation.org>
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

interface TokenLike {
    // function totalSupply() external view returns (uint256);
    // function balanceOf(address) external view returns (uint256);
}

interface PsmLike {
    function gemJoin() external view returns (address);
}

interface GemJoinLike {
    function gem() external view returns (address);
}


contract D3MUsdcPsmPlan is ID3MPlan {

    mapping (address => uint256) public wards;
    uint256                      public amt; // Target USDC [10 ** 6]

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MUsdcPsmPlan/not-authorized");
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
        if (what == "amt") amt = data;
        else revert("D3MUsdcPsmPlan/file-unrecognized-param");
        emit File(what, data);
    }

    // Note: This view function has no reentrancy protection.
    //       On chain integrations should consider verifying `hub.locked()` is zero before relying on it.
    function getTargetAssets(uint256 currentAssets) external override view returns (uint256) {
        currentAssets;
        return amt * 10 **12;
    }

    function active() public view override returns (bool) {
        if (amt == 0) return false;
        return true;
    }

    function disable() external override {
        require(wards[msg.sender] == 1 || !active(), "D3MUsdcPsmPlan/not-authorized");
        amt = 0; // ensure deactivation even if active conditions return later
        emit Disable();
    }
}
