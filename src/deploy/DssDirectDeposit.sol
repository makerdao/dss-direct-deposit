// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "dss-interfaces/Interfaces.sol";
import { DssInstance } from "dss-test/MCD.sol";

import { ID3MPlan } from "../plans/ID3MPlan.sol";
import { ID3MPool } from "../pools/ID3MPool.sol";
import { D3MAavePlan } from "../plans/D3MAavePlan.sol";
import { D3MAavePool } from "../pools/D3MAavePool.sol";
import { D3MCompoundPlan } from "../plans/D3MCompoundPlan.sol";
import { D3MCompoundPool } from "../pools/D3MCompoundPool.sol";
import { D3MHub } from "../D3MHub.sol";
import { D3MOracle } from "../D3MOracle.sol";

struct D3MInstance {
    ID3MPlan plan;
    ID3MPool pool;
    D3MOracle oracle;
}

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

// Deploy and initialize the D3Ms
library DssDirectDeposit {

    function switchOwner(address base, address deployer, address newOwner) internal {
        if (deployer == newOwner) return;
        require(WardsAbstract(base).wards(deployer) == 1, "deployer-not-authed");
        WardsAbstract(base).rely(newOwner);
        WardsAbstract(base).deny(deployer);
    }

    function deployAave(
        address deployer,
        address owner,
        bytes32 ilk,
        address vat,
        address hub,
        address dai,
        address lendingPool
    ) internal returns (D3MInstance memory d3m) {
        d3m.plan = new D3MAavePlan(dai, lendingPool);
        d3m.pool = new D3MAavePool(ilk, hub, dai, lendingPool);
        d3m.oracle = new D3MOracle(vat, ilk);

        switchOwner(address(d3m.plan), deployer, owner);
        switchOwner(address(d3m.pool), deployer, owner);
        switchOwner(address(d3m.oracle), deployer, owner);
    }

    function deployCompound(
        address deployer,
        address owner,
        bytes32 ilk,
        address vat,
        address hub,
        address cdai
    ) internal returns (D3MInstance memory d3m) {
        d3m.plan = new D3MCompoundPlan(cdai);
        d3m.pool = new D3MCompoundPool(ilk, hub, cdai);
        d3m.oracle = new D3MOracle(vat, ilk);

        switchOwner(address(d3m.plan), deployer, owner);
        switchOwner(address(d3m.pool), deployer, owner);
        switchOwner(address(d3m.oracle), deployer, owner);
    }

    function _init(
        DssInstance memory dss,
        D3MInstance memory d3m,
        D3MCommonConfig memory cfg
    ) private {
        bytes32 ilk = cfg.ilk;
        D3MHub hub = D3MHub(dss.chainlog.getAddress("DIRECT_HUB"));

        // Sanity checks
        require(d3m.oracle.vat() == address(dss.vat), "Oracle vat mismatch");
        require(d3m.oracle.ilk() == ilk, "Oracle ilk mismatch");

        hub.file(ilk, "pool", address(d3m.pool));
        hub.file(ilk, "plan", address(d3m.plan));
        hub.file(ilk, "tau", cfg.tau);

        d3m.oracle.file("hub", address(hub));

        dss.spotter.file(ilk, "pip", address(d3m.oracle));
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

        GemAbstract gem = GemAbstract(d3m.pool.redeemable());
        IlkRegistryAbstract(dss.chainlog.getAddress("ILK_REGISTRY")).put(
            ilk,
            address(hub),
            address(gem),
            gem.decimals(),
            4,
            address(d3m.oracle),
            address(0),
            gem.name(),
            gem.symbol()
        );
    }

    function initAave(
        DssInstance memory dss,
        D3MInstance memory d3m,
        D3MCommonConfig memory cfg,
        D3MAaveConfig memory aaveCfg
    ) internal {
        _init(dss, d3m, cfg);

        D3MAavePlan plan = D3MAavePlan(address(d3m.plan));
        D3MAavePool pool = D3MAavePool(address(d3m.pool));

        // Sanity checks
        require(address(pool.hub()) == address(dss.chainlog.getAddress("DIRECT_HUB")), "Pool hub mismatch");
        require(pool.ilk() == cfg.ilk, "Pool ilk mismatch");
        require(address(pool.vat()) == address(dss.vat), "Pool vat mismatch");
        require(address(pool.dai()) == address(dss.dai), "Pool dai mismatch");

        plan.rely(dss.chainlog.getAddress("DIRECT_MOM"));
        pool.file("king", aaveCfg.king);
        plan.file("bar", aaveCfg.bar);
    }

    function initCompound(
        DssInstance memory dss,
        D3MInstance memory d3m,
        D3MCommonConfig memory cfg,
        D3MCompoundConfig memory compoundCfg
    ) internal {
        _init(dss, d3m, cfg);

        D3MCompoundPlan plan = D3MCompoundPlan(address(d3m.plan));
        D3MCompoundPool pool = D3MCompoundPool(address(d3m.pool));

        // Sanity checks
        require(address(pool.hub()) == address(dss.chainlog.getAddress("DIRECT_HUB")), "Pool hub mismatch");
        require(pool.ilk() == cfg.ilk, "Pool ilk mismatch");
        require(address(pool.vat()) == address(dss.vat), "Pool vat mismatch");
        //require(pool.comptroller() == D3M_COMPTROLLER, "Pool comptroller mismatch");
        //require(pool.comp() == D3M_COMP, "Pool comp mismatch");
        require(address(pool.dai()) == address(dss.dai), "Pool dai mismatch");
        //require(pool.cDai() == D3M_CDAI, "Pool cDai mismatch");

        //require(plan.tack() == D3M_TACK, "Plan tack mismatch");
        //require(CDaiLike(D3M_CDAI).interestRateModel() == D3M_TACK, "Plan tack mismatch");
        //require(D3MCompoundPlanLike(D3M_COMPOUND_PLAN).delegate() == D3M_DELEGATE, "Plan delegate mismatch");
        //require(CDaiLike(D3M_CDAI).implementation() == D3M_DELEGATE, "Plan delegate mismatch");
        //require(D3MCompoundPlanLike(D3M_COMPOUND_PLAN).cDai() == D3M_CDAI, "Plan cDai mismatch");

        plan.rely(dss.chainlog.getAddress("DIRECT_MOM"));
        pool.file("king", compoundCfg.king);
        plan.file("barb", compoundCfg.barb);
    }

}
