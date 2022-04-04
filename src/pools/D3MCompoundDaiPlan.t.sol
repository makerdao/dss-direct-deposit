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
import "../interfaces/interfaces.sol";

import {D3MCompoundDaiPlan, CErc20} from "./D3MCompoundDaiPlan.sol";

interface CErc20Like {
    function borrowRatePerBlock() external view returns (uint256);
    function getCash()            external view returns (uint256);
    function totalBorrows()       external view returns (uint256);
    function totalReserves()      external view returns (uint256);
    function interestRateModel()  external view returns (address);
}

interface InterestRateModelLike {
    function baseRatePerBlock() external view returns (uint256);
    function kink() external view returns (uint256);
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256);
}

contract DssDirectDepositHubTest is DSTest {
    DaiLike dai;
    CErc20Like cDai;
    InterestRateModelLike model;

    D3MCompoundDaiPlan plan;

    uint256 constant WAD = 10 ** 18;

    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "overflow");
    }
    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "underflow");
    }
    function _mul(uint256 x, uint256 y) public pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    function _wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, WAD) / y;
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

    function setUp() public {
        dai   = DaiLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        cDai  = CErc20Like(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        model = InterestRateModelLike(cDai.interestRateModel());

        plan = new D3MCompoundDaiPlan(address(dai), address(cDai));
    }

    function _targetRateForUtil(uint256 util) internal view returns (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) {
        borrows  = cDai.totalBorrows();
        reserves = cDai.totalReserves();

        // reverse calculation of https://github.com/compound-finance/compound-protocol/blob/master/contracts/BaseJumpRateModelV2.sol#L79
        cash = _add(_sub(_wdiv(borrows, util), borrows), reserves);
        targetRate = model.getBorrowRate(cash, borrows, reserves);
    }

    function test_calculate_current_rate() public {
        uint256 borrowRatePerBlock = cDai.borrowRatePerBlock();
        uint256 targetSupply = plan.calculateTargetSupply(borrowRatePerBlock);

        uint256 cash = cDai.getCash();
        uint256 borrows = cDai.totalBorrows();
        uint256 reserves = cDai.totalReserves();
        assertEqApproxBPS(targetSupply, _sub(_add(cash, borrows), reserves), 1);
    }

    function test_calculate_exactly_normal_rate() public {
        uint256 util = model.kink(); // example: current kink = 80% => util = 80%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, _sub(_add(cash, borrows), reserves), 1);
    }

    function test_calculate_below_normal_rate() public {
        uint256 util = model.kink() / 2; // example: current kink = 80% => util = 40%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, _sub(_add(cash, borrows), reserves), 1);
    }

    function test_calculate_above_normal_rate() public {
        uint256 util = _add(model.kink(), _sub(WAD, model.kink()) / 2); // example: current kink = 80% => util = 80% + 10%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, _sub(_add(cash, borrows), reserves), 1);
    }

    function test_calculate_extremely_low_rate() public {
        uint256 util = model.kink() / 100; // example: current kink = 80% => util = 0.8%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, _sub(_add(cash, borrows), reserves), 1);
    }

    function test_calculate_extremely_high_rate() public {
        uint256 util = _add(model.kink(), _mul(_sub(WAD, model.kink()), 9) / 10); // example: current kink = 80% => util = 80% + 20% * 9 / 10 = 98%
        (uint256 targetRate, uint256 cash, uint256 borrows, uint256 reserves) = _targetRateForUtil(util);

        uint256 supply = plan.calculateTargetSupply(targetRate);
        assertEqApproxBPS(supply, _sub(_add(cash, borrows), reserves), 1);
    }

    function test_calculate_base_rate() public {
        uint256 supply = plan.calculateTargetSupply(model.baseRatePerBlock());
        assertEq(supply, 0);
    }

    function test_calculate_zero_rate() public {
        uint256 supply = plan.calculateTargetSupply(model.baseRatePerBlock());
        assertEq(supply, 0);
    }

    function test_supplies_current_rate() public {
        uint256 borrowRatePerBlock = cDai.borrowRatePerBlock();
        plan.file("barb", borrowRatePerBlock);

        uint256 cash = cDai.getCash();
        (uint256 totalAssets, uint256 targetAssets)  = plan.calcSupplies(cash);

        assertEqApproxBPS(totalAssets, targetAssets, 1);

        uint256 borrows = cDai.totalBorrows();
        uint256 reserves = cDai.totalReserves();
        assertEqApproxBPS(totalAssets, _sub(_add(cash, borrows), reserves), 0);
    }
}

