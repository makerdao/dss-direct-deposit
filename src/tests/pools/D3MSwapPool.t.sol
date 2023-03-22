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

import { D3MPoolBaseTest, FakeHub, FakeVat, FakeEnd, DaiLike } from "./D3MPoolBase.t.sol";
import { D3MTestGem } from "../stubs/D3MTestGem.sol";

import { D3MSwapPool } from "../../pools/D3MSwapPool.sol";

contract PipMock {
    uint256 public val;
    function read() external view returns (bytes32) {
        return bytes32(val);
    }
    function void() external {
        val = 0;
    }
    function poke(uint256 wut) external {
        val = wut;
    }
}

contract D3MSwapPoolTest is D3MPoolBaseTest {

    bytes32 constant ILK = "TEST-ILK";

    D3MSwapPool swapPool;
    D3MTestGem gem;
    FakeEnd end;
    PipMock pip;

    event SellGem(address indexed owner, uint256 gems, uint256 dai);
    event BuyGem(address indexed owner, uint256 gems, uint256 dai);

    function setUp() public override {
        contractName = "D3MSwapPool";

        dai = DaiLike(address(new D3MTestGem(18)));
        gem = new D3MTestGem(6);

        vat = address(new FakeVat());

        hub = address(new FakeHub(vat));
        end = FakeHub(hub).end();
        pip = new PipMock();
        pip.poke(2e18); // Gem is worth $2 / unit

        d3mTestPool = address(swapPool = new D3MSwapPool(ILK, hub, address(dai), address(gem)));
        swapPool.file("pip", address(pip));

        swapPool.file("buffer", 10 ether);          // 10 DAI buffer to switch between tin/tout1 and tin/tout2
        swapPool.file("tin1",  10005 * WAD / BPS);  // 5 bps negative wind fee (pay people to wind)
        swapPool.file("tout1",  9980 * WAD / BPS);  // 20 bps unwind fee
        swapPool.file("tin2",   9990 * WAD / BPS);  // 10 bps fee after the buffer is reached
        swapPool.file("tout2", 10015 * WAD / BPS);  // 15 bps negative fee (pay people to unwind)

        gem.approve(d3mTestPool, type(uint256).max);
        dai.approve(d3mTestPool, type(uint256).max);
    }

    function test_constructor() public {
        assertEq(address(swapPool.hub()), hub);
        assertEq(swapPool.ilk(), ILK);
        assertEq(address(swapPool.vat()), vat);
        assertEq(address(swapPool.dai()), address(dai));
        assertEq(address(swapPool.gem()), address(gem));
    }

    function test_file() public {
        checkFileUint(d3mTestPool, contractName, ["buffer", "tin1", "tin2", "tout1", "tout2"]);
        checkFileAddress(d3mTestPool, contractName, ["hub", "pip"]);
    }

    function test_withdraw() public {
        uint256 startingBal = dai.balanceOf(address(this));
        dai.transfer(d3mTestPool, 100 ether);
        assertEq(dai.balanceOf(d3mTestPool), 100 ether);
        assertEq(dai.balanceOf(address(this)), startingBal - 100 ether);
        assertEq(dai.balanceOf(hub), 0);
        vm.prank(hub); swapPool.withdraw(50 ether);
        assertEq(dai.balanceOf(d3mTestPool), 50 ether);
        assertEq(dai.balanceOf(address(this)), startingBal - 100 ether);
        assertEq(dai.balanceOf(hub), 50 ether);
    }

    function test_redeemable_returns_gem() public {
        assertEq(swapPool.redeemable(), address(gem));
    }

    function test_exit_gem() public {
        uint256 tokens = gem.balanceOf(address(this));
        gem.transfer(d3mTestPool, tokens);
        assertEq(gem.balanceOf(address(this)), 0);
        assertEq(gem.balanceOf(d3mTestPool), tokens);

        end.setArt(tokens);
        vm.prank(hub); swapPool.exit(address(this), tokens);

        assertEq(gem.balanceOf(address(this)), tokens);
        assertEq(gem.balanceOf(d3mTestPool), 0);
    }

    function test_quit_moves_balance() public {
        uint256 tokens = gem.balanceOf(address(this));
        gem.transfer(d3mTestPool, tokens);
        assertEq(gem.balanceOf(address(this)), 0);
        assertEq(gem.balanceOf(d3mTestPool), tokens);

        swapPool.quit(address(this));

        assertEq(gem.balanceOf(address(this)), tokens);
        assertEq(gem.balanceOf(d3mTestPool), 0);
    }

    function test_assetBalance() public {
        assertEq(swapPool.assetBalance(), 0);

        gem.transfer(d3mTestPool, 10 * 1e6);
        dai.transfer(d3mTestPool, 30 ether);

        assertEq(swapPool.assetBalance(), 50 ether);    // 10 tokens @ $2 / unit + 30 dai
    }

    function test_maxDeposit() public {
        assertEq(swapPool.maxDeposit(), type(uint256).max);
    }

    function test_maxWithdraw() public {
        dai.transfer(d3mTestPool, 100 ether);

        assertEq(swapPool.maxWithdraw(), 100 ether);
    }

    function test_previewSellGem_under_buffer() public {
        dai.transfer(d3mTestPool, 100 ether);

        // 10 tokens @ $2 / unit + 5bps payment = 20.01
        assertEq(swapPool.previewSellGem(10 * 1e6), 20.010 ether);
    }

    function test_previewSellGem_over_buffer() public {
        swapPool.file("buffer", 100 ether);
        dai.transfer(d3mTestPool, 100 ether);

        // 10 tokens @ $2 / unit + 10bps fee = 19.98
        assertEq(swapPool.previewSellGem(10 * 1e6), 19.980 ether);
    }

    function test_previewSellGem_mixed_fees() public {
        dai.transfer(d3mTestPool, 100 ether);

        // ~45 tokens will earn the 5bps fee, remainding ~55 pays the 10bps fee
        assertEq(swapPool.previewSellGem(100 * 1e6), 199934932533733133433);
    }

    function test_previewSellGem_mixed_fees_exact_cancel() public {
        dai.transfer(d3mTestPool, 100 ether);
        swapPool.file("tin2", WAD*WAD / swapPool.tin1());

        // ~45 tokens will earn the 5bps fee, remainding ~45 pays the 5bps fee
        // Allow for a 1bps error due to rounding
        assertApproxEqRel(swapPool.previewSellGem(90 * 1e6), 180 ether, WAD / 10000);
    }

    function test_previewSellGem_buffer_zero_dai_zero() public {
        swapPool.file("buffer", 0);

        // 10 tokens @ $2 / unit + 10bps fee = 19.98
        assertEq(swapPool.previewSellGem(10 * 1e6), 19.980 ether);
    }

    function test_previewSellGem_buffer_zero() public {
        swapPool.file("buffer", 0);
        dai.transfer(d3mTestPool, 10 ether);

        assertEq(swapPool.previewSellGem(10 * 1e6), 19994992503748125936);
    }

    function test_previewSellGem_dai_zero() public {
        assertEq(swapPool.previewSellGem(10 * 1e6), 19.980 ether);
    }

    function test_previewBuyGem_over_buffer() public {
        dai.transfer(d3mTestPool, 5 ether);

        // 4 DAI + 15bps payment = 2.003 tokens
        assertEq(swapPool.previewBuyGem(4 ether), 2.003 * 1e6);
    }

    function test_previewBuyGem_under_buffer() public {
        dai.transfer(d3mTestPool, 100 ether);

        // 20 DAI + 20bps fee = 9.96 tokens
        assertEq(swapPool.previewBuyGem(20 ether), 9.98 * 1e6);
    }

    function test_previewBuyGem_mixed_fees() public {
        dai.transfer(d3mTestPool, 5 ether);

        // 5 of the DAI gets paid the 15bps fee, the other 5 pays the 20bps fee
        // Result is slightly less than 5 tokens
        assertEq(swapPool.previewBuyGem(10 ether), 4998750);
    }

    function test_previewBuyGem_mixed_fees_exact_cancel() public {
        dai.transfer(d3mTestPool, 5 ether);
        swapPool.file("tout2", WAD*WAD / swapPool.tout1());

        // 10 DAI unwind should almost exactly cancel out
        // Allow for a 1bps error due to rounding
        assertApproxEqRel(swapPool.previewBuyGem(10 ether), 5 * 1e6, WAD / 10000);
    }

    function test_previewBuyGem_buffer_zero_dai_zero() public {
        swapPool.file("buffer", 0);

        assertEq(swapPool.previewBuyGem(20 ether), 9.98 * 1e6);
    }

    function test_previewBuyGem_buffer_zero() public {
        swapPool.file("buffer", 0);
        dai.transfer(d3mTestPool, 10 ether);

        assertEq(swapPool.previewBuyGem(20 ether), 9.98 * 1e6);
    }

    function test_previewBuyGem_dai_zero() public {
        assertEq(swapPool.previewBuyGem(4 ether), 2.003 * 1e6);
    }

    function test_sellGem() public {
        dai.transfer(d3mTestPool, 100 ether);

        uint256 gemBal = gem.balanceOf(address(this));
        assertEq(dai.balanceOf(TEST_ADDRESS), 0);

        vm.expectEmit(true, true, true, true);
        emit SellGem(TEST_ADDRESS, 10 * 1e6, 20.01 ether);
        swapPool.sellGem(TEST_ADDRESS, 10 * 1e6, swapPool.previewSellGem(10 * 1e6));

        assertEq(gem.balanceOf(address(this)), gemBal - 10 * 1e6);
        assertEq(dai.balanceOf(TEST_ADDRESS), 20.01 ether);
    }

    function test_sellGem_minDaiAmt_too_high() public {
        dai.transfer(d3mTestPool, 100 ether);

        uint256 amt = swapPool.previewSellGem(10 * 1e6);
        vm.expectRevert("D3MSwapPool/too-little-dai");
        swapPool.sellGem(TEST_ADDRESS, 10 * 1e6, amt + 1);
    }

    function test_buyGem() public {
        gem.transfer(d3mTestPool, 100 * 1e6);

        uint256 daiBal = dai.balanceOf(address(this));
        assertEq(gem.balanceOf(TEST_ADDRESS), 0);

        vm.expectEmit(true, true, true, true);
        emit BuyGem(TEST_ADDRESS, 5.0075 * 1e6, 10 ether);
        swapPool.buyGem(TEST_ADDRESS, 10 ether, swapPool.previewBuyGem(10 ether));

        assertEq(gem.balanceOf(TEST_ADDRESS), 5.0075 * 1e6);
        assertEq(dai.balanceOf(address(this)), daiBal - 10 ether);
    }

    function test_buyGem_minGemAmt_too_high() public {
        gem.transfer(d3mTestPool, 100 * 1e6);

        uint256 amt = swapPool.previewBuyGem(10 ether);
        vm.expectRevert("D3MSwapPool/too-little-gems");
        swapPool.buyGem(TEST_ADDRESS, 10 ether, amt + 1);
    }
}