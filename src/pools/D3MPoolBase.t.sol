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

pragma solidity >=0.6.12;

import "ds-test/test.sol";
import {DaiLike, CanLike, d3mHubLike} from "../tests/interfaces/interfaces.sol";

import "./ID3MPool.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;

    function load(address, bytes32) external view returns (bytes32);
}

contract D3MPoolBase is ID3MPool {

    DaiLike public immutable asset; // Dai

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "D3MAaveDaiPool/not-authorized");
        _;
    }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    constructor(address hub_, address dai_) public {
        asset = DaiLike(dai_);

        CanLike(d3mHubLike(hub_).vat()).hope(hub_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

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

    function maxDeposit() external view override returns (uint256) {}

    function maxWithdraw() external view override returns (uint256) {}

    function recoverTokens(address token, address dst, uint256 amt) external override auth returns (bool) {}

    function active() external override view returns(bool) {
        return true;
    }
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

        address hub = address(new FakeHub());

        d3mTestPool = address(new D3MPoolBase(hub, address(dai)));
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

    function test_sets_creator_as_ward() public {
        assertEq(D3MPoolBase(d3mTestPool).wards(address(this)), 1);
    }

    function test_can_rely() public {
        assertEq(D3MPoolBase(d3mTestPool).wards(address(123)), 0);

        D3MPoolBase(d3mTestPool).rely(address(123));

        assertEq(D3MPoolBase(d3mTestPool).wards(address(123)), 1);
    }

    function test_can_deny() public {
        assertEq(D3MPoolBase(d3mTestPool).wards(address(this)), 1);

        D3MPoolBase(d3mTestPool).deny(address(this));

        assertEq(D3MPoolBase(d3mTestPool).wards(address(this)), 0);
    }

    function testFail_cannot_rely_without_auth() public {
        assertEq(D3MPoolBase(d3mTestPool).wards(address(this)), 1);

        D3MPoolBase(d3mTestPool).deny(address(this));
        D3MPoolBase(d3mTestPool).rely(address(this));
    }

    function testFail_no_auth_cannot_recoverTokens() public {
        D3MPoolBase(d3mTestPool).deny(address(this));

        D3MPoolBase(d3mTestPool).recoverTokens(address(dai), address(this), 10 * WAD);
    }

    function test_implements_accrueIfNeeded() public {
        D3MPoolBase(d3mTestPool).accrueIfNeeded();
    }

    function test_implements_active() public view {
        D3MPoolBase(d3mTestPool).active();
    }
}
