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

import { D3MHub } from "../D3MHub.sol";
import { D3MMom } from "../D3MMom.sol";
import { D3MOracle } from "../D3MOracle.sol";
import { D3MInstance } from "./D3MInstance.sol";
import { D3MAaveV2TypeRateTargetPlan } from "../plans/D3MAaveV2TypeRateTargetPlan.sol";
import { D3MAaveTypeBufferPlan } from "../plans/D3MAaveTypeBufferPlan.sol";
import { D3MCompoundV2TypeRateTargetPlan } from "../plans/D3MCompoundV2TypeRateTargetPlan.sol";
import { D3MALMDelegateControllerPlan } from "../plans/D3MALMDelegateControllerPlan.sol";
import { D3MAaveV2TypePool } from "../pools/D3MAaveV2TypePool.sol";
import { D3MAaveV3NoSupplyCapTypePool } from "../pools/D3MAaveV3NoSupplyCapTypePool.sol";
import { D3MCompoundV2TypePool } from "../pools/D3MCompoundV2TypePool.sol";
import { D3MLinearFeeSwapPool } from "../pools/D3MLinearFeeSwapPool.sol";
import { D3MGatedOffchainSwapPool } from "../pools/D3MGatedOffchainSwapPool.sol";
import { D3MForwardFees } from "../fees/D3MForwardFees.sol";

// Deploy a D3M instance
library D3MDeploy {

    function deployHub(
        address deployer,
        address owner,
        address daiJoin
    ) internal returns (address hub) {
        hub = address(new D3MHub(daiJoin));

        ScriptTools.switchOwner(hub, deployer, owner);
    }

    function deployMom(
        address owner
    ) internal returns (address mom) {
        mom = address(new D3MMom());

        DSAuthAbstract(mom).setOwner(owner);
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

    function deployLinearFeeSwapPool(
        address deployer,
        address owner,
        bytes32 ilk,
        address hub,
        address dai,
        address gem
    ) internal returns (address pool) {
        pool = address(new D3MLinearFeeSwapPool(ilk, hub, dai, gem));

        ScriptTools.switchOwner(pool, deployer, owner);
    }

    function deployGatedOffchainSwapPool(
        address deployer,
        address owner,
        bytes32 ilk,
        address hub,
        address dai,
        address gem
    ) internal returns (address pool) {
        pool = address(new D3MGatedOffchainSwapPool(ilk, hub, dai, gem));

        ScriptTools.switchOwner(pool, deployer, owner);
    }

    function deployALMDelegateControllerPlan(
        address deployer,
        address owner
    ) internal returns (address plan) {
        plan = address(new D3MALMDelegateControllerPlan());

        ScriptTools.switchOwner(plan, deployer, owner);
    }

    function deployForwardFees(
        address vat,
        address target
    ) internal returns (address fees) {
        fees = address(new D3MForwardFees(vat, target));
    }

}
