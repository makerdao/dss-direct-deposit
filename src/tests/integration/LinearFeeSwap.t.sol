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

import "./IntegrationBase.t.sol";

import "./SwapPoolBase.t.sol";

import { D3MLinearFeeSwapPool } from "../../pools/D3MLinearFeeSwapPool.sol";

abstract contract LinearFeeSwapBaseTest is SwapPoolBaseTest {

    D3MLinearFeeSwapPool pool;

    function deployPool() internal override returns (address) {
        pool = D3MLinearFeeSwapPool(D3MDeploy.deployLinearFeeSwapPool(
            address(this),
            admin,
            ilk,
            address(hub),
            address(dai),
            address(gem)
        ));
        return address(pool);
    }

}

contract USDCSwapTest is LinearFeeSwapBaseTest {
    
    function getGem() internal override pure returns (address) {
        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function getPip() internal override pure returns (address) {
        return 0x77b68899b99b686F415d074278a9a16b336085A0;  // Hardcoded $1 pip
    }

    function getSwapGemForDaiPip() internal override pure returns (address) {
        return 0x77b68899b99b686F415d074278a9a16b336085A0;
    }

    function getSwapDaiForGemPip() internal override pure returns (address) {
        return 0x77b68899b99b686F415d074278a9a16b336085A0;
    }

}

contract GUSDSwapTest is LinearFeeSwapBaseTest {

    using stdStorage for StdStorage;
    
    function getGem() internal override pure returns (address) {
        return 0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd;
    }

    function getPip() internal override pure returns (address) {
        return 0xf45Ae69CcA1b9B043dAE2C83A5B65Bc605BEc5F5;  // Hardcoded $1 pip
    }

    function getSwapGemForDaiPip() internal override pure returns (address) {
        return 0xf45Ae69CcA1b9B043dAE2C83A5B65Bc605BEc5F5;
    }

    function getSwapDaiForGemPip() internal override pure returns (address) {
        return 0xf45Ae69CcA1b9B043dAE2C83A5B65Bc605BEc5F5;
    }

    // GUSD has a separate storage contract so we need to override deal
    function deal(address token, address to, uint256 give) internal override {
        if (token == getGem()) {
            // Target the storage contract for GUSD
            stdstore.target(0xc42B14e49744538e3C239f8ae48A1Eaaf35e68a0).sig(bytes4(abi.encodeWithSignature("balances(address)"))).with_key(to).checked_write(give);
        } else {
            super.deal(token, to, give);
        }
    }

}

contract USDPSwapTest is LinearFeeSwapBaseTest {
    
    function getGem() internal override pure returns (address) {
        return 0x8E870D67F660D95d5be530380D0eC0bd388289E1;
    }

    function getPip() internal override pure returns (address) {
        return 0x043B963E1B2214eC90046167Ea29C2c8bDD7c0eC;  // Hardcoded $1 pip
    }

    function getSwapGemForDaiPip() internal override pure returns (address) {
        return 0x043B963E1B2214eC90046167Ea29C2c8bDD7c0eC;
    }

    function getSwapDaiForGemPip() internal override pure returns (address) {
        return 0x043B963E1B2214eC90046167Ea29C2c8bDD7c0eC;
    }

}

contract BackedIB01SwapTest is LinearFeeSwapBaseTest {

    PipMock private _pip;

    function setUp() public override {
        // Setup an oracle
        _pip = new PipMock();
        _pip.poke(1.2 ether);   // Set to some non-$1 value
        
        super.setUp();
    }
    
    function getGem() internal override pure returns (address) {
        return 0xCA30c93B02514f86d5C86a6e375E3A330B435Fb5;
    }

    function getPip() internal override view returns (address) {
        return address(_pip);
    }

    function getSwapGemForDaiPip() internal override view returns (address) {
        return address(_pip);
    }

    function getSwapDaiForGemPip() internal override view returns (address) {
        return address(_pip);
    }

    // Backed IB01 earns interest by asset value appreciation vs getting more tokens
    function generateInterest() internal override {
        _pip.poke(uint256(_pip.read()) * 101 / 100);
    }

}
