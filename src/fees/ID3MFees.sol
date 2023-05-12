// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
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

pragma solidity >=0.8.0;

/**
    @title D3M Fees Interface
    @notice Receives fees from the Hub and distributes them
*/
interface ID3MFees {

    /**
     * @notice Emitted when fees are collected
     * @param ilk The ilk where the fees were collected
     * @param fees The amount of fees collected [rad]
     */
    event FeesCollected(bytes32 indexed ilk, uint256 fees);

    /**
     * @notice Called after fees have been received.
     * @param ilk The ilk where the fees were collected
     * @param fees The amount of fees collected [rad]
     */
    function feesCollected(bytes32 ilk, uint256 fees) external;

}
