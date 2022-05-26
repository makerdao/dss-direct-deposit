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

pragma solidity >=0.6.12;

import { D3MTestGem } from "./D3MTestGem.sol";
import "../../pools/ID3MPool.sol";
import { TokenLike, CanLike, d3mHubLike } from "../interfaces/interfaces.sol";

interface RewardsClaimerLike {
    function claimRewards(address[] memory assets, uint256 amount, address to) external returns (uint256);
}

contract D3MTestPool is ID3MPool {

    RewardsClaimerLike public immutable rewardsClaimer;
    address            public immutable share; // Token representing a share of the asset pool
    TokenLike          public immutable asset; // Dai
    address            public           king;  // Who gets the rewards

    // test helper variables
    uint256        maxDepositAmount = type(uint256).max;
    bool    public accrued = false;
    bool    public active_ = true;

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "D3MTestPool/not-authorized");
        _;
    }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Collect(address indexed king, address[] assets, uint256 amt);

    constructor(address hub_, address dai_, address share_, address _rewardsClaimer) public {
        asset = TokenLike(dai_);
        share = share_;

        rewardsClaimer = RewardsClaimerLike(_rewardsClaimer);

        CanLike(d3mHubLike(hub_).vat()).hope(hub_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Testing Admin ---
    function file(bytes32 what, bool data) external auth {
        if (what == "accrued") accrued = data;
        else if (what == "active_") active_ = data;
        else revert("D3MTestPool/file-unrecognized-param");
    }
    function file(bytes32 what, uint256 data) external auth {
        if (what == "maxDepositAmount") maxDepositAmount = data;
        else revert("D3MTestPool/file-unrecognized-param");
    }

    // --- Admin ---
    function file(bytes32 what, address data) external auth {
        if (what == "king") king = data;
        else revert("D3MTestPool/file-unrecognized-param");
    }

    function deposit(uint256 amt) external override {
        D3MTestGem(share).mint(address(this), amt);
        TokenLike(asset).transfer(share, amt);
    }

    function withdraw(uint256 amt) external override {
        D3MTestGem(share).burn(address(this), amt);
        TokenLike(asset).transferFrom(share, address(msg.sender), amt);
    }

    function transfer(address dst, uint256 amt) public override auth returns (bool) {
        return TokenLike(share).transfer(dst, amt);
    }

    function transferAll(address dst) external override auth returns (bool) {
        return TokenLike(share).transfer(dst, shareBalance());
    }

    function accrueIfNeeded() external override {
        accrued = true;
    }

    function assetBalance() external view override returns (uint256) {
        return convertToAssets(shareBalance());
    }

    function maxDeposit() external view override returns (uint256) {
        return maxDepositAmount;
    }

    function maxWithdraw() external view override returns (uint256) {
        return TokenLike(asset).balanceOf(share);
    }

    function shareBalance() public view returns (uint256) {
        return TokenLike(share).balanceOf(address(this));
    }

    function convertToAssets(uint256 shares) public pure returns (uint256) {
        return shares;
    }

    function recoverTokens(address token, address dst, uint256 amt) external override auth returns (bool) {
        return TokenLike(token).transfer(dst, amt);
    }

    function active() external view override returns (bool) {
        return active_;
    }

    function collect() external auth returns (uint256 amt) {
        require(king != address(0), "D3MTestPool/king-not-set");

        address[] memory assets = new address[](1);
        assets[0] = address(share);

        amt = rewardsClaimer.claimRewards(assets, type(uint256).max, king);
        emit Collect(king, assets, amt);
    }
}
