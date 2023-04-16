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

import "./D3MPoolBase.t.sol";

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

abstract contract D3MSwapPoolTest is D3MPoolBaseTest {

    bytes32 constant ILK = "TEST-ILK";

    D3MSwapPool private pool;
    TokenMock internal gem;
    PipMock internal pip;

    event SellGem(address indexed owner, uint256 gems, uint256 dai);
    event BuyGem(address indexed owner, uint256 gems, uint256 dai);

    function baseInit(string memory _contractName) internal virtual override {
        super.baseInit(_contractName);
        gem = new TokenMock(6);

        pip = new PipMock();
        pip.poke(2e18); // Gem is worth $2 / unit

        gem.mint(address(this), 1_000_000 * 1e6);
        dai.mint(address(this), 1_000_000 * 1e18);
    }

    function setPoolContract(address _pool) internal virtual override {
        super.setPoolContract(_pool);
        pool = D3MSwapPool(_pool);
        gem.approve(_pool, type(uint256).max);
        dai.approve(_pool, type(uint256).max);

        pool.file("pip", address(pip));
        pool.file("sellGemPip", address(pip));
        pool.file("buyGemPip", address(pip));
    }

    function test_constructor() public {
        assertEq(address(pool.hub()), address(hub));
        assertEq(pool.ilk(), ILK);
        assertEq(address(pool.vat()), address(vat));
        assertEq(address(pool.dai()), address(dai));
        assertEq(address(pool.gem()), address(gem));
    }

    function test_file_addresses() public {
        checkFileAddress(address(pool), contractName, ["hub", "pip", "sellGemPip", "buyGemPip"]);
    }

    function test_withdraw() public {
        uint256 startingBal = dai.balanceOf(address(this));
        dai.transfer(address(pool), 100 ether);
        assertEq(dai.balanceOf(address(pool)), 100 ether);
        assertEq(dai.balanceOf(address(this)), startingBal - 100 ether);
        assertEq(dai.balanceOf(address(hub)), 0);
        vm.prank(address(hub)); pool.withdraw(50 ether);
        assertEq(dai.balanceOf(address(pool)), 50 ether);
        assertEq(dai.balanceOf(address(this)), startingBal - 100 ether);
        assertEq(dai.balanceOf(address(hub)), 50 ether);
    }

    function test_redeemable_returns_gem() public {
        assertEq(pool.redeemable(), address(gem));
    }

    function test_exit_gem() public {
        uint256 tokens = gem.balanceOf(address(this));
        gem.transfer(address(pool), tokens);
        assertEq(gem.balanceOf(address(this)), 0);
        assertEq(gem.balanceOf(address(pool)), tokens);

        end.setArt(tokens);
        vm.prank(address(hub)); pool.exit(address(this), tokens);

        assertEq(gem.balanceOf(address(this)), tokens);
        assertEq(gem.balanceOf(address(pool)), 0);
    }

    function test_quit_moves_balance() public {
        uint256 tokens = gem.balanceOf(address(this));
        gem.transfer(address(pool), tokens);
        assertEq(gem.balanceOf(address(this)), 0);
        assertEq(gem.balanceOf(address(pool)), tokens);
        // TODO check that it moves dai balance as well

        pool.quit(address(this));

        assertEq(gem.balanceOf(address(this)), tokens);
        assertEq(gem.balanceOf(address(pool)), 0);
    }

    function test_assetBalance() public {
        assertEq(pool.assetBalance(), 0);

        gem.transfer(address(pool), 10 * 1e6);
        dai.transfer(address(pool), 30 ether);

        assertEq(pool.assetBalance(), 50 ether);    // 10 tokens @ $2 / unit + 30 dai
    }

    function test_maxDeposit() public {
        assertEq(pool.maxDeposit(), type(uint256).max);
    }

    function test_maxWithdraw() public {
        dai.transfer(address(pool), 100 ether);

        assertEq(pool.maxWithdraw(), 100 ether);
    }

    function _ensureCanSellGems(uint256 daiAmt) internal virtual {
        dai.transfer(address(pool), daiAmt);
    }

    function _ensureCanBuyGems(uint256 gemAmt) internal virtual {
        gem.transfer(address(pool), gemAmt);
    }

    function test_sellGem() public {
        _ensureCanSellGems(100 ether);

        uint256 gemBal = gem.balanceOf(address(this));
        assertEq(dai.balanceOf(TEST_ADDRESS), 0);

        uint256 amountOut =  pool.previewSellGem(10 * 1e6);
        vm.expectEmit(true, true, true, true);
        emit SellGem(TEST_ADDRESS, 10 * 1e6, amountOut);
        pool.sellGem(TEST_ADDRESS, 10 * 1e6, amountOut);

        assertEq(gem.balanceOf(address(this)), gemBal - 10 * 1e6);
        assertEq(dai.balanceOf(TEST_ADDRESS), amountOut);
    }

    function test_sellGem_minDaiAmt_too_high() public {
        _ensureCanSellGems(100 ether);

        uint256 amountOut = pool.previewSellGem(10 * 1e6);
        vm.expectRevert("D3MSwapPool/too-little-dai");
        pool.sellGem(TEST_ADDRESS, 10 * 1e6, amountOut + 1);
    }

    function test_buyGem() public {
        _ensureCanBuyGems(100 * 1e6);

        uint256 daiBal = dai.balanceOf(address(this));
        assertEq(gem.balanceOf(TEST_ADDRESS), 0);

        uint256 amountOut =  pool.previewBuyGem(10 ether);
        vm.expectEmit(true, true, true, true);
        emit BuyGem(TEST_ADDRESS, amountOut, 10 ether);
        pool.buyGem(TEST_ADDRESS, 10 ether, amountOut);

        assertEq(gem.balanceOf(TEST_ADDRESS), amountOut);
        assertEq(dai.balanceOf(address(this)), daiBal - 10 ether);
    }

    function test_buyGem_minGemAmt_too_high() public {
        _ensureCanBuyGems(100 * 1e6);

        uint256 amountOut = pool.previewBuyGem(10 ether);
        vm.expectRevert("D3MSwapPool/too-little-gems");
        pool.buyGem(TEST_ADDRESS, 10 ether, amountOut + 1);
    }
}
