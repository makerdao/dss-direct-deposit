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
    D3MAaveRateTargetPlanConfig,
    D3MCompoundRateTargetPlanConfig,
    D3MAavePoolLike,
    D3MAaveRateTargetPlanLike,
    D3MAaveBufferPlanLike,
    D3MAaveBufferPlanConfig,
    D3MCompoundPoolLike,
    D3MCompoundRateTargetPlanLike,
    CDaiLike
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
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        poolType = config.readString(".poolType");
        planType = config.readString(".planType");
        ilk = config.readString(".ilk").stringToBytes32();

        d3m = D3MInstance({
            pool: dependencies.readAddress(".pool"),
            plan: dependencies.readAddress(".plan"),
            oracle: dependencies.readAddress(".oracle")
        });
        cfg = D3MCommonConfig({
            hub: dependencies.readAddress(".hub"),
            mom: dependencies.readAddress(".mom"),
            ilk: ilk,
            existingIlk: config.readBool(".existingIlk"),
            maxLine: config.readUint(".maxLine") * RAD,
            gap: config.readUint(".gap") * RAD,
            ttl: config.readUint(".ttl"),
            tau: config.readUint(".tau")
        });

        vm.startBroadcast();
        
        // Common config setup
        D3MInit.initCommon(
            dss,
            d3m,
            cfg
        );

        // Pool
        if (poolType.eq("aave-v2") || poolType.eq("aave-v3")) {
            D3MAavePoolConfig memory aaveCfg = D3MAavePoolConfig({
                king: config.readAddress(".king"),
                adai: D3MAavePoolLike(d3m.pool).adai(),
                stableDebt: D3MAavePoolLike(d3m.pool).stableDebt(),
                variableDebt: D3MAavePoolLike(d3m.pool).variableDebt()
            });
            D3MInit.initAavePool(
                dss,
                d3m,
                cfg,
                aaveCfg
            );
        } else if (poolType.eq("compound-v2")) {
            D3MCompoundPoolConfig memory compoundCfg = D3MCompoundPoolConfig({
                king: config.readAddress(".king"),
                cdai: D3MCompoundPoolLike(d3m.pool).cDai(),
                comptroller: D3MCompoundPoolLike(d3m.pool).comptroller(),
                comp: D3MCompoundPoolLike(d3m.pool).comp()
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
            if (poolType.eq("aave-v2")) {
                D3MAaveRateTargetPlanConfig memory aaveCfg = D3MAaveRateTargetPlanConfig({
                    bar: config.readUint(".bar") * RAY / BPS,
                    adai: D3MAavePoolLike(d3m.pool).adai(),
                    stableDebt: D3MAavePoolLike(d3m.pool).stableDebt(),
                    variableDebt: D3MAavePoolLike(d3m.pool).variableDebt(),
                    tack: D3MAaveRateTargetPlanLike(d3m.plan).tack(),
                    adaiRevision: D3MAaveRateTargetPlanLike(d3m.plan).adaiRevision()
                });
                D3MInit.initAaveRateTargetPlan(
                    d3m,
                    aaveCfg
                );
            } else if (poolType.eq("compound-v2")) {
                D3MCompoundRateTargetPlanConfig memory compoundCfg = D3MCompoundRateTargetPlanConfig({
                    barb: config.readUint(".barb"),
                    cdai: D3MCompoundPoolLike(d3m.pool).cDai(),
                    tack: CDaiLike(D3MCompoundRateTargetPlanLike(d3m.plan).cDai()).interestRateModel(),
                    delegate: CDaiLike(D3MCompoundRateTargetPlanLike(d3m.plan).cDai()).implementation()
                });
                D3MInit.initCompoundRateTargetPlan(
                    d3m,
                    compoundCfg
                );
            } else {
                revert("Invalid pool type for rate target plan type");
            }
        } else if (planType.eq("liquidity-buffer")) {
            if (poolType.eq("aave-v2") || poolType.eq("aave-v3")) {
                D3MAaveBufferPlanConfig memory aaveCfg = D3MAaveBufferPlanConfig({
                    buffer: config.readUint(".buffer") * WAD,
                    adai: D3MAavePoolLike(d3m.pool).adai(),
                    adaiRevision: D3MAaveBufferPlanLike(d3m.plan).adaiRevision()
                });
                D3MInit.initAaveBufferPlan(
                    d3m,
                    aaveCfg
                );
            } else {
                revert("Invalid pool type for rate target plan type");
            }
        } else {
            revert("Unknown plan type");
        }

        vm.stopBroadcast();
    }

}
