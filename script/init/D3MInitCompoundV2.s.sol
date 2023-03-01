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

pragma solidity ^0.8.0;

import { D3MInitBase, D3MInit } from "./D3MInitBase.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";

import {
    D3MCompoundConfig,
    CompoundPoolLike,
    CompoundPlanLike
} from "../../src/deploy/D3MInit.sol";

contract D3MInitScript is D3MInitBase {

    using stdJson for string;
    using ScriptTools for string;

    function run() external {
        _setup();

        vm.startBroadcast();

        compoundCfg = D3MCompoundConfig({
            king: config.readAddress("king"),
            barb: config.readUint("barb"),
            cdai: CompoundPoolLike(d3m.pool).cDai(),
            comptroller: CompoundPoolLike(d3m.pool).comptroller(),
            comp: CompoundPoolLike(d3m.pool).comp(),
            tack: CompoundPlanLike(d3m.plan).tack(),
            delegate: CompoundPlanLike(d3m.plan).delegate()
        });
        D3MInit.initCompound(
            dss,
            d3m,
            cfg,
            compoundCfg
        );

        vm.stopBroadcast();
    }

}
