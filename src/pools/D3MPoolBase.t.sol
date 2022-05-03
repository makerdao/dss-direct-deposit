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
import {DaiLike} from "../tests/interfaces/interfaces.sol";

import "./D3MPoolBase.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;

    function load(address, bytes32) external view returns (bytes32);
}

contract FakeD3MPoolBase is D3MPoolBase {
    constructor(address hub_, address dai_) public D3MPoolBase(hub_, dai_) {}

    function validTarget() external view override returns (bool) {}

    function deposit(uint256 amt) external override {}

    function withdraw(uint256 amt) external override {}

    function transfer(address dst, uint256 amt)
        external
        override
        returns (bool)
    {}

    function accrueIfNeeded() external override {}

    function assetBalance() external view override returns (uint256) {}

    function transferAll(address dst) external override returns (bool) {}

    function maxWithdraw() external view override returns (uint256) {}
}

contract FakeVat {
    function hope(address who) external pure returns(bool) {
        who;
        return true;
    }
}

contract FakeHub {
    address public immutable vat;

    constructor() public {
        vat = address(new FakeVat());
    }
}

contract D3MPoolBaseTest is DSTest {
    uint256 constant WAD = 10**18;

    Hevm hevm;

    DaiLike dai;

    address d3mTestPool;

    function setUp() public virtual {
        hevm = Hevm(
            address(bytes20(uint160(uint256(keccak256("hevm cheat code")))))
        );

        dai = DaiLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);

        d3mTestPool = address(new FakeD3MPoolBase(address(new FakeHub()), address(dai)));
    }

    function _giveTokens(DaiLike token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (token.balanceOf(address(this)) == amount) return;

        for (int256 i = 0; i < 100; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                address(token),
                keccak256(abi.encode(address(this), uint256(i)))
            );
            hevm.store(
                address(token),
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (token.balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function test_sets_dai_value() public {
        assertEq(address(FakeD3MPoolBase(d3mTestPool).asset()), address(dai));
    }

    function test_sets_creator_as_ward() public {
        assertEq(FakeD3MPoolBase(d3mTestPool).wards(address(this)), 1);
    }

    function test_sets_hub_as_ward() public {
        assertEq(FakeD3MPoolBase(d3mTestPool).wards(address(this)), 1);
    }

    function test_can_rely() public {
        assertEq(FakeD3MPoolBase(d3mTestPool).wards(address(123)), 0);

        FakeD3MPoolBase(d3mTestPool).rely(address(123));

        assertEq(FakeD3MPoolBase(d3mTestPool).wards(address(123)), 1);
    }

    function test_can_deny() public {
        assertEq(FakeD3MPoolBase(d3mTestPool).wards(address(this)), 1);

        FakeD3MPoolBase(d3mTestPool).deny(address(this));

        assertEq(FakeD3MPoolBase(d3mTestPool).wards(address(this)), 0);
    }

    function testFail_cannot_rely_without_auth() public {
        assertEq(FakeD3MPoolBase(d3mTestPool).wards(address(this)), 1);

        FakeD3MPoolBase(d3mTestPool).deny(address(this));
        FakeD3MPoolBase(d3mTestPool).rely(address(this));
    }

    function test_recoverTokens() public {
        _giveTokens(dai, 10 * WAD);
        assertEq(dai.balanceOf(address(this)), 10 * WAD);

        dai.transfer(d3mTestPool, 10 * WAD);
        assertEq(dai.balanceOf(d3mTestPool), 10 * WAD);
        assertEq(dai.balanceOf(address(this)), 0);

        bool result = FakeD3MPoolBase(d3mTestPool).recoverTokens(address(dai), address(this), 10 * WAD);

        assertTrue(result);

        assertEq(dai.balanceOf(d3mTestPool), 0);
        assertEq(dai.balanceOf(address(this)), 10 * WAD);
    }

    function testFail_no_auth_cannot_recoverTokens() public {
        _giveTokens(dai, 10 * WAD);
        dai.transfer(d3mTestPool, 10 * WAD);
        assertEq(dai.balanceOf(d3mTestPool), 10 * WAD);
        assertEq(dai.balanceOf(address(this)), 0);

        FakeD3MPoolBase(d3mTestPool).deny(address(this));

        FakeD3MPoolBase(d3mTestPool).recoverTokens(address(dai), address(this), 10 * WAD);
    }

    function test_auth_can_cage() public {
        assertEq(FakeD3MPoolBase(d3mTestPool).live(), 1);

        FakeD3MPoolBase(d3mTestPool).cage();

        assertEq(FakeD3MPoolBase(d3mTestPool).live(), 0);
    }

    function testFail_no_auth_cannot_cage() public {
        assertEq(FakeD3MPoolBase(d3mTestPool).live(), 1);

        FakeD3MPoolBase(d3mTestPool).deny(address(this));

        FakeD3MPoolBase(d3mTestPool).cage();
    }

    function test_implements_accrueIfNeeded() public {
        FakeD3MPoolBase(d3mTestPool).accrueIfNeeded();
    }
}
