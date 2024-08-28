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

contract OptionalLoadDependencies {

    function loadDependencies(string memory name) external returns (string memory) {
        return ScriptTools.loadDependencies(name);
    }

}

contract D3MDeployScript is Script {

    using stdJson for string;
    using ScriptTools for string;

    string config;
    string dependencies;
    DssInstance dss;

    string poolType;
    string planType;
    address admin;
    address hub;
    bytes32 ilk;
    D3MInstance d3m;

    function run() external {
        config = ScriptTools.loadConfig();
        OptionalLoadDependencies lp = new OptionalLoadDependencies();   // Try catch needs external function
        try lp.loadDependencies("core") returns (string memory deps) {
            dependencies = deps;
        } catch {
            // Fallback to chainlog
        }
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        poolType = config.readString(".poolType");
        planType = config.readString(".planType");
        admin = config.readAddress(".admin");
        hub = dependencies.eq("") ? dss.chainlog.getAddress("DIRECT_HUB") : dependencies.readAddress(".hub");
        ilk = config.readString(".ilk").stringToBytes32();

        vm.startBroadcast();

        // Oracle
        d3m.oracle = D3MDeploy.deployOracle(
            msg.sender,
            admin,
            ilk,
            address(dss.vat)
        );

        // Pool
        if (poolType.eq("aave-v2")) {
            d3m.pool = D3MDeploy.deployAaveV2TypePool(
                msg.sender,
                admin,
                ilk,
                hub,
                address(dss.dai),
                config.readAddress(".lendingPool")
            );
        } else if (poolType.eq("aave-v3-no-supply-cap")) {
            d3m.pool = D3MDeploy.deployAaveV3NoSupplyCapTypePool(
                msg.sender,
                admin,
                ilk,
                hub,
                address(dss.dai),
                config.readAddress(".lendingPool")
            );
        } else if (poolType.eq("aave-v3-usds-no-supply-cap")) {
            d3m.pool = D3MDeploy.deployAaveV3USDSNoSupplyCapTypePool(
                msg.sender,
                admin,
                ilk,
                hub,
                config.readAddress(".usdsJoin"),
                address(dss.daiJoin),
                config.readAddress(".lendingPool")
            );
        } else if (poolType.eq("compound-v2")) {
            d3m.pool = D3MDeploy.deployCompoundV2TypePool(
                msg.sender,
                admin,
                ilk,
                hub,
                config.readAddress(".cdai")
            );
        } else if (poolType.eq("erc4626")) {
            d3m.pool = D3MDeploy.deploy4626TypePool(
                msg.sender,
                admin,
                ilk,
                hub,
                address(dss.dai),
                config.readAddress(".vault")
            );
        } else {
            revert("Unknown pool type");
        }

        // Plan
        if (planType.eq("rate-target")) {
            if (poolType.eq("aave-v2")) {
                d3m.plan = D3MDeploy.deployAaveV2TypeRateTargetPlan(
                    msg.sender,
                    admin,
                    address(dss.dai),
                    config.readAddress(".lendingPool")
                );
            } else if (poolType.eq("compound-v2")) {
                d3m.plan = D3MDeploy.deployCompoundV2TypeRateTargetPlan(
                    msg.sender,
                    admin,
                    config.readAddress(".cdai")
                );
            } else {
                revert("Invalid pool type for rate target plan type");
            }
        } else if (planType.eq("liquidity-buffer")) {
            if (poolType.eq("aave-v2") || poolType.eq("aave-v3-no-supply-cap")) {
                d3m.plan = D3MDeploy.deployAaveBufferPlan(
                    msg.sender,
                    admin,
                    config.readAddress(".adai")
                );
            } else {
                revert("Invalid pool type for liquidity buffer plan type");
            }
        } else if (planType.eq("operator")) {
            d3m.plan = D3MDeploy.deployOperatorPlan(
                msg.sender,
                admin
            );
        } else {
            revert("Unknown plan type");
        }
        vm.stopBroadcast();

        ScriptTools.exportContract("pool", d3m.pool);
        ScriptTools.exportContract("plan", d3m.plan);
        ScriptTools.exportContract("oracle", d3m.oracle);
    }

}
