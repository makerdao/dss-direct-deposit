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

pragma solidity >=0.8.0;

import "dss-interfaces/dss/DssAutoLineAbstract.sol";
import "dss-interfaces/dss/IlkRegistryAbstract.sol";
import "dss-interfaces/utils/WardsAbstract.sol";
import "dss-interfaces/ERC/GemAbstract.sol";
import { DssInstance } from "dss-test/MCD.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";

import { ID3MPool } from "../pools/ID3MPool.sol";
import { D3MInstance } from "./D3MInstance.sol";
import { D3MCoreInstance } from "./D3MCoreInstance.sol";

interface DebtCeilingPlanLike {
    function ilk() external view returns (bytes32);
    function vat() external view returns (address);
}

interface AavePoolLike {
    function hub() external view returns (address);
    function dai() external view returns (address);
    function ilk() external view returns (bytes32);
    function vat() external view returns (address);
    function file(bytes32, address) external;
    function adai() external view returns (address);
    function stableDebt() external view returns (address);
    function variableDebt() external view returns (address);
}

interface AavePlanLike {
    function file(bytes32, uint256) external;
    function adai() external view returns (address);
    function stableDebt() external view returns (address);
    function variableDebt() external view returns (address);
    function tack() external view returns (address);
    function adaiRevision() external view returns (uint256);
}

interface AaveBufferPlanLike {
    function file(bytes32, uint256) external;
    function adai() external view returns (address);
    function adaiRevision() external view returns (uint256);
}

interface ADaiLike {
    function ATOKEN_REVISION() external view returns (uint256);
}

interface CompoundPoolLike {
    function hub() external view returns (address);
    function dai() external view returns (address);
    function ilk() external view returns (bytes32);
    function vat() external view returns (address);
    function file(bytes32, address) external;
    function cDai() external view returns (address);
    function comptroller() external view returns (address);
    function comp() external view returns (address);
}

interface CompoundPlanLike {
    function file(bytes32, uint256) external;
    function tack() external view returns (address);
    function delegate() external view returns (address);
    function cDai() external view returns (address);
}

interface CDaiLike {
    function interestRateModel() external view returns (address);
    function implementation() external view returns (address);
}

interface D3MOracleLike {
    function vat() external view returns (address);
    function ilk() external view returns (bytes32);
    function file(bytes32, address) external;
}

interface D3MHubLike {
    function vat() external view returns (address);
    function daiJoin() external view returns (address);
    function file(bytes32, address) external;
    function file(bytes32, bytes32, address) external;
    function file(bytes32, bytes32, uint256) external;
}

interface D3MMomLike {
    function setAuthority(address) external;
}

struct D3MCommonConfig {
    address hub;
    address mom;
    bytes32 ilk;
    bool existingIlk;
    uint256 maxLine;
    uint256 gap;
    uint256 ttl;
    uint256 tau;
}

struct D3MAavePoolConfig {
    address king;
    address adai;
    address stableDebt;
    address variableDebt;
}

struct D3MAavePlanConfig {
    uint256 bar;
    address adai;
    address stableDebt;
    address variableDebt;
    address tack;
    uint256 adaiRevision;
}

struct D3MCompoundPoolConfig {
    address king;
    address cdai;
    address comptroller;
    address comp;
}

struct D3MCompoundPlanConfig {
    uint256 barb;
    address cdai;
    address tack;
    address delegate;
}

// Init a D3M instance
library D3MInit {

    using ScriptTools for string;

    function initCore(
        DssInstance memory dss,
        D3MCoreInstance memory d3mCore
    ) internal {
        D3MHubLike hub = D3MHubLike(d3mCore.hub);
        D3MMomLike mom = D3MMomLike(d3mCore.mom);

        // Sanity checks
        require(hub.vat() == address(dss.vat), "Hub vat mismatch");
        require(hub.daiJoin() == address(dss.daiJoin), "Hub daiJoin mismatch");

        hub.file("vow", address(dss.vow));
        hub.file("end", address(dss.end));

        mom.setAuthority(dss.chainlog.getAddress("MCD_ADM"));

        dss.vat.rely(address(hub));

        dss.chainlog.setAddress("DIRECT_HUB", address(hub));
        dss.chainlog.setAddress("DIRECT_MOM", address(mom));
    }

    function initCommon(
        DssInstance memory dss,
        D3MInstance memory d3m,
        D3MCommonConfig memory cfg
    ) internal {
        bytes32 ilk = cfg.ilk;
        D3MHubLike hub = D3MHubLike(cfg.hub);
        D3MOracleLike oracle = D3MOracleLike(d3m.oracle);

        // Sanity checks
        require(oracle.vat() == address(dss.vat), "Oracle vat mismatch");
        require(oracle.ilk() == ilk, "Oracle ilk mismatch");

        WardsAbstract(d3m.plan).rely(cfg.mom);

        hub.file(ilk, "pool", d3m.pool);
        hub.file(ilk, "plan", d3m.plan);
        hub.file(ilk, "tau", cfg.tau);

        oracle.file("hub", address(hub));

        dss.spotter.file(ilk, "pip", address(oracle));
        dss.spotter.file(ilk, "mat", 10 ** 27);
        uint256 previousIlkLine;
        if (cfg.existingIlk) {
            (,,, previousIlkLine,) = dss.vat.ilks(ilk);
        } else {
            dss.vat.init(ilk);
            dss.jug.init(ilk);
        }
        dss.vat.file(ilk, "line", cfg.gap);
        dss.vat.file("Line", dss.vat.Line() + cfg.gap - previousIlkLine);
        DssAutoLineAbstract(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE")).setIlk(
            ilk,
            cfg.maxLine,
            cfg.gap,
            cfg.ttl
        );
        dss.spotter.poke(ilk);

        GemAbstract gem = GemAbstract(ID3MPool(d3m.pool).redeemable());
        IlkRegistryAbstract(dss.chainlog.getAddress("ILK_REGISTRY")).put(
            ilk,
            address(hub),
            address(gem),
            gem.decimals(),
            4,
            address(oracle),
            address(0),
            gem.name(),
            gem.symbol()
        );

        string memory clPrefix = ScriptTools.ilkToChainlogFormat(ilk);
        dss.chainlog.setAddress(ScriptTools.stringToBytes32(string(abi.encodePacked(clPrefix, "_POOL"))), d3m.pool);
        dss.chainlog.setAddress(ScriptTools.stringToBytes32(string(abi.encodePacked(clPrefix, "_PLAN"))), d3m.plan);
        dss.chainlog.setAddress(ScriptTools.stringToBytes32(string(abi.encodePacked(clPrefix, "_ORACLE"))), d3m.oracle);
    }

    function initAavePool(
        DssInstance memory dss,
        D3MInstance memory d3m,
        D3MCommonConfig memory cfg,
        D3MAavePoolConfig memory aaveCfg
    ) internal {
        AavePoolLike pool = AavePoolLike(d3m.pool);

        // Sanity checks
        require(pool.hub() == cfg.hub, "Pool hub mismatch");
        require(pool.ilk() == cfg.ilk, "Pool ilk mismatch");
        require(pool.vat() == address(dss.vat), "Pool vat mismatch");
        require(pool.dai() == address(dss.dai), "Pool dai mismatch");
        require(pool.adai() == aaveCfg.adai, "Pool adai mismatch");
        require(pool.stableDebt() == aaveCfg.stableDebt, "Pool stableDebt mismatch");
        require(pool.variableDebt() == aaveCfg.variableDebt, "Pool variableDebt mismatch");

        pool.file("king", aaveCfg.king);
    }

    function initCompoundPool(
        DssInstance memory dss,
        D3MInstance memory d3m,
        D3MCommonConfig memory cfg,
        D3MCompoundPoolConfig memory compoundCfg
    ) internal {
        CompoundPoolLike pool = CompoundPoolLike(d3m.pool);
        CDaiLike cdai = CDaiLike(compoundCfg.cdai);

        // Sanity checks
        require(pool.hub() == cfg.hub, "Pool hub mismatch");
        require(pool.ilk() == cfg.ilk, "Pool ilk mismatch");
        require(pool.vat() == address(dss.vat), "Pool vat mismatch");
        require(pool.dai() == address(dss.dai), "Pool dai mismatch");
        require(pool.comptroller() == compoundCfg.comptroller, "Pool comptroller mismatch");
        require(pool.comp() == compoundCfg.comp, "Pool comp mismatch");
        require(pool.cDai() == address(cdai), "Pool cDai mismatch");

        pool.file("king", compoundCfg.king);
    }

    function initAavePlan(
        D3MInstance memory d3m,
        D3MAavePlanConfig memory aaveCfg
    ) internal {
        AavePlanLike plan = AavePlanLike(d3m.plan);
        ADaiLike adai = ADaiLike(aaveCfg.adai);

        // Sanity checks
        require(plan.adai() == address(adai), "Plan adai mismatch");
        require(plan.stableDebt() == aaveCfg.stableDebt, "Plan stableDebt mismatch");
        require(plan.variableDebt() == aaveCfg.variableDebt, "Plan variableDebt mismatch");
        require(plan.tack() == aaveCfg.tack, "Plan tack mismatch");
        require(plan.adaiRevision() == aaveCfg.adaiRevision, "Plan adaiRevision mismatch");
        require(adai.ATOKEN_REVISION() == aaveCfg.adaiRevision, "ADai adaiRevision mismatch");

        plan.file("bar", aaveCfg.bar);
    }

    function initCompoundPlan(
        D3MInstance memory d3m,
        D3MCompoundPlanConfig memory compoundCfg
    ) internal {
        CompoundPlanLike plan = CompoundPlanLike(d3m.plan);
        CDaiLike cdai = CDaiLike(compoundCfg.cdai);

        // Sanity checks
        require(plan.tack() == compoundCfg.tack, "Plan tack mismatch");
        require(cdai.interestRateModel() == compoundCfg.tack, "CDai tack mismatch");
        require(plan.delegate() == compoundCfg.delegate, "Plan delegate mismatch");
        require(cdai.implementation() == compoundCfg.delegate, "CDai delegate mismatch");
        require(plan.cDai() == address(cdai), "Plan cDai mismatch");

        plan.file("barb", compoundCfg.barb);
    }

}
