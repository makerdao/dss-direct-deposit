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

    struct FeeData {
        uint24 buffer;  // where to place the fee1/fee2 change as ratio between gem and dai [bps]
        uint24 tin1;    // toll in under the buffer  [bps]
        uint24 tout1;   // toll out under the buffer [bps]
        uint24 tin2;    // toll in over the buffer   [bps]
        uint24 tout2;   // toll out over the buffer  [bps]
    }

    // --- Data ---
    mapping (address => uint256) public wards;

    HubLike public hub;
    PipLike public pip;
    PipLike public sellGemPip;
    PipLike public buyGemPip;
    FeeData public feeData;
    uint256 public exited;

    bytes32   immutable public ilk;
    VatLike   immutable public vat;
    TokenLike immutable public dai;
    TokenLike immutable public gem;

    uint256 immutable private GEM_CONVERSION_FACTOR;

    uint256 constant BPS = 10 ** 4;
    uint256 constant WAD = 10 ** 18;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint24 data);
    event File(bytes32 indexed what, uint24 tin, uint24 tout);
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

        // Initialize all fees to zero
        feeData = FeeData({
            buffer: 0,
            tin1: uint24(BPS),
            tout1: uint24(BPS),
            tin2: uint24(BPS),
            tout2: uint24(BPS)
        });

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

    function file(bytes32 what, uint24 data) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");
        require(data <= BPS, "D3MSwapPool/invalid-buffer");

        if (what == "buffer") feeData.buffer = data;
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

    function file(bytes32 what, address data) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");

        if (what == "hub") {
            vat.nope(address(hub));
            hub = HubLike(data);
            vat.hope(data);
        } else if (what == "pip") {
            pip = PipLike(data);
        } else if (what == "sellGemPip") {
            sellGemPip = PipLike(data);
        } else if (what == "buyGemPip") {
            buyGemPip = PipLike(data);
        } else revert("D3MSwapPool/file-unrecognized-param");

        emit File(what, data);
    }

    // --- Getters ---

    function buffer() external view returns (uint256) {
        return feeData.buffer;
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
    }

    function preDebtChange() external override {}

    function postDebtChange() external override {}

    function assetBalance() external view override returns (uint256) {
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
        FeeData memory _feeData = feeData;
        uint256 pipValue = uint256(sellGemPip.read());
        uint256 gemValue = gemAmt * GEM_CONVERSION_FACTOR * pipValue / WAD;
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 gemBalance = gem.balanceOf(address(this)) * GEM_CONVERSION_FACTOR * pipValue / WAD;
        uint256 desiredGemBalance = _feeData.buffer * (daiBalance + gemBalance) / BPS;
        if (gemBalance >= desiredGemBalance) {
            // We are above the buffer so apply tin2
            daiAmt = gemValue * _feeData.tin2 / BPS;
        } else {
            uint256 daiAvailableAtTin1;
            unchecked {
                daiAvailableAtTin1 = desiredGemBalance - gemBalance;
            }

            // We are below the buffer so could be a mix of tin1 and tin2
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

    function previewBuyGem(uint256 daiAmt) public view returns (uint256 gemAmt) {
        FeeData memory _feeData = feeData;
        uint256 pipValue = uint256(buyGemPip.read());
        uint256 gemValue;
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 gemBalance = gem.balanceOf(address(this)) * GEM_CONVERSION_FACTOR * pipValue / WAD;
        uint256 desiredGemBalance = _feeData.buffer * (daiBalance + gemBalance) / BPS;
        if (gemBalance <= desiredGemBalance) {
            // We are below the buffer so apply tout1
            gemValue = daiAmt * _feeData.tout1 / BPS;
        } else {
            uint256 gemsAvailableAtTout2;
            unchecked {
                gemsAvailableAtTout2 = gemBalance - desiredGemBalance;
            }

            // We are above the buffer so could be a mix of tout1 and tout2
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
