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

        // 0% usage has 5bps negative fee, 20bps positive fee
        pool.file("fees1", 10005, 9980);
        // 100% usage has 10bps negative fee, 8bps negative fee
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

    /*function test_previewSellGem_under_ratio() public {
        dai.transfer(address(pool), 100 ether);

        // 10 tokens @ $2 / unit + 5bps payment = 20.01
        assertEq(pool.previewSellGem(10 * 1e6), 20.010 ether);
    }

    function test_previewSellGem_over_ratio() public {
        pool.file("ratio", 0);
        dai.transfer(address(pool), 100 ether);

        // 10 tokens @ $2 / unit + 10bps fee = 19.98
        assertEq(pool.previewSellGem(10 * 1e6), 19.980 ether);
    }

    function test_previewSellGem_mixed_fees() public {
        dai.transfer(address(pool), 100 ether);

        // ~45 tokens will earn the 5bps fee, remainding ~55 pays the 10bps fee
        assertEq(pool.previewSellGem(100 * 1e6), 199934932533733133433);
    }

    function test_previewSellGem_mixed_fees_exact_cancel() public {
        dai.transfer(address(pool), 100 ether);
        pool.file("fees2", uint24(BPS*BPS / pool.tin1()), uint24(pool.tin1()));

        // ~45 tokens will earn the 5bps fee, remainding ~45 pays the 5bps fee
        // Allow for a 1bps error due to rounding
        assertApproxEqRel(pool.previewSellGem(90 * 1e6), 180 ether, WAD / 10000);
    }

    function test_previewBuyGem_over_ratio() public {
        gem.transfer(address(pool), 100 * 1e6);
        dai.transfer(address(pool), 5 ether);

        // 4 DAI + 8bps payment = 2.003 tokens
        assertEq(pool.previewBuyGem(4 ether), 2.0016 * 1e6);
    }

    function test_previewBuyGem_under_ratio() public {
        dai.transfer(address(pool), 100 ether);

        // 20 DAI + 20bps fee = 9.96 tokens
        assertEq(pool.previewBuyGem(20 ether), 9.98 * 1e6);
    }

    function test_previewBuyGem_mixed_fees() public {
        dai.transfer(address(pool), 5 ether);

        // 5 of the DAI gets paid the 8bps fee, the other 5 pays the 20bps fee
        // Result is slightly less than 5 tokens
        assertEq(pool.previewBuyGem(10 ether), 4990000);
    }

    function test_previewBuyGem_mixed_fees_exact_cancel() public {
        dai.transfer(address(pool), 5 ether);
        pool.file("fees2", uint24(pool.tout1()), uint24(BPS*BPS / pool.tout1()));

        // 10 DAI unwind should almost exactly cancel out
        // Allow for a 1% error due to rounding
        assertApproxEqRel(pool.previewBuyGem(10 ether), 5 * 1e6, WAD / 100);
    }*/

}
