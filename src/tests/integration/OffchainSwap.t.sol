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

import "./SwapPoolBase.t.sol";

import { D3MOffchainSwapPool } from "../../pools/D3MOffchainSwapPool.sol";

abstract contract OffchainSwapBaseTest is SwapPoolBaseTest {

    D3MOffchainSwapPool pool;

    function deployPool() internal override returns (address) {
        pool = D3MOffchainSwapPool(D3MDeploy.deployOffchainSwapPool(
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

contract MonetalisSwapTest is OffchainSwapBaseTest {
    
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
