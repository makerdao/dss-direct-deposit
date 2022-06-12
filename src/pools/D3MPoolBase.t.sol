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
import {DaiLike, CanLike, D3mHubLike} from "../tests/interfaces/interfaces.sol";

import "./ID3MPool.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;

    function load(address, bytes32) external view returns (bytes32);

    function roll(uint256) external;
}

interface VatLike {
    function live() external view returns (uint256);
    function hope(address) external;
    function nope(address) external;
}

contract D3MPoolBase is ID3MPool {

    address public hub;

    VatLike public immutable vat;

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
        require(wards[msg.sender] == 1, "D3MPoolBase/not-authorized");
        _;
    }

    modifier onlyHub {
        require(msg.sender == hub, "D3MPoolBase/only-hub");
        _;
    }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    constructor(address hub_, address dai_) {
        asset = DaiLike(dai_);

        hub = hub_;
        vat = VatLike(D3mHubLike(hub_).vat());

        CanLike(D3mHubLike(hub_).vat()).hope(hub_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function file(bytes32 what, address data) external auth {
        require(vat.live() == 1, "D3MPoolBase/no-file-during-shutdown");
        if (what == "hub") {
            vat.nope(hub);
            hub = data;
            vat.hope(data);
        }
        else revert("D3MPoolBase/file-unrecognized-param");
    }

    function deposit(uint256 wad) external onlyHub override {}

    function withdraw(uint256 wad) external onlyHub override {}

    function transfer(address dst, uint256 wad) onlyHub external override {}

    function preDebtChange(bytes32 what) external override {}

    function postDebtChange(bytes32 what) external override {}

    function assetBalance() external view override returns (uint256) {}

    function quit(address dst) external auth view override {
        dst;
        require(vat.live() == 1, "D3MAavePool/no-quit-during-shutdown");
    }

    function maxDeposit() external view override returns (uint256) {}

    function maxWithdraw() external view override returns (uint256) {}

    function redeemable() external override pure returns(address) {
        return address(0);
    }
}

contract FakeVat {
    uint256 public live = 1;
    mapping(address => mapping (address => uint)) public can;
    function cage() external { live = 0; }
    function hope(address usr) external { can[msg.sender][usr] = 1; }
    function nope(address usr) external { can[msg.sender][usr] = 0; }
}

contract FakeHub {
    address public immutable vat;

    constructor(address vat_) {
        vat = vat_;
    }
}

contract D3MPoolBaseTest is DSTest {
    uint256 constant WAD = 10**18;

    Hevm hevm;

    DaiLike dai;

    address d3mTestPool;
    address hub;
    address vat;

    function setUp() public virtual {
        hevm = Hevm(
            address(bytes20(uint160(uint256(keccak256("hevm cheat code")))))
        );

        dai = DaiLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);

        vat = address(new FakeVat());

        hub = address(new FakeHub(vat));

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

    function test_hopes_on_hub() public {
        assertEq(CanLike(vat).can(d3mTestPool, hub), 1);
    }

    function test_can_rely_deny() public {
        assertEq(D3MPoolBase(d3mTestPool).wards(address(123)), 0);

        D3MPoolBase(d3mTestPool).rely(address(123));

        assertEq(D3MPoolBase(d3mTestPool).wards(address(123)), 1);

        D3MPoolBase(d3mTestPool).deny(address(123));

        assertEq(D3MPoolBase(d3mTestPool).wards(address(123)), 0);
    }

    function testFail_cannot_rely_no_auth() public {
        D3MPoolBase(d3mTestPool).deny(address(this));

        D3MPoolBase(d3mTestPool).rely(address(123));
    }

    function testFail_cannot_deny_no_auth() public {
        D3MPoolBase(d3mTestPool).deny(address(this));

        D3MPoolBase(d3mTestPool).deny(address(123));
    }

    function test_can_file_hub() public {
        address newHub = address(new FakeHub(vat));
        assertEq(CanLike(vat).can(d3mTestPool, hub), 1);
        assertEq(CanLike(vat).can(d3mTestPool, newHub), 0);
        D3MPoolBase(d3mTestPool).file("hub", newHub);
        assertEq(CanLike(vat).can(d3mTestPool, hub), 0);
        assertEq(CanLike(vat).can(d3mTestPool, newHub), 1);
    }

    function testFail_cannot_file_hub_no_auth() public {
        D3MPoolBase(d3mTestPool).deny(address(this));

        D3MPoolBase(d3mTestPool).file("hub", address(123));
    }

    function testFail_cannot_file_hub_vat_caged() public {
        FakeVat(vat).cage();

        D3MPoolBase(d3mTestPool).file("hub", address(123));
    }

    function testFail_cannot_file_unknown_param() public {
        D3MPoolBase(d3mTestPool).file("fail", address(123));
    }

    function testFail_deposit_not_hub() public {
        D3MPoolBase(d3mTestPool).deposit(1);
    }

    function testFail_withdraw_not_hub() public {
        D3MPoolBase(d3mTestPool).withdraw(1);
    }

    function testFail_transfer_not_hub() public {
        D3MPoolBase(d3mTestPool).transfer(address(this), 0);
    }

    function testFail_quit_no_auth() public {
        D3MPoolBase(d3mTestPool).deny(address(this));
        D3MPoolBase(d3mTestPool).quit(address(this));
    }

    function testFail_quit_vat_caged() public {
        FakeVat(vat).cage();
        D3MPoolBase(d3mTestPool).quit(address(this));
    }

    function test_implements_preDebtChange() public {
        D3MPoolBase(d3mTestPool).preDebtChange("test");
    }

    function test_implements_postDebtChange() public {
        D3MPoolBase(d3mTestPool).postDebtChange("test");
    }
}
