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

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
}

interface DssDirectDepositHubLike {
    function vat() external view returns (address);
    function ilks(bytes32) external view returns (address, address, uint256, uint256, uint256);
    function dai() external view returns (address);
    function exec(bytes32) external;
}

interface DssDirectDepositPoolLike {
    function plan() external view returns (address);
    function bar() external view returns (uint256);
}

interface DssDirectDepositPlanLike {
    function getCurrentRate() external view returns (uint256);
}

// Helper functions for keeper bots
contract DssDirectDepositHelper {

    // --- Math ---
    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "DssDirectDepositHelper/overflow");
    }
    uint256 constant RAY  = 10 ** 27;
    function _rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, RAY) / y;
    }

    // Use this to determine whether exec() should be called based on your interest rate deviation threshold
    // This assumes normal operation, culled / global shutdown should be handled externally
    // Also assumes no liquidity issues
    function shouldExec(
        address _directHub,
        bytes32 ilk,
        uint256 interestRateTolerance
    ) public view returns (bool) {
        // IMPORTANT: this function assumes Vat rate of this ilk will always be == 1 * RAY (no fees).
        // That's why this module converts normalized debt (art) to Vat DAI generated with a simple RAY multiplication or division
        // This module will have an unintended behaviour if rate is changed to some other value.

        DssDirectDepositHubLike directHub = DssDirectDepositHubLike(_directHub);
        VatLike vat = VatLike(directHub.vat());
        (address pool,,,,) = directHub.ilks(ilk);
        address plan = DssDirectDepositPoolLike(pool).plan();
        uint256 bar = DssDirectDepositPoolLike(pool).bar();

        (, uint256 daiDebt) = vat.urns(ilk, address(directHub));
        if (bar == 0) {
            return daiDebt > 1;     // Always attempt to close out if we have debt remaining
        }

        uint256 deviation = _rdiv(DssDirectDepositPlanLike(plan).getCurrentRate(), bar);
        if (deviation < RAY) {
            // Unwind case
            return daiDebt > 1 && (RAY - deviation) > interestRateTolerance;
        } else if (deviation > RAY) {
            // Wind case
            (,,, uint256 line,) = vat.ilks(ilk);
            return (daiDebt + 1)*RAY < line && (deviation - RAY) > interestRateTolerance;
        } else {
            // No change
            return false;
        }
    }

    function conditionalExec(
        address directHub,
        bytes32 ilk,
        uint256 interestRateTolerance
    ) external {
        require(shouldExec(directHub, ilk, interestRateTolerance), "DssDirectDepositHelper/exec-not-ready");

        DssDirectDepositHubLike(directHub).exec(ilk);
    }

}
