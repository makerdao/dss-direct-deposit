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
    D3MDeploy,
    D3MInstance
} from "../src/deploy/D3MDeploy.sol";

contract D3MDeployScript is Script {

    using stdJson for string;
    using ScriptTools for string;

    string config;
    DssInstance dss;

    string d3mType;
    address admin;
    address hub;
    bytes32 ilk;
    D3MInstance d3m;

    function run() external {
        config = ScriptTools.loadConfig("aave");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        d3mType = config.readString(".type");
        admin = config.readAddress(".admin");
        hub = config.readAddress(".hub");
        ilk = config.readString(".ilk").stringToBytes32();

        vm.startBroadcast();
        if (d3mType.eq("aave")) {
            d3m = D3MDeploy.deployAave(
                msg.sender,
                admin,
                ilk,
                address(dss.vat),
                hub,
                address(dss.dai),
                config.readAddress(".lendingPool")
            );
        } else if (d3mType.eq("compound")) {
            d3m = D3MDeploy.deployCompound(
                msg.sender,
                admin,
                ilk,
                address(dss.vat),
                hub,
                config.readAddress(".cdai")
            );
        } else {
            revert("unknown-d3m-type");
        }
        vm.stopBroadcast();

        ScriptTools.exportContract("POOL", d3m.pool);
        ScriptTools.exportContract("PLAN", d3m.plan);
        ScriptTools.exportContract("ORACLE", d3m.oracle);
    }

}
