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

pragma solidity ^0.8.14;

import "./ID3MFees.sol";

interface VatLike {
    function dai(address) external view returns (uint256);
    function move(address, address, uint256) external;
}

/**
 * @title Forward Fees
 * @notice Forwards all fees to a single contract
 */
contract D3MForwardFees is ID3MFees {

    VatLike public immutable vat;
    address public immutable target;

    constructor(address _vat, address _target) {
        vat = VatLike(_vat);
        target = _target;
    }

    function feesCollected(bytes32 ilk, uint256) external {
        uint256 dai = vat.dai(address(this));   // Maybe someone permissionlessly sent us DAI
        vat.move(address(this), target, dai);

        emit FeesCollected(ilk, dai);
    }

}
