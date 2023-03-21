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

import "./ID3MPool.sol";

interface VatLike {
    function live() external view returns (uint256);
    function hope(address) external;
    function nope(address) external;
}

interface TokenLike {
    function decimals() external view returns (uint8);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface PipLike {
    function read() external view returns (bytes32);
}

interface HubLike {
    function vat() external view returns (VatLike);
    function end() external view returns (EndLike);
}

interface EndLike {
    function Art(bytes32) external view returns (uint256);
}

/**
 *  @title D3M Swap Pool
 *  @notice Swap an asset for DAI. Fees vary based on whether the pool is above or below the buffer.
 */
contract D3MSwapPool is ID3MPool {

    // --- Data ---
    mapping (address => uint256) public wards;

    HubLike public hub;
    PipLike public pip;
    uint256 public buffer;   // Keep a buffer in DAI for liquidity [WAD]
    uint256 public tin1;     // toll in under the buffer  [wad]
    uint256 public tin2;     // toll in over the buffer   [wad]
    uint256 public tout1;    // toll out over the buffer  [wad]
    uint256 public tout2;    // toll out under the buffer [wad]
    uint256 public exited;

    bytes32   immutable public ilk;
    VatLike   immutable public vat;
    TokenLike immutable public dai;
    TokenLike immutable public gem;

    uint256 immutable private GEM_CONVERSION_FACTOR;

    uint256 constant WAD = 10 ** 18;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);
    event SellGem(address indexed owner, uint256 gems, uint256 dai);
    event BuyGem(address indexed owner, uint256 gems, uint256 dai);

    modifier auth {
        require(wards[msg.sender] == 1, "D3MSwapPool/not-authorized");
        _;
    }

    modifier onlyHub {
        require(msg.sender == address(hub), "D3MSwapPool/only-hub");
        _;
    }

    constructor(bytes32 _ilk, address _hub, address _dai, address _gem) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        
        ilk = _ilk;
        hub = HubLike(_hub);
        vat = HubLike(hub).vat();
        dai = TokenLike(_dai);
        gem = TokenLike(_gem);
        vat.hope(_hub);

        GEM_CONVERSION_FACTOR = 10 ** (18 - gem.decimals());
    }

    // --- Administration ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, uint256 data) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");

        if (what == "buffer") buffer = data;
        else if (what == "tin1") tin1 = data;
        else if (what == "tin2") tin2 = data;
        else if (what == "tout1") tout1 = data;
        else if (what == "tout2") tout2 = data;
        else revert("D3MSwapPool/file-unrecognized-param");

        emit File(what, data);
    }

    function file(bytes32 what, address data) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");

        if (what == "hub") {
            vat.nope(address(hub));
            hub = HubLike(data);
            vat.hope(data);
        } else if (what == "pip") {
            pip = PipLike(data);
        } else revert("D3MSwapPool/file-unrecognized-param");

        emit File(what, data);
    }

    // --- Pool Support ---

    function deposit(uint256 wad) external override onlyHub {
        // Nothing to do
    }

    function withdraw(uint256 wad) external override onlyHub {
        dai.transfer(msg.sender, wad);
    }

    function quit(address dst) external override auth {
        require(vat.live() == 1, "D3MSwapPool/no-quit-during-shutdown");
        require(gem.transfer(dst, gem.balanceOf(address(this))), "D3MSwapPool/transfer-failed");
    }

    function preDebtChange() external override {}

    function postDebtChange() external override {}

    function assetBalance() public view override returns (uint256) {
        return dai.balanceOf(address(this)) + gem.balanceOf(address(this)) * GEM_CONVERSION_FACTOR * uint256(pip.read()) / WAD;
    }

    function maxDeposit() external pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw() external view override returns (uint256) {
        return dai.balanceOf(address(this));
    }

    function redeemable() external view override returns (address) {
        return address(gem);
    }

    function exit(address dst, uint256 wad) external override onlyHub {
        uint256 exited_ = exited;
        exited = exited_ + wad;
        uint256 amt = wad * gem.balanceOf(address(this)) / (hub.end().Art(ilk) - exited_);
        require(gem.transfer(dst, amt), "D3MSwapPool/transfer-failed");
    }

    // --- Swaps ---

    function previewSellGem(uint256 gemAmt) public view returns (uint256 daiAmt) {
        uint256 gemValue = gemAmt * GEM_CONVERSION_FACTOR * uint256(pip.read()) / WAD;
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 _buffer = buffer;
        if (daiBalance <= _buffer) {
            // We are above the buffer so apply tin2
            daiAmt = gemValue * tin2 / WAD;
        } else {
            uint256 daiAvailableAtTin1;
            unchecked {
                daiAvailableAtTin1 = daiBalance - _buffer;
            }

            // We are below the buffer so could be a mix of tin1 and tin2
            uint256 daiAmtTin1 = gemValue * tin1 / WAD;
            if (daiAmtTin1 <= daiAvailableAtTin1) {
                // We are entirely in the tin1 region
                daiAmt = daiAmtTin1;
            } else {
                // We are a mix between tin1 and tin2
                uint256 daiRemainder;
                unchecked {
                    daiRemainder = daiAmtTin1 - daiAvailableAtTin1;
                }
                daiAmt = daiAvailableAtTin1 + (daiRemainder * WAD / tin1) * tin2 / WAD;
            }
        }
    }

    function previewBuyGem(uint256 daiAmt) public view returns (uint256 gemAmt) {
        uint256 gemValue;
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 _buffer = buffer;
        if (daiBalance >= _buffer) {
            // We are below the buffer so apply tout2
            gemValue = daiAmt * tout2 / WAD;
        } else {
            uint256 daiAvailableAtTout1;
            unchecked {
                daiAvailableAtTout1 = _buffer - daiBalance;
            }

            // We are above the buffer so could be a mix of tout1 and tout1
            if (daiAmt <= daiAvailableAtTout1) {
                // We are entirely in the tout1 region
                gemValue = daiAmt * tout1 / WAD;
            } else {
                // We are a mix between tout1 and tout1
                uint256 daiRemainder;
                unchecked {
                    daiRemainder = daiAmt - daiAvailableAtTout1;
                }
                gemValue = daiAvailableAtTout1 * tout1 / WAD + daiRemainder * tout2 / WAD;
            }
        }
        gemAmt = gemValue * WAD / (GEM_CONVERSION_FACTOR * uint256(pip.read()));
    }

    function sellGem(address usr, uint256 gemAmt, uint256 minDaiAmt) external returns (uint256 daiAmt) {
        daiAmt = previewSellGem(gemAmt);
        require(daiAmt >= minDaiAmt, "D3MSwapPool/too-little-dai");
        require(gem.transferFrom(msg.sender, address(this), gemAmt), "D3MSwapPool/failed-transfer");
        dai.transfer(usr, daiAmt);

        emit SellGem(usr, gemAmt, daiAmt);
    }

    function buyGem(address usr, uint256 daiAmt, uint256 minGemAmt) external returns (uint256 gemAmt) {
        gemAmt = previewBuyGem(daiAmt);
        require(gemAmt >= minGemAmt, "D3MSwapPool/too-little-gems");
        dai.transferFrom(msg.sender, address(this), daiAmt);
        require(gem.transfer(usr, gemAmt), "D3MSwapPool/failed-transfer");

        emit BuyGem(usr, gemAmt, daiAmt);
    }

}
