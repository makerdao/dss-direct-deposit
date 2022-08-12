// D3MHub.spec

using Vat as vat
using Dai as dai
using DaiJoin as daiJoin
using D3MTestPool as pool
using D3MTestPlan as plan

methods {
    vat() returns (address) envfree
    daiJoin() returns (address) envfree
    plan(bytes32) returns (address) envfree => DISPATCHER(true)
    pool(bytes32) returns (address) envfree => DISPATCHER(true)
    tic(bytes32) returns (uint256) envfree => DISPATCHER(true)
    culled(bytes32) returns (uint256) envfree => DISPATCHER(true)
    vat.can(address, address) returns (uint256) envfree
    vat.debt() returns (uint256) envfree
    vat.dai(address) returns (uint256) envfree
    vat.gem(bytes32, address) returns (uint256) envfree
    vat.Line() returns (uint256) envfree
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
    debt() returns (uint256) => DISPATCHER(true)
    skim(bytes32, address) => DISPATCHER(true)
    active() returns (bool) => DISPATCHER(true)
    getTargetAssets(uint256) returns (uint256) => DISPATCHER(true)
    assetBalance() returns (uint256) => DISPATCHER(true)
    maxDeposit() returns (uint256) => DISPATCHER(true)
    maxWithdraw() returns (uint256) => DISPATCHER(true)
    deposit(uint256) => DISPATCHER(true)
    withdraw(uint256) => DISPATCHER(true)
    preDebtChange() => DISPATCHER(true)
    postDebtChange() => DISPATCHER(true)
    balanceOf(address) returns (uint256) => DISPATCHER(true)
    burn(address, uint256) => DISPATCHER(true)
    mint(address, uint256) => DISPATCHER(true)
}

definition WAD() returns uint256 = 10^18;
definition RAY() returns uint256 = 10^27;

definition min_int256() returns mathint = -1 * 2^255;
definition max_int256() returns mathint = 2^255 - 1;

rule exec_normal(bytes32 ilk) {
    require(vat() == vat);
    require(daiJoin() == daiJoin);
    require(plan(ilk) == plan);
    require(pool(ilk) == pool);
    require(daiJoin.dai() == dai);
    require(daiJoin.vat() == vat);
    require(plan.dai() == dai);
    require(pool.hub() == currentContract);
    require(pool.vat() == vat);
    require(pool.dai() == dai);

    env e;

    uint256 tic = tic(ilk);
    uint256 culled = culled(ilk);

    uint256 LineBefore = vat.Line();
    uint256 debtBefore = vat.debt();
    uint256 ArtBefore;
    uint256 rateBefore;
    uint256 spotBefore;
    uint256 lineBefore;
    uint256 dustBefore;
    ArtBefore, rateBefore, spotBefore, lineBefore, dustBefore = vat.ilks(ilk);
    uint256 inkBefore;
    uint256 artBefore;
    inkBefore, artBefore = vat.urns(ilk, pool);

    bool active = plan.active(e);
    uint256 maxDeposit = pool.maxDeposit(e);
    uint256 maxWithdraw = pool.maxWithdraw(e);
    uint256 currentAssets = pool.assetBalance(e);
    uint256 targetAssets = plan.getTargetAssets(e, currentAssets);

    require(vat.live() == 1);
    require(culled == 0);
    require(inkBefore >= artBefore);
    require(currentAssets >= inkBefore);

    exec(e, ilk);

    uint256 LineAfter = vat.Line();
    uint256 debtAfter = vat.debt();
    uint256 ArtAfter;
    uint256 rateAfter;
    uint256 spotAfter;
    uint256 lineAfter;
    uint256 dustAfter;
    ArtAfter, rateAfter, spotAfter, lineAfter, dustAfter = vat.ilks(ilk);
    uint256 inkAfter;
    uint256 artAfter;
    inkAfter, artAfter = vat.urns(ilk, pool);

    uint256 lineWad = lineBefore / RAY();
    uint256 underLine = inkBefore < lineWad ? lineWad - inkBefore : 0;
    uint256 fixInk = currentAssets > inkBefore
                     ? currentAssets - inkBefore < underLine + maxWithdraw
                        ? currentAssets - inkBefore
                        : underLine + maxWithdraw
                     : 0;
    uint256 fixArt = inkBefore + fixInk - artBefore;
    uint256 debtMiddle = debtBefore + fixArt * RAY();

    assert(LineAfter == LineBefore, "Line should not change");
    assert(lineAfter == lineBefore, "line should not change");
    assert(artAfter == ArtAfter, "art should be same than Art");
    assert(inkAfter == artAfter, "ink and art should end up being the same");
    assert(inkAfter <= lineWad || inkAfter <= inkBefore, "Ink can not overpass debt ceiling or be higher than prev one");
    // Winding
    assert(
        tic == 0 && active &&
        targetAssets >= currentAssets &&
        targetAssets <= lineWad &&
        maxDeposit >= targetAssets - currentAssets &&
        (LineBefore - debtMiddle) / RAY() >= targetAssets - currentAssets
            => artAfter == targetAssets, "wind: art should end as targetAssets"
    );
    assert(
        tic == 0 && active &&
        targetAssets >= currentAssets &&
        targetAssets > lineWad &&
        inkBefore <= lineWad &&
        maxDeposit >= targetAssets - currentAssets &&
        (LineBefore - debtMiddle) / RAY() >= targetAssets - currentAssets
            => artAfter == lineWad, "wind: art should end at the value of lineWad"
    );
    //
    // Unwinding
    assert(
        tic == 0 && active &&
        targetAssets >= currentAssets &&
        targetAssets > lineWad &&
        inkBefore > lineWad &&
        inkBefore - lineWad > maxWithdraw &&
        maxDeposit >= targetAssets - currentAssets &&
        (LineBefore - debtMiddle) / RAY() >= targetAssets - currentAssets
            => artAfter == inkBefore + fixInk - maxWithdraw, "unwind: art should end at the value of inkBefore + fixInk - maxWithdraw"
    );
    assert(
        (tic > 0 || !active) &&
        currentAssets == maxWithdraw
            => artAfter == 0, "unwind: art should end as 0"
    );
    assert(
        (tic > 0 || !active) &&
        currentAssets - maxWithdraw < lineWad
            => artAfter == currentAssets - maxWithdraw, "unwind: art should end as currentAssets - maxWithdraw"
    );
    assert(
        (tic > 0 || !active) &&
        currentAssets - maxWithdraw >= lineWad &&
        inkBefore <= lineWad
            => artAfter == lineWad, "unwind: art should end as lineWad"
    );
    assert(
        (tic > 0 || !active) &&
        currentAssets - maxWithdraw >= inkBefore &&
        inkBefore > lineWad
            => artAfter == inkBefore, "unwind: art should end as inkBefore"
    );
    // assert(
    //     tic == 0 && active &&
    //     targetAssets >= currentAssets &&
    //     targetAssets > lineWad &&
    //     inkBefore > lineWad &&
    //     inkBefore - lineWad <= maxWithdraw &&
    //     maxDeposit >= targetAssets - currentAssets &&
    //     (LineBefore - debtMiddle) / RAY() >= targetAssets - currentAssets
    //         => artAfter == inkBefore, "unwind: art should end at the value of inkBefore"
    // );
}
