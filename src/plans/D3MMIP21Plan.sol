// SPDX-FileCopyrightText: © 2021-2022 Dai Foundation <www.daifoundation.org>
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

import "./ID3MPlan.sol";

interface TokenLike {
    function totalSupply() external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

/// Combines the MIP21 Input and Output conduits
contract D3MMIP21Plan is ID3MPlan {

    mapping (address => uint256) public wards;
    mapping (address => uint256) public can;
    mapping (address => uint256) public bud;
    address                      public to;
    uint256                      public cap;

    TokenLike public immutable dai;
    TokenLike public immutable gov;
    address public immutable escrow;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event Hope(address indexed usr);
    event Nope(address indexed usr);
    event Kiss(address indexed who);
    event Diss(address indexed who);
    event Pick(address indexed who);
    event Push(address indexed to, uint256 wad);

    constructor(address dai_, address gov_, address escrow_) {
        dai = TokenLike(dai_);
        gov = TokenLike(gov_);
        escrow = escrow_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MMIP21Plan/not-authorized");
        _;
    }

    modifier operator {
        require(can[msg.sender] == 1, "D3MMIP21Plan/not-operator");
        _;
    }

    // --- Math ---
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

    function hope(address usr) external auth {
        can[usr] = 1;
        emit Hope(usr);
    }
    function nope(address usr) external auth {
        can[usr] = 0;
        emit Nope(usr);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "cap") {
            cap = data;
        } else revert("D3MMIP21Plan/file-unrecognized-param");
        emit File(what, data);
    }

    function kiss(address who) public auth {
        bud[who] = 1;
        emit Kiss(who);
    }
    function diss(address who) public auth {
        if (to == who) to = address(0);
        bud[who] = 0;
        emit Diss(who);
    }

    // --- Plan Interface ---
    function getTargetAssets(uint256 currentAssets) external override view returns (uint256) {
        currentAssets;
        return cap;
    }

    function active() public pure override returns (bool) {
        return true;
    }

    function disable() external override {
        require(
            wards[msg.sender] == 1 ||
            !active()
        , "D3MMIP21Plan/not-authorized");
        cap = 0;
        emit Disable();
    }

    // --- Routing ---
    function pick(address who) public operator {
        require(bud[who] == 1 || who == address(0), "D3MMIP21Plan/not-bud");
        to = who;
        emit Pick(who);
    }
    function push() external {
        require(to != address(0), "D3MMIP21Plan/to-not-set");
        require(gov.balanceOf(msg.sender) > 0, "D3MMIP21Plan/no-gov");
        uint256 balance = dai.balanceOf(address(escrow));
        uint256 amtToPush = _min(balance, cap);
        unchecked {
            cap -= amtToPush;
        }
        emit Push(to, balance);
        dai.transferFrom(escrow, to, amtToPush);
        to = address(0);
    }
    function pull() external {
        require(gov.balanceOf(msg.sender) > 0, "D3MMIP21Plan/no-gov");
        uint256 balance = dai.balanceOf(address(this));
        emit Push(escrow, balance);
        dai.transfer(escrow, balance);
    }
}
