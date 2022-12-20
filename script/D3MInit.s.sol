// SPDX-License-Identifier: AGPL-3.0-or-later

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
    D3MCompoundConfig
} from "../src/deploy/D3MInit.sol";

contract D3MInitScript is Script {

    using stdJson for string;
    using ScriptTools for string;

    uint256 constant BPS = 10 ** 4;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    string config;
    DssInstance dss;

    bytes32 d3mType;
    string planType;
    bytes32 ilk;
    D3MInstance d3m;
    D3MCommonConfig cfg;
    D3MAaveConfig aaveCfg;
    D3MCompoundConfig compoundCfg;

    function run() external {
        config = ScriptTools.readInput("config");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog", "D3M_CHAINLOG"));

        d3mType = keccak256(bytes(config.readString(".type", "D3M_TYPE")));
        planType = config.readString(".planType", "D3M_PLAN_TYPE");
        ilk = config.readString(".ilk", "D3M_ILK").stringToBytes32();

        d3m = D3MInstance({
            pool: ScriptTools.importContract("POOL"),
            plan: ScriptTools.importContract("PLAN"),
            oracle: ScriptTools.importContract("ORACLE")
        });
        cfg = D3MCommonConfig({
            ilk: ilk,
            maxLine: config.readUint(".maxLine", "D3M_MAX_LINE") * RAD,
            gap: config.readUint(".gap", "D3M_GAP") * RAD,
            ttl: config.readUint(".ttl", "D3M_TTL"),
            tau: config.readUint(".tau", "D3M_TAU")
        });

        vm.startBroadcast();
        if (d3mType == keccak256("aave")) {
            aaveCfg = D3MAaveConfig({
                planType: planType,
                king: config.readAddress(".aave.king", "D3M_AAVE_KING"),
                bar: config.readUint(".aave.bar", "D3M_AAVE_BAR") * RAY / BPS
            });
            D3MInit.initAave(
                dss,
                d3m,
                cfg,
                aaveCfg
            );
        } else if (d3mType == keccak256("compound")) {
            compoundCfg = D3MCompoundConfig({
                planType: planType,
                king: config.readAddress(".compound.king", "D3M_COMPOUND_KING"),
                barb: config.readUint(".compound.barb", "D3M_COMPOUND_BARB")
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
