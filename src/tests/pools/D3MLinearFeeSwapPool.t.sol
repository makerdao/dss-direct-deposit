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

    event File(bytes32 indexed what, uint64 tin, uint64 tout);

    function setUp() public {
        baseInit("D3MSwapPool");

        pool = new D3MLinearFeeSwapPool(ILK, address(hub), address(dai), address(gem));

        // 0% usage has tin=5bps (negative fee), tout=20bps (positive fee)
        pool.file("fees1", 1.0005 ether, 0.9980 ether);
        // 100% usage has tin=10bps (negative fee), tout=8bps (negative fee)
        pool.file("fees2", 0.9990 ether, 1.0008 ether);

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
        pool.file("fees1", uint64(WAD + 1), uint64(WAD));
    }

    function test_previewSellGem_tin1_edge() public {
        dai.transfer(address(pool), 100 ether);
        // 10% between 1.0005 and 0.9990 (average of 0% and 20% endpoints)
        assertEq(pool.previewSellGem(10 * 1e6), 20.007 ether);  
    }

    function test_previewSellGem_tin2_edge() public {
        dai.transfer(address(pool), 20 ether);
        gem.transfer(address(pool), 40 * 1e6);
        // 90% between 1.0005 and 0.9990 (average of 80% and 100% endpoints)
        assertEq(pool.previewSellGem(10 * 1e6), 19.983 ether);  
    }

    function test_previewSellGem_middle() public {
        dai.transfer(address(pool), 80 ether);
        gem.transfer(address(pool), 10 * 1e6);
        // 30% between 1.0005 and 0.9990 (average of 20% and 40% endpoints)
        assertEq(pool.previewSellGem(10 * 1e6), 20.001 ether);  
    }

    function test_previewSellGem_take_all_dai() public {
        dai.transfer(address(pool), 100 ether);
        // 50% between 1.0005 and 0.9990 (average of 0% and 100% endpoints)
        assertEq(pool.previewSellGem(50 * 1e6), 99.975 ether);
    }

    function test_previewSellGem_cant_take_all_dai_plus_one() public {
        dai.transfer(address(pool), 100 ether);
        // Even though the fee makes it so you could take more in theory
        // the linear function ends at 100% of the pre-fee amount
        vm.expectRevert(abi.encodePacked(contractName, "/insufficient-dai-in-pool"));
        pool.previewSellGem(50 * 1e6 + 1);
    }

    function test_previewSellGem_empty() public {
        vm.expectRevert(abi.encodePacked(contractName, "/insufficient-dai-in-pool"));
        pool.previewSellGem(10 * 1e6);
    }

    function test_previewSellGem_zero() public {
        dai.transfer(address(pool), 100 ether);
        assertEq(pool.previewSellGem(0), 0);
    }

    function test_previewBuyGem_tout2_edge() public {
        gem.transfer(address(pool), 50 * 1e6);
        // 10% between 1.0008 and 0.9980 (average of 0% and 20% endpoints)
        assertEq(pool.previewBuyGem(20 ether), 10.0052 * 1e6);
    }

    function test_previewBuyGem_tout1_edge() public {
        dai.transfer(address(pool), 80 ether);
        gem.transfer(address(pool), 10 * 1e6);
        // 90% between 1.0008 and 0.9980 (average of 80% and 100% endpoints)
        assertEq(pool.previewBuyGem(20 ether), 9.9828 * 1e6);  
    }

    function test_previewBuyGem_middle() public {
        dai.transfer(address(pool), 20 ether);
        gem.transfer(address(pool), 40 * 1e6);
        // 30% between 1.0008 and 0.9980 (average of 20% and 40% endpoints)
        assertEq(pool.previewBuyGem(20 ether), 9.9996 * 1e6);  
    }

    function test_previewBuyGem_take_all_gems() public {
        gem.transfer(address(pool), 50 * 1e6);
        // 50% between 1.0008 and 0.9980 (average of 0% and 100% endpoints)
        assertEq(pool.previewBuyGem(100 ether), 49.97 * 1e6);
    }

    function test_previewBuyGem_cant_take_all_gems_plus_one() public {
        gem.transfer(address(pool), 50 * 1e6);
        // Even though the fee makes it so you could take more in theory
        // the linear function ends at 100% of the pre-fee amount
        vm.expectRevert(abi.encodePacked(contractName, "/insufficient-gems-in-pool"));
        pool.previewBuyGem(100 ether + 1);
    }

    function test_previewBuyGem_empty() public {
        vm.expectRevert(abi.encodePacked(contractName, "/insufficient-gems-in-pool"));
        pool.previewBuyGem(20 ether);
    }

    function test_previewBuyGem_zero() public {
        gem.transfer(address(pool), 50 * 1e6);
        assertEq(pool.previewBuyGem(0), 0);
    }

}
