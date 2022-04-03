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

pragma solidity 0.6.12;

import "../bases/D3MPoolBase.sol";

interface CErc20 {
    function interestRateModel()                 external view returns (address);
    function underlying()                        external view returns (address);
    function comptroller()                       external view returns (address);
    function exchangeRateStored()                external view returns (uint256);
    function getCash()                           external view returns (uint256);
    function getAccountSnapshot(address account) external view returns (uint256, uint256, uint256, uint256);
    function mint(uint256 mintAmount)               external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
}

interface Comptroller {
    function getCompAddress() external view returns (address);
    function claimComp(address[] memory holders, address[] memory cTokens, bool borrowers, bool suppliers) external;
}

contract D3MCompoundDaiPool is D3MPoolBase {

    Comptroller public immutable comptroller;
    address     public immutable rateModel;

    address public king; // Who gets the rewards

    event Collect(address indexed king, address indexed comp);

    // TODO: remove the address(0) passing once pool is removed from D3MPlanBase
    constructor(address hub_, address dai_, address cDai_) public D3MPoolBase(hub_, dai_, address(0)) {

        address rateModel_   = CErc20(cDai_).interestRateModel();
        address comptroller_ = CErc20(cDai_).comptroller();

        require(dai_               == CErc20(cDai_).underlying(), "D3MCompoundDaiPool/cdai-dai-mismatch");
        require(rateModel_         != address(0), "D3MCompoundDaiPool/invalid-rateModel");
        require(comptroller_       != address(0), "D3MCompoundDaiPool/invalid-comptroller");

        rateModel   = rateModel_;
        comptroller = Comptroller(comptroller_);
        share       = cDai_;

        TokenLike(dai_).approve(cDai_,  type(uint256).max);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;

    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "D3MCompoundDaiPool/overflow");
    }
    function _wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, y) / WAD;
    }
    function _wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, WAD) / y;
    }

    // --- Admin ---
    function file(bytes32 what, address data) public override auth {
        require(live == 1, "D3MCompoundDaiPool/no-file-not-live");

        if (what == "king") king = data;
        else super.file(what, data);
    }

    function validTarget() external view override returns (bool) {
        return CErc20(share).interestRateModel() == rateModel;
    }

    function deposit(uint256 amt) external override auth {
        require(CErc20(share).mint(amt) == 0, "D3MCompoundDaiPool/mint-failure");
        // TODO: emit deposit event if we decide to leave it in base
    }

    function withdraw(uint256 amt) external override auth {
        require(CErc20(share).redeemUnderlying(amt) == 0, "D3MCompoundDaiPool/redeemUnderlying-failure");
        TokenLike(asset).transfer(hub, amt);
        // TODO: emit withdraw event if we decide to leave it in base
    }

    // --- Collect any rewards ---
    function collect() external auth {
        require(king != address(0), "D3MCompoundDaiPool/king-not-set");

        address[] memory holders = new address[](1);
        holders[0] = address(this);
        address[] memory cTokens = new address[](1);
        cTokens[0] = share;

        comptroller.claimComp(holders, cTokens, false, true);
        TokenLike comp = TokenLike(comptroller.getCompAddress());
        comp.transfer(king, comp.balanceOf(address(this)));

        emit Collect(king, address(comp));
    }

    function transferShares(address dst, uint256 amt) external override returns (bool) {
        return TokenLike(share).transfer(dst, amt);
    }

    // Note: Does not accrue interest (as opposed to cToken's balanceOfUnderlying() which is not a view function).
    function assetBalance() external view override returns (uint256) {
        (uint256 error, uint256 cTokenBalance,, uint256 exchangeRate) = CErc20(share).getAccountSnapshot(address(this));
        return (error == 0) ? _wmul(cTokenBalance, exchangeRate) : 0;
    }

    function shareBalance() public view override returns (uint256) {
        return TokenLike(share).balanceOf(address(this));
    }

    function maxWithdraw() external view override returns (uint256) {
        return CErc20(share).getCash();
    }

    // Note: Does not accrue interest.
    function convertToShares(uint256 amt) external view override returns (uint256) {
        return _wdiv(amt, CErc20(share).exchangeRateStored());
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        // TODO: return amt? possibly remove if we remove it from the base
    }

    // TODO: see if need an authed function to send to pause proxy any token, assuming it will be done in base
}
