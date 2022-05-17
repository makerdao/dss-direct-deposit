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

import { Hevm, D3MPoolBaseTest } from "./D3MPoolBase.t.sol";
import { DaiLike, TokenLike }    from "../tests/interfaces/interfaces.sol";
import { D3MCompoundDaiPool }    from "./D3MCompoundDaiPool.sol";

interface CErc20Like {
    function balanceOf(address owner) external view returns (uint256);
    function comptroller()            external view returns (uint256);
    function balanceOfUnderlying(address owner) external returns (uint256);
}

interface CompltrollerLike {
    function compSupplySpeeds(address cToken) external view returns (uint256);
}

interface LensLike {
    function getCompBalanceMetadataExt(address comp, address comptroller, address account) external returns (uint256, uint256, address, uint256);
}

contract D3MCompoundDaiPoolTest is D3MPoolBaseTest {

    CErc20Like         cDai;
    D3MCompoundDaiPool pool;
    CompltrollerLike   comptroller;
    TokenLike          comp;
    LensLike           lens;

    address public vat; // Needed in pool's ctr

    function _mul(uint256 x, uint256 y) public pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function assertEqApproxBPS(uint256 _a, uint256 _b, uint256 _tolerance_bps) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > _mul(_b, _tolerance_bps) / 10 ** 4) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function setUp() public override {
        hevm = Hevm(
            address(bytes20(uint160(uint256(keccak256("hevm cheat code")))))
        );

        dai         = DaiLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        cDai        = CErc20Like(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        comptroller = CompltrollerLike(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
        comp        = TokenLike(0xc00e94Cb662C3520282E6f5717214004A7f26888);
        lens        = LensLike(0xdCbDb7306c6Ff46f77B349188dC18cEd9DF30299);
        vat         = 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B;

        d3mTestPool = address(new D3MCompoundDaiPool(address(this), address(dai), address(cDai)));
        pool = D3MCompoundDaiPool(d3mTestPool);

        // allocate some dai for the pool
        _giveTokens(dai, 100 * WAD);
        dai.transfer(address(pool), 100 * WAD);
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

    function testFail_cannot_file_king_no_auth() public {
        assertEq(address(pool.king()), address(0));

        pool.deny(address(this));
        pool.file("king", address(123));
    }

    function testFail_cannot_file_unknown_param() public {
        pool.file("fail", address(123));
    }

    function test_deposit_calls_cdai_deposit() public {
        assertEq(cDai.balanceOfUnderlying(address(pool)), 0);
        uint256 poolBefore = dai.balanceOf(address(pool));

        pool.deposit(1 * WAD);

        assertEqApproxBPS(cDai.balanceOfUnderlying(address(pool)), 1 * WAD, 1);
        assertEq(poolBefore - dai.balanceOf(address(pool)), 1 * WAD);
    }

    function testFail_deposit_requires_auth() public {
        pool.deny(address(this));
        pool.deposit(1);
    }

    function test_withdraw_calls_cdai_withdraw() public {
        pool.deposit(1 * WAD);

        assertEqApproxBPS(cDai.balanceOfUnderlying(address(pool)), 1 * WAD, 1);
        uint256 before = dai.balanceOf(address(this));

        pool.withdraw(1 * WAD);

        assertEqApproxBPS(cDai.balanceOfUnderlying(address(pool)), 0, 1);
        assertEq(dai.balanceOf(address(this)) - before, 1 * WAD);
    }

    function testFail_withdraw_requires_auth() public {
        pool.deposit(1 * WAD);
        pool.deny(address(this));
        pool.withdraw(1 * WAD);
    }

    function test_collect_claims_for_king() public {

        // Return if rewards are turned off - this is still an acceptable state
        if (CompltrollerLike(cDai.comptroller()).compSupplySpeeds(address(cDai)) == 0) return;

        address king = address(123);
        pool.file("king", king);

        pool.deposit(100 * WAD);

        uint256 compBefore = comp.balanceOf(king);
        hevm.roll(block.number + 5760);

        (,,,uint256 expected) = lens.getCompBalanceMetadataExt(address(comp), address(comptroller), address(pool));
        assertGt(expected, 0);

        pool.collect();

        assertEq(comp.balanceOf(address(king)), compBefore + expected);
    }

    function testFail_collect_no_king() public {
        assertEq(pool.king(), address(0));

        pool.collect();
    }

    function test_transfer_cdai() public {
        pool.deposit(100 * WAD);

        uint256 balanceCdai = cDai.balanceOf(address(pool));
        assertGt(balanceCdai, 2);

        pool.transfer(address(123), 50 * WAD);

        assertEq(balanceCdai - cDai.balanceOf(address(pool)), balanceCdai / 2);
        assertEq(cDai.balanceOf(address(123)), balanceCdai / 2);
    }

    function testFail_transfer_no_auth() public {
        pool.deposit(100 * WAD);
        pool.deny(address(this));
        pool.transfer(address(123), 50 * WAD);
    }

    function test_transferAll_moves_balance() public {
        pool.deposit(100 * WAD);

        uint256 balanceCdai = cDai.balanceOf(address(pool));
        assertGt(balanceCdai, 0);

        pool.transferAll(address(123));

        assertEq(cDai.balanceOf(address(pool)), 0);
        assertEq(cDai.balanceOf(address(123)), balanceCdai);
    }

    function testFail_transferAll_no_auth() public {
        pool.deposit(100 * WAD);
        pool.deny(address(this));
        pool.transferAll(address(123));
    }

    function test_assetBalance_gets_dai_balanceOf_pool() public {
        uint256 before = pool.assetBalance();
        pool.deposit(1 * WAD);
        assertEqApproxBPS(pool.assetBalance() - before, 1 * WAD, 1);
    }

    function test_maxWithdraw_gets_available_assets() public {
        pool.deposit(1 * WAD);
        assertEqApproxBPS(pool.assetBalance(), pool.maxWithdraw(), 1);
    }

    function test_maxDeposit_returns_max_uint() public {
        assertEq(pool.maxDeposit(), type(uint256).max);
    }
}
