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

import "./D3MSwapPool.t.sol";

import { D3MWhitelistedSwapPool } from "../../pools/D3MWhitelistedSwapPool.sol";

contract PlanMock {

    uint256 public targetAssets;

    function setTargetAssets(uint256 _targetAssets) external {
        targetAssets = _targetAssets;
    }

    function getTargetAssets(bytes32, uint256) external view returns (uint256) {
        return targetAssets;
    }

}

contract D3MWhitelistedSwapPoolTest is D3MSwapPoolTest {

    PlanMock plan;

    D3MWhitelistedSwapPool internal pool;

    event SetPlan(address plan);
    event File(bytes32 indexed what, uint128 tin, uint128 tout);
    event AddOperator(address indexed operator);
    event RemoveOperator(address indexed operator);

    function setUp() public {
        baseInit("D3MSwapPool");

        plan = new PlanMock();

        pool = new D3MWhitelistedSwapPool(ILK, address(hub), address(dai), address(gem), address(plan));

        // Fees set to tin=5bps, tout=-10bps
        pool.file("fees", 1.0005 ether, 0.9990 ether);

        setPoolContract(address(pool));
    }

    function _ensureCanSellGems(uint256 daiAmt) internal override virtual {
        dai.transfer(address(pool), daiAmt);
        plan.setTargetAssets(daiAmt);
    }

    function _ensureCanBuyGems(uint256 gemAmt) internal override virtual {
        gem.transfer(address(pool), gemAmt);
        plan.setTargetAssets(0);
    }

    function test_authModifier() public {
        pool.deny(address(this));

        checkModifier(address(pool), string(abi.encodePacked(contractName, "/not-authorized")), [
            D3MWhitelistedSwapPool.setPlan.selector,
            bytes4(keccak256("file(bytes32,uint128,uint128)")),
            D3MWhitelistedSwapPool.addOperator.selector,
            D3MWhitelistedSwapPool.removeOperator.selector
        ]);
    }

    function test_setPlan() public {
        assertEq(address(pool.plan()), address(plan));
        vm.expectEmit(true, true, true, true);
        emit SetPlan(TEST_ADDRESS);
        pool.setPlan(TEST_ADDRESS);
        assertEq(address(pool.plan()), TEST_ADDRESS);

        vat.cage();
        vm.expectRevert(abi.encodePacked(contractName, "/no-file-during-shutdown"));
        pool.setPlan(address(1));
    }

    function test_file_fees() public {
        vm.expectRevert(abi.encodePacked(contractName, "/file-unrecognized-param"));
        pool.file("an invalid value", 1, 2);

        vm.expectEmit(true, true, true, true);
        emit File("fees", 1, 2);
        pool.file("fees", 1, 2);

        assertEq(pool.tin(), 1);
        assertEq(pool.tout(), 2);

        vat.cage();
        vm.expectRevert(abi.encodePacked(contractName, "/no-file-during-shutdown"));
        pool.file("some value", 1, 2);
    }

    function test_file_invalid_fees() public {
        vm.expectRevert(abi.encodePacked(contractName, "/invalid-fees"));
        pool.file("fees", uint128(WAD + 1), uint128(WAD));
    }

    function test_addOperator() public {
        assertEq(pool.operators(TEST_ADDRESS), 0);
        vm.expectEmit(true, true, true, true);
        emit AddOperator(TEST_ADDRESS);
        pool.addOperator(TEST_ADDRESS);
        assertEq(pool.operators(TEST_ADDRESS), 1);

        vat.cage();
        vm.expectRevert(abi.encodePacked(contractName, "/no-file-during-shutdown"));
        pool.addOperator(address(1));
    }

    function test_removeOperator() public {
        pool.addOperator(TEST_ADDRESS);

        assertEq(pool.operators(TEST_ADDRESS), 1);
        vm.expectEmit(true, true, true, true);
        emit RemoveOperator(TEST_ADDRESS);
        pool.removeOperator(TEST_ADDRESS);
        assertEq(pool.operators(TEST_ADDRESS), 0);

        vat.cage();
        vm.expectRevert(abi.encodePacked(contractName, "/no-file-during-shutdown"));
        pool.addOperator(address(1));
    }

}
