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

import { D3MLinearFeeSwapPool } from "../../pools/D3MLinearFeeSwapPool.sol";

contract D3MLinearFeeSwapPoolTest is D3MSwapPoolTest {

    D3MLinearFeeSwapPool internal pool;

    event File(bytes32 indexed what, uint24 tin, uint24 tout);

    function setUp() public {
        baseInit("D3MSwapPool");

        pool = new D3MLinearFeeSwapPool(ILK, address(hub), address(dai), address(gem));

        // 0% usage has tin=5bps (negative fee), tout=20bps (positive fee)
        pool.file("fees1", 10005, 9980);
        // 100% usage has tin=10bps (negative fee), tout=8bps (negative fee)
        pool.file("fees2", 9990, 10008);

        setPoolContract(address(pool));
    }

    function test_file_fees() public {
        vm.expectRevert(abi.encodePacked(contractName, "/file-unrecognized-param"));
        pool.file("an invalid value", 1, 2);

        vm.expectEmit(true, true, true, true);
        emit File("fees1", 1, 2);
        pool.file("fees1", 1, 2);

        assertEq(pool.tin1(), 1);
        assertEq(pool.tout1(), 2);

        vm.expectEmit(true, true, true, true);
        emit File("fees2", 3, 4);
        pool.file("fees2", 3, 4);

        assertEq(pool.tin2(), 3);
        assertEq(pool.tout2(), 4);

        vat.cage();
        vm.expectRevert(abi.encodePacked(contractName, "/no-file-during-shutdown"));
        pool.file("some value", 1, 2);

        pool.deny(address(this));
        vm.expectRevert(abi.encodePacked(contractName, "/not-authorized"));
        pool.file("some value", 1, 2);
    }

    function test_file_invalid_fees() public {
        vm.expectRevert(abi.encodePacked(contractName, "/invalid-fees"));
        pool.file("fees1", uint24(BPS + 1), uint24(BPS));
    }

    function test_previewSellGem_empty() public {
        // Should have no fee due to pool being empty
        assertEq(pool.previewSellGem(10 * 1e6), 20 ether);
    }

    function test_previewBuyGem_empty() public {
        // Should have no fee due to pool being empty
        assertEq(pool.previewBuyGem(20 ether), 10 * 1e6);
    }

    function test_previewSellGem() public {
        dai.transfer(address(pool), 100 ether);
        assertEq(pool.previewSellGem(10 * 1e6), 20 ether);
    }

    function test_previewBuyGem() public {
        dai.transfer(address(pool), 100 ether);
        assertEq(pool.previewSellGem(20 ether), 10 * 1e6);
    }

}
