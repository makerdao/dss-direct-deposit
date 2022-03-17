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

import "./DssDirectDepositTestGem.sol";

contract DssDirectDepositTestRewards {

    DssDirectDepositTestGem public immutable rewards;
    address public immutable testGem;

     // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    constructor(address testGem_) public {
        rewards = new DssDirectDepositTestGem(18);
        testGem = testGem_;
    }

    function claimRewards(address[] memory assets, uint256 amount, address dst) external returns (uint256 amt) {
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == testGem) {
                amt += amount;
                rewards.mint(dst, amount);
            }
        }
    }
}
