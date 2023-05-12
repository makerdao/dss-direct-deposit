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
import {ID3MPlan} from "../plans/ID3MPlan.sol";

/**
 *  @title D3M Gated Swap Pool
 *  @notice Swaps are gated by comparing target assets to the amount of gems in the pool.
 *          The pool will only work to fill/empty to reach the desired target allocation.
 */
contract D3MGatedSwapPool is D3MSwapPool {

    struct FeeData {
        uint128 tin;     // toll in  [wad]
        uint128 tout;    // toll out [wad]
    }

    // --- Data ---
    FeeData public feeData;

    // --- Events ---
    event File(bytes32 indexed what, uint128 tin, uint128 tout);

    constructor(
        bytes32 _ilk,
        address _hub,
        address _dai,
        address _gem
    ) D3MSwapPool(_ilk, _hub, _dai, _gem) {
        // Initialize all fees to zero
        feeData = FeeData({
            tin: uint128(WAD),
            tout: uint128(WAD)
        });
    }

    // --- Administration ---

    function file(bytes32 what, uint128 _tin, uint128 _tout) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");
        // Please note we allow tin and tout to be both negative fees because swaps are gated by
        // the desired target debt which only allows filling/emptying this pool in one direction
        // at a time.

        if (what == "fees") {
            feeData.tin = _tin;
            feeData.tout = _tout;
        } else revert("D3MSwapPool/file-unrecognized-param");

        emit File(what, _tin, _tout);
    }

    // --- Getters ---

    function tin() external view returns (uint256) {
        return feeData.tin;
    }

    function tout() external view returns (uint256) {
        return feeData.tout;
    }

    // --- Swaps ---

    function previewSwapGemForDai(uint256 gemAmt) public view override returns (uint256 daiAmt) {
        uint256 currentAssets = assetBalance();
        uint256 gemBalance = currentAssets - dai.balanceOf(address(this));
        uint256 targetAssets = ID3MPlan(hub.plan(ilk)).getTargetAssets(ilk, currentAssets);
        uint256 pipValue = uint256(swapGemForDaiPip.read());
        uint256 gemValue = gemAmt * GEM_CONVERSION_FACTOR * pipValue / WAD;
        require(gemBalance + gemValue <= targetAssets, "D3MSwapPool/not-accepting-gems");
        FeeData memory _feeData = feeData;
        daiAmt = gemValue * _feeData.tin / WAD;
    }

    function previewSwapDaiForGem(uint256 daiAmt) public view override returns (uint256 gemAmt) {
        uint256 currentAssets = assetBalance();
        uint256 gemBalance = currentAssets - dai.balanceOf(address(this));
        uint256 targetAssets = ID3MPlan(hub.plan(ilk)).getTargetAssets(ilk, currentAssets);
        FeeData memory _feeData = feeData;
        uint256 gemValue = daiAmt * _feeData.tout / WAD;
        require(targetAssets + gemValue <= gemBalance, "D3MSwapPool/not-accepting-dai");
        uint256 pipValue = uint256(swapDaiForGemPip.read());
        gemAmt = gemValue * WAD / (GEM_CONVERSION_FACTOR * pipValue);
    }

}
