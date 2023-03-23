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

import "../../plans/ID3MPlan.sol";

abstract contract D3MPlanBaseTest is DssTest {

    string public contractName;

    ID3MPlan private plan;

    function baseInit(ID3MPlan _plan, string memory _contractName) internal {
        plan = _plan;
        contractName = _contractName;
    }

    function test_auth() public {
        checkAuth(address(plan), contractName);
    }

    function test_auth_modifiers() public virtual {
        WardsAbstract(address(plan)).deny(address(this));

        checkModifier(address(plan), string(abi.encodePacked(contractName, "/not-authorized")), [
            abi.encodeWithSelector(ID3MPlan.disable.selector)
        ]);
    }

    function test_disable_makes_inactive() public virtual {
        assertEq(plan.active(), true);
        plan.disable();
        assertEq(plan.active(), false);
    }

}
