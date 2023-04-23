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
    function plan(bytes32) external view returns (address);
}

interface EndLike {
    function Art(bytes32) external view returns (uint256);
}

/**
 *  @title D3M Swap Pool
 *  @notice Swap an asset for DAI. Base contract to be extended to implement fee logic.
 */
abstract contract D3MSwapPool is ID3MPool {

    // --- Data ---
    mapping (address => uint256) public wards;

    HubLike public hub;
    PipLike public pip;
    PipLike public swapGemForDaiPip;
    PipLike public swapDaiForGemPip;
    uint256 public exited;

    bytes32   immutable public ilk;
    VatLike   immutable public vat;
    TokenLike immutable public dai;
    TokenLike immutable public gem;

    uint256 constant internal WAD = 10 ** 18;

    uint256 immutable internal GEM_CONVERSION_FACTOR;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event SwapGemForDai(address indexed owner, uint256 gems, uint256 dai);
    event SwapDaiForGem(address indexed owner, uint256 dai, uint256 gems);

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

    function file(bytes32 what, address data) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");

        if (what == "hub") {
            vat.nope(address(hub));
            hub = HubLike(data);
            vat.hope(data);
        } else if (what == "pip") {
            pip = PipLike(data);
        } else if (what == "swapGemForDaiPip") {
            swapGemForDaiPip = PipLike(data);
        } else if (what == "swapDaiForGemPip") {
            swapDaiForGemPip = PipLike(data);
        } else revert("D3MSwapPool/file-unrecognized-param");

        emit File(what, data);
    }

    // --- Pool Support ---

    function deposit(uint256) external override onlyHub {
        // Nothing to do
    }

    function withdraw(uint256 wad) external override onlyHub {
        dai.transfer(msg.sender, wad);
    }

    function quit(address dst) external override auth {
        require(vat.live() == 1, "D3MSwapPool/no-quit-during-shutdown");
        require(gem.transfer(dst, gem.balanceOf(address(this))), "D3MSwapPool/transfer-failed");
        dai.transfer(dst, dai.balanceOf(address(this)));
    }

    function preDebtChange() external override {}

    function postDebtChange() external override {}

    function assetBalance() external view virtual returns (uint256) {
        return dai.balanceOf(address(this)) + gem.balanceOf(address(this)) * GEM_CONVERSION_FACTOR * uint256(pip.read()) / WAD;
    }

    function maxDeposit() external pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw() external view override returns (uint256) {
        return dai.balanceOf(address(this));
    }

    function liquidityAvailable() external view override returns (uint256) {
        return dai.balanceOf(address(this));
    }

    function idleLiquidity() external view override returns (uint256) {
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

    function previewSwapGemForDai(uint256 gemAmt) public view virtual returns (uint256 daiAmt);

    function previewSwapDaiForGem(uint256 daiAmt) public view virtual returns (uint256 gemAmt);

    function swapGemForDai(address usr, uint256 gemAmt, uint256 minDaiAmt) external returns (uint256 daiAmt) {
        daiAmt = previewSwapGemForDai(gemAmt);
        require(daiAmt >= minDaiAmt, "D3MSwapPool/too-little-dai");
        require(gem.transferFrom(msg.sender, address(this), gemAmt), "D3MSwapPool/failed-transfer");
        dai.transfer(usr, daiAmt);

        emit SwapGemForDai(usr, gemAmt, daiAmt);
    }

    function swapDaiForGem(address usr, uint256 daiAmt, uint256 minGemAmt) external returns (uint256 gemAmt) {
        gemAmt = previewSwapDaiForGem(daiAmt);
        require(gemAmt >= minGemAmt, "D3MSwapPool/too-little-gems");
        dai.transferFrom(msg.sender, address(this), daiAmt);
        require(gem.transfer(usr, gemAmt), "D3MSwapPool/failed-transfer");

        emit SwapDaiForGem(usr, daiAmt, gemAmt);
    }

}
