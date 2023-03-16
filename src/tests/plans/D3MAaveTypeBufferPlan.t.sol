// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
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

import { D3MPlanBaseTest, DaiLike } from "./D3MPlanBase.t.sol";
import { D3MAaveTypeBufferPlan } from "../../plans/D3MAaveTypeBufferPlan.sol";

contract ADaiMock {

    address public dai;

    constructor(address _dai) {
        dai = _dai;
    }

    function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
        return dai;
    }

}

contract DaiMock {

    uint256 liquidity;

    function setLiquidity(uint256 value) external {
        liquidity = value;
    }

    function balanceOf(address) external view returns (uint256) {
        return liquidity;
    }

}

contract D3MAaveTypeBufferPlanTest is D3MPlanBaseTest {

    ADaiMock adai;
    DaiMock  _dai;

    D3MAaveTypeBufferPlan plan;

    event Disable();

    function setUp() public override {
        contractName = "D3MAaveTypeBufferPlan";

        dai = DaiLike(address(_dai = new DaiMock()));
        adai = new ADaiMock(address(dai));

        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        d3mTestPlan = address(plan = new D3MAaveTypeBufferPlan(address(adai)));
    }

    function test_constructor() public {
        assertEq(address(plan.dai()), address(dai));
        assertEq(address(plan.adai()), address(adai));
    }

    function test_file() public {
        checkFileUint(d3mTestPlan, contractName, ["buffer"]);
    }

    function test_disable_unauthed() public {
        plan.file("buffer", 1);
        plan.deny(address(this));

        vm.expectRevert("D3MAaveTypeBufferPlan/not-authorized");
        plan.disable();
    }

    function test_implements_getTargetAssets() public override {
        assertEq(plan.getTargetAssets(0), 0);
    }

    function test_liquidity_less_than_buffer() public {
        _dai.setLiquidity(40 ether);
        plan.file("buffer", 100 ether);
        assertEq(plan.getTargetAssets(0), 60 ether);
    }

    function test_liquidity_equals_buffer() public {
        _dai.setLiquidity(100 ether);
        plan.file("buffer", 100 ether);
        assertEq(plan.getTargetAssets(0), 0);
    }

    function test_liquidity_greater_than_buffer_partial_unwind() public {
        _dai.setLiquidity(100 ether);
        plan.file("buffer", 40 ether);
        assertEq(plan.getTargetAssets(200 ether), 140 ether);
    }

    function test_liquidity_greater_than_buffer_full_unwind() public {
        _dai.setLiquidity(100 ether);
        plan.file("buffer", 40 ether);
        assertEq(plan.getTargetAssets(40 ether), 0);
    }

    function test_buffer_equals_zero() public {
        _dai.setLiquidity(100 ether);
        plan.file("buffer", 0);
        assertEq(plan.getTargetAssets(10000 ether), 0);
    }

    function test_increase_liquidity() public {
        plan.file("buffer", 100 ether);
        assertEq(plan.getTargetAssets(20 ether), 120 ether);
    }

    function test_decrease_liquidity_sole_provider() public {
        plan.file("buffer", 100 ether);
        assertEq(plan.getTargetAssets(0), 100 ether);
        _dai.setLiquidity(100 ether);   // Simulate adding liquidity
        _dai.setLiquidity(80 ether);    // Simulate someone borrowed 20 DAI
        assertEq(plan.getTargetAssets(100 ether), 120 ether);
        _dai.setLiquidity(100 ether);   // Topped back up to 100 DAI
        _dai.setLiquidity(120 ether);   // User returned the 20 DAI
        assertEq(plan.getTargetAssets(120 ether), 100 ether);
        _dai.setLiquidity(100 ether);   // Liquidity goes back to 100 DAI
    }

    function test_decrease_liquidity_multiple_providers() public {
        plan.file("buffer", 100 ether);
        assertEq(plan.getTargetAssets(0), 100 ether);
        _dai.setLiquidity(100 ether);   // Simulate adding liquidity
        _dai.setLiquidity(150 ether);   // Someone else adds 50 DAI
        assertEq(plan.getTargetAssets(100 ether), 50 ether);
        _dai.setLiquidity(100 ether);   // Simulate removing liquidity
        _dai.setLiquidity(300 ether);   // Someone else adds 200 DAI
        assertEq(plan.getTargetAssets(50 ether), 0);    // Plan will remove all liquidity
    }

    function test_active_buffer_set() public {
        assertEq(plan.buffer(), 0);
        assertTrue(!plan.active());
        plan.file("buffer", 1);
        assertEq(plan.buffer(), 1);
        assertTrue(plan.active());
    }

    function test_disable() public {
        plan.file("buffer", 1);

        assertEq(plan.buffer(), 1);
        assertTrue(plan.active());
        vm.expectEmit(true, true, true, true);
        emit Disable();
        plan.disable();
        assertTrue(!plan.active());
        assertEq(plan.buffer(), 0);
    }

    function test_disable_not_active() public {
        plan.file("buffer", 1);
        assertEq(plan.buffer(), 1);
        assertTrue(plan.active());
        plan.file("buffer", 0);
        assertTrue(!plan.active());

        plan.deny(address(this));

        vm.expectEmit(true, true, true, true);
        emit Disable();
        plan.disable();
        assertTrue(!plan.active());
        assertEq(plan.buffer(), 0);
    }
    
}
