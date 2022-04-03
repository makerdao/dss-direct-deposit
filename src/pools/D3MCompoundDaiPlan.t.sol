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

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//    Methodology for Calculating Target Supply from Target Rate Per Block    //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

// apy to rate per block off-chain conversion info:
//         apy = ((1 + (borrowRatePerBlock / WAD) * blocksPerDay) ^ 365 - 1) * 100
// (0)     borrowRatePerBlock = ((((apy / 100) + 1) ^ (1 / 365) - 1) / blocksPerDay) * WAD
//
// https://github.com/compound-finance/compound-protocol/blob/master/contracts/BaseJumpRateModelV2.sol#L95
//
// util > kink:
//         targetInterestRate = normalRate + jumpMultiplierPerBlock * (util - kink) / WAD
//         util * jumpMultiplierPerBlock = (targetInterestRate - normalRate) * WAD + kink * jumpMultiplierPerBlock
// (1)     util = kink + (targetInterestRate - normalRate) * WAD / jumpMultiplierPerBlock
//
// util <= kink:
//         targetInterestRate = util * multiplierPerBlock / WAD + baseRatePerBlock
// (2)     util = (targetInterestRate - baseRatePerBlock) * WAD / multiplierPerBlock
//
// https://github.com/compound-finance/compound-protocol/blob/master/contracts/BaseJumpRateModelV2.sol#L79
//
//         util = borrows * WAD / (cash + borrows - reserves);
// (3)     cash + borrows - reserves = borrows * WAD / util

pragma solidity 0.6.12;

import "ds-test/test.sol";
import "../interfaces/interfaces.sol";

import {D3MCompoundDaiPlan, CErc20} from "./D3MCompoundDaiPlan.sol";

interface CErc20Like {
    function borrowRatePerBlock() external view returns (uint256);
    function getCash() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
}

contract DssDirectDepositHubTest is DSTest {
    uint256 constant WAD = 10**18;

    DaiLike dai;
    CErc20Like cDai;

    D3MCompoundDaiPlan plan;

    function mul(uint256 x, uint256 y) public pure returns (uint256 z) {
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
        if (a - b > mul(_b, _tolerance_bps) / 10 ** 4) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function setUp() public {

        dai = DaiLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        cDai = CErc20Like(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);

        plan = new D3MCompoundDaiPlan(address(dai), address(cDai));
    }

    function test_target_supply_for_current_rate() public {
        uint256 borrowRatePerBlock = cDai.borrowRatePerBlock();
        uint256 targetSupply = plan.calculateTargetSupply(borrowRatePerBlock);

        uint256 cash = cDai.getCash();
        uint256 borrows = cDai.totalBorrows();
        uint256 reserves = cDai.totalReserves();
        assertEqApproxBPS(targetSupply, cash + borrows - reserves, 1);
    }
}