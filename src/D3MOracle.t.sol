// SPDX-FileCopyrightText: © 2021-2022 Dai Foundation <www.daifoundation.org>
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

pragma solidity ^0.8.14;

import "ds-test/test.sol";

import {D3MOracle} from "./D3MOracle.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;

    function load(address, bytes32) external view returns (bytes32);
}

contract D3MTestVat {
    uint256 public live = 1;

    function cage() external {
        live = 0;
    }
}

contract D3MTestHub {
    uint256 c = 0;

    function culled(bytes32) external view returns (uint256) {
        return c;
    }

    function cull() external {
        c = 1;
    }

    function uncull() external {
        c = 0;
    }
}

contract D3MOracleTest is DSTest {
    Hevm hevm;

    D3MTestVat vat;
    D3MTestHub hub;
    D3MOracle oracle;

    uint256 internal constant WAD = 10 ** 18;

    function setUp() public {
        hevm = Hevm(
            address(bytes20(uint160(uint256(keccak256("hevm cheat code")))))
        );

        vat = new D3MTestVat();
        hub = new D3MTestHub();

        oracle = new D3MOracle(address(vat), bytes32("random"));
        oracle.file("hub", address(hub));
    }

    function test_rely_deny() public {
        assertEq(oracle.wards(address(123)), 0);
        oracle.rely(address(123));
        assertEq(oracle.wards(address(123)), 1);
        oracle.deny(address(123));
        assertEq(oracle.wards(address(123)), 0);
    }

    function testFail_unauth_rely() public {
        oracle.deny(address(this));
        oracle.rely(address(123));
    }

    function testFail_unauth_deny() public {
        oracle.rely(address(123));
        oracle.deny(address(this));
        oracle.deny(address(123));
    }

    function test_file_hub() public {
        assertEq(oracle.hub(), address(hub));
        oracle.file("hub", address(123));
        assertEq(oracle.hub(), address(123));
    }

    function testFail_unauth_file_hub() public {
        oracle.deny(address(this));
        oracle.file("hub", address(123));
    }

    function testFail_vat_caged_file_hub() public {
        vat.cage();
        oracle.file("hub", address(123));
    }

    function test_peek() public {
        (uint256 value, bool ok) = oracle.peek();
        assertEq(value, WAD);
        assertTrue(ok);
        hub.cull();
        (value, ok) = oracle.peek();
        assertEq(value, WAD);
        assertTrue(ok);
    }

    function test_read() public {
        assertEq(oracle.read(), WAD);
        hub.cull();
        hub.uncull();
        assertEq(oracle.read(), WAD);
    }

    function testFail_read() public {
        hub.cull();
        oracle.read();
    }
}
