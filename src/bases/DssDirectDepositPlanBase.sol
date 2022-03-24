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

abstract contract DssDirectDepositPlanBase {

    address public immutable pool;
    address public immutable dai;

    constructor(address dai_, address pool_) public {
        pool = pool_;
        dai = dai_;
    }

    function maxBar() public virtual view returns (uint256);

    function calcSupplies(uint256 availableLiquidity, uint256 targetBar) external virtual view returns(uint256 supplyAmount, uint256 targetSupply);
}
