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

import "./ID3MPlan.sol";

interface TokenLike {
    function balanceOf(address) external view returns (uint256);
}

interface ATokenLike {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

/**
 *  @title D3M Aave Buffer Plan
 *  @notice Ensure `buffer` amount of DAI is always available to borrow.
 *  @dev This plan can be used with both V2 and V3 versions of the Aave codebase.
 */
contract D3MAaveTypeBufferPlan is ID3MPlan {

    mapping (address => uint256) public wards;
    uint256                      public buffer;     // Target DAI liquidity to keep in the pool [WAD]

    TokenLike  public immutable dai;
    ATokenLike public immutable adai;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);

    constructor(address adai_) {
        adai = ATokenLike(adai_);
        dai = TokenLike(adai.UNDERLYING_ASSET_ADDRESS());
        
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MAaveTypeBufferPlan/not-authorized");
        _;
    }

    // --- Admin ---
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "buffer") {
            buffer = data;
        } else revert("D3MAaveTypeBufferPlan/file-unrecognized-param");
        emit File(what, data);
    }

    function getTargetAssets(bytes32, uint256 currentAssets) external override view returns (uint256) {
        if (buffer == 0) return 0; // De-activated

        // Note that this can be manipulated by flash loans
        uint256 liquidityAvailable = dai.balanceOf(address(adai));
        if (buffer >= liquidityAvailable) {
            // Need to increase liquidity
            return currentAssets + (buffer - liquidityAvailable);
        } else {
            // Need to decrease liquidity
            unchecked {
                uint256 decrease = liquidityAvailable - buffer;
                if (currentAssets >= decrease) {
                    return currentAssets - decrease;
                } else {
                    return 0;
                }
            }
        }
    }

    function active() public view override returns (bool) {
        return buffer > 0;
    }

    function disable() external override {
        require(wards[msg.sender] == 1 || !active(), "D3MAaveTypeBufferPlan/not-authorized");
        buffer = 0;
        emit Disable();
    }
}
