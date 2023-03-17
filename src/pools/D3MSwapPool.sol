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

interface SpotterLike {
    function ilks(bytes32) external view returns (address, uint256);
}

interface PipLike {
    function read() external view returns (bytes32);
}

/**
 *  @title D3M Swap Pool
 *  @notice Swap one asset for another.
 */
contract D3MSwapPool is ID3MPool {

    // --- Data ---
    mapping (address => uint256) public wards;
    address                      public hub;

    int256  public tin;      // toll in  [wad]
    int256  public tout;     // toll out [wad]

    bytes32     immutable public ilk;
    TokenLike   immutable public gem;
    VatLike     immutable public vat;
    TokenLike   immutable public dai;
    DaiJoinLike immutable public daiJoin;
    SpotterLike immutable public spotter;

    uint256 immutable private to18ConversionFactor;

    uint256 constant WAD = 10 ** 18;
    int256 constant SWAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    string constant ARITHMETIC_ERROR = string(abi.encodeWithSignature("Panic(uint256)", 0x11));

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, int256 data);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, uint256 data);
    event SellGem(address indexed owner, uint256 gemsLocked, uint256 daiMinted, int256 fee);
    event BuyGem(address indexed owner, uint256 gemsUnlocked, uint256 daiBurned, int256 fee);
    event Exit(address indexed usr, uint256 amt);
    event Rectify(uint256 nav, uint256 debt);

    modifier auth {
        require(wards[msg.sender] == 1, "Psm/not-authorized");
        _;
    }

    modifier onlyHub {
        require(msg.sender == hub, "D3MCompoundV2TypePool/only-hub");
        _;
    }

    constructor(bytes32 _ilk, address _gem, address _daiJoin, address _spotter) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        
        ilk = _ilk;
        gem = TokenLike(_gem);
        daiJoin = DaiJoinLike(_daiJoin);
        vat = VatLike(daiJoin.vat());
        dai = TokenLike(daiJoin.dai());
        spotter = SpotterLike(_spotter);

        to18ConversionFactor = 10 ** (18 - gem.decimals());

        dai.approve(_daiJoin, type(uint256).max);
        vat.hope(_daiJoin);
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

    function file(bytes32 what, int256 data) external auth {
        require(-SWAD <= data && data <= SWAD, "Psm/out-of-range");

        if (what == "tin") tin = data;
        else if (what == "tout") tout = data;
        else revert("Psm/file-unrecognized-param");

        emit File(what, data);
    }

    // --- Swaps ---
    function sellGem(address usr, uint256 gemAmt) external {
        uint256 gemAmt18;
        uint256 mintAmount;
        {
            (address pip,) = spotter.ilks(ilk);
            gemAmt18 = gemAmt * to18ConversionFactor;
            mintAmount = gemAmt18 * uint256(PipLike(pip).read()) / WAD;  // Round down against user
        }

        // Transfer in gems and mint dai
        (uint256 Art,,, uint256 line,) = vat.ilks(ilk);
        require(gem.transferFrom(msg.sender, address(this), gemAmt), "Psm/failed-transfer");
        require((Art + mintAmount) * RAY + buff <= line, "Psm/buffer-exceeded");
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
        require(dai.transferFrom(msg.sender, address(this), daiAmt), "Psm/failed-transfer");
        daiJoin.join(address(this), daiAmt);
        vat.frob(ilk, address(this), address(this), address(this), -_int256(gemAmt18), -int256(burnAmount));
        vat.slip(ilk, address(this), -int256(gemAmt18));
        require(gem.transfer(usr, gemAmt), "Psm/failed-transfer");
        if (fee >= 0) {
            vat.move(address(this), vow, uint256(fee) * RAY);
        }

        emit BuyGem(usr, gemAmt, daiAmt, fee);
    }

    // --- Global Settlement Support ---
    function exit(address usr, uint256 gemAmt) external {
        vat.slip(ilk, msg.sender, -_int256(gemAmt * to18ConversionFactor));
        require(gem.transfer(usr, gemAmt), "Psm/failed-transfer");

        emit Exit(usr, gemAmt);
    }

}
