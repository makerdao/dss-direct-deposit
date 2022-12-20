// SPDX-License-Identifier: AGPL-3.0-or-later

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

    bytes32 d3mType;
    string planType;
    address admin;
    bytes32 ilk;
    D3MInstance d3m;

    function run() external {
        config = ScriptTools.readInput("config");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog", "D3M_CHAINLOG"));

        d3mType = keccak256(bytes(config.readString(".type", "D3M_TYPE")));
        planType = config.readString(".planType", "D3M_PLAN_TYPE");
        admin = config.readAddress(".admin", "D3M_ADMIN");
        ilk = config.readString(".ilk", "D3M_ILK").stringToBytes32();

        vm.startBroadcast();
        if (d3mType == keccak256("aave")) {
            d3m = D3MDeploy.deployAave(
                msg.sender,
                admin,
                planType,
                ilk,
                address(dss.vat),
                dss.chainlog.getAddress("DIRECT_HUB"),
                address(dss.dai),
                config.readAddress(".aave.lendingPool", "D3M_AAVE_LENDING_POOL")
            );
        } else if (d3mType == keccak256("compound")) {
            d3m = D3MDeploy.deployCompound(
                msg.sender,
                admin,
                planType,
                ilk,
                address(dss.vat),
                dss.chainlog.getAddress("DIRECT_HUB"),
                config.readAddress(".compound.cdai", "D3M_COMPOUND_CDAI")
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
