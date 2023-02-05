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
    D3MCommonConfig,
    D3MAavePoolConfig,
    D3MCompoundPoolConfig,
    D3MAavePlanConfig,
    D3MCompoundPlanConfig,
    AavePoolLike,
    AavePlanLike,
    CompoundPoolLike,
    CompoundPlanLike
} from "../src/deploy/D3MInit.sol";

contract D3MInitScript is Script {

    using stdJson for string;
    using ScriptTools for string;

    uint256 constant BPS = 10 ** 4;
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    string config;
    string dependencies;
    DssInstance dss;

    string poolType;
    string planType;
    bytes32 ilk;
    D3MInstance d3m;
    D3MCommonConfig cfg;

    function run() external {
        config = ScriptTools.loadConfig();
        dependencies = ScriptTools.loadDependencies();
        dss = MCD.loadFromChainlog(config.readAddress("chainlog"));

        poolType = config.readString("poolType");
        planType = config.readString("planType");
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

        vm.startBroadcast();

        D3MInit.initCommon(
            dss,
            d3m,
            cfg
        );

        // Pool
        if (poolType.eq("aave")) {
            D3MAavePoolConfig memory aaveCfg = D3MAavePoolConfig({
                king: config.readAddress("king"),
                adai: AavePoolLike(d3m.pool).adai(),
                stableDebt: AavePoolLike(d3m.pool).stableDebt(),
                variableDebt: AavePoolLike(d3m.pool).variableDebt()
            });
            D3MInit.initAavePool(
                dss,
                d3m,
                cfg,
                aaveCfg
            );
        } else if (poolType.eq("compound")) {
            D3MCompoundPoolConfig memory compoundCfg = D3MCompoundPoolConfig({
                king: config.readAddress("king"),
                cdai: CompoundPoolLike(d3m.pool).cDai(),
                comptroller: CompoundPoolLike(d3m.pool).comptroller(),
                comp: CompoundPoolLike(d3m.pool).comp()
            });
            D3MInit.initCompoundPool(
                dss,
                d3m,
                cfg,
                compoundCfg
            );
        } else {
            revert("Unknown pool type");
        }

        // Plan
        if (planType.eq("rate-target")) {
            if (poolType.eq("aave")) {
                D3MAavePlanConfig memory aaveCfg = D3MAavePlanConfig({
                    bar: config.readUint("bar") * RAY / BPS,
                    adai: AavePoolLike(d3m.pool).adai(),
                    stableDebt: AavePoolLike(d3m.pool).stableDebt(),
                    variableDebt: AavePoolLike(d3m.pool).variableDebt(),
                    tack: AavePlanLike(d3m.plan).tack(),
                    adaiRevision: AavePlanLike(d3m.plan).adaiRevision()
                });
                D3MInit.initAavePlan(
                    d3m,
                    aaveCfg
                );
            } else if (poolType.eq("compound")) {
                D3MCompoundPlanConfig memory compoundCfg = D3MCompoundPlanConfig({
                    barb: config.readUint("barb"),
                    cdai: CompoundPoolLike(d3m.pool).cDai(),
                    tack: CompoundPlanLike(d3m.plan).tack(),
                    delegate: CompoundPlanLike(d3m.plan).delegate()
                });
                D3MInit.initCompoundPlan(
                    d3m,
                    compoundCfg
                );
            } else {
                revert("Invalid pool type for rate target plan type");
            }
        } else if (planType.eq("debt-ceiling")) {
            D3MInit.initDebtCeilingPlan(
                dss,
                d3m,
                cfg
            );
        } else {
            revert("Unknown plan type");
        }

        vm.stopBroadcast();
    }

}
