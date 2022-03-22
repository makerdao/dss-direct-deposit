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
import "dss-interfaces/Interfaces.sol";
import "ds-value/value.sol";

import {DssDirectDepositHub, DssDirectDepositPoolLike} from "./DssDirectDepositHub.sol";
import {DssDirectDepositMom} from "./DssDirectDepositMom.sol";

import {DssDirectDepositTestPool} from "./test-stubs/DssDirectDepositTestPool.sol";
import {DssDirectDepositTestPlan} from "./test-stubs/DssDirectDepositTestPlan.sol";
import {DssDirectDepositTestGem} from "./test-stubs/DssDirectDepositTestGem.sol";
import {DssDirectDepositTestRewards} from "./test-stubs/DssDirectDepositTestRewards.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;

    function load(address, bytes32) external view returns (bytes32);
}

interface AuthLike {
    function wards(address) external returns (uint256);
}

contract DssDirectDepositHubTest is DSTest {
    uint256 constant WAD = 10**18;
    uint256 constant RAY = 10**27;
    uint256 constant RAD = 10**45;

    Hevm hevm;

    ChainlogAbstract chainlog;
    VatAbstract vat;
    EndAbstract end;
    DssDirectDepositTestRewards rewardsClaimer;
    DaiAbstract dai;
    DaiJoinAbstract daiJoin;
    DssDirectDepositTestGem testGem;
    DSTokenAbstract testReward;
    SpotAbstract spot;
    DSTokenAbstract weth;
    address vow;
    address pauseProxy;

    bytes32 constant ilk = "DD-DAI-TEST";
    DssDirectDepositHub directDepositHub;
    DssDirectDepositTestPool directDepositTestPool;
    DssDirectDepositTestPlan directDepositTestPlan;
    DssDirectDepositMom directDepositMom;
    DSValue pip;

    // Allow for a 1 BPS margin of error on interest rates
    uint256 constant INTEREST_RATE_TOLERANCE = RAY / 10000;
    uint256 constant EPSILON_TOLERANCE = 4;

    function setUp() public {
        hevm = Hevm(
            address(bytes20(uint160(uint256(keccak256("hevm cheat code")))))
        );

        chainlog = ChainlogAbstract(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
        vat = VatAbstract(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        end = EndAbstract(0xBB856d1742fD182a90239D7AE85706C2FE4e5922);
        dai = DaiAbstract(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        daiJoin = DaiJoinAbstract(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
        spot = SpotAbstract(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);
        weth = DSTokenAbstract(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        vow = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;
        pauseProxy = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

        // Force give admin access to these contracts via hevm magic
        _giveAuthAccess(address(vat), address(this));
        _giveAuthAccess(address(end), address(this));
        _giveAuthAccess(address(spot), address(this));

        testGem = new DssDirectDepositTestGem(18);
        directDepositHub = new DssDirectDepositHub(address(chainlog));
        directDepositHub.file(ilk, "gem", address(testGem));

        rewardsClaimer = new DssDirectDepositTestRewards(address(testGem));
        directDepositTestPool = new DssDirectDepositTestPool(
            address(directDepositHub),
            address(daiJoin),
            address(123),
            address(rewardsClaimer)
        );
        directDepositTestPool.hope(address(vat), address(daiJoin));
        directDepositTestPlan = new DssDirectDepositTestPlan(address(dai), address(123));
        directDepositTestPool.file("plan", address(directDepositTestPlan));

        // Test Target Setup
        testGem.rely(address(directDepositTestPool));
        directDepositTestPlan.file("maxBar_", type(uint256).max);
        directDepositTestPool.file("share", address(testGem));
        directDepositTestPool.file("isValidTarget", true);
        testGem.giveAllowance(
            address(dai),
            address(directDepositTestPool),
            type(uint256).max
        );

        directDepositHub.file(ilk, "tau", 7 days);
        directDepositHub.file(ilk, "pool", address(directDepositTestPool));
        directDepositMom = new DssDirectDepositMom();
        directDepositHub.rely(address(directDepositMom));

        // Init new collateral
        pip = new DSValue();
        pip.poke(bytes32(WAD));
        spot.file(ilk, "pip", address(pip));
        spot.file(ilk, "mat", RAY);
        spot.poke(ilk);

        vat.rely(address(directDepositHub));
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

    function _giveTokens(DSTokenAbstract token, uint256 amount) internal {
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

    function _windSystem() internal {
        directDepositTestPool.file("bar", 10);
        directDepositTestPlan.file("totalAssets", 50 * WAD);
        directDepositTestPlan.file("targetAssets", 100 * WAD);
        directDepositHub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
    }

    function test_approvals() public {
        assertEq(
            dai.allowance(address(directDepositTestPool), address(daiJoin)),
            type(uint256).max
        );
    }

    // function test_can_file_bar() public {
    //     (, , , uint256 bar, , , ) = directDepositHub.ilks(ilk);
    //     assertEq(bar, 0);
    //     directDepositHub.file(ilk, "bar", 1);
    //     (, , , bar, , , ) = directDepositHub.ilks(ilk);
    //     assertEq(bar, 1);
    // }

    function test_can_file_tau() public {
        (, , uint256 tau, , ) = directDepositHub.ilks(ilk);
        assertEq(tau, 7 days);
        directDepositHub.file(ilk, "tau", 1 days);
        (, , tau, , ) = directDepositHub.ilks(ilk);
        assertEq(tau, 1 days);
    }

    function testFail_unauth_file_tau() public {
        directDepositHub.deny(address(this));

        directDepositHub.file(ilk, "tau", 1 days);
    }

    function testFail_hub_not_live_tau_file() public {
        directDepositHub.file(ilk, "tau", 1 days);
        (, , uint256 tau, , ) = directDepositHub.ilks(ilk);
        assertEq(tau, 1 days);

        // Cage Join
        directDepositHub.cage();

        directDepositHub.file(ilk, "tau", 7 days);
    }

    function testFail_pool_not_live_tau_file() public {
        directDepositHub.file(ilk, "tau", 1 days);
        (, , uint256 tau, , ) = directDepositHub.ilks(ilk);
        assertEq(tau, 1 days);

        // Cage Join
        directDepositHub.cage(ilk);

        directDepositHub.file(ilk, "tau", 7 days);
    }

    function testFail_unknown_uint256_file() public {
        directDepositHub.file(ilk, "unknown", 1);
    }

    // function testFail_unauth_file_bar() public {
    //     directDepositHub.deny(address(this));

    //     directDepositHub.file(ilk, "bar", 1);
    // }

    // function testFail_bar_file_too_high() public {
    //     directDepositTestPlan.file("maxBar", 1);

    //     directDepositTestPool.file("bar", 1);

    //     assertEq(directDepositTestPool.bar(), 1);

    //     directDepositTestPool.file("bar", 2);
    // }

    // function test_can_file_king() public {
    //     (, , , , , address king, ) = directDepositHub.ilks(ilk);
    //     assertEq(king, address(0));

    //     directDepositHub.file(ilk, "king", address(this));

    //     (, , , , , king, ) = directDepositHub.ilks(ilk);
    //     assertEq(king, address(this));
    // }

    function test_can_file_pool() public {
        (DssDirectDepositPoolLike pool, , , , ) = directDepositHub.ilks(
            ilk
        );

        assertEq(address(pool), address(directDepositTestPool));

        directDepositHub.file(ilk, "pool", address(this));

        (pool, , , , ) = directDepositHub.ilks(ilk);
        assertEq(address(pool), address(this));
    }

    // function testFail_unauth_file_king() public {
    //     directDepositHub.deny(address(this));

    //     directDepositHub.file(ilk, "king", address(this));
    // }

    // function testFail_pool_not_live_king_file() public {
    //     directDepositHub.file(ilk, "king", address(this));
    //     (, , , , , address king, ) = directDepositHub.ilks(ilk);
    //     assertEq(king, address(this));

    //     // Cage Join
    //     directDepositHub.cage(ilk);

    //     directDepositHub.file(ilk, "king", address(123));
    // }

    function testFail_unauth_file_pool() public {
        directDepositHub.deny(address(this));

        directDepositHub.file(ilk, "pool", address(this));
    }

    function testFail_hub_not_live_pool_file() public {
        // Cage Pool
        directDepositHub.cage(ilk);

        directDepositHub.file(ilk, "pool", address(123));
    }

    function testFail_hub_not_live_gem_file() public {
        // Cage Pool
        directDepositHub.cage(ilk);

        directDepositHub.file(ilk, "gem", address(123));
    }

    function testFail_unknown_address_file() public {
        directDepositHub.file(ilk, "unknown", address(123));
    }

    function testFail_vat_not_live_address_file() public {
        directDepositHub.file(ilk, "pool", address(this));
        (DssDirectDepositPoolLike pool, , , ,) = directDepositHub.ilks(ilk);

        assertEq(address(pool), address(this));

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        directDepositHub.file(ilk, "pool", address(123));
    }

    function test_wind_amount_less_target() public {
        directDepositTestPool.file("bar", 10);
        directDepositTestPlan.file("totalAssets", 50 * WAD);
        directDepositTestPlan.file("targetAssets", 100 * WAD);

        (uint256 pink, uint256 part) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(pink, 0);
        assertEq(part, 0);
        assertEq(dai.balanceOf(address(testGem)), 0);

        directDepositHub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(dai.balanceOf(address(testGem)), 50 * WAD);
        assertEq(testGem.balanceOf(address(directDepositTestPool)), 50 * WAD);
    }

    function test_unwind_bar_zero() public {
        _windSystem();

        // Temporarily disable the module
        directDepositTestPool.file("bar", 0);
        directDepositHub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function test_unwind_mcd_caged() public {
        _windSystem();

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        directDepositHub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function test_unwind_module_caged() public {
        _windSystem();

        // Module caged
        directDepositHub.cage();

        directDepositHub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(ink, 0);
        assertEq(art, 0);
    }

    function test_unwind_target_less_amount() public {
        _windSystem();

        (uint256 pink, uint256 part) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(pink, 50 * WAD);
        assertEq(part, 50 * WAD);

        directDepositTestPlan.file("targetAssets", 75 * WAD);
        directDepositTestPlan.file("totalAssets", 100 * WAD);

        directDepositHub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(ink, 25 * WAD);
        assertEq(art, 25 * WAD);
    }

    function test_reap_available_liquidity() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        _giveTokens(DSTokenAbstract(address(testGem)), 10 * WAD);
        testGem.transfer(address(directDepositTestPool), 10 * WAD);

        (, uint256 part) = vat.urns(ilk, address(directDepositTestPool));
        assertEq(part, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        directDepositHub.reap(ilk);

        (, uint256 art) = vat.urns(ilk, address(directDepositTestPool));
        assertEq(art, 50 * WAD);
        uint256 currentDai = vat.dai(vow);
        assertEq(currentDai, prevDai + 10 * RAD); // Interest shows up in vat Dai for the Vow [rad]
    }

    function test_reap_not_enough_liquidity() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        _giveTokens(DSTokenAbstract(address(testGem)), 55 * WAD);
        testGem.transfer(address(directDepositTestPool), 10 * WAD);

        (, uint256 part) = vat.urns(ilk, address(directDepositTestPool));
        assertEq(part, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        // If we do not have enough liquidity then we pull out what we can for the fees
        // This will pull out all but 5 WAD of the liquidity
        assertEq(dai.balanceOf(address(testGem)), 50 * WAD); // liquidity before simulating other user's withdraw
        testGem.giveAllowance(address(dai), address(this), type(uint256).max);
        dai.transferFrom(address(testGem), address(this), 45 * WAD);
        assertEq(dai.balanceOf(address(testGem)), 5 * WAD); // liquidity after

        directDepositHub.reap(ilk);

        (, uint256 art) = vat.urns(ilk, address(directDepositTestPool));
        assertEq(art, 50 * WAD);
        uint256 currentDai = vat.dai(vow);
        assertEq(currentDai, prevDai + 5 * RAD); // Interest shows up in vat Dai for the Vow [rad]
    }

    function testFail_no_reap_mcd_caged() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        _giveTokens(DSTokenAbstract(address(testGem)), 10 * WAD);
        testGem.transfer(address(directDepositTestPool), 10 * WAD);

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        directDepositHub.reap(ilk);
    }

    function testFail_no_reap_module_caged() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        _giveTokens(DSTokenAbstract(address(testGem)), 10 * WAD);
        testGem.transfer(address(directDepositTestPool), 10 * WAD);

        // module caged
        directDepositHub.cage();

        directDepositHub.reap(ilk);
    }

    function test_collect() public {
        address rewardToken = address(rewardsClaimer.rewards());
        directDepositTestPool.file("king", address(pauseProxy));

        assertEq(
            DSTokenAbstract(rewardToken).balanceOf(address(pauseProxy)),
            0
        );

        address[] memory tokens = new address[](1);
        tokens[0] = address(testGem);
        directDepositHub.collect(ilk, tokens, 10 * WAD);

        assertEq(
            DSTokenAbstract(rewardToken).balanceOf(address(pauseProxy)),
            10 * WAD
        );
    }

    function testFail_collect_no_king() public {
        address rewardToken = address(rewardsClaimer.rewards());

        assertEq(
            DSTokenAbstract(rewardToken).balanceOf(address(pauseProxy)),
            0
        );

        address[] memory tokens = new address[](1);
        tokens[0] = address(testGem);
        directDepositHub.collect(ilk, tokens, 10 * WAD);
    }

    function test_exit() public {
        _windSystem();
        // Vat is caged for global settlement
        vat.cage();

        // Simulate DAI holder gets some gems from GS
        vat.grab(
            ilk,
            address(directDepositTestPool),
            address(this),
            address(this),
            -int256(50 * WAD),
            -int256(0)
        );

        uint256 prevBalance = testGem.balanceOf(address(this));

        // User can exit and get the aDAI
        directDepositHub.exit(ilk, address(this), 50 * WAD);
        assertEq(testGem.balanceOf(address(this)), prevBalance + 50 * WAD);
    }

    function test_cage_hub() public {
        assertEq(directDepositHub.live(), 1);

        directDepositHub.cage();

        assertEq(directDepositHub.live(), 0);
    }

    function testFail_cage_no_auth() public {
        directDepositHub.deny(address(this));
        directDepositHub.cage();
    }

    function test_cage_pool() public {
        (, , , , uint256 tic) = directDepositHub.ilks(ilk);
        assertEq(tic, 0);
        assertEq(directDepositTestPool.live(), 1);

        directDepositHub.cage(ilk);

        (, , , , tic) = directDepositHub.ilks(ilk);
        assertEq(tic, block.timestamp);
        assertEq(directDepositTestPool.live(), 0);
    }

    function testFail_cage_pool_no_auth() public {
        directDepositHub.deny(address(this));
        directDepositHub.cage(ilk);
    }

    function test_cage_pool_invalid_target() public {
        (, , , , uint256 tic) = directDepositHub.ilks(ilk);
        assertEq(tic, 0);
        assertEq(directDepositTestPool.live(), 1);

        // We should not need permission for this
        directDepositHub.deny(address(this));
        // Simulate some condition on the target that makes it invalid
        directDepositTestPool.file("isValidTarget", false);

        directDepositHub.cage(ilk);

        (, , , , tic) = directDepositHub.ilks(ilk);
        assertEq(tic, block.timestamp);
        assertEq(directDepositTestPool.live(), 0);
    }

    function test_cage_pool_hub_caged() public {
        (, , , , uint256 tic) = directDepositHub.ilks(ilk);
        assertEq(tic, 0);
        assertEq(directDepositTestPool.live(), 1);

        directDepositHub.cage();
        // We should not need permission for this
        directDepositHub.deny(address(this));

        directDepositHub.cage(ilk);

        (, , , , tic) = directDepositHub.ilks(ilk);
        assertEq(tic, block.timestamp);
        assertEq(directDepositTestPool.live(), 0);
    }


    function test_cull() public {
        _windSystem();
        directDepositHub.cage();
        directDepositHub.cage(ilk);

        (uint256 pink, uint256 part) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(pink, 50 * WAD);
        assertEq(part, 50 * WAD);
        uint256 gemBefore = vat.gem(ilk, address(directDepositTestPool));
        assertEq(gemBefore, 0);
        uint256 sinBefore = vat.sin(vow);

        directDepositHub.cull(ilk);

        (uint256 ink, uint256 art) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(ink, 0);
        assertEq(art, 0);
        uint256 gemAfter = vat.gem(ilk, address(directDepositTestPool));
        assertEq(gemAfter, 50 * WAD);
        assertEq(sinBefore + 50 * RAD, vat.sin(vow));
        (, , , uint256 culled, ) = directDepositHub.ilks(ilk);
        assertEq(culled, 1);
    }

    function test_cull_no_auth_time_passed() public {
        _windSystem();
        directDepositHub.cage();
        directDepositHub.cage(ilk);
        // with auth we can cull anytime
        directDepositHub.deny(address(this));
        // but with enough time, anyone can cull
        hevm.warp(block.timestamp + 7 days);

        (uint256 pink, uint256 part) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(pink, 50 * WAD);
        assertEq(part, 50 * WAD);
        uint256 gemBefore = vat.gem(ilk, address(directDepositTestPool));
        assertEq(gemBefore, 0);
        uint256 sinBefore = vat.sin(vow);

        directDepositHub.cull(ilk);

        (uint256 ink, uint256 art) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(ink, 0);
        assertEq(art, 0);
        uint256 gemAfter = vat.gem(ilk, address(directDepositTestPool));
        assertEq(gemAfter, 50 * WAD);
        assertEq(sinBefore + 50 * RAD, vat.sin(vow));
        (, , , uint256 culled, ) = directDepositHub.ilks(ilk);
        assertEq(culled, 1);
    }

    function testFail_no_cull_mcd_caged() public {
        _windSystem();
        directDepositHub.cage();
        directDepositHub.cage(ilk);
        vat.cage();

        directDepositHub.cull(ilk);
    }

    function testFail_no_cull_hub_live() public {
        _windSystem();
        directDepositHub.cage(ilk);

        directDepositHub.cull(ilk);
    }

    function testFail_no_cull_module_live() public {
        _windSystem();
        directDepositHub.cage();

        directDepositHub.cull(ilk);
    }

    function testFail_no_cull_unauth_too_soon() public {
        _windSystem();
        directDepositHub.cage();
        directDepositHub.cage(ilk);
        directDepositHub.deny(address(this));
        hevm.warp(block.timestamp + 6 days);

        directDepositHub.cull(ilk);
    }

    function testFail_no_cull_already_culled() public {
        _windSystem();
        directDepositHub.cage();
        directDepositHub.cage(ilk);

        directDepositHub.cull(ilk);
        directDepositHub.cull(ilk);
    }

    function test_uncull() public {
        _windSystem();
        directDepositHub.cage();
        directDepositHub.cage(ilk);

        directDepositHub.cull(ilk);
        (uint256 pink, uint256 part) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(pink, 0);
        assertEq(part, 0);
        uint256 gemBefore = vat.gem(ilk, address(directDepositTestPool));
        assertEq(gemBefore, 50 * WAD);
        uint256 sinBefore = vat.sin(vow);
        (, , , uint256 culled, ) = directDepositHub.ilks(ilk);
        assertEq(culled, 1);

        vat.cage();
        directDepositHub.uncull(ilk);

        (uint256 ink, uint256 art) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        uint256 gemAfter = vat.gem(ilk, address(directDepositTestPool));
        assertEq(gemAfter, 0);
        // Sin should not change since we suck before grabbing
        assertEq(sinBefore, vat.sin(vow));
        (, , , culled, ) = directDepositHub.ilks(ilk);
        assertEq(culled, 0);
    }

    function testFail_no_uncull_not_culled() public {
        _windSystem();
        directDepositHub.cage();
        directDepositHub.cage(ilk);

        vat.cage();
        directDepositHub.uncull(ilk);
    }

    function testFail_no_uncull_mcd_live() public {
        _windSystem();
        directDepositHub.cage();
        directDepositHub.cage(ilk);

        directDepositHub.cull(ilk);

        directDepositHub.uncull(ilk);
    }

    function test_quit_culled() public {
        _windSystem();
        directDepositHub.cage();
        directDepositHub.cage(ilk);

        directDepositHub.cull(ilk);

        uint256 balBefore = testGem.balanceOf(address(this));
        assertEq(50 * WAD, testGem.balanceOf(address(directDepositTestPool)));
        assertEq(50 * WAD, vat.gem(ilk, address(directDepositTestPool)));

        directDepositHub.quit(ilk, address(this));

        assertEq(balBefore + 50 * WAD, testGem.balanceOf(address(this)));
        assertEq(0, testGem.balanceOf(address(directDepositTestPool)));
        assertEq(0, vat.gem(ilk, address(directDepositTestPool)));
    }

    function test_quit_not_culled() public {
        _windSystem();
        vat.hope(address(directDepositHub));

        uint256 balBefore = testGem.balanceOf(address(this));
        assertEq(50 * WAD, testGem.balanceOf(address(directDepositTestPool)));
        (uint256 pink, uint256 part) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(pink, 50 * WAD);
        assertEq(part, 50 * WAD);
        (uint256 tink, uint256 tart) = vat.urns(ilk, address(this));
        assertEq(tink, 0);
        assertEq(tart, 0);

        directDepositHub.quit(ilk, address(this));

        assertEq(balBefore + 50 * WAD, testGem.balanceOf(address(this)));
        (uint256 joinInk, uint256 joinArt) = vat.urns(
            ilk,
            address(directDepositTestPool)
        );
        assertEq(joinInk, 0);
        assertEq(joinArt, 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(this));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
    }

    function testFail_no_quit_not_culled_who_not_accepting() public {
        _windSystem();

        directDepositHub.quit(ilk, address(this));
    }

    function testFail_no_quit_mcd_caged() public {
        _windSystem();
        directDepositHub.cull(ilk);

        vat.cage();
        directDepositHub.quit(ilk, address(this));
    }

    function testFail_no_quit_no_auth() public {
        _windSystem();
        directDepositHub.cull(ilk);

        directDepositHub.deny(address(this));
        directDepositHub.quit(ilk, address(this));
    }
}
