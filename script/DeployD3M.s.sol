// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";

import {
    DssDirectDeposit,
    D3MInstance
} from "../src/deploy/DssDirectDeposit.sol";

contract DeployD3M is Script {

    using stdJson for string;

    string config;
    DssInstance dss;

    bytes32 d3mType;
    address admin;
    bytes32 ilk;
    D3MInstance d3m;

    function readInput(string memory input) internal returns (string memory) {
        string memory root = vm.projectRoot();
        string memory chainInputFolder = string(abi.encodePacked("/script/input/", vm.toString(block.chainid), "/"));
        return vm.readFile(string(abi.encodePacked(root, chainInputFolder, input, ".json")));
    }

    function stringToBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function logContract(string memory name, address addr) internal {
        console.log(string(abi.encodePacked(name, "=", vm.toString(addr))));
    }

    function run() external {
        config = readInput("config");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        d3mType = keccak256(bytes(vm.envString("DEPLOY_D3M_TYPE")));
        admin = vm.envAddress("DEPLOY_ADMIN");
        ilk = stringToBytes32(vm.envString("DEPLOY_ILK"));

        vm.startBroadcast();
        if (d3mType == keccak256("aave")) {
            d3m = DssDirectDeposit.deployAave(
                msg.sender,
                admin,
                ilk,
                address(dss.vat),
                dss.chainlog.getAddress("DIRECT_HUB"),
                address(dss.dai),
                vm.envAddress("DEPLOY_AAVE_LENDING_POOL")
            );
        } else if (d3mType == keccak256("compound")) {
            d3m = DssDirectDeposit.deployCompound(
                msg.sender,
                admin,
                ilk,
                address(dss.vat),
                dss.chainlog.getAddress("DIRECT_HUB"),
                vm.envAddress("DEPLOY_COMPOUND_CDAI")
            );
        } else {
            revert("unknown-d3m-type");
        }
        vm.stopBroadcast();

        logContract("POOL", address(d3m.pool));
        logContract("PLAN", address(d3m.plan));
        logContract("ORACLE", address(d3m.oracle));
    }

}
