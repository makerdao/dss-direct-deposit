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
import { D3MDebtCeilingPlan } from "../plans/D3MDebtCeilingPlan.sol";
import { D3MAavePlan } from "../plans/D3MAavePlan.sol";
import { D3MAavePool } from "../pools/D3MAavePool.sol";
import { D3MCompoundPlan } from "../plans/D3MCompoundPlan.sol";
import { D3MCompoundPool } from "../pools/D3MCompoundPool.sol";
import { D3MOracle } from "../D3MOracle.sol";

// Deploy a D3M instance
library D3MDeploy {

    using ScriptTools for string;

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
        if (planType.eq("rate-target")) {
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
        if (planType.eq("rate-target")) {
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
