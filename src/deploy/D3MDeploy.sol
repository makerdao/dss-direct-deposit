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

import "dss-interfaces/Interfaces.sol";
import { DssInstance } from "dss-test/MCD.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";

import { D3MCoreInstance } from "./D3MCoreInstance.sol";
import { D3MHub } from "../D3MHub.sol";
import { D3MMom } from "../D3MMom.sol";
import { D3MInstance } from "./D3MInstance.sol";
import { D3MAaveV2TypeRateTargetPlan } from "../plans/D3MAaveV2TypeRateTargetPlan.sol";
import { D3MAaveTypeBufferPlan } from "../plans/D3MAaveTypeBufferPlan.sol";
import { D3MAaveV2TypePool } from "../pools/D3MAaveV2TypePool.sol";
import { D3MAaveV3NoSupplyCapTypePool } from "../pools/D3MAaveV3NoSupplyCapTypePool.sol";
import { D3MCompoundV2TypeRateTargetPlan } from "../plans/D3MCompoundV2TypeRateTargetPlan.sol";
import { D3MCompoundV2TypePool } from "../pools/D3MCompoundV2TypePool.sol";
import { D3MOracle } from "../D3MOracle.sol";

// Deploy a D3M instance
library D3MDeploy {

    function deployCore(
        address deployer,
        address owner,
        address daiJoin
    ) internal returns (D3MCoreInstance memory d3mCore) {
        d3mCore.hub = address(new D3MHub(daiJoin));
        d3mCore.mom = address(new D3MMom());

        ScriptTools.switchOwner(d3mCore.hub, deployer, owner);
        DSAuthAbstract(d3mCore.mom).setOwner(owner);
    }

    function deployOracle(
        address deployer,
        address owner,
        bytes32 ilk,
        address vat
    ) internal returns (address oracle) {
        oracle = address(new D3MOracle(vat, ilk));

        ScriptTools.switchOwner(oracle, deployer, owner);
    }

    function deployAaveV2TypePool(
        address deployer,
        address owner,
        bytes32 ilk,
        address hub,
        address dai,
        address lendingPool
    ) internal returns (address pool) {
        pool = address(new D3MAaveV2TypePool(ilk, hub, dai, lendingPool));

        ScriptTools.switchOwner(pool, deployer, owner);
    }

    function deployAaveV3NoSupplyCapTypePool(
        address deployer,
        address owner,
        bytes32 ilk,
        address hub,
        address dai,
        address lendingPool
    ) internal returns (address pool) {
        pool = address(new D3MAaveV3NoSupplyCapTypePool(ilk, hub, dai, lendingPool));

        ScriptTools.switchOwner(pool, deployer, owner);
    }

    function deployCompoundV2TypePool(
        address deployer,
        address owner,
        bytes32 ilk,
        address hub,
        address cdai
    ) internal returns (address pool) {
        pool = address(new D3MCompoundV2TypePool(ilk, hub, cdai));

        ScriptTools.switchOwner(pool, deployer, owner);
    }

    function deployAaveV2TypeRateTargetPlan(
        address deployer,
        address owner,
        address dai,
        address lendingPool
    ) internal returns (address plan) {
        plan = address(new D3MAaveV2TypeRateTargetPlan(dai, lendingPool));

        ScriptTools.switchOwner(plan, deployer, owner);
    }

    function deployAaveBufferPlan(
        address deployer,
        address owner,
        address adai
    ) internal returns (address plan) {
        plan = address(new D3MAaveTypeBufferPlan(adai));

        ScriptTools.switchOwner(plan, deployer, owner);
    }

    function deployCompoundV2TypeRateTargetPlan(
        address deployer,
        address owner,
        address cdai
    ) internal returns (address plan) {
        plan = address(new D3MCompoundV2TypeRateTargetPlan(cdai));

        ScriptTools.switchOwner(plan, deployer, owner);
    }

}
