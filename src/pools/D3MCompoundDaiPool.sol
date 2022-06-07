// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021-2022 Dai Foundation
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
    function balanceOf(address)         external view returns (uint256);
    function approve(address, uint256)  external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

interface CanLike {
    function hope(address) external;
    function nope(address) external;
}

interface D3mHubLike {
    function vat() external view returns (address);
}

// https://github.com/compound-finance/compound-protocol/blob/3affca87636eecd901eb43f81a4813186393905d/contracts/CErc20.sol#L14
interface CErc20Like is TokenLike {
    function underlying()                           external view returns (address);
    function comptroller()                          external view returns (address);
    function exchangeRateStored()                   external view returns (uint256);
    function getCash()                              external view returns (uint256);
    function getAccountSnapshot(address account)    external view returns (uint256, uint256, uint256, uint256);
    function mint(uint256 mintAmount)               external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function accrueInterest()                       external returns (uint256);
    function exchangeRateCurrent()                  external returns (uint256);
}

// https://github.com/compound-finance/compound-protocol/blob/3affca87636eecd901eb43f81a4813186393905d/contracts/ComptrollerG7.sol#L15
interface ComptrollerLike {
    function getCompAddress() external view returns (address);
    function claimComp(address[] memory holders, address[] memory cTokens, bool borrowers, bool suppliers) external;
}

contract D3MCompoundDaiPool is ID3MPool {

    mapping (address => uint256) public wards;
    address                      public king; // Who gets the rewards

    ComptrollerLike public immutable comptroller;
    TokenLike       public immutable dai;
    CErc20Like      public immutable cDai;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event Collect(address indexed king, address indexed gift, uint256 amt);

    constructor(address hub_, address dai_, address cDai_) {
        address comptroller_ = CErc20Like(cDai_).comptroller();

        require(comptroller_ != address(0), "D3MCompoundDaiPool/invalid-comptroller");
        require(dai_         == CErc20Like(cDai_).underlying(), "D3MCompoundDaiPool/cdai-dai-mismatch");

        comptroller = ComptrollerLike(comptroller_);
        dai         = TokenLike(dai_);
        cDai        = CErc20Like(cDai_);

        TokenLike(dai_).approve(cDai_, type(uint256).max);

        CanLike(D3mHubLike(hub_).vat()).hope(hub_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MCompoundDaiPool/not-authorized");
        _;
    }

    // --- Math ---
    uint256 internal constant WAD = 10 ** 18;
    function _wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * y) / WAD;
    }
    function _wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * WAD) / y;
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
        if (what == "king") king = data;
        else revert("D3MCompoundDaiPool/file-unrecognized-param");
        emit File(what, data);
    }

    function hope(address hub) external override auth {
        CanLike(D3mHubLike(hub).vat()).hope(hub);
    }

    function nope(address hub) external override auth {
        CanLike(D3mHubLike(hub).vat()).nope(hub);
    }

    function deposit(uint256 wad) external override auth returns (bool) {
        uint256 prev = cDai.balanceOf(address(this));
        require(cDai.mint(wad) == 0, "D3MCompoundDaiPool/mint-failure");
        // As interest was accrued on `mint` we can use the non accruing `exchangeRateStored`
        require(
            cDai.balanceOf(address(this)) ==
            prev + _wdiv(wad, cDai.exchangeRateStored()), "D3MCompoundDaiPool/incorrect-cdai-credit"
        );
        return true;
    }

    function withdraw(uint256 wad) external override auth returns (bool) {
        require(cDai.redeemUnderlying(wad) == 0, "D3MCompoundDaiPool/redeemUnderlying-failure");
        dai.transfer(msg.sender, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) external override auth returns (bool) {
        return cDai.transfer(dst, _wdiv(wad, cDai.exchangeRateCurrent()));
    }

    function transferAll(address dst) external override auth returns (bool) {
        return cDai.transfer(dst, cDai.balanceOf(address(this)));
    }

    function preDebtChange(bytes32 what) external override {
        require(cDai.accrueInterest() == 0, "D3MCompoundDaiPool/accrueInterest-failure");
    }

    function postDebtChange(bytes32 what) external override {}

    // Does not accrue interest (as opposed to cToken's balanceOfUnderlying() which is not a view function).
    function assetBalance() public view override returns (uint256) {
        (uint256 error, uint256 cTokenBalance,, uint256 exchangeRate) = cDai.getAccountSnapshot(address(this));
        require(error == 0, "D3MCompoundDaiPool/getAccountSnapshot-failure");
        return _wmul(cTokenBalance, exchangeRate);
    }

    function maxDeposit() external pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw() external view override returns (uint256) {
        return _min(cDai.getCash(), assetBalance());
    }

    // TODO: remove active from pool and rely just on active in plan? - once supported in the interface
    function active() external pure override returns (bool) {
        return true;
    }

    function collect() external {
        require(king != address(0), "D3MCompoundDaiPool/king-not-set");

        address[] memory holders = new address[](1);
        holders[0] = address(this);
        address[] memory cTokens = new address[](1);
        cTokens[0] = address(cDai);

        comptroller.claimComp(holders, cTokens, false, true);

        TokenLike comp = TokenLike(comptroller.getCompAddress());
        uint256 amt = comp.balanceOf(address(this));
        comp.transfer(king, amt);

        emit Collect(king, address(comp), amt);
    }

    // TODO: add utility function for what token we move on transfer() - once supported in the interface
}
