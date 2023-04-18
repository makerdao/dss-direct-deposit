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
 *  @title D3M Whitelisted Swap Pool
 *  @notice Whitelisted addresses can remove gems from this pool.
 *  @dev DAI to GEM swaps only occur in one direction depending on if the outstanding debt is lower
 *       or higher than the debt ceiling.
 */
contract D3MWhitelistedSwapPool is D3MSwapPool {

    struct FeeData {
        uint128 tin;     // toll in  [wad]
        uint128 tout;    // toll out [wad]
    }

    // --- Data ---
    mapping (address => uint256) public operators;

    FeeData public feeData;
    ID3MPlan public plan;
    uint256 public gemsOutstanding;

    // --- Events ---
    event SetPlan(address plan);
    event File(bytes32 indexed what, uint128 tin, uint128 tout);
    event AddOperator(address indexed operator);
    event RemoveOperator(address indexed operator);

    modifier onlyOperator {
        require(operators[msg.sender] == 1, "D3MSwapPool/only-operator");
        _;
    }

    constructor(
        bytes32 _ilk,
        address _hub,
        address _dai,
        address _gem,
        address _plan
    ) D3MSwapPool(_ilk, _hub, _dai, _gem) {
        plan = ID3MPlan(_plan);

        // Initialize all fees to zero
        feeData = FeeData({
            tin: uint128(WAD),
            tout: uint128(WAD)
        });
    }

    // --- Administration ---

    function setPlan(address _plan) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");

        plan = ID3MPlan(_plan);

        emit SetPlan(_plan);
    }

    function file(bytes32 what, uint128 _tin, uint128 _tout) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");
        // We need to restrict tin/tout combinations to be less than 100% to avoid arbitragers able to endlessly take money
        require(uint256(_tin) * uint256(_tout) <= WAD * WAD, "D3MSwapPool/invalid-fees");

        if (what == "fees") {
            feeData.tin = _tin;
            feeData.tout = _tout;
        } else revert("D3MSwapPool/file-unrecognized-param");

        emit File(what, _tin, _tout);
    }

    function addOperator(address operator) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");

        operators[operator] = 1;
        emit AddOperator(operator);
    }

    function removeOperator(address operator) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");

        operators[operator] = 0;
        emit RemoveOperator(operator);
    }

    // --- Pool Support ---

    function assetBalance() external view override returns (uint256) {
        return dai.balanceOf(address(this)) + (gem.balanceOf(address(this)) + gemsOutstanding) * GEM_CONVERSION_FACTOR * uint256(pip.read()) / WAD;
    }

    // --- Getters ---

    function tin() external view returns (uint256) {
        return feeData.tin;
    }

    function tout() external view returns (uint256) {
        return feeData.tout;
    }

    // --- Swaps ---

    function previewSellGem(uint256 gemAmt) public view override returns (uint256 daiAmt) {
        uint256 gemBalance = (gem.balanceOf(address(this)) + gemsOutstanding) * GEM_CONVERSION_FACTOR * uint256(sellGemPip.read()) / WAD;
        uint256 targetAssets = plan.getTargetAssets(ilk, gemBalance + dai.balanceOf(address(this)));
        uint256 pipValue = uint256(sellGemPip.read());
        uint256 gemValue = gemAmt * GEM_CONVERSION_FACTOR * pipValue / WAD;
        require(gemBalance + gemValue <= targetAssets, "D3MSwapPool/not-accepting-gems");
        FeeData memory _feeData = feeData;
        daiAmt = gemValue * _feeData.tin / WAD;
    }

    function previewBuyGem(uint256 daiAmt) public view override returns (uint256 gemAmt) {
        uint256 gemBalance = (gem.balanceOf(address(this)) + gemsOutstanding) * GEM_CONVERSION_FACTOR * uint256(buyGemPip.read()) / WAD;
        uint256 targetAssets = plan.getTargetAssets(ilk, gemBalance + dai.balanceOf(address(this)));
        FeeData memory _feeData = feeData;
        uint256 gemValue = daiAmt * _feeData.tout / WAD;
        require(targetAssets + gemValue <= gemBalance, "D3MSwapPool/not-accepting-dai");
        uint256 pipValue = uint256(buyGemPip.read());
        gemAmt = gemValue * WAD / (GEM_CONVERSION_FACTOR * pipValue);
    }

    // --- Whitelisted push/pull + helper functions ---

    function pull(address to, uint256 amount) external onlyOperator {
        require(amount <= pendingDeposits(), "D3MSwapPool/amount-exceeds-pending");
        gemsOutstanding += amount;
        require(gem.transfer(to, amount), "D3MSwapPool/failed-transfer");
    }

    function push(uint256 amount) external onlyOperator {
        require(gem.transferFrom(msg.sender, address(this), amount), "D3MSwapPool/failed-transfer");
        if (gemsOutstanding > amount) {
            gemsOutstanding -= amount;
        } else {
            gemsOutstanding = 0;
        }
    }
    
    /**
     * @notice The amount of gems that should be deployed off-chain.
     * @dev It's possible gems are in this adapter, but are earmarked to be exchanged back to DAI.
     */
    function pendingDeposits() public view returns (uint256 gemAmt) {
        uint256 conversionFactor = GEM_CONVERSION_FACTOR * uint256(pip.read());
        uint256 gemBalance = gem.balanceOf(address(this));
        uint256 gemsPlusOutstanding = (gemBalance + gemsOutstanding) * conversionFactor / WAD;
        uint256 targetAssets = plan.getTargetAssets(ilk, gemsPlusOutstanding + dai.balanceOf(address(this)));
        // We can ignore the DAI as that will just be removed right away
        if (targetAssets >= gemsPlusOutstanding) {
            // Target debt is higher than the current exposure
            // Can deploy the full amount of gems
            gemAmt = gemBalance;
        } else {
            uint256 toBeRemoved = (gemsPlusOutstanding - targetAssets) * WAD / conversionFactor;
            if (toBeRemoved < gemBalance) {
                // Part of the gems are earmarked to be removed
                gemAmt = gemBalance - toBeRemoved;
            } else {
                // All of the gems are earmarked to be removed
                gemAmt = 0;
            }
        }
    }
    
    /**
     * @notice The amount of gems that should be returned by liquidating the off-chain position.
     */
    function pendingWithdrawals() external view returns (uint256 gemAmt) {
        uint256 _gemsOutstanding = gemsOutstanding;
        uint256 gemBalance = (gem.balanceOf(address(this)) + gemsOutstanding) * GEM_CONVERSION_FACTOR * uint256(pip.read()) / WAD;    // TODO should probably use the buy or sell pip
        uint256 targetAssets = plan.getTargetAssets(ilk, gemBalance + dai.balanceOf(address(this)));
        if (targetAssets < _gemsOutstanding) {
            // Need to liquidate
            gemAmt = _gemsOutstanding - targetAssets;
        } else {
            gemAmt = 0;
        }
    }

}
