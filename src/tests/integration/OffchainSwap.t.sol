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

import "./SwapPoolBase.t.sol";

import { D3MOffchainSwapPool } from "../../pools/D3MOffchainSwapPool.sol";

abstract contract OffchainSwapBaseTest is SwapPoolBaseTest {

    D3MOffchainSwapPool pool;

    function deployPool() internal override returns (address) {
        pool = D3MOffchainSwapPool(D3MDeploy.deployOffchainSwapPool(
            address(this),
            admin,
            ilk,
            address(hub),
            address(dai),
            address(gem)
        ));
        return address(pool);
    }

    function test_full_offchain_investment_cycle() public {
        // We pay 10bps to fill or empty the gems
        uint128 fee = uint128(10010 * WAD / 10000);
        vm.prank(admin); pool.file("fees", fee, fee);
        vm.prank(admin); pool.addOperator(TEST_ADDRESS);

        plan.setAllocation(address(this), ilk, uint128(standardDebtSize));
        hub.exec(ilk);

        assertEq(dai.balanceOf(address(pool)), standardDebtSize);
        assertEq(gem.balanceOf(address(pool)), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(gem.balanceOf(address(this)), 0);
        assertEq(pool.assetBalance(), standardDebtSize);

        // We want an arbitrager to fill the pool
        uint256 gemAmt = daiToGem(standardDebtSize) * WAD / fee;
        deal(address(gem), address(this), gemAmt);
        pool.swapGemForDai(address(this), gemAmt, 0);

        assertLe(dai.balanceOf(address(pool)), WAD); // 1 DAI dust is fine
        assertRoundingEq(gem.balanceOf(address(pool)), gemAmt);
        assertRoundingEq(dai.balanceOf(address(this)), standardDebtSize);
        assertEq(gem.balanceOf(address(this)), 0);
        assertRoundingEq(pool.assetBalance(), standardDebtSize * WAD / fee); // Lost a bit of assets from the fees paid out

        // Top up the pool just to simplify the future calculations
        // This could be done via pulling from the vow
        gemAmt = daiToGem(standardDebtSize);
        deal(address(gem), address(pool), gemAmt);
        (, uint256 art) = vat.urns(ilk, address(pool));
        assertRoundingEq(art, pool.assetBalance());

        // Operator queries how much can be pulled out and deploys
        uint256 pendingDeposits = pool.pendingDeposits();
        assertRoundingEq(pendingDeposits, gemAmt);
        assertEq(pool.pendingWithdrawals(), 0);
        assertEq(pool.gemsOutstanding(), 0);
        vm.prank(TEST_ADDRESS); pool.pull(TEST_ADDRESS, pendingDeposits);
        assertEq(pool.pendingDeposits(), 0);
        assertEq(pool.pendingWithdrawals(), 0);
        assertEq(gem.balanceOf(address(pool)), 0);
        assertEq(gem.balanceOf(address(TEST_ADDRESS)), gemAmt);
        assertEq(pool.gemsOutstanding(), gemAmt);

        // --- Offchain deploy of funds occurs here ---

        // Some time passes and interest accumulates (5%)
        uint256 positionSize = pool.gemsOutstanding() * 105 / 100;
        uint256 earned = positionSize - pool.gemsOutstanding();
        deal(address(gem), TEST_ADDRESS, gemAmt + earned);
        uint256 vowDai = vat.dai(address(vow));
        vm.prank(admin); pool.file("gemsOutstanding", positionSize);
        (, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(art, pool.assetBalance() * 100 / 105);    // Debt should be about 5% less than assets
        hub.exec(ilk);
        (, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(art, pool.assetBalance());
        assertRoundingEq(vat.dai(address(vow)), vowDai + gemToDai(earned) * RAY);   // Surplus increases due to asset appreciation
        assertRoundingEq(pool.assetBalance(), standardDebtSize + gemToDai(earned));

        // Due to position size being at the target debt limit the operator is required to repay the interest
        assertEq(pool.pendingWithdrawals(), earned);
        vm.prank(TEST_ADDRESS); gem.approve(address(pool), type(uint256).max);
        vm.prank(TEST_ADDRESS); pool.push(earned);
        assertEq(pool.pendingWithdrawals(), 0);

        // Arbitrager swaps gem for dai
        assertEq(gem.balanceOf(address(pool)), earned);
        assertEq(gem.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(pool)), 0);
        uint256 daiAmt = gemToDai(earned) * WAD / fee;
        deal(address(dai), address(this), daiAmt);
        pool.swapDaiForGem(address(this), daiAmt, 0);
        assertLe(gem.balanceOf(address(pool)), daiToGem(1 ether));  // Some dust is fine
        assertRoundingEq(gem.balanceOf(address(this)), earned);
        assertEq(dai.balanceOf(address(pool)), daiAmt);

        // Exec should now clear out the excess debt to get us back to desired amount
        (, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(art, standardDebtSize * 105 / 100);
        hub.exec(ilk);
        (, art) = vat.urns(ilk, address(pool));
        assertRoundingEq(art, standardDebtSize);
    }

}

contract MonetalisSwapTest is OffchainSwapBaseTest {
    
    function getGem() internal override pure returns (address) {
        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function getPip() internal override pure returns (address) {
        return 0x77b68899b99b686F415d074278a9a16b336085A0;  // Hardcoded $1 pip
    }

    function getSwapGemForDaiPip() internal override pure returns (address) {
        return 0x77b68899b99b686F415d074278a9a16b336085A0;
    }

    function getSwapDaiForGemPip() internal override pure returns (address) {
        return 0x77b68899b99b686F415d074278a9a16b336085A0;
    }

}
