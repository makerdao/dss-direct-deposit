// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
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

import "dss-test/DssTest.sol";
import "dss-interfaces/Interfaces.sol";
import { VatMock } from "../mocks/VatMock.sol";

import { D3MForwardFees } from "../../fees/D3MForwardFees.sol";

contract D3MForwardFeesTest is DssTest {

    VatMock vat;
    
    D3MForwardFees private fees;

    event FeesCollected(bytes32 indexed ilk, uint256 fees);

    function setUp() public {
        vat = new VatMock();
        
        fees = new D3MForwardFees(address(vat), TEST_ADDRESS);
    }

    function test_forward_fees() public {
        vat.suck(address(this), address(fees), 100 * RAD);

        assertEq(vat.dai(address(fees)), 100 * RAD);
        assertEq(vat.dai(TEST_ADDRESS), 0);
        fees.feesCollected("ETH-A", 100 * RAD);
        assertEq(vat.dai(address(fees)), 0);
        assertEq(vat.dai(TEST_ADDRESS), 100 * RAD);
    }

    function test_forward_fees_amount_mismatch() public {
        vat.suck(address(this), address(fees), 100 * RAD);

        assertEq(vat.dai(address(fees)), 100 * RAD);
        assertEq(vat.dai(TEST_ADDRESS), 0);
        fees.feesCollected("ETH-A", 0);
        assertEq(vat.dai(address(fees)), 0);
        assertEq(vat.dai(TEST_ADDRESS), 100 * RAD);
    }

}
