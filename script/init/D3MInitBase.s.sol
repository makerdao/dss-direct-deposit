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

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";

import {
    D3MInit,
    D3MInstance,
    D3MCommonConfig
} from "../../src/deploy/D3MInit.sol";

contract D3MInitBase is Script {

    using stdJson for string;
    using ScriptTools for string;

    uint256 constant BPS = 10 ** 4;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    string config;
    string dependencies;
    DssInstance dss;

    string d3mType;
    bytes32 ilk;
    D3MInstance d3m;
    D3MCommonConfig cfg;

    function _setup() internal {
        config = ScriptTools.loadConfig();
        dependencies = ScriptTools.loadDependencies();
        dss = MCD.loadFromChainlog(config.readAddress("chainlog"));

        d3mType = config.readString("type");
        ilk = config.readString("ilk").stringToBytes32();

        d3m = D3MInstance({
            pool: dependencies.readAddress("pool"),
            plan: dependencies.readAddress("plan"),
            oracle: dependencies.readAddress("oracle")
        });
        cfg = D3MCommonConfig({
            hub: dependencies.readAddress("hub"),
            mom: dependencies.readAddress("mom"),
            ilk: ilk,
            existingIlk: config.readBool("existingIlk"),
            maxLine: config.readUint("maxLine") * RAD,
            gap: config.readUint("gap") * RAD,
            ttl: config.readUint("ttl"),
            tau: config.readUint("tau")
        });
    }

}
