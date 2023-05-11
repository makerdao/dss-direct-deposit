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

import { D3MGatedSwapPool } from "../../pools/D3MGatedSwapPool.sol";

contract PlanMock {

    uint256 public targetAssets;

    function setTargetAssets(uint256 _targetAssets) external {
        targetAssets = _targetAssets;
    }

    function getTargetAssets(bytes32, uint256) external view returns (uint256) {
        return targetAssets;
    }

}

contract D3MGatedSwapPoolTest is D3MSwapPoolTest {

    PlanMock internal plan;

    D3MGatedSwapPool private pool;

    event File(bytes32 indexed what, uint128 tin, uint128 tout);

    function setUp() public virtual {
        baseInit("D3MSwapPool");

        plan = new PlanMock();
        hub.setPlan(address(plan));

        pool = new D3MGatedSwapPool(ILK, address(hub), address(dai), address(gem));

        // Fees set to tin=-5bps, tout=10bps

        setPoolContract(address(pool));
    }

    function setPoolContract(address _pool) internal virtual override {
        super.setPoolContract(_pool);
        pool = D3MGatedSwapPool(_pool);

        pool.file("fees", 1.0005 ether, 0.9990 ether);
        plan = new PlanMock();
        hub.setPlan(address(plan));
    }

    function _ensureRatio(uint256 ratioInBps, uint256 totalBalance, bool isSellingGem) internal override virtual {
        super._ensureRatio(ratioInBps, totalBalance, isSellingGem);
        plan.setTargetAssets(isSellingGem ? totalBalance : 0);
    }

    function test_authModifier() public {
        pool.deny(address(this));

        checkModifier(address(pool), string(abi.encodePacked(contractName, "/not-authorized")), [
            bytes4(keccak256("file(bytes32,uint128,uint128)"))
        ]);
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

    function test_previewSwapGemForDai() public {
        _ensureRatio(5000, 100 ether, true);
        
        assertEq(pool.previewSwapGemForDai(10 * 1e6), 20.01 ether);
    }

    function test_previewSwapGemForDai_not_accepting_gems() public {
        _ensureRatio(5000, 100 ether, false);
        
        vm.expectRevert(abi.encodePacked(contractName, "/not-accepting-gems"));
        pool.previewSwapGemForDai(10 * 1e6);
    }

    function test_previewSwapDaiForGem() public {
        _ensureRatio(5000, 100 ether, false);
        
        assertEq(pool.previewSwapDaiForGem(20 ether), 9.99 * 1e6);
    }

    function test_previewSwapDaiForGem_not_accepting_gems() public {
        _ensureRatio(5000, 100 ether, true);
        
        vm.expectRevert(abi.encodePacked(contractName, "/not-accepting-dai"));
        pool.previewSwapDaiForGem(20 ether);
    }

}
