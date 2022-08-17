// D3MHub.spec

using Vat as vat
using Dai as dai
using DaiJoin as daiJoin
using End as end
using D3MTestPool as pool
using D3MTestPlan as plan
using D3MTestGem as share

methods {
    vat() returns (address) envfree
    daiJoin() returns (address) envfree
    vow() returns (address) envfree
    end() returns (address) envfree
    plan(bytes32) returns (address) envfree => DISPATCHER(true)
    pool(bytes32) returns (address) envfree => DISPATCHER(true)
    tic(bytes32) returns (uint256) envfree
    tau(bytes32) returns (uint256) envfree
    culled(bytes32) returns (uint256) envfree
    vat.can(address, address) returns (uint256) envfree
    vat.debt() returns (uint256) envfree
    vat.dai(address) returns (uint256) envfree
    vat.gem(bytes32, address) returns (uint256) envfree
    vat.Line() returns (uint256) envfree
    vat.live() returns (uint256) envfree
    vat.ilks(bytes32) returns (uint256, uint256, uint256, uint256, uint256) envfree
    vat.sin(address) returns (uint256) envfree
    vat.urns(bytes32, address) returns (uint256, uint256) envfree
    vat.vice() returns (uint256) envfree
    dai.allowance(address, address) returns (uint256) envfree
    dai.balanceOf(address) returns (uint256) envfree
    daiJoin.dai() returns (address) envfree
    daiJoin.vat() returns (address) envfree
    end.vat() returns (address) envfree
    end.tag(bytes32) returns (uint256) envfree
    plan.dai() returns (address) envfree
    pool.hub() returns (address) envfree
    pool.vat() returns (address) envfree
    pool.dai() returns (address) envfree
    pool.share() returns (address) envfree
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
    transfer(address, uint256) => DISPATCHER(true)
    balanceOf(address) returns (uint256) => DISPATCHER(true)
    burn(address, uint256) => DISPATCHER(true)
    mint(address, uint256) => DISPATCHER(true)
}

definition WAD() returns uint256 = 10^18;
definition RAY() returns uint256 = 10^27;

definition min_int256() returns mathint = -1 * 2^255;
definition max_int256() returns mathint = 2^255 - 1;

rule exec_normal(bytes32 ilk) {
    env e;

    address vow = vow();

    require(vat() == vat);
    require(daiJoin() == daiJoin);
    require(plan(ilk) == plan);
    require(pool(ilk) == pool);
    require(vow != daiJoin);
    require(daiJoin.dai() == dai);
    require(daiJoin.vat() == vat);
    require(plan.dai() == dai);
    require(pool.hub() == currentContract);
    require(pool.vat() == vat);
    require(pool.dai() == dai);

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
    uint256 assetsBefore = pool.assetBalance(e);
    uint256 targetAssets = plan.getTargetAssets(e, assetsBefore);
    uint256 vatDaiVowBefore = vat.dai(vow);

    require(vat.live() == 1);
    require(culled == 0);
    require(inkBefore >= artBefore);
    require(assetsBefore >= inkBefore);

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

    uint256 assetsAfter = pool.assetBalance(e);
    uint256 vatDaiVowAfter = vat.dai(vow);

    uint256 lineWad = lineBefore / RAY();
    uint256 underLine = inkBefore < lineWad ? lineWad - inkBefore : 0;
    uint256 fixInk = assetsBefore > inkBefore
                     ? assetsBefore - inkBefore < underLine + maxWithdraw
                        ? assetsBefore - inkBefore
                        : underLine + maxWithdraw
                     : 0;
    uint256 fixArt = inkBefore + fixInk - artBefore;
    uint256 debtMiddle = debtBefore + fixArt * RAY();

    // General asserts
    assert(LineAfter == LineBefore, "Line should not change");
    assert(lineAfter == lineBefore, "line should not change");
    assert(artAfter == ArtAfter, "art should be same than Art");
    assert(inkAfter == artAfter, "ink and art should end up being the same");
    assert(inkAfter <= lineWad || inkAfter <= inkBefore, "ink can not overpass debt ceiling or be higher than prev one");
    assert(vatDaiVowAfter == vatDaiVowBefore + fixArt * RAY(), "vatDaiVow did not increase as expected");
    // Winding to targetAssets
    assert(
        tic == 0 && active && // regular path in normal path
        targetAssets >= assetsBefore && // plan determines we need to go up (or keep the same)
        maxDeposit >= targetAssets - assetsBefore && // target IS NOT restricted by maxDeposit
        targetAssets <= lineWad && // target IS NOT restricted by ilk line
        (LineBefore - debtMiddle) / RAY() >= targetAssets - assetsBefore // target IS NOT restricted by global Line
            => artAfter == targetAssets &&
               assetsAfter == artAfter,
               "wind: error 1"
    );
    // Winding to ilk line
    assert(
        tic == 0 && active && // regular path in normal path
        targetAssets >= assetsBefore && // plan determines we need to go up (or keep the same)
        maxDeposit >= targetAssets - assetsBefore && // target IS NOT restricted by maxDeposit
        targetAssets > lineWad && // target IS restricted by ilk line
        (LineBefore - debtMiddle) / RAY() >= targetAssets - assetsBefore && // target IS NOT restricted by global Line
        inkBefore <= lineWad // ink before execution is safe under ilk line
            => artAfter == lineWad &&
               assetsAfter >= artAfter,
               "wind: error 2"
    );
    assert(
        tic == 0 && active && // regular path in normal path
        targetAssets >= assetsBefore && // plan determines we need to go up (or keep the same)
        maxDeposit >= targetAssets - assetsBefore && // target IS NOT restricted by maxDeposit
        targetAssets > lineWad && // target IS restricted by ilk line
        (LineBefore - debtMiddle) / RAY() >= targetAssets - assetsBefore && // target IS NOT restricted by global Line
        assetsBefore <= lineWad && // assets before execution is safe under ilk line
        targetAssets >= lineWad // target is pointed above ilk line
            => artAfter == lineWad &&
               assetsAfter == artAfter,
               "wind: error 3"
    );
    // Unwinding to targetAssets
    assert(
        tic == 0 && active && // regular path in normal path
        targetAssets <= assetsBefore && // plan determines we need to go down (or keep the same)
        targetAssets <= lineWad && // target IS NOT restricted by ilk line
        (LineBefore - debtMiddle) / RAY() >= 0 && // target IS NOT restricted by global Line
        maxWithdraw >= assetsBefore - targetAssets // target IS NOT restricted by maxWithdraw
            => artAfter == targetAssets &&
               assetsAfter == artAfter,
               "unwind: error 1"
    );
    // Unwinding due to targetAssets but restricted
    assert(
        tic == 0 && active && // regular path in normal path
        targetAssets <= assetsBefore && // plan determines we need to go down (or keep the same)
        targetAssets <= lineWad && // target IS NOT restricted by ilk line
        (LineBefore - debtMiddle) / RAY() >= 0 && // target IS NOT restricted by global Line
        maxWithdraw < assetsBefore - targetAssets && // target IS restricted by maxWithdraw
        assetsBefore <= lineWad
            => artAfter == assetsBefore - maxWithdraw &&
               assetsAfter == artAfter,
               "unwind: error 2"
    );
    assert(
        tic == 0 && active && // regular path in normal path
        targetAssets <= assetsBefore && // plan determines we need to go down (or keep the same)
        targetAssets <= lineWad && // target IS NOT restricted by ilk line
        (LineBefore - debtMiddle) / RAY() >= 0 && // target IS NOT restricted by global Line
        maxWithdraw < assetsBefore - targetAssets && // target IS restricted by maxWithdraw
        inkBefore > lineWad &&
        assetsBefore - inkBefore > maxWithdraw
            => artAfter == inkBefore,
               "unwind: error 3"
    );
    // Unwinding due to line
    assert(
        tic == 0 && active && // regular path in normal path
        targetAssets >= assetsBefore && // plan determines we need to go up (or keep the same)
        targetAssets > lineWad && // target IS restricted by ilk line
        (LineBefore - debtMiddle) / RAY() >= targetAssets - assetsBefore && // target IS NOT restricted by global Line
        inkBefore > lineWad && // ink before execution is not safe (over ilk line)
        maxWithdraw >= assetsBefore - lineWad // enough to rebalance and decrease to ilk line value
            => artAfter == lineWad &&
               assetsAfter == artAfter,
               "unwind: error 4"
    );
    assert(
        tic == 0 && active && // regular path in normal path
        targetAssets >= assetsBefore && // plan determines we need to go up (or keep the same)
        targetAssets > lineWad && // target IS restricted by ilk line
        (LineBefore - debtMiddle) / RAY() >= targetAssets - assetsBefore && // target IS NOT restricted by global Line
        inkBefore > lineWad && // ink before execution is not safe (over ilk line)
        maxWithdraw < assetsBefore - inkBefore // NOT enough for full rebalance
            => artAfter == inkBefore &&
               assetsAfter > artAfter,
               "unwind: error 5"
    );
    assert(
        tic == 0 && active && // regular path in normal path
        targetAssets >= assetsBefore && // plan determines we need to go up (or keep the same)
        targetAssets > lineWad && // target IS restricted by ilk line
        (LineBefore - debtMiddle) / RAY() >= targetAssets - assetsBefore && // target IS NOT restricted by global Line
        inkBefore > lineWad && // ink before execution is not safe (over ilk line)
        maxWithdraw < inkBefore - lineWad // no way to decrease to ilk line value
            => artAfter == inkBefore + fixInk - maxWithdraw &&
               assetsAfter >= artAfter,
               "unwind: error 6"
    );
    assert(
        tic == 0 && active && // regular path in normal path
        targetAssets >= assetsBefore && // plan determines we need to go up (or keep the same)
        targetAssets > lineWad && // target IS restricted by ilk line
        (LineBefore - debtMiddle) / RAY() >= targetAssets - assetsBefore && // target IS NOT restricted by global Line
        inkBefore > lineWad && // ink before execution is not safe (over ilk line)
        maxWithdraw < assetsBefore - lineWad && // NOT enough to rebalance and decrease to ilk line value
        maxWithdraw >= assetsBefore - inkBefore // enough for full rebalance
            => artAfter == assetsBefore - maxWithdraw &&
               artAfter <= inkBefore &&
               artAfter >= lineWad &&
               assetsAfter == artAfter,
               "unwind: error 7"
    );
    // Force unwinding due to ilk caged (but not culled yet) or plan inactive:
    assert(
        (tic > 0 || !active) &&
        assetsBefore == maxWithdraw
            => artAfter == 0, "unwind: error 8"
    );
    assert(
        (tic > 0 || !active) &&
        assetsBefore - maxWithdraw < lineWad
            => artAfter == assetsBefore - maxWithdraw, "unwind: error 9"
    );
    assert(
        (tic > 0 || !active) &&
        assetsBefore - maxWithdraw >= lineWad &&
        inkBefore <= lineWad
            => artAfter == lineWad, "unwind: error 10"
    );
    assert(
        (tic > 0 || !active) &&
        assetsBefore - maxWithdraw >= inkBefore &&
        inkBefore > lineWad
            => artAfter == inkBefore, "unwind: error 11"
    );
}

rule exec_ilk_culled(bytes32 ilk) {
    env e;

    address vow = vow();

    require(vat() == vat);
    require(daiJoin() == daiJoin);
    require(plan(ilk) == plan);
    require(pool(ilk) == pool);
    require(vow != daiJoin);
    require(daiJoin.dai() == dai);
    require(daiJoin.vat() == vat);
    require(plan.dai() == dai);
    require(pool.hub() == currentContract);
    require(pool.vat() == vat);
    require(pool.dai() == dai);

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

    uint256 maxWithdraw = pool.maxWithdraw(e);
    uint256 assetsBefore = pool.assetBalance(e);
    uint256 targetAssets = plan.getTargetAssets(e, assetsBefore);

    require(vat.live() == 1);
    require(inkBefore >= artBefore);
    require(assetsBefore >= inkBefore);

    cull(e, ilk);

    uint256 vatGemPoolBefore = vat.gem(ilk, pool);
    uint256 vatDaiVowBefore = vat.dai(vow);

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

    uint256 assetsAfter = pool.assetBalance(e);

    uint256 vatGemPoolAfter = vat.gem(ilk, pool);
    uint256 vatDaiVowAfter = vat.dai(vow);

    // General asserts
    assert(LineAfter == LineBefore, "Line should not change");
    assert(lineAfter == lineBefore, "line should not change");
    assert(artAfter == 0, "art should end up being 0");
    assert(inkAfter == 0, "ink should end up being 0");

    assert(assetsAfter == 0 || assetsAfter == assetsBefore - maxWithdraw, "assets should be 0 or decreased by maxWithdraw");
    assert(vatGemPoolAfter == 0 || vatGemPoolAfter == vatGemPoolBefore - maxWithdraw, "vatGemPool should be 0 or decreased by maxWithdraw");
    assert(vatDaiVowAfter == vatDaiVowBefore + (assetsBefore - assetsAfter) * RAY(), "vatDaiVow did not increase as expected");
}

rule exec_vat_caged(bytes32 ilk) {
    env e;

    address vow = vow();

    require(vat() == vat);
    require(daiJoin() == daiJoin);
    require(end() == end);
    require(plan(ilk) == plan);
    require(pool(ilk) == pool);
    require(vow != daiJoin);
    require(daiJoin.dai() == dai);
    require(daiJoin.vat() == vat);
    require(end.vat() == vat);
    require(plan.dai() == dai);
    require(pool.hub() == currentContract);
    require(pool.vat() == vat);
    require(pool.dai() == dai);

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

    uint256 maxWithdraw = pool.maxWithdraw(e);
    uint256 assetsBefore = pool.assetBalance(e);
    uint256 targetAssets = plan.getTargetAssets(e, assetsBefore);

    require(vat.live() == 0);
    require(end.tag(ilk) == RAY());
    require(inkBefore >= artBefore);
    require(assetsBefore >= inkBefore);

    uint256 vatGemEndBeforeOriginal = vat.gem(ilk, end);
    require(inkBefore == 0 || vatGemEndBeforeOriginal == 0); // To ensure correct behavior
    uint256 vatGemEndBefore = vatGemEndBeforeOriginal != 0 ? vatGemEndBeforeOriginal : artBefore;
    uint256 vatDaiVowBefore = vat.dai(vow);

    require(assetsBefore >= vatGemEndBefore);

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

    uint256 assetsAfter = pool.assetBalance(e);

    uint256 vatGemEndAfter = vat.gem(ilk, end);
    uint256 vatDaiVowAfter = vat.dai(vow);

    // General asserts
    assert(LineAfter == LineBefore, "Line should not change");
    assert(lineAfter == lineBefore, "line should not change");
    assert(artAfter == 0, "art should end up being 0");

    assert(assetsAfter == 0 || assetsAfter == assetsBefore - maxWithdraw, "assets should be 0 or decreased by maxWithdraw");
    assert(vatGemEndAfter == 0 || vatGemEndAfter == vatGemEndBefore - maxWithdraw, "vatGemEnd should be 0 or decreased by maxWithdraw");
    assert(vatDaiVowAfter == vatDaiVowBefore + (assetsBefore - assetsAfter) * RAY(), "vatDaiVow did not increase as expected");
}

rule exec_exec(bytes32 ilk) {
    env e;

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

    uint256 maxDeposit = pool.maxDeposit(e);
    uint256 assetsBefore = pool.assetBalance(e);
    uint256 targetAssets = plan.getTargetAssets(e, assetsBefore);

    require(maxDeposit > targetAssets - assetsBefore);

    exec(e, ilk);

    uint256 assetsAfter1 = pool.assetBalance(e);

    uint256 inkAfter1;
    uint256 artAfter1;
    inkAfter1, artAfter1 = vat.urns(ilk, pool);

    exec(e, ilk);

    uint256 assetsAfter2 = pool.assetBalance(e);

    uint256 inkAfter2;
    uint256 artAfter2;
    inkAfter2, artAfter2 = vat.urns(ilk, pool);

    assert(assetsAfter2 == assetsAfter1, "assetsAfter did not remain as expected");
    assert(inkAfter2 == inkAfter1, "inkAfter did not remain as expected");
    assert(artAfter2 == artAfter1, "artAfter did not remain as expected");
}

rule exit(bytes32 ilk, address usr, uint256 wad) {
    env e;

    require(vat() == vat);
    require(pool(ilk) == pool);
    require(pool.hub() == currentContract);
    require(pool.vat() == vat);
    require(pool.share() == share);

    uint256 vatGemSenderBefore = vat.gem(ilk, e.msg.sender);
    uint256 poolShareUsrBefore = share.balanceOf(e, usr);

    exit(e, ilk, usr, wad);

    uint256 vatGemSenderAfter = vat.gem(ilk, e.msg.sender);
    uint256 poolShareUsrAfter = share.balanceOf(e, usr);

    assert(vatGemSenderAfter == vatGemSenderBefore - wad, "vatGemSender did not decrease by wad amount");
    assert(usr != pool => poolShareUsrAfter == poolShareUsrBefore + wad, "poolShareUsr did not increase by wad amount");
}

rule cage(bytes32 ilk) {
    env e;

    require(vat() == vat);

    cage(e, ilk);

    assert(tic(ilk) == e.block.timestamp + tau(ilk), "tic was not set as expected");
}

rule cull(bytes32 ilk) {
    env e;

    require(vat() == vat);

    uint256 ArtBefore;
    uint256 rateBefore;
    uint256 spotBefore;
    uint256 lineBefore;
    uint256 dustBefore;
    ArtBefore, rateBefore, spotBefore, lineBefore, dustBefore = vat.ilks(ilk);

    require(rateBefore == RAY());

    uint256 inkBefore;
    uint256 artBefore;
    inkBefore, artBefore = vat.urns(ilk, pool(ilk));

    uint256 vatGemPoolBefore = vat.gem(ilk, pool(ilk));
    uint256 vatSinVowBefore = vat.sin(vow());
    uint256 vatViceBefore = vat.vice();

    cull(e, ilk);

    uint256 inkAfter;
    uint256 artAfter;
    inkAfter, artAfter = vat.urns(ilk, pool(ilk));

    uint256 vatGemPoolAfter = vat.gem(ilk, pool(ilk));

    uint256 culledAfter = culled(ilk);
    uint256 vatSinVowAfter = vat.sin(vow());
    uint256 vatViceAfter = vat.vice();

    assert(inkAfter == 0, "ink did not go to 0 as expected");
    assert(artAfter == 0, "art did not go to 0 as expected");
    assert(vatGemPoolAfter == vatGemPoolBefore + inkBefore, "vatGemPool did not increase as expected");
    assert(culledAfter == 1, "culled was not set to 1 as expected");
    assert(vatSinVowAfter == vatSinVowBefore + artBefore * RAY(), "vatSinVow did not increase as expected");
    assert(vatViceAfter == vatViceBefore + artBefore * RAY(), "vatVice did not increase as expected");
}

rule uncull(bytes32 ilk) {
    env e;

    require(vat() == vat);

    uint256 ArtBefore;
    uint256 rateBefore;
    uint256 spotBefore;
    uint256 lineBefore;
    uint256 dustBefore;
    ArtBefore, rateBefore, spotBefore, lineBefore, dustBefore = vat.ilks(ilk);

    require(rateBefore == RAY());

    uint256 inkBefore;
    uint256 artBefore;
    inkBefore, artBefore = vat.urns(ilk, pool(ilk));

    uint256 vatGemPoolBefore = vat.gem(ilk, pool(ilk));
    uint256 vatDaiVowBefore = vat.dai(vow());

    uncull(e, ilk);

    uint256 inkAfter;
    uint256 artAfter;
    inkAfter, artAfter = vat.urns(ilk, pool(ilk));

    uint256 vatGemPoolAfter = vat.gem(ilk, pool(ilk));

    uint256 culledAfter = culled(ilk);
    uint256 vatDaiVowAfter = vat.dai(vow());

    assert(inkAfter == inkBefore + vatGemPoolBefore, "ink did not increase by prev value of vatGemPool as expected");
    assert(artAfter == artBefore + vatGemPoolBefore, "art did not increase by prev value of vatGemPool as expected");
    assert(vatGemPoolAfter == 0, "vatGemPool did not descrease to 0 as expected");
    assert(culledAfter == 0, "culled was not set to 0 as expected");
    assert(vatDaiVowAfter == vatDaiVowBefore + vatGemPoolBefore * RAY(), "vatDaiVow did not increase as expected");
}
