// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
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
    function hope(address) external;
    function nope(address) external;
    function move(address, address, uint256) external;
    function slip(bytes32, address, int256) external;
    function frob(bytes32, address, address, address, int256, int256) external;
    function suck(address, address, uint256) external;
    function urns(bytes32, address) external view returns (uint256, uint256);
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
}

interface DaiJoinLike {
    function vat() external view returns (address);
    function dai() external view returns (address);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

interface TokenLike {
    function decimals() external view returns (uint8);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface PipLike {
    function read() external view returns (bytes32);
}

interface D3mHubLike {
    function vat() external view returns (address);
    function end() external view returns (EndLike);
}

interface EndLike {
    function Art(bytes32) external view returns (uint256);
}

/**
 *  @title D3M Swap Pool
 *  @notice Swap one asset for another. Pays market participants to hit desired ratio.
 */
contract D3MSwapPool is ID3MPool {

    // --- Data ---
    mapping (address => uint256) public wards;
    address                      public hub;
    uint256                      public exited;
    uint256                      public buffer;   // Keep a buffer in DAI for liquidity [WAD]

    int256  public tin;      // toll in  [wad]
    int256  public tout;     // toll out [wad]

    bytes32   immutable public ilk;
    VatLike   immutable public vat;
    TokenLike immutable public dai;
    TokenLike immutable public gem;
    PipLike   immutable public pip;

    uint256 immutable private GEM_CONVERSION_FACTOR;

    uint256 constant WAD = 10 ** 18;
    int256 constant SWAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    string constant ARITHMETIC_ERROR = string(abi.encodeWithSignature("Panic(uint256)", 0x11));

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, int256 data);
    event File(bytes32 indexed what, address data);
    event SellGem(address indexed owner, uint256 gemsLocked, uint256 daiMinted, int256 fee);
    event BuyGem(address indexed owner, uint256 gemsUnlocked, uint256 daiBurned, int256 fee);

    modifier auth {
        require(wards[msg.sender] == 1, "D3MSwapPool/not-authorized");
        _;
    }

    modifier onlyHub {
        require(msg.sender == hub, "D3MSwapPool/only-hub");
        _;
    }

    constructor(bytes32 _ilk, address _hub, address _vat, address _dai, address _gem, address _pip) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        
        ilk = _ilk;
        hub = _hub;
        vat = VatLike(_vat);
        dai = TokenLike(_dai);
        gem = TokenLike(_gem);
        pip = TokenLike(_pip);

        GEM_CONVERSION_FACTOR = 10 ** (18 - gem.decimals());
    }

    // --- Math ---
    function _int256(uint256 x) internal pure returns (int256 y) {
        require((y = int256(x)) >= 0, ARITHMETIC_ERROR);
    }

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x + y - 1) / y;
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
        else revert("D3MSwapPool/file-unrecognized-param");

        emit File(what, data);
    }

    function file(bytes32 what, int256 data) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");
        require(-SWAD <= data && data <= SWAD, "D3MSwapPool/out-of-range");

        if (what == "tin") tin = data;
        else if (what == "tout") tout = data;
        else revert("D3MSwapPool/file-unrecognized-param");

        emit File(what, data);
    }

    function file(bytes32 what, address data) external auth {
        require(vat.live() == 1, "D3MSwapPool/no-file-during-shutdown");

        if (what == "hub") {
            vat.nope(hub);
            hub = data;
            vat.hope(data);
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

    // --- Swaps ---
    function sellGem(address usr, uint256 gemAmt) external {
        // TODO
        uint256 gemAmt18;
        uint256 mintAmount;
        {
            (address pip,) = spotter.ilks(ilk);
            gemAmt18 = gemAmt * to18ConversionFactor;
            mintAmount = gemAmt18 * uint256(PipLike(pip).read()) / WAD;  // Round down against user
        }

        // Transfer in gems and mint dai
        (uint256 Art,,, uint256 line,) = vat.ilks(ilk);
        require(gem.transferFrom(msg.sender, address(this), gemAmt), "D3MSwapPool/failed-transfer");
        require((Art + mintAmount) * RAY + buff <= line, "D3MSwapPool/buffer-exceeded");
        vat.slip(ilk, address(this), _int256(gemAmt18));
        vat.frob(ilk, address(this), address(this), address(this), int256(gemAmt18), _int256(mintAmount));

        // Fee calculations
        int256 fee = int256(mintAmount) * tin / SWAD;
        uint256 daiAmt;
        if (fee >= 0) {
            // Positive fee - move fee to vow
            // NOTE: we exclude the case where ufee > mintAmount in the tin file constraint
            uint256 ufee = uint256(fee);
            daiAmt = mintAmount - ufee;
            vat.move(address(this), vow, ufee * RAY);
        } else {
            // Negative fee - pay the user extra from the vow
            uint256 ufee = uint256(-fee);
            daiAmt = mintAmount + ufee;
            vat.suck(vow, address(this), ufee * RAY);
        }
        daiJoin.exit(usr, daiAmt);

        emit SellGem(usr, gemAmt, daiAmt, fee);
    }
    function buyGem(address usr, uint256 gemAmt) external {
        // TODO
        uint256 gemAmt18;
        uint256 burnAmount;
        {
            (address pip,) = spotter.ilks(ilk);
            gemAmt18 = gemAmt * to18ConversionFactor;
            burnAmount = _divup(gemAmt18 * uint256(PipLike(pip).read()), WAD);  // Round up against user
        }

        // Fee calculations
        int256 fee = _int256(burnAmount) * tout / SWAD;
        uint256 daiAmt;
        if (fee >= 0) {
            // Positive fee - move fee to vow below after daiAmt comes in
            daiAmt = burnAmount + uint256(fee);
        } else {
            // Negative fee - pay the user extra from the vow
            // NOTE: we exclude the case where ufee > burnAmount in the tout file constraint
            uint256 ufee = uint256(-fee);
            daiAmt = burnAmount - ufee;
            vat.suck(vow, address(this), ufee * RAY);
        }

        // Transfer in dai, repay loan and transfer out gems
        require(dai.transferFrom(msg.sender, address(this), daiAmt), "D3MSwapPool/failed-transfer");
        daiJoin.join(address(this), daiAmt);
        vat.frob(ilk, address(this), address(this), address(this), -_int256(gemAmt18), -int256(burnAmount));
        vat.slip(ilk, address(this), -int256(gemAmt18));
        require(gem.transfer(usr, gemAmt), "D3MSwapPool/failed-transfer");
        if (fee >= 0) {
            vat.move(address(this), vow, uint256(fee) * RAY);
        }

        emit BuyGem(usr, gemAmt, daiAmt, fee);
    }

    // --- Global Settlement Support ---
    function exit(address dst, uint256 wad) external override onlyHub {
        uint256 exited_ = exited;
        exited = exited_ + wad;
        uint256 amt = wad * assetBalance() / ((D3mHubLike(hub).end().Art(ilk) - exited_) * GEM_CONVERSION_FACTOR);
        require(gem.transfer(dst, amt), "D3MCompoundV2TypePool/transfer-failed");
    }

}
