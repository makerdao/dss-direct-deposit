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

import "./D3MPoolBase.t.sol";

import { D3MCompoundV2TypePool } from "../../pools/D3MCompoundV2TypePool.sol";

interface CErc20Like {
    function balanceOf(address owner) external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function comptroller() external view returns (address);
    function balanceOfUnderlying(address owner) external returns (uint256);
}

interface ComptrollerLike {
    function compBorrowSpeeds(address cToken) external view returns (uint256);
}

interface LensLike {
    function getCompBalanceMetadataExt(address comp, address comptroller, address account) external returns (uint256, uint256, address, uint256);
}

contract D3MCompoundV2TypePoolTest is D3MPoolBaseTest {

    bytes32 constant ILK = "TEST-ILK";

    CErc20Like            cDai;
    D3MCompoundV2TypePool pool;
    ComptrollerLike       comptroller;
    GemAbstract           comp;
    LensLike              lens;

    function _wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * WAD / y;
    }

    function _assertEqApprox(uint256 _a, uint256 _b) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > b / 10 ** 9) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        baseInit("D3MCompoundV2TypePool");

        // TODO these should be mocked
        dai         = TokenMock(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        cDai        = CErc20Like(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        comptroller = ComptrollerLike(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
        comp        = GemAbstract(0xc00e94Cb662C3520282E6f5717214004A7f26888);
        lens        = LensLike(0xdCbDb7306c6Ff46f77B349188dC18cEd9DF30299);

        setPoolContract(pool = new D3MCompoundV2TypePool(ILK, address(hub), address(cDai)));

        // allocate some dai for the pool
        GodMode.setBalance(address(dai), address(pool), 100 * WAD);
    }

    function test_sets_dai_value() public {
        assertEq(address(pool.dai()), address(dai));
    }

    function test_sets_cdai_value() public {
        assertEq(address(pool.cDai()), address(cDai));
    }

    function test_sets_comptroller_value() public {
        assertEq(address(pool.comptroller()), address(comptroller));
    }

    function test_can_file_king() public {
        assertEq(address(pool.king()), address(0));

        pool.file("king", address(123));
        assertEq(address(pool.king()), address(123));
    }

    function test_cannot_file_king_no_auth() public {
        pool.deny(address(this));
        assertRevert(address(pool), abi.encodeWithSignature("file(bytes32,address)", bytes32("king"), address(123)), "D3MCompoundV2TypePool/not-authorized");
    }

    function test_cannot_file_king_vat_caged() public {
        vat.cage();
        assertRevert(address(pool), abi.encodeWithSignature("file(bytes32,address)", bytes32("king"), address(123)), "D3MCompoundV2TypePool/no-file-during-shutdown");
    }

    function test_deposit_calls_cdai_deposit() public {
        assertEq(cDai.balanceOfUnderlying(address(pool)), 0);
        assertEq(cDai.balanceOf(address(pool)), 0);
        uint256 poolBefore = dai.balanceOf(address(pool));

        vm.prank(address(hub)); pool.deposit(1 * WAD);

        _assertEqApprox(cDai.balanceOfUnderlying(address(pool)), 1 * WAD);
        assertGt(cDai.balanceOf(address(pool)), 0);
        assertEq(cDai.balanceOf(address(pool)), _wdiv(1 * WAD, cDai.exchangeRateStored()));
        assertEq(poolBefore - dai.balanceOf(address(pool)), 1 * WAD);
    }

    function test_withdraw_calls_cdai_withdraw() public {
        vm.prank(address(hub));
        pool.deposit(1 * WAD);

        _assertEqApprox(cDai.balanceOfUnderlying(address(pool)), 1 * WAD);
        uint256 before = dai.balanceOf(address(hub));

        vm.prank(address(hub)); pool.withdraw(1 * WAD);

        _assertEqApprox(cDai.balanceOfUnderlying(address(pool)), 0);
        assertEq(dai.balanceOf(address(hub)) - before, 1 * WAD);
    }

    function test_withdraw_calls_cdai_withdraw_vat_caged() public {
        vm.prank(address(hub)); pool.deposit(1 * WAD);

        _assertEqApprox(cDai.balanceOfUnderlying(address(pool)), 1 * WAD);
        uint256 before = dai.balanceOf(address(hub));

        vat.cage();
        vm.prank(address(hub)); pool.withdraw(1 * WAD);

        _assertEqApprox(cDai.balanceOfUnderlying(address(pool)), 0);
        assertEq(dai.balanceOf(address(hub)) - before, 1 * WAD);
    }

    function test_collect_claims_for_king() public {

        // Return if rewards are turned off - this is still an acceptable state
        if (ComptrollerLike(cDai.comptroller()).compBorrowSpeeds(address(cDai)) == 0) return;

        address king = address(123);
        pool.file("king", king);

        vm.prank(address(hub)); pool.deposit(100 * WAD);

        uint256 compBefore = comp.balanceOf(king);
        vm.roll(block.number + 5760);

        (,,,uint256 expected) = lens.getCompBalanceMetadataExt(address(comp), address(comptroller), address(pool));
        assertGt(expected, 0);

        pool.collect(true);

        assertEq(comp.balanceOf(address(king)), compBefore + expected);
    }

    function test_collect_without_claim() public {

        // Return if rewards are turned off - this is still an acceptable state
        if (ComptrollerLike(cDai.comptroller()).compBorrowSpeeds(address(cDai)) == 0) return;

        address king = address(this);
        pool.file("king", king);

        vm.prank(address(hub)); pool.deposit(100 * WAD);
        vm.roll(block.number + 5760);
        pool.collect(true);

        uint256 kingBalance = comp.balanceOf(address(king));
        assertGt(kingBalance, 0);

        // Since COMP can be claimed to the pool directly through Compound by a 3rd party make sure it can be recovered
        // later even if comptroller would revert for some reason.
        assertEq(comp.balanceOf(address(pool)), 0);
        comp.transfer(address(pool), 1);
        assertEq(comp.balanceOf(address(pool)), 1);
        assertEq(comp.balanceOf(address(king)), kingBalance - 1);

        pool.collect(false);
        assertEq(comp.balanceOf(address(pool)), 0);
        assertEq(comp.balanceOf(address(king)), kingBalance);
    }

    function test_collect_no_king() public {
        assertEq(pool.king(), address(0));

        assertRevert(address(pool), abi.encodeWithSignature("collect(bool)", true), "D3MCompoundV2TypePool/king-not-set");
    }

    function test_redeemable_returns_cdai() public {
        assertEq(pool.redeemable(), address(cDai));
    }

    function test_exit_cdai() public {
        vm.prank(address(hub)); pool.deposit(100 * WAD);

        uint256 balanceCdai = cDai.balanceOf(address(pool));
        assertGt(balanceCdai, 2);

        end.setArt(100 * WAD);
        vm.prank(address(hub)); pool.exit(address(123), 50 * WAD);

        assertEq(balanceCdai - cDai.balanceOf(address(pool)), balanceCdai / 2);
        assertEq(cDai.balanceOf(address(123)), balanceCdai / 2);
    }

    function test_quit_moves_balance() public {
        vm.prank(address(hub)); pool.deposit(100 * WAD);

        uint256 balanceCdai = cDai.balanceOf(address(pool));
        assertGt(balanceCdai, 0);

        pool.quit(address(123));

        assertEq(cDai.balanceOf(address(pool)), 0);
        assertEq(cDai.balanceOf(address(123)), balanceCdai);
    }

    function test_assetBalance_gets_dai_balanceOf_pool() public {
        uint256 before = pool.assetBalance();
        vm.prank(address(hub)); pool.deposit(1 * WAD);
        _assertEqApprox(pool.assetBalance() - before, 1 * WAD);
    }

    function test_maxWithdraw_gets_available_assets() public {
        vm.prank(address(hub)); pool.deposit(1 * WAD);
        assertEq(pool.assetBalance(), pool.maxWithdraw());
    }

    function test_maxDeposit_returns_max_uint() public {
        assertEq(pool.maxDeposit(), type(uint256).max);
    }
}
