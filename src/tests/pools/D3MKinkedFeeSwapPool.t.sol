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

import { D3MKinkedFeeSwapPool } from "../../pools/D3MKinkedFeeSwapPool.sol";

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

contract D3MKinkedFeeSwapPoolTest is D3MPoolBaseTest {

    bytes32 constant ILK = "TEST-ILK";

    D3MKinkedFeeSwapPool swapPool;
    D3MTestGem gem;
    FakeEnd end;
    PipMock pip;

    event File(bytes32 indexed what, uint24 tin, uint24 tout);
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

        d3mTestPool = address(swapPool = new D3MKinkedFeeSwapPool(ILK, hub, address(dai), address(gem)));
        swapPool.file("pip", address(pip));
        swapPool.file("sellGemPip", address(pip));
        swapPool.file("buyGemPip", address(pip));

        // Set the fee switch to 90% (targeting 90% of the swap pool in gems)
        swapPool.file("ratio", 9000);
        // 5 bps negative wind fee (pay people to wind), 20 bps unwind fee
        swapPool.file("fees1", 10005, 9980);
        // 10 bps fee after the ratio is reached, 8 bps negative fee (pay people to unwind)
        swapPool.file("fees2", 9990, 10008);
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

    function test_file_addresses() public {
        checkFileAddress(d3mTestPool, contractName, ["hub", "pip", "sellGemPip", "buyGemPip"]);
    }

    function test_file_ratio() public {
        vm.expectRevert(abi.encodePacked(contractName, "/file-unrecognized-param"));
        swapPool.file("an invalid value", 1);

        swapPool.file("ratio", 1);
        
        assertEq(swapPool.ratio(), 1);

        FakeVat(vat).cage();
        vm.expectRevert(abi.encodePacked(contractName, "/no-file-during-shutdown"));
        swapPool.file("some value", 1);

        swapPool.deny(address(this));
        vm.expectRevert(abi.encodePacked(contractName, "/not-authorized"));
        swapPool.file("some value", 1);
    }

    function test_file_invalid_ratio() public {
        vm.expectRevert(abi.encodePacked(contractName, "/invalid-ratio"));
        swapPool.file("ratio", uint24(BPS + 1));
    }

    function test_file_fees() public {
        vm.expectRevert(abi.encodePacked(contractName, "/file-unrecognized-param"));
        swapPool.file("an invalid value", 1, 2);

        vm.expectEmit(true, true, true, true);
        emit File("fees1", 1, 2);
        swapPool.file("fees1", 1, 2);
        
        assertEq(swapPool.tin1(), 1);
        assertEq(swapPool.tout1(), 2);

        vm.expectEmit(true, true, true, true);
        emit File("fees2", 3, 4);
        swapPool.file("fees2", 3, 4);
        
        assertEq(swapPool.tin2(), 3);
        assertEq(swapPool.tout2(), 4);

        FakeVat(vat).cage();
        vm.expectRevert(abi.encodePacked(contractName, "/no-file-during-shutdown"));
        swapPool.file("some value", 1, 2);

        swapPool.deny(address(this));
        vm.expectRevert(abi.encodePacked(contractName, "/not-authorized"));
        swapPool.file("some value", 1, 2);
    }

    function test_file_invalid_fees() public {
        vm.expectRevert(abi.encodePacked(contractName, "/invalid-fees"));
        swapPool.file("fees1", uint24(BPS + 1), uint24(BPS));
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

    function test_previewSellGem_under_ratio() public {
        dai.transfer(d3mTestPool, 100 ether);

        // 10 tokens @ $2 / unit + 5bps payment = 20.01
        assertEq(swapPool.previewSellGem(10 * 1e6), 20.010 ether);
    }

    function test_previewSellGem_over_ratio() public {
        swapPool.file("ratio", 0);
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
        swapPool.file("fees2", uint24(BPS*BPS / swapPool.tin1()), uint24(swapPool.tin1()));

        // ~45 tokens will earn the 5bps fee, remainding ~45 pays the 5bps fee
        // Allow for a 1bps error due to rounding
        assertApproxEqRel(swapPool.previewSellGem(90 * 1e6), 180 ether, WAD / 10000);
    }

    function test_previewBuyGem_over_ratio() public {
        gem.transfer(d3mTestPool, 100 * 1e6);
        dai.transfer(d3mTestPool, 5 ether);

        // 4 DAI + 8bps payment = 2.003 tokens
        assertEq(swapPool.previewBuyGem(4 ether), 2.0016 * 1e6);
    }

    function test_previewBuyGem_under_ratio() public {
        dai.transfer(d3mTestPool, 100 ether);

        // 20 DAI + 20bps fee = 9.96 tokens
        assertEq(swapPool.previewBuyGem(20 ether), 9.98 * 1e6);
    }

    function test_previewBuyGem_mixed_fees() public {
        dai.transfer(d3mTestPool, 5 ether);

        // 5 of the DAI gets paid the 8bps fee, the other 5 pays the 20bps fee
        // Result is slightly less than 5 tokens
        assertEq(swapPool.previewBuyGem(10 ether), 4990000);
    }

    function test_previewBuyGem_mixed_fees_exact_cancel() public {
        dai.transfer(d3mTestPool, 5 ether);
        swapPool.file("fees2", uint24(swapPool.tout1()), uint24(BPS*BPS / swapPool.tout1()));

        // 10 DAI unwind should almost exactly cancel out
        // Allow for a 1% error due to rounding
        assertApproxEqRel(swapPool.previewBuyGem(10 ether), 5 * 1e6, WAD / 100);
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
        emit BuyGem(TEST_ADDRESS, 5.004 * 1e6, 10 ether);
        swapPool.buyGem(TEST_ADDRESS, 10 ether, swapPool.previewBuyGem(10 ether));

        assertEq(gem.balanceOf(TEST_ADDRESS), 5.004 * 1e6);
        assertEq(dai.balanceOf(address(this)), daiBal - 10 ether);
    }

    function test_buyGem_minGemAmt_too_high() public {
        gem.transfer(d3mTestPool, 100 * 1e6);

        uint256 amt = swapPool.previewBuyGem(10 ether);
        vm.expectRevert("D3MSwapPool/too-little-gems");
        swapPool.buyGem(TEST_ADDRESS, 10 ether, amt + 1);
    }
}
