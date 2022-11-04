// SPDX-FileCopyrightText: © 2021 Dai Foundation <www.daifoundation.org>
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

interface TokenLike {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface VatLike {
    function live() external view returns (uint256);
    function hope(address) external;
    function nope(address) external;
}

interface D3mHubLike {
    function vat() external view returns (address);
    function end() external view returns (EndLike);
}

interface EndLike {
    function Art(bytes32) external view returns (uint256);
}

interface PsmLike {
    function gemJoin() external view returns (address);
    function buyGem(address, uint256) external;
    function sellGem(address, uint256) external;
}

interface GemJoinLike {
    function gem() external view returns (address);
}

contract D3MUsdcPsmPool is ID3MPool {

    mapping (address => uint256) public wards;
    address                      public hub;
    address                      public king; // Who gets the rewards
    uint256                      public exited;

    bytes32   public immutable ilk;
    VatLike   public immutable vat;
    PsmLike   public immutable psm;
    address   public immutable gemJoin;
    TokenLike public immutable dai;
    TokenLike public immutable usdc;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event Collect(address indexed king, address indexed gift, uint256 amt);

    constructor(bytes32 ilk_, address hub_, address dai_, address psm_) {
        ilk  = ilk_;
        dai  = TokenLike(dai_);
        psm  = PsmLike(psm_);
        gemJoin = psm.gemJoin();
        usdc = TokenLike(GemJoinLike(gemJoin).gem());

        dai.approve(psm_, type(uint256).max);
        dai.approve(gemJoin, type(uint256).max);
        usdc.approve(gemJoin, type(uint256).max);

        hub = hub_;
        vat = VatLike(D3mHubLike(hub_).vat());
        vat.hope(hub_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MUsdcPsmPool/not-authorized");
        _;
    }

    modifier onlyHub {
        require(msg.sender == hub, "D3MUsdcPsmPool/only-hub");
        _;
    }

    // --- Math ---
    uint256 internal constant RAY = 10 ** 27;
    function _rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * RAY) / y;
    }
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
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

    function file(bytes32 what, address data) external auth {
        require(vat.live() == 1, "D3MUsdcPsmPool/no-file-during-shutdown");
        if (what == "hub") {
            vat.nope(hub);
            hub = data;
            vat.hope(data);
        } else if (what == "king") king = data;
        else revert("D3MUsdcPsmPool/file-unrecognized-param");
        emit File(what, data);
    }

    function deposit(uint256 wad) external override onlyHub {
        uint256 prev = usdc.balanceOf(address(this));

        uint256 wad6 = wad / 10 ** 12;

        psm.buyGem(address(this), wad6);

        require(usdc.balanceOf(address(this)) == (prev + wad6), "D3MUsdcPsmPool/incorrect-adai-balance-received");
    }

    // Withdraws Dai from Aave in exchange for adai
    // Aave: https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#withdraw
    function withdraw(uint256 wad) external override onlyHub {
        uint256 prevDai = dai.balanceOf(msg.sender);

        psm.sellGem(msg.sender, wad / 10 ** 12);

        require(dai.balanceOf(msg.sender) == prevDai + wad, "D3MUsdcPsmPool/incorrect-dai-balance-received");
    }

    function exit(address dst, uint256 wad) external override onlyHub {
        uint256 exited_ = exited;
        exited = exited_ + wad;
        uint256 amt = wad * assetBalance() / (D3mHubLike(hub).end().Art(ilk) - exited_);
        require(usdc.transfer(dst, amt/10**12), "D3MUsdcPsmPool/transfer-failed");
    }

    function quit(address dst) external override auth {
        require(vat.live() == 1, "D3MUsdcPsmPool/no-quit-during-shutdown");
        require(usdc.transfer(dst, usdc.balanceOf(address(this))), "D3MUsdcPsmPool/transfer-failed");
    }

    function preDebtChange() external override {}

    function postDebtChange() external override {}

    // --- Balance of the underlying asset (Dai)
    function assetBalance() public view override returns (uint256) {
        return usdc.balanceOf(address(this)) * 10**12;
    }

    function maxDeposit() external view override returns (uint256) {
        return usdc.balanceOf(address(gemJoin)) * 10**12;
    }

    function maxWithdraw() external view override returns (uint256) {
        return assetBalance();
    }

    function redeemable() external view override returns (address) {
        return address(usdc);
    }
}
