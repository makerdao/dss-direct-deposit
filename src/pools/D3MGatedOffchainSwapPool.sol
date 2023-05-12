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

import "./D3MGatedSwapPool.sol";

/**
 *  @title D3M Gated Offchain Swap Pool
 *  @notice Approved operators can add/remove gems from this pool for off-chain investment.
 */
contract D3MGatedOffchainSwapPool is D3MGatedSwapPool {

    // --- Data ---
    mapping (address => uint256) public operators;

    uint256 public gemsOutstanding;

    // --- Events ---
    event File(bytes32 indexed what, uint256 data);
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
        address _gem
    ) D3MGatedSwapPool(_ilk, _hub, _dai, _gem) {
    }

    // --- Administration ---

    function file(bytes32 what, uint256 data) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");

        if (what == "gemsOutstanding") {
            gemsOutstanding = data;
        } else revert("D3MSwapPool/file-unrecognized-param");

        emit File(what, data);
    }

    function addOperator(address operator) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-addOperator-during-shutdown");

        operators[operator] = 1;
        emit AddOperator(operator);
    }

    function removeOperator(address operator) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-removeOperator-during-shutdown");

        operators[operator] = 0;
        emit RemoveOperator(operator);
    }

    // --- Pool Support ---

    function assetBalance() public view override returns (uint256) {
        return dai.balanceOf(address(this)) + (gem.balanceOf(address(this)) + gemsOutstanding) * GEM_CONVERSION_FACTOR * uint256(pip.read()) / WAD;
    }

    // --- Offchain push/pull + helper functions ---

    /**
     * @notice Pull out the gem to invest off-chain.
     * @param to The address to pull the gems to.
     * @param amount The amount of gems to pull.
     */
    function pull(address to, uint256 amount) external onlyOperator {
        require(amount <= pendingDeposits(), "D3MSwapPool/amount-exceeds-pending");
        gemsOutstanding += amount;
        require(gem.transfer(to, amount), "D3MSwapPool/failed-transfer");
    }

    /**
     * @notice Repay the loan with gems.
     * @param amount The amount of gems to repay.
     */
    function push(uint256 amount) external onlyOperator {
        require(gem.transferFrom(msg.sender, address(this), amount), "D3MSwapPool/failed-transfer");
        gemsOutstanding -= amount;
    }
    
    /**
     * @notice The amount of gems that should be deployed off-chain.
     * @dev It's possible gems are in this adapter, but are earmarked to be exchanged back to DAI.
     */
    function pendingDeposits() public view returns (uint256 gemAmt) {
        uint256 conversionFactor = GEM_CONVERSION_FACTOR * uint256(pip.read());
        uint256 gemBalance = gem.balanceOf(address(this));
        uint256 gemsPlusOutstanding = (gemBalance + gemsOutstanding) * conversionFactor / WAD;
        uint256 targetAssets = ID3MPlan(hub.plan(ilk)).getTargetAssets(ilk, gemsPlusOutstanding + dai.balanceOf(address(this)));
        // We can ignore the DAI as that will just be removed right away
        if (targetAssets >= gemsPlusOutstanding) {
            // Target debt is higher than the current exposure
            // Can deploy the full amount of gems
            gemAmt = gemBalance;
        } else {
            // Note this rounds up towards the user, but it's not a big deal as it's a whitelisted user responsible for the entire principal
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
        uint256 conversionFactor = GEM_CONVERSION_FACTOR * uint256(pip.read());
        uint256 _gemsOutstanding = gemsOutstanding;
        uint256 gemBalance = (gem.balanceOf(address(this)) + gemsOutstanding) * conversionFactor / WAD;
        uint256 targetAssetsInGems = ID3MPlan(hub.plan(ilk)).getTargetAssets(ilk, gemBalance + dai.balanceOf(address(this))) * WAD / conversionFactor;
        if (targetAssetsInGems < _gemsOutstanding) {
            // Need to liquidate
            gemAmt = _gemsOutstanding - targetAssetsInGems;
        } else {
            gemAmt = 0;
        }
    }

}
