// SPDX-FileCopyrightText: © 2021-2022 Dai Foundation <www.daifoundation.org>
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

pragma solidity ^0.8.14;

import "ds-test/test.sol";

contract DssTest is DSTest{
    function assertRevert(address target, bytes memory data, string memory contractName, string memory expectedMessage) internal {
        assertRevert(target, data, 0, string(abi.encodePacked(contractName, "/", expectedMessage)));
    }

    function assertRevert(address target, bytes memory data, string memory expectedMessage) internal {
        assertRevert(target, data, 0, expectedMessage);
    }

    function assertRevert(address target, bytes memory data, uint256 value, string memory expectedMessage) internal {
        bool succeeded;
        bytes memory response;
        (succeeded, response) = target.call{value:value}(data);
        if (succeeded) {
            emit log("Error: call not reverted");
            fail();
        } else {
            string memory message;
            assembly {
                let size := mload(add(response, 0x44))
                message := mload(0x40)
                mstore(message, size)
                mstore(0x40, add(message, and(add(add(size, 0x20), 0x1f), not(0x1f))))
                returndatacopy(add(message, 0x20), 0x44, size)
            }
            if (keccak256(abi.encodePacked(message)) != keccak256(abi.encodePacked(expectedMessage))) {
                emit log("Error: revert message not satisfied");
                fail();
            }
        }
    }
}
