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
        uint24 tin1;    // toll in at 0% gems    [bps]
        uint24 tout1;   // toll out at 0% gems   [bps]
        uint24 tin2;    // toll in at 100% gems  [bps]
        uint24 tout2;   // toll out at 100% gems [bps]
    }

    // --- Data ---
    FeeData public feeData;

    uint256 constant internal BPS = 10 ** 4;

    // --- Events ---
    event File(bytes32 indexed what, uint24 data);
    event File(bytes32 indexed what, uint24 tin, uint24 tout);

    constructor(bytes32 _ilk, address _hub, address _dai, address _gem) D3MSwapPool(_ilk, _hub, _dai, _gem) {
        // Initialize all fees to zero
        feeData = FeeData({
            tin1: uint24(BPS),
            tout1: uint24(BPS),
            tin2: uint24(BPS),
            tout2: uint24(BPS)
        });
    }

    // --- Administration ---

    function file(bytes32 what, uint24 tin, uint24 tout) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");
        // We need to restrict tin/tout combinations to be less than 100% to avoid arbitragers able to endlessly take money
        require(uint256(tin) * uint256(tout) <= BPS * BPS, "D3MSwapPool/invalid-fees");

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

    function previewSellGem(uint256 gemAmt) public view override returns (uint256 daiAmt) {
        FeeData memory _feeData = feeData;
        uint256 pipValue = uint256(sellGemPip.read());
        uint256 gemValue = gemAmt * GEM_CONVERSION_FACTOR * pipValue / WAD;
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 gemBalance = gem.balanceOf(address(this)) * GEM_CONVERSION_FACTOR * pipValue / WAD;
        uint256 fee = BPS;
        uint256 totalBalance = daiBalance + gemBalance;
        if (totalBalance > 0) {
            // Please note the fee deduction is not included in the new total dai+gem balance to drastically simplify the calculation
            fee = (_feeData.tin1 * daiBalance + _feeData.tin2 * gemBalance - (_feeData.tin1 + _feeData.tin2) * gemValue / 2) / totalBalance;
        }
        daiAmt = gemValue * fee / BPS;
    }

    function previewBuyGem(uint256 daiAmt) public view override returns (uint256 gemAmt) {
        FeeData memory _feeData = feeData;
        uint256 pipValue = uint256(buyGemPip.read());
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 gemBalance = gem.balanceOf(address(this)) * GEM_CONVERSION_FACTOR * pipValue / WAD;
        uint256 fee = BPS;
        uint256 totalBalance = daiBalance + gemBalance;
        if (totalBalance > 0) {
            // Please note the fee deduction is not included in the new total dai+gem balance to drastically simplify the calculation
            fee = (_feeData.tout2 * daiBalance + _feeData.tout1 * gemBalance - (_feeData.tout1 + _feeData.tout2) * daiAmt / 2) / totalBalance;
        }
        uint256 gemValue = daiAmt * fee / BPS;
        gemAmt = gemValue * WAD / (GEM_CONVERSION_FACTOR * pipValue);
    }

}
