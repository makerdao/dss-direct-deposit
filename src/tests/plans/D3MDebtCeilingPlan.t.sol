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

import { D3MPlanBaseTest } from "./D3MPlanBase.t.sol";
import { D3MDebtCeilingPlan } from "../../plans/D3MDebtCeilingPlan.sol";

contract VatMock {

    uint256 debtCeiling;

    function setDebtCeiling(uint256 value) external {
        debtCeiling = value;
    }

    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256) {
        return (0, 0, 0, debtCeiling, 0);
    }

}

contract D3MDebtCeilingPlanTest is D3MPlanBaseTest {

    bytes32 ilk = "DIRECT-PROTOCOL-A";
    VatMock vat;

    D3MDebtCeilingPlan plan;

    event Disable();

    function setUp() public override {
        contractName = "D3MDebtCeilingPlan";

        vat = new VatMock();

        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        d3mTestPlan = address(plan = new D3MDebtCeilingPlan(address(vat), ilk));
    }

    function test_constructor() public {
        assertEq(address(plan.vat()), address(vat));
        assertEq(plan.ilk(), ilk);
        assertEq(plan.enabled(), 1);
    }

    function test_file() public {
        // File checks will increment the current value by 1 so
        // just set it to 0 to start with so there is no revert.
        plan.file("enabled", 0);
        checkFileUint(d3mTestPlan, contractName, ["enabled"]);
    }

    function test_file_bad_value() public {
        vm.expectRevert("D3MDebtCeilingPlan/invalid-value");
        plan.file("enabled", 2);
    }

    function test_auth_modifier() public {
        plan.deny(address(this));

        checkModifier(d3mTestPlan, "D3MDebtCeilingPlan/not-authorized", [
            abi.encodeWithSelector(D3MDebtCeilingPlan.disable.selector)
        ]);
    }

    function test_implements_getTargetAssets() public override {
        vat.setDebtCeiling(100 * RAD);
        uint256 result = plan.getTargetAssets(456);

        assertEq(result, 100 * WAD);
    }

    function test_active_no_debt_ceiling() public {
        assertEq(plan.enabled(), 1);
        assertTrue(!plan.active());
        vat.setDebtCeiling(100 * RAD);
        assertEq(plan.enabled(), 1);
        assertTrue(plan.active());
    }

    function test_disable() public {
        vat.setDebtCeiling(100 * RAD);

        assertEq(plan.enabled(), 1);
        assertTrue(plan.active());
        vm.expectEmit(true, true, true, true);
        emit Disable();
        plan.disable();
        assertTrue(!plan.active());
        assertEq(plan.enabled(), 0);
    }

}
