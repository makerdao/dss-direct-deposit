// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "dss-interfaces/Interfaces.sol";
import { DssInstance } from "dss-test/MCD.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";

import { D3MInstance } from "./D3MInstance.sol";
import { D3MDebtCeilingPlan } from "../plans/D3MDebtCeilingPlan.sol";
import { D3MAavePlan } from "../plans/D3MAavePlan.sol";
import { D3MAavePool } from "../pools/D3MAavePool.sol";
import { D3MCompoundPlan } from "../plans/D3MCompoundPlan.sol";
import { D3MCompoundPool } from "../pools/D3MCompoundPool.sol";
import { D3MOracle } from "../D3MOracle.sol";

struct D3MCommonConfig {
    bytes32 ilk;
    uint256 maxLine;
    uint256 gap;
    uint256 ttl;
    uint256 tau;
}

struct D3MAaveConfig {
    address king;
    uint256 bar;
}

struct D3MCompoundConfig {
    address king;
    uint256 barb;
}

// Deploy a D3M instance
library D3MDeploy {

    function deployAave(
        address deployer,
        address owner,
        string memory planType,
        bytes32 ilk,
        address vat,
        address hub,
        address dai,
        address lendingPool
    ) internal returns (D3MInstance memory d3m) {
        if (keccak256(bytes(planType)) == keccak256("rate-target")) {
            d3m.plan = address(new D3MAavePlan(dai, lendingPool));
        } else {
            d3m.plan = address(new D3MDebtCeilingPlan(vat, ilk));
        }
        d3m.pool = address(new D3MAavePool(ilk, hub, dai, lendingPool));
        d3m.oracle = address(new D3MOracle(vat, ilk));

        ScriptTools.switchOwner(d3m.plan, deployer, owner);
        ScriptTools.switchOwner(d3m.pool, deployer, owner);
        ScriptTools.switchOwner(d3m.oracle, deployer, owner);
    }

    function deployCompound(
        address deployer,
        address owner,
        string memory planType,
        bytes32 ilk,
        address vat,
        address hub,
        address cdai
    ) internal returns (D3MInstance memory d3m) {
        if (keccak256(bytes(planType)) == keccak256("rate-target")) {
            d3m.plan = address(new D3MCompoundPlan(cdai));
        } else {
            d3m.plan = address(new D3MDebtCeilingPlan(vat, ilk));
        }
        d3m.pool = address(new D3MCompoundPool(ilk, hub, cdai));
        d3m.oracle = address(new D3MOracle(vat, ilk));

        ScriptTools.switchOwner(d3m.plan, deployer, owner);
        ScriptTools.switchOwner(d3m.pool, deployer, owner);
        ScriptTools.switchOwner(d3m.oracle, deployer, owner);
    }

}
