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

    using stdStorage for StdStorage;

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

        // Fees set to tin=-5bps, tout=10bps
        pool.file("fees", 1.0005 ether, 0.9990 ether);

        setPoolContract(address(pool));
    }

    function _ensureRatio(uint256 ratioInBps, uint256 totalBalance, bool isSellingGem) internal override virtual {
        super._ensureRatio(ratioInBps, totalBalance, isSellingGem);
        plan.setTargetAssets(isSellingGem ? totalBalance : 0);
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

    function test_assetBalance() public override {
        dai.transfer(address(pool), 50 ether);
        assertEq(pool.assetBalance(), 50 ether);
        gem.transfer(address(pool), 25 * 1e6);
        assertEq(pool.assetBalance(), 100 ether);
        stdstore.target(address(pool)).sig("gemsOutstanding()").checked_write(bytes32(uint256(10 * 1e6)));
        assertEq(pool.assetBalance(), 120 ether);
    }

    function test_previewSellGem() public {
        _ensureRatio(5000, 100 ether, true);
        
        assertEq(pool.previewSellGem(10 * 1e6), 20.01 ether);
    }

    function test_previewSellGem_not_accepting_gems() public {
        _ensureRatio(5000, 100 ether, false);
        
        vm.expectRevert(abi.encodePacked(contractName, "/not-accepting-gems"));
        pool.previewSellGem(10 * 1e6);
    }

    function test_previewBuyGem() public {
        _ensureRatio(5000, 100 ether, false);
        
        assertEq(pool.previewBuyGem(20 ether), 9.99 * 1e6);
    }

    function test_previewBuyGem_not_accepting_gems() public {
        _ensureRatio(5000, 100 ether, true);
        
        vm.expectRevert(abi.encodePacked(contractName, "/not-accepting-dai"));
        pool.previewBuyGem(20 ether);
    }

    function _initPushPull() public {
        pool.addOperator(address(this));
        plan.setTargetAssets(50 ether);
        gem.transfer(address(pool), 25 * 1e6);
        gem.burn(address(this), gem.balanceOf(address(this)));     // Burn the rest for easy accounting
    }

    function test_pull() public {
        _initPushPull();

        assertEq(gem.balanceOf(address(pool)), 25 * 1e6);
        assertEq(gem.balanceOf(address(this)), 0);
        assertEq(pool.gemsOutstanding(), 0);
        assertEq(pool.assetBalance(), 50 ether);
        pool.pull(address(this), 25 * 1e6);
        assertEq(gem.balanceOf(address(pool)), 0 * 1e6);
        assertEq(gem.balanceOf(address(this)), 25 * 1e6);
        assertEq(pool.gemsOutstanding(), 25 * 1e6);
        assertEq(pool.assetBalance(), 50 ether);
    }

    function test_pull_partial() public {
        _initPushPull();

        assertEq(gem.balanceOf(address(pool)), 25 * 1e6);
        assertEq(gem.balanceOf(address(this)), 0);
        assertEq(pool.gemsOutstanding(), 0);
        pool.pull(address(this), 10 * 1e6);
        assertEq(gem.balanceOf(address(pool)), 15 * 1e6);
        assertEq(gem.balanceOf(address(this)), 10 * 1e6);
        assertEq(pool.gemsOutstanding(), 10 * 1e6);
    }

    function test_pull_amount_exceeds_pending() public {
        _initPushPull();

        plan.setTargetAssets(0);
        vm.expectRevert(abi.encodePacked(contractName, "/amount-exceeds-pending"));
        pool.pull(address(this), 10 * 1e6);
    }

    function test_push_principal() public {
        _initPushPull();
        
        pool.pull(address(this), 25 * 1e6);
        assertEq(gem.balanceOf(address(pool)), 0);
        assertEq(gem.balanceOf(address(this)), 25 * 1e6);
        assertEq(pool.gemsOutstanding(), 25 * 1e6);
        assertEq(pool.assetBalance(), 50 ether);
        gem.approve(address(pool), 25 * 1e6);
        pool.push(25 * 1e6);
        assertEq(gem.balanceOf(address(pool)), 25 * 1e6);
        assertEq(gem.balanceOf(address(this)), 0);
        assertEq(pool.gemsOutstanding(), 0);
        assertEq(pool.assetBalance(), 50 ether);
    }

    function test_push_principal_plus_interest() public {
        _initPushPull();
        
        pool.pull(address(this), 25 * 1e6);
        assertEq(gem.balanceOf(address(pool)), 0);
        assertEq(gem.balanceOf(address(this)), 25 * 1e6);
        assertEq(pool.gemsOutstanding(), 25 * 1e6);
        assertEq(pool.assetBalance(), 50 ether);
        gem.mint(address(this), 10 * 1e6);
        gem.approve(address(pool), 35 * 1e6);
        pool.push(35 * 1e6);
        assertEq(gem.balanceOf(address(pool)), 35 * 1e6);
        assertEq(gem.balanceOf(address(this)), 0);
        assertEq(pool.gemsOutstanding(), 0);
        assertEq(pool.assetBalance(), 70 ether);
    }

    function test_pendingDeposits_target_above_gems() public {
        _initPushPull();
        
        assertEq(pool.pendingDeposits(), 25 * 1e6);
    }

    function test_pendingDeposits_target_below_gems() public {
        _initPushPull();
        
        plan.setTargetAssets(40 ether);
        assertEq(pool.pendingDeposits(), 20 * 1e6);
    }

    function test_pendingDeposits_outstanding_target_above_gems() public {
        _initPushPull();
        
        pool.pull(address(this), 10 * 1e6);
        assertEq(pool.pendingDeposits(), 15 * 1e6);
    }

    function test_pendingDeposits_outstanding_target_below_gems() public {
        _initPushPull();
        
        plan.setTargetAssets(40 ether);
        pool.pull(address(this), 10 * 1e6);
        assertEq(pool.pendingDeposits(), 10 * 1e6);
    }

    function test_pendingDeposits_too_much_outstanding() public {
        _initPushPull();
        
        pool.pull(address(this), 15 * 1e6);
        assertEq(pool.pendingDeposits(), 10 * 1e6);
        plan.setTargetAssets(30 ether);
        assertEq(pool.pendingDeposits(), 0);
    }

    function test_pendingDeposits_target_zero() public {
        _initPushPull();
        
        plan.setTargetAssets(0);
        assertEq(pool.pendingDeposits(), 0);
    }

}
