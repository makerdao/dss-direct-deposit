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
import "./tests/interfaces/interfaces.sol";

import {D3MHub} from "./D3MHub.sol";
import "./pools/ID3MPool.sol";
import "./plans/ID3MPlan.sol";

import {D3MTestPool} from "./tests/stubs/D3MTestPool.sol";
import {D3MTestPlan} from "./tests/stubs/D3MTestPlan.sol";
import {D3MTestGem} from "./tests/stubs/D3MTestGem.sol";
import {D3MTestRewards} from "./tests/stubs/D3MTestRewards.sol";
import {ValueStub} from "./tests/stubs/ValueStub.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;

    function load(address, bytes32) external view returns (bytes32);
}

contract D3MHubTest is DSTest {
    uint256 constant WAD = 10**18;
    uint256 constant RAY = 10**27;
    uint256 constant RAD = 10**45;

    Hevm hevm;

    VatLike vat;
    EndLike end;
    D3MTestRewards rewardsClaimer;
    DaiLike dai;
    DaiJoinLike daiJoin;
    D3MTestGem testGem;
    TokenLike testReward;
    SpotLike spot;
    TokenLike weth;
    address vow;
    address pauseProxy;

    bytes32 constant ilk = "DD-DAI-TEST";
    D3MHub d3mHub;
    D3MTestPool d3mTestPool;
    D3MTestPlan d3mTestPlan;
    ValueStub pip;

    function setUp() public {
        hevm = Hevm(
            address(bytes20(uint160(uint256(keccak256("hevm cheat code")))))
        );

        vat = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        end = EndLike(0x0e2e8F1D1326A4B9633D96222Ce399c708B19c28);
        dai = DaiLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        daiJoin = DaiJoinLike(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
        spot = SpotLike(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);
        weth = TokenLike(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        vow = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;
        pauseProxy = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

        // Force give admin access to these contracts via hevm magic
        _giveAuthAccess(address(vat), address(this));
        _giveAuthAccess(address(end), address(this));
        _giveAuthAccess(address(spot), address(this));

        testGem = new D3MTestGem(18);
        d3mHub = new D3MHub(address(vat), address(daiJoin));

        rewardsClaimer = new D3MTestRewards(address(testGem));
        d3mTestPool = new D3MTestPool(
            address(d3mHub),
            address(dai),
            address(testGem),
            address(rewardsClaimer)
        );
        d3mTestPool.rely(address(d3mHub));
        d3mTestPlan = new D3MTestPlan(address(dai));

        // Test Target Setup
        testGem.rely(address(d3mTestPool));
        d3mTestPlan.file("maxBar_", type(uint256).max);
        testGem.giveAllowance(
            address(dai),
            address(d3mTestPool),
            type(uint256).max
        );

        d3mHub.file("vow", vow);
        d3mHub.file("end", address(end));

        d3mHub.file(ilk, "pool", address(d3mTestPool));
        d3mHub.file(ilk, "plan", address(d3mTestPlan));
        d3mHub.file(ilk, "tau", 7 days);

        // Init new collateral
        pip = new ValueStub();
        pip.poke(bytes32(WAD));
        spot.file(ilk, "pip", address(pip));
        spot.file(ilk, "mat", RAY);
        spot.poke(ilk);

        vat.rely(address(d3mHub));
        vat.init(ilk);
        vat.file(ilk, "line", 5_000_000_000 * RAD);
        vat.file("Line", vat.Line() + 5_000_000_000 * RAD);
    }

    // --- Math ---
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }

    function _giveAuthAccess(address _base, address target) internal {
        AuthLike base = AuthLike(_base);

        // Edge case - ward is already set
        if (base.wards(target) == 1) return;

        for (int256 i = 0; i < 100; i++) {
            // Scan the storage for the ward storage slot
            bytes32 prevValue = hevm.load(
                address(base),
                keccak256(abi.encode(target, uint256(i)))
            );
            hevm.store(
                address(base),
                keccak256(abi.encode(target, uint256(i))),
                bytes32(uint256(1))
            );
            if (base.wards(target) == 1) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(base),
                    keccak256(abi.encode(target, uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function _giveTokens(TokenLike token, address usr, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (token.balanceOf(usr) == amount) return;

        for (int256 i = 0; i < 100; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                address(token),
                keccak256(abi.encode(usr, uint256(i)))
            );
            hevm.store(
                address(token),
                keccak256(abi.encode(usr, uint256(i))),
                bytes32(amount)
            );
            if (token.balanceOf(usr) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(token),
                    keccak256(abi.encode(usr, uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function _giveTokens(TokenLike token, uint256 amount) internal {
        _giveTokens(token, address(this), amount);
    }

    function _windSystem() internal {
        d3mTestPlan.file("bar", 10);
        d3mTestPlan.file("targetAssets", 50 * WAD);
        d3mHub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
        d3mTestPool.file("preDebt", false); // reset preDebt
        d3mTestPool.file("postDebt", false); // reset postDebt
    }

    function test_approvals() public {
        assertEq(
            dai.allowance(address(d3mHub), address(daiJoin)),
            type(uint256).max
        );
        assertEq(vat.can(address(d3mHub), address(daiJoin)), 1);
    }

    function test_can_file_tau() public {
        (, , uint256 tau, , ) = d3mHub.ilks(ilk);
        assertEq(tau, 7 days);
        d3mHub.file(ilk, "tau", 1 days);
        (, , tau, , ) = d3mHub.ilks(ilk);
        assertEq(tau, 1 days);
    }

    function testFail_unauth_file_tau() public {
        d3mHub.deny(address(this));

        d3mHub.file(ilk, "tau", 1 days);
    }

    function testFail_unknown_uint256_file() public {
        d3mHub.file(ilk, "unknown", 1);
    }

    function testFail_unknown_address_file() public {
        d3mHub.file("unknown", address(this));
    }

    function test_can_file_pool() public {
        (ID3MPool pool, , , , ) = d3mHub.ilks(ilk);

        assertEq(address(pool), address(d3mTestPool));

        d3mHub.file(ilk, "pool", address(this));

        (pool, , , , ) = d3mHub.ilks(ilk);
        assertEq(address(pool), address(this));
    }

    function test_can_file_plan() public {
        (, ID3MPlan plan, , , ) = d3mHub.ilks(ilk);

        assertEq(address(plan), address(d3mTestPlan));

        d3mHub.file(ilk, "plan", address(this));

        (, plan, , , ) = d3mHub.ilks(ilk);
        assertEq(address(plan), address(this));
    }

    function test_can_file_vow() public {
        address setVow = d3mHub.vow();

        assertEq(vow, setVow);

        d3mHub.file("vow", address(this));

        setVow = d3mHub.vow();
        assertEq(setVow, address(this));
    }

    function test_can_file_end() public {
        address setEnd = address(d3mHub.end());

        assertEq(address(end), setEnd);

        d3mHub.file("end", address(this));

        setEnd = address(d3mHub.end());
        assertEq(setEnd, address(this));
    }

    function testFail_vat_not_live_address_file() public {
        d3mHub.file("end", address(this));
        address hubEnd = address(d3mHub.end());

        assertEq(hubEnd, address(this));

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        d3mHub.file("end", address(123));
    }

    function testFail_unauth_file_pool() public {
        d3mHub.deny(address(this));

        d3mHub.file(ilk, "pool", address(this));
    }

    function testFail_hub_not_live_pool_file() public {
        // Cage Pool
        d3mHub.cage(ilk);

        d3mHub.file(ilk, "pool", address(123));
    }

    function testFail_unknown_ilk_address_file() public {
        d3mHub.file(ilk, "unknown", address(123));
    }

    function testFail_vat_not_live_ilk_address_file() public {
        d3mHub.file(ilk, "pool", address(this));
        (ID3MPool pool, , , , ) = d3mHub.ilks(ilk);

        assertEq(address(pool), address(this));

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        d3mHub.file(ilk, "pool", address(123));
    }

    function test_can_nope_daiJoin() public {
        assertEq(vat.can(address(d3mHub), address(daiJoin)), 1);
        d3mHub.nope();
        assertEq(vat.can(address(d3mHub), address(daiJoin)), 0);
    }

    function testFail_cannot_nope_without_auth() public {
        assertEq(vat.can(address(d3mHub), address(daiJoin)), 1);
        d3mHub.deny(address(this));
        d3mHub.nope();
    }

    function testFail_exec_no_ilk() public {
        d3mHub.exec("fake-ilk");
    }

    function testFail_exec_rate_not_one() public {
        vat.fold(ilk, vow, int(2 * RAY));
        d3mHub.exec(ilk);
    }
    
    function test_wind_limited_ilk_line() public {
        d3mTestPlan.file("bar", 10);
        d3mTestPlan.file("targetAssets", 50 * WAD);
        vat.file(ilk, "line", 40 * RAD);
        d3mHub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 40 * WAD);
        assertEq(art, 40 * WAD);
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_wind_limited_Line() public {
        d3mTestPlan.file("bar", 10);
        d3mTestPlan.file("targetAssets", 50 * WAD);
        vat.file("Line", vat.debt() + 40 * RAD);
        d3mHub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 40 * WAD);
        assertEq(art, 40 * WAD);
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_wind_limited_by_maxDeposit() public {
        _windSystem(); // winds to 50 * WAD
        d3mTestPlan.file("targetAssets", 75 * WAD);
        d3mTestPool.file("maxDepositAmount", 5 * WAD);

        d3mHub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 55 * WAD);
        assertEq(art, 55 * WAD);
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_wind_limited_to_zero_by_maxDeposit() public {
        _windSystem(); // winds to 50 * WAD
        d3mTestPlan.file("targetAssets", 75 * WAD);
        d3mTestPool.file("maxDepositAmount", 0);

        d3mHub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_wind_limited_by_pool_loss() public {
        _windSystem(); // winds to 50 * WAD

        // Set debt ceiling to 60 to limit loss
        vat.file(ilk, "line", 60 * RAD);

        // Simulate a loss event by removing the share tokens
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(testGem.balanceOf(address(d3mTestPool)), 50 * WAD);
        assertEq(d3mTestPool.assetBalance(), 50 * WAD);

        _giveTokens(TokenLike(address(testGem)), address(d3mTestPool), 0);

        assertEq(testGem.balanceOf(address(d3mTestPool)), 0);
        assertEq(d3mTestPool.assetBalance(), 0);
        (ink, art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);

        // This should only fill another 10 because the debt ceiling
        directDepositHub.exec(ilk);

        assertEq(d3mTestPool.assetBalance(), 10 * WAD);
        (ink, art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 60 * WAD);
        assertEq(art, 60 * WAD);
    }

    function test_unwind_pool_not_active() public {
        _windSystem();

        // Temporarily disable the module
        d3mTestPool.file("active_", false);
        d3mHub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        // Make sure pre/post functions get called
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_unwind_plan_not_active() public {
        _windSystem();

        // Temporarily disable the module
        d3mTestPlan.file("active_", false);
        d3mHub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        // Make sure pre/post functions get called
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_unwind_bar_zero() public {
        _windSystem();

        // Temporarily disable the module
        d3mTestPlan.file("bar", 0);
        d3mHub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        // Make sure pre/post functions get called
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_unwind_ilk_line_lowered() public {
        _windSystem();

        // Set ilk line below current debt
        d3mTestPlan.file("targetAssets", 55 * WAD); // Increasing target in 5 WAD
        vat.file(ilk, "line", 45 * RAD);
        d3mHub.exec(ilk);

        // Ensure we unwound our position to debt ceiling
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 45 * WAD); // Instead of 5 WAD more results in 5 WAD less due debt ceiling
        assertEq(art, 45 * WAD);
        // Make sure pre/post functions get called
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_unwind_global_Line_lowered() public {
        _windSystem();

        // Set ilk line below current debt
        d3mTestPlan.file("targetAssets", 55 * WAD); // Increasing target in 5 WAD
        vat.file("Line", vat.debt() - 5 * RAD);
        d3mHub.exec(ilk);

        // Ensure we unwound our position to debt ceiling
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 45 * WAD); // Instead of 5 WAD more results in 5 WAD less due debt ceiling
        assertEq(art, 45 * WAD);
        // Make sure pre/post functions get called
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_unwind_mcd_caged() public {
        _windSystem();

        // MCD shuts down
        end.cage();
        end.cage(ilk);

        d3mHub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        // Make sure pre/post functions get called
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_unwind_mcd_caged_debt_paid_back() public {
        _windSystem();

        // Someone pays back our debt
        _giveTokens(TokenLike(address(dai)), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(ilk, address(d3mTestPool), address(d3mTestPool), address(this), 0, -int256(10 * WAD));

        // MCD shuts down
        end.cage();
        end.cage(ilk);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mTestPool));
        assertEq(pink, 50 * WAD);
        assertEq(part, 40 * WAD);
        uint256 gemBefore = vat.gem(ilk, address(end));
        assertEq(gemBefore, 0);
        uint256 sinBefore = vat.sin(vow);

        d3mHub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 10 * WAD);
        assertEq(art, 0);
        uint256 gemAfter = vat.gem(ilk, address(end));
        assertEq(gemAfter, 0);
        uint256 daiAfter = vat.dai(address(d3mHub));
        assertEq(daiAfter, 0);
        assertEq(sinBefore + 40 * RAD, vat.sin(vow));
    }

    function test_unwind_pool_caged() public {
        _windSystem();

        // Module caged
        d3mHub.cage(ilk);

        d3mHub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        // Make sure pre/post functions get called
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_unwind_target_less_amount() public {
        _windSystem();

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mTestPool));
        assertEq(pink, 50 * WAD);
        assertEq(part, 50 * WAD);

        d3mTestPlan.file("targetAssets", 25 * WAD);

        d3mHub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 25 * WAD);
        assertEq(art, 25 * WAD);
        // Make sure pre/post functions get called
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_wind_unwind_non_standard_token() public {
        // setup system
        bytes32 otherIlk = "DD-OTHER-GEM";
        D3MTestGem otherGem = new D3MTestGem(6);
        D3MTestRewards otherRewards = new D3MTestRewards(address(otherGem));
        D3MTestPool otherPool = new D3MTestPool(
            address(d3mHub),
            address(dai),
            address(otherGem),
            address(otherRewards)
        );
        otherPool.rely(address(d3mHub));
        otherGem.rely(address(otherPool));
        otherGem.giveAllowance(
            address(dai),
            address(otherPool),
            type(uint256).max
        );

        d3mHub.file(otherIlk, "pool", address(otherPool));
        d3mHub.file(otherIlk, "plan", address(d3mTestPlan));
        d3mHub.file(otherIlk, "tau", 7 days);

        spot.file(otherIlk, "pip", address(pip));
        spot.file(otherIlk, "mat", RAY);
        spot.poke(otherIlk);
        vat.init(otherIlk);
        vat.file(otherIlk, "line", 5_000_000_000 * RAD);
        vat.file("Line", vat.Line() + 10_000_000_000 * RAD);

        // wind up system
        d3mTestPlan.file("bar", 10);
        d3mTestPlan.file("targetAssets", 50 * WAD);
        d3mHub.exec(otherIlk);

        (uint256 ink, uint256 art) = vat.urns(otherIlk, address(otherPool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertTrue(otherPool.preDebt());
        assertTrue(otherPool.postDebt());
        otherPool.file("preDebt", false); // reset preDebt
        otherPool.file("postDebt", false); // reset postDebt

        // wind down system
        d3mTestPlan.file("bar", 10);
        d3mTestPlan.file("targetAssets", 5 * WAD);
        d3mHub.exec(otherIlk);

        (ink, art) = vat.urns(otherIlk, address(otherPool));
        assertEq(ink, 5 * WAD);
        assertEq(art, 5 * WAD);
        assertTrue(otherPool.preDebt());
        assertTrue(otherPool.postDebt());
        otherPool.file("preDebt", false); // reset preDebt
        otherPool.file("postDebt", false); // reset postDebt
    }

    function test_reap_available_liquidity() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        _giveTokens(TokenLike(address(testGem)), 10 * WAD);
        testGem.transfer(address(d3mTestPool), 10 * WAD);

        (, uint256 part) = vat.urns(ilk, address(d3mTestPool));
        assertEq(part, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        d3mHub.reap(ilk);

        (, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(art, 50 * WAD);
        uint256 currentDai = vat.dai(vow);
        assertEq(currentDai, prevDai + 10 * RAD); // Interest shows up in vat Dai for the Vow [rad]
        // Make sure pre/post functions get called
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_reap_not_enough_liquidity() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        _giveTokens(TokenLike(address(testGem)), 55 * WAD);
        testGem.transfer(address(d3mTestPool), 10 * WAD);

        (, uint256 part) = vat.urns(ilk, address(d3mTestPool));
        assertEq(part, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        // If we do not have enough liquidity then we pull out what we can for the fees
        // This will pull out all but 5 WAD of the liquidity
        assertEq(dai.balanceOf(address(testGem)), 50 * WAD); // liquidity before simulating other user's withdraw
        testGem.giveAllowance(address(dai), address(this), type(uint256).max);
        dai.transferFrom(address(testGem), address(this), 45 * WAD);
        assertEq(dai.balanceOf(address(testGem)), 5 * WAD); // liquidity after

        d3mHub.reap(ilk);

        (, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(art, 50 * WAD);
        uint256 currentDai = vat.dai(vow);
        assertEq(currentDai, prevDai + 5 * RAD); // Interest shows up in vat Dai for the Vow [rad]
        // Make sure pre/post functions get called
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function testFail_no_reap_mcd_caged() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        _giveTokens(TokenLike(address(testGem)), 10 * WAD);
        testGem.transfer(address(d3mTestPool), 10 * WAD);

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        d3mHub.reap(ilk);
    }

    function testFail_no_reap_pool_caged() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        _giveTokens(TokenLike(address(testGem)), 10 * WAD);
        testGem.transfer(address(d3mTestPool), 10 * WAD);

        // module caged
        d3mHub.cage(ilk);

        d3mHub.reap(ilk);
    }

    function testFail_no_reap_pool_inactive() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        _giveTokens(TokenLike(address(testGem)), 10 * WAD);
        testGem.transfer(address(d3mTestPool), 10 * WAD);

        // pool inactive
        d3mTestPool.file("active_", false);

        d3mHub.reap(ilk);
    }

    function testFail_no_reap_plan_inactive() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        _giveTokens(TokenLike(address(testGem)), 10 * WAD);
        testGem.transfer(address(d3mTestPool), 10 * WAD);

        // pool inactive
        d3mTestPlan.file("active_", false);

        d3mHub.reap(ilk);
    }

    function test_recify_no_limit() public {
        _windSystem(); // winds to 50 * WAD

        // Set debt ceiling to 60 to limit loss
        vat.file(ilk, "line", 60 * RAD);

        // Simulate a loss event by removing the share tokens
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(testGem.balanceOf(address(d3mTestPool)), 50 * WAD);
        assertEq(d3mTestPool.assetBalance(), 50 * WAD);

        _giveTokens(TokenLike(address(testGem)), address(d3mTestPool), 0);

        assertEq(testGem.balanceOf(address(d3mTestPool)), 0);
        assertEq(d3mTestPool.assetBalance(), 0);
        (ink, art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);

        // This should only fill another 10 because the debt ceiling
        directDepositHub.exec(ilk);

        assertEq(d3mTestPool.assetBalance(), 10 * WAD);
        (ink, art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 60 * WAD);
        assertEq(art, 60 * WAD);

        // Repay the bad debt
        uint256 vowSin = vat.sin(vow);
        directDepositHub.rectify(ilk, type(uint256).max);

        assertEq(d3mTestPool.assetBalance(), 10 * WAD);
        (ink, art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 10 * WAD);
        assertEq(art, 10 * WAD);
        assertEq(vat.sin(vow), vowSin + 50 * RAD);

        // Refill back up to the target of 50
        directDepositHub.exec(ilk);

        assertEq(d3mTestPool.assetBalance(), 50 * WAD);
        (ink, art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
    }

    function test_recify_limit() public {
        _windSystem(); // winds to 50 * WAD

        // Set debt ceiling to 60 to limit loss
        vat.file(ilk, "line", 60 * RAD);

        // Simulate a loss event by removing the share tokens
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(testGem.balanceOf(address(d3mTestPool)), 50 * WAD);
        assertEq(d3mTestPool.assetBalance(), 50 * WAD);

        _giveTokens(TokenLike(address(testGem)), address(d3mTestPool), 0);

        assertEq(testGem.balanceOf(address(d3mTestPool)), 0);
        assertEq(d3mTestPool.assetBalance(), 0);
        (ink, art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);

        // This should only fill another 10 because the debt ceiling
        directDepositHub.exec(ilk);

        assertEq(d3mTestPool.assetBalance(), 10 * WAD);
        (ink, art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 60 * WAD);
        assertEq(art, 60 * WAD);

        // Repay only part of the bad debt
        uint256 vowSin = vat.sin(vow);
        directDepositHub.rectify(ilk, 20 * WAD);

        assertEq(d3mTestPool.assetBalance(), 10 * WAD);
        (ink, art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 40 * WAD);
        assertEq(art, 40 * WAD);
        assertEq(vat.sin(vow), vowSin + 20 * RAD);

        // Refill can only reach 30 as we still have bad debt to clear
        directDepositHub.exec(ilk);

        assertEq(d3mTestPool.assetBalance(), 30 * WAD);
        (ink, art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 60 * WAD);
        assertEq(art, 60 * WAD);
    }

    function test_exit() public {
        _windSystem();
        // Vat is caged for global settlement
        vat.cage();

        // Simulate DAI holder gets some gems from GS
        vat.grab(
            ilk,
            address(d3mTestPool),
            address(this),
            address(this),
            -int256(50 * WAD),
            -int256(0)
        );

        uint256 prevBalance = testGem.balanceOf(address(this));

        // User can exit and get the aDAI
        d3mHub.exit(ilk, address(this), 50 * WAD);
        assertEq(testGem.balanceOf(address(this)), prevBalance + 50 * WAD);
    }

    function test_cage_pool() public {
        (, , uint256 tau, , uint256 tic) = d3mHub.ilks(ilk);
        assertEq(tic, 0);

        d3mHub.cage(ilk);

        (, , , , tic) = d3mHub.ilks(ilk);
        assertEq(tic, block.timestamp + tau);
    }

    function testFail_cage_pool_mcd_caged() public {
        vat.cage();
        d3mHub.cage(ilk);
    }
    
    function testFail_cage_pool_no_auth() public {
        d3mHub.deny(address(this));
        d3mHub.cage(ilk);
    }

    function testFail_cage_pool_already_caged() public {
        d3mHub.cage(ilk);
        d3mHub.cage(ilk);
    }

    function test_cull() public {
        _windSystem();
        d3mHub.cage(ilk);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mTestPool));
        assertEq(pink, 50 * WAD);
        assertEq(part, 50 * WAD);
        uint256 gemBefore = vat.gem(ilk, address(d3mTestPool));
        assertEq(gemBefore, 0);
        uint256 sinBefore = vat.sin(vow);

        d3mHub.cull(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        uint256 gemAfter = vat.gem(ilk, address(d3mTestPool));
        assertEq(gemAfter, 50 * WAD);
        assertEq(sinBefore + 50 * RAD, vat.sin(vow));
        (, , , uint256 culled, ) = d3mHub.ilks(ilk);
        assertEq(culled, 1);
    }

    function test_cull_debt_paid_back() public {
        _windSystem();

        // Someone pays back our debt
        _giveTokens(TokenLike(address(dai)), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(ilk, address(d3mTestPool), address(d3mTestPool), address(this), 0, -int256(10 * WAD));

        d3mHub.cage(ilk);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mTestPool));
        assertEq(pink, 50 * WAD);
        assertEq(part, 40 * WAD);
        uint256 gemBefore = vat.gem(ilk, address(d3mTestPool));
        assertEq(gemBefore, 0);
        uint256 sinBefore = vat.sin(vow);
        uint256 vowDaiBefore = vat.dai(vow);

        d3mHub.cull(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        uint256 gemAfter = vat.gem(ilk, address(d3mTestPool));
        assertEq(gemAfter, 40 * WAD);
        uint256 daiAfter = vat.dai(address(d3mHub));
        assertEq(daiAfter, 0);
        // Sin only increases by 40 WAD since 10 was covered previously
        assertEq(sinBefore + 40 * RAD, vat.sin(vow));
        assertEq(vowDaiBefore, vat.dai(vow));
        (, , , uint256 culled, ) = d3mHub.ilks(ilk);
        assertEq(culled, 1);

        d3mHub.exec(ilk);

        assertEq(vat.gem(ilk, address(d3mTestPool)), 0);
        assertEq(vat.dai(address(d3mHub)), 0);
        // Still 50 WAD because the extra 10 WAD from repayment are not
        // accounted for in the fees from unwind
        assertEq(vowDaiBefore + 50 * RAD, vat.dai(vow));
    }

    function test_cull_no_auth_time_passed() public {
        _windSystem();
        d3mHub.cage(ilk);
        // with auth we can cull anytime
        d3mHub.deny(address(this));
        // but with enough time, anyone can cull
        hevm.warp(block.timestamp + 7 days);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mTestPool));
        assertEq(pink, 50 * WAD);
        assertEq(part, 50 * WAD);
        uint256 gemBefore = vat.gem(ilk, address(d3mTestPool));
        assertEq(gemBefore, 0);
        uint256 sinBefore = vat.sin(vow);

        d3mHub.cull(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 0);
        assertEq(art, 0);
        uint256 gemAfter = vat.gem(ilk, address(d3mTestPool));
        assertEq(gemAfter, 50 * WAD);
        assertEq(sinBefore + 50 * RAD, vat.sin(vow));
        (, , , uint256 culled, ) = d3mHub.ilks(ilk);
        assertEq(culled, 1);
    }

    function testFail_no_cull_mcd_caged() public {
        _windSystem();
        d3mHub.cage(ilk);
        vat.cage();

        d3mHub.cull(ilk);
    }

    function testFail_no_cull_pool_live() public {
        _windSystem();

        d3mHub.cull(ilk);
    }

    function testFail_no_cull_unauth_too_soon() public {
        _windSystem();
        d3mHub.cage(ilk);
        d3mHub.deny(address(this));
        hevm.warp(block.timestamp + 6 days);

        d3mHub.cull(ilk);
    }

    function testFail_no_cull_already_culled() public {
        _windSystem();
        d3mHub.cage(ilk);

        d3mHub.cull(ilk);
        d3mHub.cull(ilk);
    }

    function testFail_no_cull_no_ilk() public {
        d3mHub.cull("fake-ilk");
    }

    function test_uncull() public {
        _windSystem();
        d3mHub.cage(ilk);

        d3mHub.cull(ilk);
        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mTestPool));
        assertEq(pink, 0);
        assertEq(part, 0);
        uint256 gemBefore = vat.gem(ilk, address(d3mTestPool));
        assertEq(gemBefore, 50 * WAD);
        uint256 sinBefore = vat.sin(vow);
        (, , , uint256 culled, ) = d3mHub.ilks(ilk);
        assertEq(culled, 1);

        vat.cage();
        d3mHub.uncull(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        uint256 gemAfter = vat.gem(ilk, address(d3mTestPool));
        assertEq(gemAfter, 0);
        // Sin should not change since we suck before grabbing
        assertEq(sinBefore, vat.sin(vow));
        (, , , culled, ) = d3mHub.ilks(ilk);
        assertEq(culled, 0);
    }

    function testFail_no_uncull_not_culled() public {
        _windSystem();
        d3mHub.cage(ilk);

        vat.cage();
        d3mHub.uncull(ilk);
    }

    function testFail_no_uncull_mcd_live() public {
        _windSystem();
        d3mHub.cage(ilk);

        d3mHub.cull(ilk);

        d3mHub.uncull(ilk);
    }

    function test_quit_culled() public {
        _windSystem();
        d3mHub.cage(ilk);

        d3mHub.cull(ilk);

        uint256 balBefore = testGem.balanceOf(address(this));
        assertEq(50 * WAD, testGem.balanceOf(address(d3mTestPool)));
        assertEq(50 * WAD, vat.gem(ilk, address(d3mTestPool)));

        d3mHub.quit(ilk, address(this));

        assertEq(balBefore + 50 * WAD, testGem.balanceOf(address(this)));
        assertEq(0, testGem.balanceOf(address(d3mTestPool)));
        assertEq(0, vat.gem(ilk, address(d3mTestPool)));
    }

    function test_quit_not_culled() public {
        _windSystem();
        vat.hope(address(d3mHub));

        uint256 balBefore = testGem.balanceOf(address(this));
        assertEq(50 * WAD, testGem.balanceOf(address(d3mTestPool)));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(d3mTestPool));
        assertEq(pink, 50 * WAD);
        assertEq(part, 50 * WAD);
        (uint256 tink, uint256 tart) = vat.urns(ilk, address(this));
        assertEq(tink, 0);
        assertEq(tart, 0);

        d3mHub.quit(ilk, address(this));

        assertEq(balBefore + 50 * WAD, testGem.balanceOf(address(this)));
        (uint256 joinInk, uint256 joinArt) = vat.urns(
            ilk,
            address(d3mTestPool)
        );
        assertEq(joinInk, 0);
        assertEq(joinArt, 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(this));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
    }

    function testFail_no_quit_not_culled_who_not_accepting() public {
        _windSystem();

        d3mHub.quit(ilk, address(this));
    }

    function testFail_no_quit_mcd_caged() public {
        _windSystem();
        d3mHub.cull(ilk);

        vat.cage();
        d3mHub.quit(ilk, address(this));
    }

    function testFail_no_quit_no_auth() public {
        _windSystem();
        d3mHub.cull(ilk);

        d3mHub.deny(address(this));
        d3mHub.quit(ilk, address(this));
    }

    function test_pool_upgrade_unwind_wind() public {
        _windSystem(); // Tests that the current pool has ink/art

        // Setup new pool
        D3MTestPool newPool = new D3MTestPool(
            address(d3mHub),
            address(dai),
            address(testGem),
            address(rewardsClaimer)
        );
        newPool.rely(address(d3mHub));
        testGem.rely(address(newPool));
        testGem.giveAllowance(
            address(dai),
            address(newPool),
            type(uint256).max
        );

        (uint256 npink, uint256 npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 0);
        assertEq(npart, 0);
        assertTrue(newPool.preDebt() == false);
        assertTrue(newPool.postDebt() == false);

        // Pool Inactive
        d3mTestPool.file("active_", false);
        assertTrue(d3mTestPool.active() == false);

        d3mHub.exec(ilk);

        // Ensure we unwound our position
        (uint256 opink, uint256 opart) = vat.urns(ilk, address(d3mTestPool));
        assertEq(opink, 0);
        assertEq(opart, 0);
        // Make sure pre/post functions get called
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
        d3mTestPool.file("preDebt", false); // reset preDebt
        d3mTestPool.file("postDebt", false); // reset postDebt

        d3mHub.file(ilk, "pool", address(newPool));
        d3mHub.exec(ilk);

        // New Pool should get wound up to the original amount because plan didn't change
        (npink, npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 50 * WAD);
        assertEq(npart, 50 * WAD);
        assertTrue(newPool.preDebt() == true);
        assertTrue(newPool.postDebt() == true);

        (opink, opart) = vat.urns(ilk, address(d3mTestPool));
        assertEq(opink, 0);
        assertEq(opart, 0);
        // Make sure unwind calls hooks
        assertTrue(d3mTestPool.preDebt() == false);
        assertTrue(d3mTestPool.postDebt() == false);
    }

    function test_pool_upgrade_quit() public {
        _windSystem(); // Tests that the current pool has ink/art

        // Setup new pool
        D3MTestPool newPool = new D3MTestPool(
            address(d3mHub),
            address(dai),
            address(testGem),
            address(rewardsClaimer)
        );
        newPool.rely(address(d3mHub));
        testGem.rely(address(newPool));
        testGem.giveAllowance(
            address(dai),
            address(newPool),
            type(uint256).max
        );


        (uint256 npink, uint256 npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 0);
        assertEq(npart, 0);
        assertTrue(newPool.preDebt() == false);
        assertTrue(newPool.postDebt() == false);

        // quit to new pool
        d3mHub.quit(ilk, address(newPool));

        // Ensure we quit our position
        (uint256 opink, uint256 opart) = vat.urns(ilk, address(d3mTestPool));
        assertEq(opink, 0);
        assertEq(opart, 0);
        // quit does not call hooks
        assertTrue(d3mTestPool.preDebt() == false);
        assertTrue(d3mTestPool.postDebt() == false);

        (npink, npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 50 * WAD);
        assertEq(npart, 50 * WAD);
        assertTrue(newPool.preDebt() == false);
        assertTrue(newPool.postDebt() == false);

        // file new pool
        d3mHub.file(ilk, "pool", address(newPool));

        // test unwind/wind
        d3mTestPlan.file("targetAssets", 45 * WAD);
        d3mHub.exec(ilk);

        (opink, opart) = vat.urns(ilk, address(d3mTestPool));
        assertEq(opink, 0);
        assertEq(opart, 0);

        (npink, npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 45 * WAD);
        assertEq(npart, 45 * WAD);

        d3mTestPlan.file("targetAssets", 100 * WAD);
        d3mHub.exec(ilk);

        (opink, opart) = vat.urns(ilk, address(d3mTestPool));
        assertEq(opink, 0);
        assertEq(opart, 0);

        (npink, npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 100 * WAD);
        assertEq(npart, 100 * WAD);
    }

    function test_plan_upgrade() public {
        _windSystem(); // Tests that the current pool has ink/art

        // Setup new plan
        D3MTestPlan newPlan = new D3MTestPlan(address(dai));
        newPlan.file("maxBar_", type(uint256).max);
        newPlan.file("bar", 5);
        newPlan.file("targetAssets", 100 * WAD);

        d3mHub.file(ilk, "plan", address(newPlan));

        (, ID3MPlan plan, , , ) = d3mHub.ilks(ilk);
        assertEq(address(plan), address(newPlan));
        
        d3mHub.exec(ilk);

        // New Plan should determine the pool position
        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 100 * WAD);
        assertEq(art, 100 * WAD);
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function test_hub_upgrade_same_d3ms() public {
        _windSystem(); // Tests that the current pool has ink/art

        // Setup New hub
        D3MHub newHub = new D3MHub(address(vat), address(daiJoin));
        newHub.file("vow", vow);
        newHub.file("end", address(end));

        newHub.file(ilk, "pool", address(d3mTestPool));
        newHub.file(ilk, "plan", address(d3mTestPlan));
        newHub.file(ilk, "tau", 7 days);

        // Update permissions on d3ms
        d3mTestPool.rely(address(newHub));
        d3mTestPool.deny(address(d3mHub));
        d3mTestPool.hope(address(newHub));
        d3mTestPool.nope(address(d3mHub));
        
        // Update Permissions in Vat
        vat.deny(address(d3mHub));
        vat.rely(address(newHub));
        d3mHub.nope();

        // Clean up old hub
        d3mHub.file(ilk, "pool", address(0));
        d3mHub.file(ilk, "plan", address(0));
        d3mHub.file(ilk, "tau", 0);

        // Ensure new hub operation
        d3mTestPlan.file("bar", 10);
        d3mTestPlan.file("targetAssets", 100 * WAD);
        newHub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(d3mTestPool));
        assertEq(ink, 100 * WAD);
        assertEq(art, 100 * WAD);
        assertTrue(d3mTestPool.preDebt());
        assertTrue(d3mTestPool.postDebt());
    }

    function testFail_hub_upgrade_kills_old_hub() public {
        _windSystem(); // Tests that the current pool has ink/art

        // Setup New hub
        D3MHub newHub = new D3MHub(address(vat), address(daiJoin));
        newHub.file("vow", vow);
        newHub.file("end", address(end));

        newHub.file(ilk, "pool", address(d3mTestPool));
        newHub.file(ilk, "plan", address(d3mTestPlan));
        newHub.file(ilk, "tau", 7 days);

        // Update permissions on d3ms
        d3mTestPool.rely(address(newHub));
        d3mTestPool.deny(address(d3mHub));
        d3mTestPool.hope(address(newHub));
        d3mTestPool.nope(address(d3mHub));
        
        // Update Permissions in Vat
        vat.deny(address(d3mHub));
        vat.rely(address(newHub));
        d3mHub.nope();

        // Clean up old hub
        d3mHub.file(ilk, "pool", address(0));
        d3mHub.file(ilk, "plan", address(0));
        d3mHub.file(ilk, "tau", 0);

        // Ensure old hub revert
        d3mHub.exec(ilk);
    }

    function test_hub_upgrade_new_d3ms() public {
        _windSystem(); // Tests that the current pool has ink/art

        // Setup New hub and D3M
        D3MHub newHub = new D3MHub(address(vat), address(daiJoin));
        newHub.file("vow", vow);
        newHub.file("end", address(end));
        vat.rely(address(newHub));

        // Setup new pool
        D3MTestPool newPool = new D3MTestPool(
            address(newHub),
            address(dai),
            address(testGem),
            address(rewardsClaimer)
        );
        newPool.rely(address(newHub));
        testGem.rely(address(newPool));
        testGem.giveAllowance(
            address(dai),
            address(newPool),
            type(uint256).max
        );

        // Setup new plan
        D3MTestPlan newPlan = new D3MTestPlan(address(dai));
        newPlan.file("maxBar_", type(uint256).max);
        newPlan.file("bar", 5);
        newPlan.file("targetAssets", 100 * WAD);

        // Create D3M in New Hub
        newHub.file(ilk, "pool", address(newPool));
        newHub.file(ilk, "plan", address(newPlan));
        (, , uint256 tau, , ) = d3mHub.ilks(ilk);
        newHub.file(ilk, "tau", tau);

        (uint256 npink, uint256 npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 0);
        assertEq(npart, 0);
        assertTrue(newPool.preDebt() == false);
        assertTrue(newPool.postDebt() == false);

        // Transition Balances
        newPool.hope(address(d3mHub));
        d3mHub.quit(ilk, address(newPool));
        newPool.nope(address(d3mHub));

        // Ensure we quit our position
        (uint256 opink, uint256 opart) = vat.urns(ilk, address(d3mTestPool));
        assertEq(opink, 0);
        assertEq(opart, 0);
        // quit does not call hooks
        assertTrue(d3mTestPool.preDebt() == false);
        assertTrue(d3mTestPool.postDebt() == false);

        (npink, npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 50 * WAD);
        assertEq(npart, 50 * WAD);
        assertTrue(newPool.preDebt() == false);
        assertTrue(newPool.postDebt() == false);
        
        // Clean up after transition
        d3mHub.cage(ilk);
        d3mTestPool.deny(address(d3mHub));
        d3mTestPool.nope(address(d3mHub));
        vat.deny(address(d3mHub));
        d3mHub.nope();

        // Ensure new hub operation
        newPlan.file("bar", 10);
        newPlan.file("targetAssets", 200 * WAD);
        newHub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(newPool));
        assertEq(ink, 200 * WAD);
        assertEq(art, 200 * WAD);
        assertTrue(newPool.preDebt());
        assertTrue(newPool.postDebt());
    }

    function cmpStr(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function test_exec_lock_protection() public {
        // Store memory slot 0x4
        hevm.store(address(d3mHub), bytes32(uint256(3)), bytes32(uint256(1)));
        assertEq(d3mHub.locked(), 1);

        try d3mHub.exec(ilk) {}
        catch Error(string memory errmsg) {
            bytes32 locked = hevm.load(address(d3mHub), bytes32(uint256(3))); // Load memory slot 0x3 from Hub
            assertTrue(uint256(locked) == 1);
            assertTrue(cmpStr(errmsg, "D3MHub/system-locked"));
        }
    }

    function test_reap_lock_protection() public {
        // Store memory slot 0x4
        hevm.store(address(d3mHub), bytes32(uint256(3)), bytes32(uint256(1)));
        assertEq(d3mHub.locked(), 1);

        try d3mHub.reap(ilk) {}
        catch Error(string memory errmsg) {
            bytes32 locked = hevm.load(address(d3mHub), bytes32(uint256(3))); // Load memory slot 0x3 from Hub
            assertTrue(uint256(locked) == 1);
            assertTrue(cmpStr(errmsg, "D3MHub/system-locked"));
        }
    }

    function test_exit_lock_protection() public {
        // Store memory slot 0x4
        hevm.store(address(d3mHub), bytes32(uint256(3)), bytes32(uint256(1)));
        assertEq(d3mHub.locked(), 1);

        try d3mHub.exit(ilk, address(this), 1) {}
        catch Error(string memory errmsg) {
            bytes32 locked = hevm.load(address(d3mHub), bytes32(uint256(3))); // Load memory slot 0x3 from Hub
            assertTrue(uint256(locked) == 1);
            assertTrue(cmpStr(errmsg, "D3MHub/system-locked"));
        }
    }

    function test_quit_lock_protection() public {
        // Store memory slot 0x4
        hevm.store(address(d3mHub), bytes32(uint256(3)), bytes32(uint256(1)));
        assertEq(d3mHub.locked(), 1);

        try d3mHub.quit(ilk, address(this)) {}
        catch Error(string memory errmsg) {
            bytes32 locked = hevm.load(address(d3mHub), bytes32(uint256(3))); // Load memory slot 0x3 from Hub
            assertTrue(uint256(locked) == 1);
            assertTrue(cmpStr(errmsg, "D3MHub/system-locked"));
        }
    }
}
