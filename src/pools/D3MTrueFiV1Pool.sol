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


import {
    TokenLike,
    CanLike,
    D3mHubLike,
    PortfolioLike
} from "../tests/interfaces/interfaces.sol";
import "./ID3MPool.sol";

contract D3MTrueFiV1Pool is ID3MPool {

    PortfolioLike public immutable portfolio;

    // --- Auth ---
    mapping (address => uint256) public wards;
    
    modifier auth {
        require(wards[msg.sender] == 1, "D3mTrueFiV1DaiPool/not-authorized");
        _;
    }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Collect();

    constructor(address dai_, address portfolio_, address hub_) {
        portfolio = PortfolioLike(portfolio_);

        TokenLike(dai_).approve(portfolio_, type(uint256).max);

        CanLike(D3mHubLike(hub_).vat()).hope(hub_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
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

    function hope(address hub) external override auth{
        CanLike(D3mHubLike(hub).vat()).hope(hub);
    }

    function nope(address hub) external override auth{
        CanLike(D3mHubLike(hub).vat()).nope(hub);
    }

    // --- Integration ---
    function deposit(uint256 amt) external override auth returns (bool) {
        portfolio.deposit(amt, "0x");
        return true;
    }

    function withdraw(uint256 amt) external override auth returns (bool) {
        uint256 sharesAmount = portfolio.getAmountToMint(amt); // convert dai into portfolio shares
        portfolio.withdraw(sharesAmount, "0x");
        return true;
    }

    function transfer(address dst, uint256 amt) external override auth returns (bool) {
        return portfolio.transfer(dst, amt);
    }

    function transferAll(address dst) external override auth returns (bool) {
        return portfolio.transfer(dst, assetBalance());
    }

    function assetBalance() public view override returns (uint256) {
        uint256 totalShares = portfolio.totalSupply();
        if (totalShares == 0) {
            return 0;
        }
        uint256 shares = portfolio.balanceOf(address(this));
        uint256 portfolioValue = portfolio.value();
        return shares * portfolioValue / totalShares;
    }

    function maxDeposit() external view override returns (uint256) {
        return portfolio.maxSize() - portfolio.totalDeposited();
    }

    function maxWithdraw() external view override returns (uint256) {
        if (portfolio.getStatus() != PortfolioLike.PortfolioStatus.Closed) {
            return 0;
        } else {
            return _min(assetBalance(), portfolio.liquidValue());
        }
    }

    function recoverTokens(address token, address dst, uint256 amt) external auth returns (bool) {
        return TokenLike(token).transfer(dst, amt);
    }

    function active() external pure override returns (bool) {
        return true;
    }

    function preDebtChange(bytes32 what) external override {}

    function postDebtChange(bytes32 what) external override {}

    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }
}
