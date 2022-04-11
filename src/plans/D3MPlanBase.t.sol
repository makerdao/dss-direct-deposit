// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021-2022 Dai Foundation
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

pragma solidity 0.6.12;

import "ds-test/test.sol";
import "../tests/interfaces/interfaces.sol";

import "./D3MPlanBase.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;

    function load(address, bytes32) external view returns (bytes32);
}

contract FakeD3MPlanBase is D3MPlanBase {
    constructor(address dai_) public D3MPlanBase(dai_) {}

    function getTargetAssets(uint256 currentAssets) external override view returns(uint256) {
        return currentAssets;
    }
}

contract D3MPlanBaseTest is DSTest {

    Hevm hevm;

    DaiLike dai;

    FakeD3MPlanBase d3mPlanBase;

    function setUp() public {
        hevm = Hevm(
            address(bytes20(uint160(uint256(keccak256("hevm cheat code")))))
        );

        dai = DaiLike(123);

        d3mPlanBase = new FakeD3MPlanBase(address(dai));
    }

    function test_sets_dai_value() public {
        assertEq(address(d3mPlanBase.dai()), address(dai));
    }

    function test_sets_creator_as_ward() public {
        assertEq(d3mPlanBase.wards(address(this)), 1);
    }

    function test_can_rely() public {
        assertEq(d3mPlanBase.wards(address(123)), 0);

        d3mPlanBase.rely(address(123));

        assertEq(d3mPlanBase.wards(address(123)), 1);
    }

    function test_can_deny() public {
        assertEq(d3mPlanBase.wards(address(this)), 1);

        d3mPlanBase.deny(address(this));

        assertEq(d3mPlanBase.wards(address(this)), 0);
    }

    function testFail_cannot_rely_without_auth() public {
        assertEq(d3mPlanBase.wards(address(this)), 1);

        d3mPlanBase.deny(address(this));
        d3mPlanBase.rely(address(this));
    }

    function test_implements_getTargetAssets() public {
        uint256 result = d3mPlanBase.getTargetAssets(2);

        assertEq(result, 2);
    }
}
