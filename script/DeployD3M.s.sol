// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";

import {
    DssDirectDeposit,
    D3MInstance
} from "../src/deploy/DssDirectDeposit.sol";

contract DeployD3M is Script {

    using stdJson for string;
    using ScriptTools for string;

    string config;
    DssInstance dss;

    bytes32 d3mType;
    address admin;
    bytes32 ilk;
    D3MInstance d3m;

    function run() external {
        config = ScriptTools.readInput("config");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog", "D3M_CHAINLOG"));

        d3mType = keccak256(bytes(config.readString(".type", "D3M_TYPE")));
        admin = config.readAddress(".admin", "D3M_ADMIN");
        ilk = config.readString(".ilk", "D3M_ILK").stringToBytes32();

        vm.startBroadcast();
        if (d3mType == keccak256("aave")) {
            d3m = DssDirectDeposit.deployAave(
                msg.sender,
                admin,
                ilk,
                address(dss.vat),
                dss.chainlog.getAddress("DIRECT_HUB"),
                address(dss.dai),
                config.readAddress(".aaveLendingPool", "D3M_AAVE_LENDING_POOL")
            );
        } else if (d3mType == keccak256("compound")) {
            d3m = DssDirectDeposit.deployCompound(
                msg.sender,
                admin,
                ilk,
                address(dss.vat),
                dss.chainlog.getAddress("DIRECT_HUB"),
                config.readAddress(".compoundCDai", "D3M_COMPOUND_CDAI")
            );
        } else {
            revert("unknown-d3m-type");
        }
        vm.stopBroadcast();

        ScriptTools.logContract("POOL", address(d3m.pool));
        ScriptTools.logContract("PLAN", address(d3m.plan));
        ScriptTools.logContract("ORACLE", address(d3m.oracle));
    }

}
