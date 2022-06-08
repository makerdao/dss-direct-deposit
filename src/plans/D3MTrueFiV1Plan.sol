// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021-2022 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//s
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.14;

import "./ID3MPlan.sol";

import { PortfolioLike } from "../tests/interfaces/interfaces.sol";

contract D3MTrueFiV1Plan is ID3MPlan {
    PortfolioLike public immutable portfolio;

    uint256 public cap; // Target Deposit Amount

    // --- Auth ---
    mapping(address => uint256) public wards;

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "D3MTrueFiV1DaiPLan/not-authorized");
        _;
    }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    constructor(address portfolio_) {
        portfolio = PortfolioLike(portfolio_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

     // --- Admin ---
    function file(bytes32 what, uint256 data) public auth {
        if (what == "cap") {
            cap = data;
        } else revert("D3MTrueFiV1DaiPLan/file-unrecognized-param");
    }

    function active() external view override returns (bool) {
        return portfolio.getStatus() == PortfolioLike.PortfolioStatus.Open;
    }

    function getTargetAssets(uint256) external view override returns (uint256) {
        return cap;
    }

    function disable() external override auth {
        emit Disable();
    }
}
