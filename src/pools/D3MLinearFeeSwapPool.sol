// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
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

import "./D3MSwapPool.sol";

/**
 *  @title D3M Linear Fee Swap Pool
 *  @notice Swap an asset for DAI. Linear bonding curve with fee1 at 0% gems and fee2 at 100% gems.
 */
contract D3MLinearFeeSwapPool is D3MSwapPool {

    struct FeeData {
        uint64 tin1;    // toll in at 0% gems    [wad]
        uint64 tout1;   // toll out at 0% gems   [wad]
        uint64 tin2;    // toll in at 100% gems  [wad]
        uint64 tout2;   // toll out at 100% gems [wad]
    }

    // --- Data ---
    FeeData public feeData;

    // --- Events ---
    event File(bytes32 indexed what, uint64 tin, uint64 tout);

    constructor(bytes32 _ilk, address _hub, address _dai, address _gem) D3MSwapPool(_ilk, _hub, _dai, _gem) {
        // Initialize all fees to zero
        feeData = FeeData({
            tin1: uint64(WAD),
            tout1: uint64(WAD),
            tin2: uint64(WAD),
            tout2: uint64(WAD)
        });
    }

    // --- Administration ---

    function file(bytes32 what, uint64 tin, uint64 tout) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");
        // We need to restrict tin/tout combinations to be less than 100% to avoid arbitragers able to endlessly take money
        require(uint256(tin) * uint256(tout) <= WAD * WAD, "D3MSwapPool/invalid-fees");

        if (what == "fees1") {
            feeData.tin1 = tin;
            feeData.tout1 = tout;
        } else if (what == "fees2") {
            feeData.tin2 = tin;
            feeData.tout2 = tout;
        } else revert("D3MSwapPool/file-unrecognized-param");

        emit File(what, tin, tout);
    }

    // --- Getters ---

    function tin1() external view returns (uint256) {
        return feeData.tin1;
    }

    function tout1() external view returns (uint256) {
        return feeData.tout1;
    }

    function tin2() external view returns (uint256) {
        return feeData.tin2;
    }

    function tout2() external view returns (uint256) {
        return feeData.tout2;
    }

    // --- Swaps ---

    function previewSwapGemForDai(uint256 gemAmt) public view override returns (uint256 daiAmt) {
        if (gemAmt == 0) return 0;

        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 pipValue = uint256(swapGemForDaiPip.read());
        uint256 gemValue = gemAmt * GEM_CONVERSION_FACTOR * pipValue / WAD;
        require(daiBalance >= gemValue, "D3MSwapPool/insufficient-dai-in-pool");
        FeeData memory _feeData = feeData;
        uint256 gemBalance = gem.balanceOf(address(this)) * GEM_CONVERSION_FACTOR * pipValue / WAD;
        // Please note the fee deduction is not included in the new total dai+gem balance to drastically simplify the calculation
        uint256 totalBalanceTimesTwo = (daiBalance + gemBalance) * 2;
        uint256 g = 2 * gemBalance + gemValue;
        daiAmt = gemValue * (_feeData.tin1 + _feeData.tin2 * g / totalBalanceTimesTwo - _feeData.tin1 * g / totalBalanceTimesTwo) / WAD;
    }

    function previewSwapDaiForGem(uint256 daiAmt) public view override returns (uint256 gemAmt) {
        if (daiAmt == 0) return 0;

        FeeData memory _feeData = feeData;
        uint256 pipValue = uint256(swapDaiForGemPip.read());
        uint256 gemBalance = gem.balanceOf(address(this)) * GEM_CONVERSION_FACTOR * pipValue / WAD;
        require(gemBalance >= daiAmt, "D3MSwapPool/insufficient-gems-in-pool");
        uint256 daiBalance = dai.balanceOf(address(this));
        // Please note the fee deduction is not included in the new total dai+gem balance to drastically simplify the calculation
        uint256 totalBalanceTimesTwo = (daiBalance + gemBalance) * 2;
        uint256 g = 2 * daiBalance + daiAmt;
        gemAmt = daiAmt * (_feeData.tout2 + _feeData.tout1 * g / totalBalanceTimesTwo - _feeData.tout2 * g / totalBalanceTimesTwo) / (GEM_CONVERSION_FACTOR * pipValue);
    }

}
