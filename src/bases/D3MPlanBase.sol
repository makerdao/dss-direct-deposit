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

abstract contract D3MPlanBase {

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
        require(wards[msg.sender] == 1, "D3MPlanBase/not-authorized");
        _;
    }

    address public immutable pool;
    address public immutable dai;

    uint256 public bar;  // Target Interest Rate [ray]

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    constructor(address dai_, address pool_) public {
        pool = pool_;
        dai = dai_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

        // --- Admin ---
    function file(bytes32 what, uint256 data) public virtual auth {
        if (what == "bar") {
            require(data <= maxBar(), "D3MPlanBase/above-max-interest");

            bar = data;
        } else revert("D3MPlanBase/file-unrecognized-param");
    }

    function maxBar() public virtual view returns (uint256 maxBar_);

    function calcSupplies(uint256 availableLiquidity) external virtual view returns (uint256 supplyAmount, uint256 targetSupply);
}
