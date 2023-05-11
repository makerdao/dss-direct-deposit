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

import { D3MGatedSwapPool } from "../../pools/D3MGatedSwapPool.sol";

abstract contract GatedSwapBaseTest is SwapPoolBaseTest {

    D3MGatedSwapPool pool;

    function deployPool() internal override returns (address) {
        pool = D3MGatedSwapPool(D3MDeploy.deployGatedSwapPool(
            address(this),
            admin,
            ilk,
            address(hub),
            address(dai),
            address(gem)
        ));
        return address(pool);
    }

    function test_full_investment_cycle() public {
        // We pay 10bps to fill or empty the gems
        uint128 fee = uint128(10010 * WAD / 10000);
        vm.prank(admin); pool.file("fees", fee, fee);

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

        // TODO interest accumulation
        uint256 earned = 0;

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

// Arrakis DAI/USDC 1bps Tight Pool
contract ArrakisSwapTest is GatedSwapBaseTest {

    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();

        // Give access to the pool to read the oracle
        stdstore.target(0xcCBa43231aC6eceBd1278B90c3a44711a00F4e93).sig("bud(address)").with_key(address(pool)).checked_write(bytes32(uint256(1)));
        stdstore.target(0xcCBa43231aC6eceBd1278B90c3a44711a00F4e93).sig("bud(address)").with_key(address(this)).checked_write(bytes32(uint256(1)));
    }
    
    function getGem() internal override pure returns (address) {
        return 0x50379f632ca68D36E50cfBC8F78fe16bd1499d1e;
    }

    function getPip() internal override pure returns (address) {
        return 0xcCBa43231aC6eceBd1278B90c3a44711a00F4e93;
    }

    function getSwapGemForDaiPip() internal override pure returns (address) {
        return 0xcCBa43231aC6eceBd1278B90c3a44711a00F4e93;
    }

    function getSwapDaiForGemPip() internal override pure returns (address) {
        return 0xcCBa43231aC6eceBd1278B90c3a44711a00F4e93;
    }

}
