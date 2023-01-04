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
    D3MAaveConfig,
    D3MCompoundConfig,
    AavePoolLike,
    AavePlanLike,
    CompoundPoolLike,
    CompoundPlanLike
} from "../src/deploy/D3MInit.sol";

contract D3MInitScript is Script {

    using stdJson for string;
    using ScriptTools for string;

    uint256 constant BPS = 10 ** 4;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    string config;
    DssInstance dss;

    string d3mType;
    string planType;
    bytes32 ilk;
    D3MInstance d3m;
    D3MCommonConfig cfg;
    D3MAaveConfig aaveCfg;
    D3MCompoundConfig compoundCfg;

    function run() external {
        config = ScriptTools.loadConfig();
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        d3mType = config.readString(".type");
        planType = config.readString(".planType");
        ilk = config.readString(".ilk").stringToBytes32();

        d3m = D3MInstance({
            pool: ScriptTools.importContract("POOL"),
            plan: ScriptTools.importContract("PLAN"),
            oracle: ScriptTools.importContract("ORACLE")
        });
        cfg = D3MCommonConfig({
            ilk: ilk,
            maxLine: config.readUint(".maxLine") * RAD,
            gap: config.readUint(".gap") * RAD,
            ttl: config.readUint(".ttl"),
            tau: config.readUint(".tau")
        });

        vm.startBroadcast();
        if (d3mType.eq("aave")) {
            aaveCfg = D3MAaveConfig({
                planType: planType,
                king: config.readAddress(".king"),
                bar: config.readUint(".bar") * RAY / BPS,
                adai: AavePoolLike(d3m.pool).adai(),
                stableDebt: AavePoolLike(d3m.pool).stableDebt(),
                variableDebt: AavePoolLike(d3m.pool).variableDebt(),
                tack: planType.eq("rate-target") ? AavePlanLike(d3m.plan).tack() : address(0),
                adaiRevision: planType.eq("rate-target") ? AavePlanLike(d3m.plan).adaiRevision() : 0
            });
            D3MInit.initAave(
                dss,
                d3m,
                cfg,
                aaveCfg
            );
        } else if (d3mType.eq("compound")) {
            compoundCfg = D3MCompoundConfig({
                planType: planType,
                king: config.readAddress(".king"),
                barb: config.readUint(".barb"),
                cdai: CompoundPoolLike(d3m.pool).cDai(),
                comptroller: CompoundPoolLike(d3m.pool).comptroller(),
                comp: CompoundPoolLike(d3m.pool).comp(),
                tack: planType.eq("rate-target") ? CompoundPlanLike(d3m.plan).tack() : address(0),
                delegate: planType.eq("rate-target") ? CompoundPlanLike(d3m.plan).delegate() : address(0)
            });
            D3MInit.initCompound(
                dss,
                d3m,
                cfg,
                compoundCfg
            );
        } else {
            revert("unknown-d3m-type");
        }
        vm.stopBroadcast();
    }

}
