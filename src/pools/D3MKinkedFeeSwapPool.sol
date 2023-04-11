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
 *  @title D3M Kinked Fee Swap Pool
 *  @notice Swap an asset for DAI. Fees vary based on whether the pool is above or below the target ratio.
 */
contract D3MKinkedFeeSwapPool is D3MSwapPool {

    struct FeeData {
        uint24 ratio;   // where to place the fee1/fee2 change as ratio between gem and dai [bps]
        uint24 tin1;    // toll in under the ratio  [bps]
        uint24 tout1;   // toll out under the ratio [bps]
        uint24 tin2;    // toll in over the ratio   [bps]
        uint24 tout2;   // toll out over the ratio  [bps]
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
            ratio: 0,
            tin1: uint24(BPS),
            tout1: uint24(BPS),
            tin2: uint24(BPS),
            tout2: uint24(BPS)
        });
    }

    // --- Administration ---

    function file(bytes32 what, uint24 data) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");
        require(data <= BPS, "D3MSwapPool/invalid-ratio");

        if (what == "ratio") feeData.ratio = data;
        else revert("D3MSwapPool/file-unrecognized-param");

        emit File(what, data);
    }

    function file(bytes32 what, uint24 tin, uint24 tout) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");
        // We need to restrict tin/tout combinations to be less than 100% to avoid arbitrage opportunities.
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

    function ratio() external view returns (uint256) {
        return feeData.ratio;
    }

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

    function previewSellGem(uint256 gemAmt) public override view returns (uint256 daiAmt) {
        FeeData memory _feeData = feeData;
        uint256 pipValue = uint256(sellGemPip.read());
        uint256 gemValue = gemAmt * GEM_CONVERSION_FACTOR * pipValue / WAD;
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 gemBalance = gem.balanceOf(address(this)) * GEM_CONVERSION_FACTOR * pipValue / WAD;
        uint256 desiredGemBalance = _feeData.ratio * (daiBalance + gemBalance) / BPS;
        if (gemBalance >= desiredGemBalance) {
            // We are above the ratio so apply tin2
            daiAmt = gemValue * _feeData.tin2 / BPS;
        } else {
            uint256 daiAvailableAtTin1;
            unchecked {
                daiAvailableAtTin1 = desiredGemBalance - gemBalance;
            }

            // We are below the ratio so could be a mix of tin1 and tin2
            uint256 daiAmtTin1 = gemValue * _feeData.tin1 / BPS;
            if (daiAmtTin1 <= daiAvailableAtTin1) {
                // We are entirely in the tin1 region
                daiAmt = daiAmtTin1;
            } else {
                // We are a mix between tin1 and tin2
                uint256 daiRemainder;
                unchecked {
                    daiRemainder = daiAmtTin1 - daiAvailableAtTin1;
                }
                daiAmt = daiAvailableAtTin1 + (daiRemainder * BPS / _feeData.tin1) * _feeData.tin2 / BPS;
            }
        }
    }

    function previewBuyGem(uint256 daiAmt) public override view returns (uint256 gemAmt) {
        FeeData memory _feeData = feeData;
        uint256 pipValue = uint256(buyGemPip.read());
        uint256 gemValue;
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 gemBalance = gem.balanceOf(address(this)) * GEM_CONVERSION_FACTOR * pipValue / WAD;
        uint256 desiredGemBalance = _feeData.ratio * (daiBalance + gemBalance) / BPS;
        if (gemBalance <= desiredGemBalance) {
            // We are below the ratio so apply tout1
            gemValue = daiAmt * _feeData.tout1 / BPS;
        } else {
            uint256 gemsAvailableAtTout2;
            unchecked {
                gemsAvailableAtTout2 = gemBalance - desiredGemBalance;
            }

            // We are above the ratio so could be a mix of tout1 and tout2
            if (daiAmt <= gemsAvailableAtTout2) {
                // We are entirely in the tout1 region
                gemValue = daiAmt * _feeData.tout2 / BPS;
            } else {
                // We are a mix between tout1 and tout2
                uint256 gemsRemainder;
                unchecked {
                    gemsRemainder = daiAmt - gemsAvailableAtTout2;
                }
                gemValue = gemsAvailableAtTout2 * _feeData.tout2 / BPS + gemsRemainder * _feeData.tout1 / BPS;
            }
        }
        gemAmt = gemValue * WAD / (GEM_CONVERSION_FACTOR * pipValue);
    }

}
