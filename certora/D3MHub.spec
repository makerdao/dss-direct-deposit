// TeleportJoin.spec

using VatMock as vat
using DaiMock as dai
using DaiJoinMock as daiJoin
using PoolMock as pool
using PlanMock as plan

methods {
    vat() returns (address) envfree
    daiJoin() returns (address) envfree
    ilks(bytes32) returns (address, address, uint256, uint256, uint256) envfree
    plan(bytes32) returns (address) envfree
    pool(bytes32) returns (address) envfree
    vat.can(address, address) returns (uint256) envfree
    vat.dai(address) returns (uint256) envfree
    vat.gem(bytes32, address) returns (uint256) envfree
    vat.live() returns (uint256) envfree
    vat.ilks(bytes32) returns (uint256, uint256, uint256, uint256, uint256) envfree
    vat.urns(bytes32, address) returns (uint256, uint256) envfree
    dai.allowance(address, address) returns (uint256) envfree
    dai.balanceOf(address) returns (uint256) envfree
    daiJoin.dai() returns (address) envfree
    daiJoin.vat() returns (address) envfree
    plan.dai() returns (address) envfree
    pool.hub() returns (address) envfree
    pool.vat() returns (address) envfree
    pool.dai() returns (address) envfree
}

definition WAD() returns uint256 = 10^18;
definition RAY() returns uint256 = 10^27;

definition min_int256() returns mathint = -1 * 2^255;
definition max_int256() returns mathint = 2^255 - 1;

rule exec(bytes32 ilk) {
    require(vat() == vat);
    require(daiJoin() == daiJoin);
    require(plan(ilk) == plan);
    require(pool(ilk) == pool);
    address pool_;
    address plan_;
    uint256 tau;
    uint256 culled;
    uint256 tic;
    pool_, plan_, tau, culled, tic = ilks(ilk);
    require(pool_ == pool);
    require(plan_ == plan);
    require(daiJoin.dai() == dai);
    require(daiJoin.vat() == vat);
    require(plan.dai() == dai);
    require(pool.hub() == currentContract);
    require(pool.vat() == vat);
    require(pool.dai() == dai);

    env e;

    uint256 ArtBefore;
    uint256 rateBefore;
    uint256 spotBefore;
    uint256 lineBefore;
    uint256 dustBefore;
    ArtBefore, rateBefore, spotBefore, lineBefore, dustBefore = vat.ilks(ilk);

    exec(e, ilk);

    uint256 ArtAfter;
    uint256 rateAfter;
    uint256 spotAfter;
    uint256 lineAfter;
    uint256 dustAfter;
    ArtAfter, rateAfter, spotAfter, lineAfter, dustAfter = vat.ilks(ilk);

    assert(lineAfter == lineBefore, "line should not change");
    assert(ArtAfter <= lineBefore || ArtAfter <= ArtBefore, "Art can not overpass debt ceiling or be higher than prev one");
}
