// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.8.0;

import "dss-interfaces/Interfaces.sol";
import { DssInstance } from "dss-test/MCD.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";

import { D3MInstance } from "./D3MInstance.sol";

interface AavePoolLike {
    function hub() external view returns (address);
    function dai() external view returns (address);
    function ilk() external view returns (bytes32);
    function vat() external view returns (address);
    function file(bytes32, address) external;
    function adai() external view returns (address);
}

interface AavePlanLike {
    function rely(address) external;
    function file(bytes32, uint256) external;
}

interface CompoundPoolLike {
    function hub() external view returns (address);
    function dai() external view returns (address);
    function ilk() external view returns (bytes32);
    function vat() external view returns (address);
    function file(bytes32, address) external;
    function cDai() external view returns (address);
}

interface CompoundPlanLike {
    function rely(address) external;
    function file(bytes32, uint256) external;
}

interface D3MOracleLike {
    function vat() external view returns (address);
    function ilk() external view returns (bytes32);
    function file(bytes32, address) external;
}

interface D3MHubLike {
    function file(bytes32, bytes32, address) external;
    function file(bytes32, bytes32, uint256) external;
}

struct D3MCommonConfig {
    bytes32 ilk;
    uint256 maxLine;
    uint256 gap;
    uint256 ttl;
    uint256 tau;
}

struct D3MAaveConfig {
    string planType;
    address king;
    uint256 bar;
}

struct D3MCompoundConfig {
    string planType;
    address king;
    uint256 barb;
}

// Init a D3M instance
library D3MInit {

    function _init(
        DssInstance memory dss,
        D3MInstance memory d3m,
        D3MCommonConfig memory cfg,
        address gem
    ) private {
        bytes32 ilk = cfg.ilk;
        D3MHubLike hub = D3MHubLike(dss.chainlog.getAddress("DIRECT_HUB"));
        D3MOracleLike oracle = D3MOracleLike(d3m.oracle);

        // Sanity checks
        require(oracle.vat() == address(dss.vat), "Oracle vat mismatch");
        require(oracle.ilk() == ilk, "Oracle ilk mismatch");

        hub.file(ilk, "pool", d3m.pool);
        hub.file(ilk, "plan", d3m.plan);
        hub.file(ilk, "tau", cfg.tau);

        oracle.file("hub", address(hub));

        dss.spotter.file(ilk, "pip", address(oracle));
        dss.spotter.file(ilk, "mat", 10 ** 27);
        dss.vat.init(ilk);
        dss.jug.init(ilk);
        dss.vat.file(ilk, "line", cfg.gap);
        dss.vat.file("Line", dss.vat.Line() + cfg.gap);
        DssAutoLineAbstract(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE")).setIlk(
            ilk,
            cfg.maxLine,
            cfg.gap,
            cfg.ttl
        );
        dss.spotter.poke(ilk);

        IlkRegistryAbstract(dss.chainlog.getAddress("ILK_REGISTRY")).put(
            ilk,
            address(hub),
            address(gem),
            GemAbstract(gem).decimals(),
            4,
            address(oracle),
            address(0),
            GemAbstract(gem).name(),
            GemAbstract(gem).symbol()
        );
    }

    function initAave(
        DssInstance memory dss,
        D3MInstance memory d3m,
        D3MCommonConfig memory cfg,
        D3MAaveConfig memory aaveCfg
    ) internal {
        AavePlanLike plan = AavePlanLike(d3m.plan);
        AavePoolLike pool = AavePoolLike(d3m.pool);

        _init(dss, d3m, cfg, pool.adai());

        // Sanity checks
        require(pool.hub() == address(dss.chainlog.getAddress("DIRECT_HUB")), "Pool hub mismatch");
        require(pool.ilk() == cfg.ilk, "Pool ilk mismatch");
        require(pool.vat() == address(dss.vat), "Pool vat mismatch");
        require(pool.dai() == address(dss.dai), "Pool dai mismatch");

        plan.rely(dss.chainlog.getAddress("DIRECT_MOM"));
        pool.file("king", aaveCfg.king);
        if (keccak256(bytes(aaveCfg.planType)) == keccak256("rate-target")) {
            plan.file("bar", aaveCfg.bar);
        }
    }

    function initCompound(
        DssInstance memory dss,
        D3MInstance memory d3m,
        D3MCommonConfig memory cfg,
        D3MCompoundConfig memory compoundCfg
    ) internal {
        CompoundPlanLike plan = CompoundPlanLike(d3m.plan);
        CompoundPoolLike pool = CompoundPoolLike(d3m.pool);

        _init(dss, d3m, cfg, pool.cDai());

        // Sanity checks
        require(pool.hub() == dss.chainlog.getAddress("DIRECT_HUB"), "Pool hub mismatch");
        require(pool.ilk() == cfg.ilk, "Pool ilk mismatch");
        require(pool.vat() == address(dss.vat), "Pool vat mismatch");
        require(pool.dai() == address(dss.dai), "Pool dai mismatch");

        plan.rely(dss.chainlog.getAddress("DIRECT_MOM"));
        pool.file("king", compoundCfg.king);
        if (keccak256(bytes(compoundCfg.planType)) == keccak256("rate-target")) {
            plan.file("barb", compoundCfg.barb);
        }
    }

}
