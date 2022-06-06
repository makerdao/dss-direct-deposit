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

import "./ID3MPool.sol";

interface TokenLike {
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface CanLike {
    function hope(address) external;
    function nope(address) external;
}

interface D3mHubLike {
    function vat() external view returns (address);
}

interface PortfolioLike is TokenLike {
    enum PortfolioStatus {
        Open,
        Frozen,
        Closed
    }

    function deposit(uint256 depositAmount, bytes memory metadata) external;
    function withdraw(uint256 sharesAmount, bytes memory) external returns (uint256);
    function getAmountToMint(uint256 amount) external returns (uint256);
    function maxSize() external view returns (uint256);
    function totalDeposited() external view returns (uint256);
    function getStatus() external view returns (PortfolioStatus);
    function liquidValue() external view returns (uint256);
}

contract D3mTrueFiV1DaiPool is ID3MPool {

    TokenLike     public immutable dai;
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

    constructor(address dai_, address portfolio_) public {
        portfolio = PortfolioLike(portfolio_);
        dai = TokenLike(dai_);

        TokenLike(dai_).approve(portfolio_, type(uint256).max);

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
    function deposit(uint256 amt) external override auth {
        portfolio.deposit(amt, "0x");
    }

    function withdraw(uint256 amt) external override auth {
        uint256 sharesAmount = portfolio.getAmountToMint(amt); // convert dai into portfolio shares
        portfolio.withdraw(sharesAmount, "0x"); 
    }

    function transfer(address dst, uint256 amt) external override auth returns (bool) {
        return portfolio.transfer(dst, amt);
    }

    function transferAll(address dst) external override auth returns (bool) {
        return portfolio.transfer(dst, assetBalance());
    }

    function accrueIfNeeded() external override {} // there is no manual interest claiming in TrueFi

    function assetBalance() public view override returns (uint256) {
        return portfolio.balanceOf(address(this));
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

    function recoverTokens(address token, address dst, uint256 amt) external override auth returns (bool) {
        return TokenLike(token).transfer(dst, amt);
    }

    function active() external view override returns (bool) {
        return true;
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }
}
