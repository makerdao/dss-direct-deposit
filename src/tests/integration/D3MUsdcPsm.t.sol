// SPDX-FileCopyrightText: © 2021 Dai Foundation <www.daifoundation.org>
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

import {DSSTest} from "dss-test/DSSTest.sol";
import "../interfaces/interfaces.sol";

import { D3MHub } from "../../D3MHub.sol";
import { D3MMom } from "../../D3MMom.sol";
import { D3MOracle } from "../../D3MOracle.sol";

import { D3MUsdcPsmPlan } from "../../plans/D3MUsdcPsmPlan.sol";
import { D3MUsdcPsmPool } from "../../pools/D3MUsdcPsmPool.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external view returns (bytes32);
}

interface PsmLike {
    function gemJoin() external view returns (address);
    function buyGem(address, uint256) external;
    function sellGem(address, uint256) external;
}

contract D3MUsdcPsmTest is DSSTest {
    VatLike vat;
    EndLike end;
    DaiLike dai;
    DaiJoinLike daiJoin;
    PsmLike psm;
    TokenLike usdc;
    SpotLike spot;
    TokenLike weth;
    address vow;
    address pauseProxy;

    bytes32 constant ilk = "DD-PSM-USDC";
    D3MHub d3mHub;
    D3MUsdcPsmPool d3mUsdcPsmPool;
    D3MUsdcPsmPlan d3mUsdcPsmPlan;
    D3MMom d3mMom;
    D3MOracle pip;

    function setUp() public override {
        emit log_named_uint("block", block.number);
        emit log_named_uint("timestamp", block.timestamp);

        vat = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        end = EndLike(0x0e2e8F1D1326A4B9633D96222Ce399c708B19c28);
        psm = PsmLike(0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A);
        usdc = TokenLike(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        dai = DaiLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        daiJoin = DaiJoinLike(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
        spot = SpotLike(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);
        vow = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;
        pauseProxy = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

        // Force give admin access to these contracts via vm magic
        _giveAuthAccess(address(vat), address(this));
        _giveAuthAccess(address(end), address(this));
        _giveAuthAccess(address(spot), address(this));

        d3mHub = new D3MHub(address(daiJoin));
        d3mUsdcPsmPool = new D3MUsdcPsmPool(ilk, address(d3mHub), address(dai), address(psm));
        d3mUsdcPsmPool.rely(address(d3mHub));
        d3mUsdcPsmPlan = new D3MUsdcPsmPlan();

        d3mHub.file(ilk, "pool", address(d3mUsdcPsmPool));
        d3mHub.file(ilk, "plan", address(d3mUsdcPsmPlan));
        d3mHub.file(ilk, "tau", 7 days);

        d3mHub.file("vow", vow);
        d3mHub.file("end", address(end));

        d3mMom = new D3MMom();
        d3mUsdcPsmPlan.rely(address(d3mMom));

        // Init new collateral
        pip = new D3MOracle(address(vat), ilk);
        pip.file("hub", address(d3mHub));
        spot.file(ilk, "pip", address(pip));
        spot.file(ilk, "mat", RAY);
        spot.poke(ilk);

        vat.rely(address(d3mHub));
        vat.init(ilk);
        vat.file(ilk, "line", 5_000_000_000 * RAD);
        vat.file("Line", vat.Line() + 5_000_000_000 * RAD);

        dai.approve(address(psm), type(uint256).max);
    }

    // --- Math ---
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }

    function _giveAuthAccess(address _base, address target) internal {
        AuthLike base = AuthLike(_base);

        // Edge case - ward is already set
        if (base.wards(target) == 1) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the ward storage slot
            bytes32 prevValue = vm.load(
                address(base),
                keccak256(abi.encode(target, uint256(i)))
            );
            vm.store(
                address(base),
                keccak256(abi.encode(target, uint256(i))),
                bytes32(uint256(1))
            );
            if (base.wards(target) == 1) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                vm.store(
                    address(base),
                    keccak256(abi.encode(target, uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function _giveTokens(TokenLike token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (token.balanceOf(address(this)) == amount) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = vm.load(
                address(token),
                keccak256(abi.encode(address(this), uint256(i)))
            );
            vm.store(
                address(token),
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (token.balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                vm.store(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function test_target_increase() public {
        uint256 prevUsdcPsm = usdc.balanceOf(psm.gemJoin());
        uint256 prevUsdcPool = usdc.balanceOf(address(d3mUsdcPsmPool));

        assertEq(prevUsdcPool, 0);
        uint256 target = 1_600_000_000 * 10**6;
        assertGt(prevUsdcPsm, target);

        d3mUsdcPsmPlan.file("amt", target);
        d3mHub.exec(ilk);

        assertEq(usdc.balanceOf(psm.gemJoin()), prevUsdcPsm - target);
        assertEq(usdc.balanceOf(address(d3mUsdcPsmPool)), target);
    }

    function test_target_decrease() public {
        uint256 prevUsdcPsm = usdc.balanceOf(psm.gemJoin());
        uint256 prevUsdcPool = usdc.balanceOf(address(d3mUsdcPsmPool));

        assertEq(prevUsdcPool, 0);

        uint256 target = 1_600_000_000 * 10**6;
        d3mUsdcPsmPlan.file("amt", target);
        d3mHub.exec(ilk);

        assertEq(usdc.balanceOf(psm.gemJoin()), prevUsdcPsm - target);
        assertEq(usdc.balanceOf(address(d3mUsdcPsmPool)), target);

        target = 1;
        d3mUsdcPsmPlan.file("amt", target);
        d3mHub.exec(ilk);

        assertEq(usdc.balanceOf(psm.gemJoin()), prevUsdcPsm - 1);
        assertEq(usdc.balanceOf(address(d3mUsdcPsmPool)), 1);
    }


    function test_cage_exit() public {
        uint256 target = 1_600_000_000 * 10**6;
        d3mUsdcPsmPlan.file("amt", target);
        d3mHub.exec(ilk);

        // Vat is caged for global settlement
        end.cage();
        end.cage(ilk);
        end.skim(ilk, address(d3mUsdcPsmPool));

        // Simulate DAI holder gets some gems from GS
        vm.prank(address(end));
        vat.flux(ilk, address(end), address(this), 100 ether);

        uint256 totalArt = end.Art(ilk);

        assertEq(usdc.balanceOf(address(this)), 0);

        // User can exit and get the USDC
        uint256 expectedUsdc = 100 ether * (usdc.balanceOf(address(d3mUsdcPsmPool)) * 10**12) / totalArt;
        d3mHub.exit(ilk, address(this), 100 ether);
        assertEq(expectedUsdc, 100 ether);
        assertEq(usdc.balanceOf(address(this)) * 10**12, expectedUsdc);
    }
}
