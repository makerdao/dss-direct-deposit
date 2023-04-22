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

pragma solidity ^0.8.14;

import "dss-test/DssTest.sol";
import "dss-interfaces/Interfaces.sol";

import { D3MHub } from "../D3MHub.sol";
import { D3MOracle } from "../D3MOracle.sol";
import { ID3MPool } from "../pools/ID3MPool.sol";
import { ID3MPlan } from "../plans/ID3MPlan.sol";
import { ID3MFees } from "../fees/ID3MFees.sol";
import { D3MForwardFees } from "../fees/D3MForwardFees.sol";

import { TokenMock } from "./mocks/TokenMock.sol";

contract PoolMock is ID3MPool {

    VatAbstract public vat;
    address public hub;
    TokenMock public dai;
    TokenMock public gem;

    bool public preDebt;
    bool public postDebt;
    uint256 public maxDeposit;

    constructor(address _vat, address _hub, address _dai, address _gem) {
        vat = VatAbstract(_vat);
        hub = _hub;
        dai = TokenMock(_dai);
        gem = TokenMock(_gem);
        maxDeposit = type(uint256).max;
        vat.hope(_hub);
    }

    function file(bytes32 what, address data) external {
        if (what == "hub") {
            vat.nope(hub);
            hub = data;
            vat.hope(data);
        }
    }

    function deposit(uint256) external override {
    }

    function withdraw(uint256 wad) external override {
        dai.transfer(msg.sender, wad);
    }

    function exit(address dst, uint256 wad) external override {
        gem.transfer(dst, wad);
    }

    function quit(address dst) external override {
        dai.transfer(dst, dai.balanceOf(address(this)));
        gem.transfer(dst, gem.balanceOf(address(this)));
    }

    function preDebtChange() external override {
        preDebt = true;
    }

    function postDebtChange() external override {
        postDebt = true;
    }

    function resetPrePostDebt() external {
        preDebt = false;
        postDebt = false;
    }

    function assetBalance() public view returns (uint256) {
        return dai.balanceOf(address(this)) + gem.balanceOf(address(this));
    }

    function setMaxDeposit(uint256 _maxDeposit) external {
        maxDeposit = _maxDeposit;
    }

    function maxWithdraw() external view override returns (uint256) {
        return dai.balanceOf(address(this));
    }

    function liquidityAvailable() external view override returns (uint256) {
        return dai.balanceOf(address(this));
    }

    function idleLiquidity() external view override returns (uint256) {
        return dai.balanceOf(address(this));
    }

    function redeemable() external view returns (address) {
        return address(gem);
    }

    function decreaseIdleLiquidity(uint256 amount) external {
        GodMode.setBalance(address(dai), address(this), dai.balanceOf(address(this)) - amount);
        GodMode.setBalance(address(gem), address(this), gem.balanceOf(address(this)) + amount);
    }

    function increaseIdleLiquidity(uint256 amount) external {
        GodMode.setBalance(address(dai), address(this), dai.balanceOf(address(this)) + amount);
        GodMode.setBalance(address(gem), address(this), gem.balanceOf(address(this)) - amount);
    }

    function accrueInterest(uint256 amount) external {
        GodMode.setBalance(address(gem), address(this), gem.balanceOf(address(this)) + amount);
    }

}

contract PlanMock is ID3MPlan {

    uint256 public targetAssets;

    function setTargetAssets(uint256 _targetAssets) external {
        targetAssets = _targetAssets;
    }

    function getTargetAssets(bytes32,uint256) external override view returns (uint256) {
        return targetAssets;
    }

    function active() external view returns (bool) {
        return targetAssets > 0;
    }

    function disable() external {
        targetAssets = 0;
    }

}

contract D3MHubTest is DssTest {

    using GodMode for *;

    VatAbstract vat;
    EndAbstract end;
    DaiAbstract dai;
    DaiJoinAbstract daiJoin;
    TokenMock testGem;
    SpotAbstract spot;
    GemAbstract weth;
    address vow;
    address pauseProxy;

    bytes32 constant ilk = "DD-DAI-TEST";
    D3MHub hub;
    PoolMock pool;
    PlanMock plan;
    D3MForwardFees fees;
    D3MOracle pip;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        // TODO these should be mocked (or this should be moved to an integration test)
        vat = VatAbstract(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        end = EndAbstract(0x0e2e8F1D1326A4B9633D96222Ce399c708B19c28);
        dai = DaiAbstract(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        daiJoin = DaiJoinAbstract(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
        spot = SpotAbstract(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);
        weth = GemAbstract(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        vow = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;
        pauseProxy = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

        // Force give admin access to these contracts via vm magic
        address(vat).setWard(address(this), 1);
        address(end).setWard(address(this), 1);
        address(spot).setWard(address(this), 1);

        testGem = new TokenMock(18);
        hub = new D3MHub(address(daiJoin));

        pool = new PoolMock(address(vat), address(hub), address(dai), address(testGem));
        plan = new PlanMock();
        fees = new D3MForwardFees(address(vat), address(vow));

        hub.file("vow", vow);
        hub.file("end", address(end));

        hub.file(ilk, "pool", address(pool));
        hub.file(ilk, "plan", address(plan));
        hub.file(ilk, "fees", address(fees));
        hub.file(ilk, "tau", 7 days);

        // Init new collateral
        pip = new D3MOracle(address(vat), ilk);
        pip.file("hub", address(hub));
        spot.file(ilk, "pip", address(pip));
        spot.file(ilk, "mat", RAY);
        spot.poke(ilk);

        vat.rely(address(hub));
        vat.init(ilk);
        vat.file(ilk, "line", 5_000_000_000 * RAD);
        vat.file("Line", vat.Line() + 5_000_000_000 * RAD);
    }

    function _windSystem() internal {
        plan.setTargetAssets(50 * WAD);
        hub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
        pool.resetPrePostDebt();
    }

    function test_approvals() public {
        assertEq(
            dai.allowance(address(hub), address(daiJoin)),
            type(uint256).max
        );
        assertEq(vat.can(address(hub), address(daiJoin)), 1);
    }

    function test_can_file_tau() public {
        (, , , uint256 tau, , ) = hub.ilks(ilk);
        assertEq(tau, 7 days);
        hub.file(ilk, "tau", 1 days);
        (, , , tau, , ) = hub.ilks(ilk);
        assertEq(tau, 1 days);
    }

    function test_unauth_file_tau() public {
        hub.deny(address(this));
        assertRevert(address(hub), abi.encodeWithSignature("file(bytes32,bytes32,uint256)", ilk, bytes32("tau"), uint256(1 days)), "D3MHub/not-authorized");
    }

    function test_unknown_uint256_file() public {
        assertRevert(address(hub), abi.encodeWithSignature("file(bytes32,bytes32,uint256)", ilk, bytes32("unknown"), uint256(1)), "D3MHub/file-unrecognized-param");
    }

    function test_unknown_address_file() public {
        assertRevert(address(hub), abi.encodeWithSignature("file(bytes32,bytes32,address)", ilk, bytes32("unknown"), address(this)), "D3MHub/file-unrecognized-param");
    }

    function test_can_file_pool() public {
        (ID3MPool _pool, , , , , ) = hub.ilks(ilk);

        assertEq(address(_pool), address(pool));

        hub.file(ilk, "pool", address(this));

        (_pool, , , , , ) = hub.ilks(ilk);
        assertEq(address(_pool), address(this));
    }

    function test_can_file_plan() public {
        (, ID3MPlan _plan, , , , ) = hub.ilks(ilk);

        assertEq(address(_plan), address(plan));

        hub.file(ilk, "plan", address(this));

        (, _plan, , , , ) = hub.ilks(ilk);
        assertEq(address(_plan), address(this));
    }

    function test_can_file_fees() public {
        (, ,  ID3MFees _fees, , , ) = hub.ilks(ilk);

        assertEq(address(_fees), address(fees));

        hub.file(ilk, "fees", address(this));

        (, , _fees, , , ) = hub.ilks(ilk);
        assertEq(address(_fees), address(this));
    }

    function test_can_file_vow() public {
        address setVow = hub.vow();

        assertEq(vow, setVow);

        hub.file("vow", address(this));

        setVow = hub.vow();
        assertEq(setVow, address(this));
    }

    function test_can_file_end() public {
        address setEnd = address(hub.end());

        assertEq(address(end), setEnd);

        hub.file("end", address(this));

        setEnd = address(hub.end());
        assertEq(setEnd, address(this));
    }

    function test_vat_not_live_address_file() public {
        hub.file("end", address(this));
        address hubEnd = address(hub.end());

        assertEq(hubEnd, address(this));

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        assertRevert(address(hub), abi.encodeWithSignature("file(bytes32,address)", bytes32("end"), address(123)), "D3MHub/no-file-during-shutdown");
    }

    function test_unauth_file_pool() public {
        hub.deny(address(this));
        assertRevert(address(hub), abi.encodeWithSignature("file(bytes32,bytes32,address)", ilk, bytes32("pool"), address(this)), "D3MHub/not-authorized");
    }

    function test_hub_not_live_pool_file() public {
        // Cage Pool
        hub.cage(ilk);
        assertRevert(address(hub), abi.encodeWithSignature("file(bytes32,bytes32,address)", ilk, bytes32("pool"), address(123)), "D3MHub/pool-not-live");
    }

    function test_unknown_ilk_address_file() public {
        assertRevert(address(hub), abi.encodeWithSignature("file(bytes32,bytes32,address)", ilk, bytes32("unknown"), address(123)), "D3MHub/file-unrecognized-param");
    }

    function test_vat_not_live_ilk_address_file() public {
        hub.file(ilk, "pool", address(this));
        (ID3MPool _pool, , , , , ) = hub.ilks(ilk);

        assertEq(address(_pool), address(this));

        // MCD shutdowns
        end.cage();
        end.cage(ilk);

        assertRevert(address(hub), abi.encodeWithSignature("file(bytes32,bytes32,address)", ilk, bytes32("pool"), address(123)), "D3MHub/no-file-during-shutdown");
    }

    function test_exec_no_ilk() public {
        assertRevert(address(hub), abi.encodeWithSignature("exec(bytes32)", bytes32("fake-ilk")), "D3MHub/rate-not-one");
    }

    function test_exec_rate_not_one() public {
        vat.fold(ilk, vow, int(2 * RAY));
        assertRevert(address(hub), abi.encodeWithSignature("exec(bytes32)", ilk), "D3MHub/rate-not-one");
    }

    function test_exec_spot_not_one() public {
        vat.file(ilk, "spot", 2 * RAY);
        assertRevert(address(hub), abi.encodeWithSignature("exec(bytes32)", ilk), "D3MHub/spot-not-one");
    }

    function test_wind_limited_ilk_line() public {
        plan.setTargetAssets(50 * WAD);
        vat.file(ilk, "line", 40 * RAD);
        hub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 40 * WAD);
        assertEq(art, 40 * WAD);
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function test_wind_limited_Line() public {
        plan.setTargetAssets(50 * WAD);
        vat.file("Line", vat.debt() + 40 * RAD);
        hub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 40 * WAD);
        assertEq(art, 40 * WAD);
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function test_wind_limited_by_maxDeposit() public {
        _windSystem(); // winds to 50 * WAD
        plan.setTargetAssets(75 * WAD);
        pool.setMaxDeposit(5 * WAD);

        hub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 55 * WAD);
        assertEq(art, 55 * WAD);
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function test_wind_limited_to_zero_by_maxDeposit() public {
        _windSystem(); // winds to 50 * WAD
        plan.setTargetAssets(75 * WAD);
        pool.setMaxDeposit(0);

        hub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function test_unwind_fixes_after_debt_paid_back() public {
        _windSystem();

        // Someone pays back our debt
        dai.setBalance(address(this), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(pool),
            address(pool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 40 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(vow);
        uint256 vowDaiBefore = vat.dai(vow);

        // It will just fix the position and send the DAI to the surplus buffer
        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEq(vat.dai(vow), vowDaiBefore + 10 * RAD);

        // can reduce and have the correct amount of locked collateral
        plan.setTargetAssets(25 * WAD);

        // exec and unwind
        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 25 * WAD);
        assertEq(art, 25 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEq(vat.dai(vow), vowDaiBefore + 10 * RAD);
    }

    function test_wind_after_debt_paid_back() public {
        _windSystem();

        // Someone pays back our debt
        dai.setBalance(address(this), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(pool),
            address(pool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 40 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(vow);
        uint256 vowDaiBefore = vat.dai(vow);

        // can re-wind and have the correct amount of debt (art)
        plan.setTargetAssets(75 * WAD);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 75 * WAD);
        assertEq(art, 75 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEq(vat.dai(vow), vowDaiBefore + 10 * RAD);
    }

    function test_fully_unwind_after_debt_paid_back() public {
        _windSystem();

        // Someone pays back our debt
        dai.setBalance(address(this), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(pool),
            address(pool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 40 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(vow);
        uint256 vowDaiBefore = vat.dai(vow);

        // fully unwind
        plan.setTargetAssets(0);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0 * WAD);
        assertEq(art, 0 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        // This comes back to us as fees at this point
        assertEq(vat.dai(vow), vowDaiBefore + 10 * RAD);
    }

    function test_wind_unwind_line_limited_debt_paid_back() public {
        _windSystem();

        // Someone pays back our debt
        dai.setBalance(address(this), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(pool),
            address(pool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 40 * WAD);
        (uint256 Art, , , , ) = vat.ilks(ilk);
        assertEq(Art, 40 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(vow);
        uint256 vowDaiBefore = vat.dai(vow);

        // limit wind with debt ceiling
        plan.setTargetAssets(500 * WAD);
        vat.file(ilk, "line", 60 * RAD);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 60 * WAD);
        assertEq(art, 60 * WAD);
        (Art, , , , ) = vat.ilks(ilk);
        assertEq(Art, 60 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEq(vat.dai(vow), vowDaiBefore + 10 * RAD);

        // unwind due to debt ceiling
        vat.file(ilk, "line", 20 * RAD);

        // we can now execute the unwind to respect the line again
        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 20 * WAD);
        assertEq(art, 20 * WAD);
        (Art, , , , ) = vat.ilks(ilk);
        assertEq(Art, 20 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        // we unwind and collect fees
        assertEq(vat.dai(vow), vowDaiBefore + 10 * RAD);
    }

    function test_exec_fees_debt_paid_back() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        pool.accrueInterest(5 * WAD);

        // Someone pays back our debt
        dai.setBalance(address(this), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(pool),
            address(pool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 40 * WAD);
        (uint256 Art, , , , ) = vat.ilks(ilk);
        assertEq(Art, 40 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(vow);
        uint256 vowDaiBefore = vat.dai(vow);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        (Art, , , , ) = vat.ilks(ilk);
        assertEq(Art, 50 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        assertEq(vat.dai(address(hub)), 0);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        // Both the debt donation and fees go to vow
        assertEq(vat.dai(vow), vowDaiBefore + 15 * RAD);
    }

    function test_unwind_plan_not_active() public {
        _windSystem();

        // Temporarily disable the module
        plan.disable();
        hub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
        // Make sure pre/post functions get called
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function test_unwind_ilk_line_lowered() public {
        _windSystem();

        // Set ilk line below current debt
        plan.setTargetAssets(55 * WAD); // Increasing target in 5 WAD
        vat.file(ilk, "line", 45 * RAD);
        hub.exec(ilk);

        // Ensure we unwound our position to debt ceiling
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 45 * WAD); // Instead of 5 WAD more results in 5 WAD less due debt ceiling
        assertEq(art, 45 * WAD);
        // Make sure pre/post functions get called
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function test_unwind_global_Line_lowered() public {
        _windSystem();

        // Set ilk line below current debt
        plan.setTargetAssets(55 * WAD); // Increasing target in 5 WAD
        vat.file("Line", vat.debt() - 5 * RAD);
        hub.exec(ilk);

        // Ensure we unwound our position to debt ceiling
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 45 * WAD); // Instead of 5 WAD more results in 5 WAD less due debt ceiling
        assertEq(art, 45 * WAD);
        // Make sure pre/post functions get called
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function test_unwind_mcd_caged() public {
        _windSystem();

        // MCD shuts down
        end.cage();
        end.cage(ilk);

        hub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
        // Make sure pre/post functions get called
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function test_unwind_mcd_caged_debt_paid_back() public {
        _windSystem();

        // Someone pays back our debt
        dai.setBalance(address(this), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(pool),
            address(pool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        // MCD shuts down
        end.cage();
        end.cage(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 40 * WAD);
        assertEq(vat.gem(ilk, address(end)), 0);
        uint256 sinBefore = vat.sin(vow);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 10 * WAD);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(end)), 0);
        assertEq(vat.dai(address(hub)), 0);
        assertEq(vat.sin(vow), sinBefore + 40 * RAD);
    }

    function test_unwind_pool_caged() public {
        _windSystem();

        // Module caged
        hub.cage(ilk);

        hub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
        // Make sure pre/post functions get called
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function test_unwind_pool_caged_debt_paid_back() public {
        _windSystem();

        // Someone pays back our debt
        dai.setBalance(address(this), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(pool),
            address(pool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        // Module caged
        hub.cage(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 40 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        uint256 viceBefore = vat.vice();
        uint256 sinBefore = vat.sin(vow);
        uint256 daiBefore = vat.dai(vow);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(pool)), 0);
        assertEq(vat.dai(address(hub)), 0);
        assertEq(vat.vice(), viceBefore);
        assertEq(vat.sin(vow), sinBefore);
        assertEq(vat.dai(vow), daiBefore + 10 * RAD);
    }

    function test_unwind_target_less_amount() public {
        _windSystem();

        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertEq(pink, 50 * WAD);
        assertEq(part, 50 * WAD);

        plan.setTargetAssets(25 * WAD);

        hub.exec(ilk);

        // Ensure we unwound our position
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 25 * WAD);
        assertEq(art, 25 * WAD);
        // Make sure pre/post functions get called
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function test_wind_unwind_non_standard_token() public {
        // setup system
        bytes32 otherIlk = "DD-OTHER-GEM";
        TokenMock otherGem = new TokenMock(6);
        PoolMock otherPool = new PoolMock(address(vat), address(hub), address(dai), address(testGem));
        otherGem.rely(address(otherPool));

        hub.file(otherIlk, "pool", address(otherPool));
        hub.file(otherIlk, "plan", address(plan));
        hub.file(otherIlk, "tau", 7 days);

        spot.file(otherIlk, "pip", address(pip));
        spot.file(otherIlk, "mat", RAY);
        spot.poke(otherIlk);
        vat.init(otherIlk);
        vat.file(otherIlk, "line", 5_000_000_000 * RAD);
        vat.file("Line", vat.Line() + 10_000_000_000 * RAD);

        // wind up system
        plan.setTargetAssets(50 * WAD);
        hub.exec(otherIlk);

        (uint256 ink, uint256 art) = vat.urns(otherIlk, address(otherPool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertTrue(otherPool.preDebt());
        assertTrue(otherPool.postDebt());
        otherPool.resetPrePostDebt();

        // wind down system
        plan.setTargetAssets(5 * WAD);
        hub.exec(otherIlk);

        (ink, art) = vat.urns(otherIlk, address(otherPool));
        assertEq(ink, 5 * WAD);
        assertEq(art, 5 * WAD);
        assertTrue(otherPool.preDebt());
        assertTrue(otherPool.postDebt());
    }

    function test_exec_fees_available_liquidity() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        pool.accrueInterest(10 * WAD);

        (, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(art, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        hub.exec(ilk);

        (, art) = vat.urns(ilk, address(pool));
        assertEq(art, 50 * WAD);
        uint256 currentDai = vat.dai(vow);
        assertEq(currentDai, prevDai + 10 * RAD); // Interest shows up in vat Dai for the Vow [rad]
        // Make sure pre/post functions get called
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function test_exec_fees_not_enough_liquidity() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        pool.accrueInterest(10 * WAD);
        assertEq(pool.assetBalance(), 60 * WAD);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        // If we do not have enough liquidity then we pull out what we can for the fees
        // This will pull out all but 2 WAD of the liquidity
        assertEq(dai.balanceOf(address(pool)), 50 * WAD);
        pool.decreaseIdleLiquidity(48 * WAD);
        assertEq(dai.balanceOf(address(pool)), 2 * WAD);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        // Collateral and debt increase by 8 WAD as there wasn't enough liquidity to pay the fees accumulated
        assertEq(ink, 58 * WAD);
        assertEq(art, 58 * WAD);
        assertEq(vat.dai(vow), prevDai + 10 * RAD);
        // Make sure pre/post functions get called
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function test_exit() public {
        _windSystem();
        pool.decreaseIdleLiquidity(50 * WAD);
        // Vat is caged for global settlement
        vat.cage();

        // Simulate DAI holder gets some gems from GS
        vat.grab(
            ilk,
            address(pool),
            address(this),
            address(this),
            -int256(50 * WAD),
            -int256(0)
        );

        uint256 prevBalance = testGem.balanceOf(address(this));

        // User can exit and get the redeem token
        hub.exit(ilk, address(this), 50 * WAD);
        assertEq(testGem.balanceOf(address(this)), prevBalance + 50 * WAD);
    }

    function test_cage_d3m_with_auth() public {
        (, , , uint256 tau, , uint256 tic) = hub.ilks(ilk);
        assertEq(tic, 0);

        hub.cage(ilk);

        (, , , , , tic) = hub.ilks(ilk);
        assertEq(tic, block.timestamp + tau);
    }

    function test_cage_d3m_mcd_caged() public {
        vat.cage();
        assertRevert(address(hub), abi.encodeWithSignature("cage(bytes32)", ilk), "D3MHub/no-cage-during-shutdown");
    }

    function test_cage_d3m_no_auth() public {
        hub.deny(address(this));
        assertRevert(address(hub), abi.encodeWithSignature("cage(bytes32)", ilk), "D3MHub/not-authorized");
    }

    function test_cage_d3m_already_caged() public {
        hub.cage(ilk);
        assertRevert(address(hub), abi.encodeWithSignature("cage(bytes32)", ilk), "D3MHub/pool-already-caged");
    }

    function test_cull() public {
        _windSystem();
        hub.cage(ilk);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertEq(pink, 50 * WAD);
        assertEq(part, 50 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        uint256 sinBefore = vat.sin(vow);

        hub.cull(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(pool)), 50 * WAD);
        assertEq(vat.sin(vow), sinBefore + 50 * RAD);
        (, , , , uint256 culled, ) = hub.ilks(ilk);
        assertEq(culled, 1);
    }

    function test_cull_debt_paid_back() public {
        _windSystem();

        // Someone pays back our debt
        dai.setBalance(address(this), 10 * WAD);
        dai.approve(address(daiJoin), type(uint256).max);
        daiJoin.join(address(this), 10 * WAD);
        vat.frob(
            ilk,
            address(pool),
            address(pool),
            address(this),
            0,
            -int256(10 * WAD)
        );

        hub.cage(ilk);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertEq(pink, 50 * WAD);
        assertEq(part, 40 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        uint256 sinBefore = vat.sin(vow);
        uint256 vowDaiBefore = vat.dai(vow);

        hub.cull(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(pool)), 50 * WAD);
        assertEq(vat.dai(address(hub)), 0);
        // Sin only increases by 40 WAD since 10 was covered previously
        assertEq(vat.sin(vow), sinBefore + 40 * RAD);
        assertEq(vat.dai(vow), vowDaiBefore);
        (, , , , uint256 culled, ) = hub.ilks(ilk);
        assertEq(culled, 1);

        hub.exec(ilk);

        assertEq(vat.gem(ilk, address(pool)), 0);
        assertEq(vat.dai(address(hub)), 0);
        // Still 50 WAD because the extra 10 WAD from repayment are not
        // accounted for in the fees from unwind
        assertEq(vat.dai(vow), vowDaiBefore + 50 * RAD);
    }

    function test_cull_no_auth_time_passed() public {
        _windSystem();
        hub.cage(ilk);
        // with auth we can cull anytime
        hub.deny(address(this));
        // but with enough time, anyone can cull
        vm.warp(block.timestamp + 7 days);

        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertEq(pink, 50 * WAD);
        assertEq(part, 50 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        uint256 sinBefore = vat.sin(vow);

        hub.cull(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 0);
        assertEq(art, 0);
        uint256 gemAfter = vat.gem(ilk, address(pool));
        assertEq(gemAfter, 50 * WAD);
        assertEq(vat.sin(vow), sinBefore + 50 * RAD);
        (, , , , uint256 culled, ) = hub.ilks(ilk);
        assertEq(culled, 1);
    }

    function test_no_cull_mcd_caged() public {
        _windSystem();
        hub.cage(ilk);
        vat.cage();

        assertRevert(address(hub), abi.encodeWithSignature("cull(bytes32)", ilk), "D3MHub/no-cull-during-shutdown");
    }

    function test_no_cull_pool_live() public {
        _windSystem();

        assertRevert(address(hub), abi.encodeWithSignature("cull(bytes32)", ilk), "D3MHub/pool-live");
    }

    function test_no_cull_unauth_too_soon() public {
        _windSystem();
        hub.cage(ilk);
        hub.deny(address(this));
        vm.warp(block.timestamp + 6 days);

        assertRevert(address(hub), abi.encodeWithSignature("cull(bytes32)", ilk), "D3MHub/unauthorized-cull");
    }

    function test_no_cull_already_culled() public {
        _windSystem();
        hub.cage(ilk);

        hub.cull(ilk);
        assertRevert(address(hub), abi.encodeWithSignature("cull(bytes32)", ilk), "D3MHub/already-culled");
    }

    function test_no_cull_no_ilk() public {
        assertRevert(address(hub), abi.encodeWithSignature("cull(bytes32)", bytes32("fake-ilk")), "D3MHub/pool-live");
    }

    function test_uncull() public {
        _windSystem();
        hub.cage(ilk);

        hub.cull(ilk);
        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertEq(pink, 0);
        assertEq(part, 0);
        assertEq(vat.gem(ilk, address(pool)), 50 * WAD);
        uint256 sinBefore = vat.sin(vow);
        (, , , , uint256 culled, ) = hub.ilks(ilk);
        assertEq(culled, 1);

        vat.cage();
        hub.uncull(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 0);
        // Sin should not change since we suck before grabbing
        assertEq(vat.sin(vow), sinBefore);
        (, , , , culled, ) = hub.ilks(ilk);
        assertEq(culled, 0);
    }

    function test_no_uncull_not_culled() public {
        _windSystem();
        hub.cage(ilk);

        vat.cage();
        assertRevert(address(hub), abi.encodeWithSignature("uncull(bytes32)", ilk), "D3MHub/not-prev-culled");
    }

    function test_no_uncull_mcd_live() public {
        _windSystem();
        hub.cage(ilk);

        hub.cull(ilk);

        assertRevert(address(hub), abi.encodeWithSignature("uncull(bytes32)", ilk), "D3MHub/no-uncull-normal-operation");
    }

    function test_quit_culled() public {
        _windSystem();
        hub.cage(ilk);

        hub.cull(ilk);

        address receiver = address(123);

        uint256 balBefore = dai.balanceOf(receiver);
        assertEq(dai.balanceOf(address(pool)), 50 * WAD);
        assertEq(vat.gem(ilk, address(pool)), 50 * WAD);

        pool.quit(receiver);
        vat.slip(
            ilk,
            address(pool),
            -int256(vat.gem(ilk, address(pool)))
        );

        assertEq(dai.balanceOf(receiver), balBefore + 50 * WAD);
        assertEq(dai.balanceOf(address(pool)), 0);
        assertEq(vat.gem(ilk, address(pool)), 0);
    }

    function test_quit_not_culled() public {
        _windSystem();

        address receiver = address(123);
        uint256 balBefore = dai.balanceOf(receiver);
        assertEq(dai.balanceOf(address(pool)), 50 * WAD);
        (uint256 pink, uint256 part) = vat.urns(ilk, address(pool));
        assertEq(pink, 50 * WAD);
        assertEq(part, 50 * WAD);
        (uint256 tink, uint256 tart) = vat.urns(ilk, receiver);
        assertEq(tink, 0);
        assertEq(tart, 0);

        pool.quit(receiver);
        vat.grab(
            ilk,
            address(pool),
            receiver,
            receiver,
            -int256(pink),
            -int256(part)
        );
        vat.grab(ilk, receiver, receiver, receiver, int256(pink), int256(part));

        assertEq(dai.balanceOf(receiver), balBefore + 50 * WAD);
        (uint256 joinInk, uint256 joinArt) = vat.urns(
            ilk,
            address(pool)
        );
        assertEq(joinInk, 0);
        assertEq(joinArt, 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, receiver);
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
    }

    function test_pool_upgrade_unwind_wind() public {
        _windSystem(); // Tests that the current pool has ink/art

        // Setup new pool
        PoolMock newPool = new PoolMock(address(vat), address(hub), address(dai), address(testGem));

        (uint256 npink, uint256 npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 0);
        assertEq(npart, 0);
        assertTrue(newPool.preDebt() == false);
        assertTrue(newPool.postDebt() == false);

        // Plan Inactive
        plan.disable();
        assertTrue(plan.active() == false);

        hub.exec(ilk);

        // Ensure we unwound our position
        (uint256 opink, uint256 opart) = vat.urns(ilk, address(pool));
        assertEq(opink, 0);
        assertEq(opart, 0);
        // Make sure pre/post functions get called
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
        pool.resetPrePostDebt();

        hub.file(ilk, "pool", address(newPool));
        // Reactivate Plan
        plan.setTargetAssets(50 * WAD);
        assertTrue(plan.active());
        hub.exec(ilk);

        // New Pool should get wound up to the original amount because plan didn't change
        (npink, npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 50 * WAD);
        assertEq(npart, 50 * WAD);
        assertTrue(newPool.preDebt());
        assertTrue(newPool.postDebt());

        (opink, opart) = vat.urns(ilk, address(pool));
        assertEq(opink, 0);
        assertEq(opart, 0);
        // Make sure unwind calls hooks
        assertTrue(pool.preDebt() == false);
        assertTrue(pool.postDebt() == false);
    }

    function test_pool_upgrade_quit() public {
        _windSystem(); // Tests that the current pool has ink/art

        // Setup new pool
        PoolMock newPool = new PoolMock(
            address(vat),
            address(hub),
            address(dai),
            address(testGem)
        );

        (uint256 opink, uint256 opart) = vat.urns(ilk, address(pool));
        assertGt(opink, 0);
        assertGt(opart, 0);

        (uint256 npink, uint256 npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 0);
        assertEq(npart, 0);
        assertTrue(newPool.preDebt() == false);
        assertTrue(newPool.postDebt() == false);

        // quit to new pool
        pool.quit(address(newPool));
        vat.grab(
            ilk,
            address(pool),
            address(newPool),
            address(newPool),
            -int256(opink),
            -int256(opart)
        );
        vat.grab(
            ilk,
            address(newPool),
            address(newPool),
            address(newPool),
            int256(opink),
            int256(opart)
        );

        // Ensure we quit our position
        (opink, opart) = vat.urns(ilk, address(pool));
        assertEq(opink, 0);
        assertEq(opart, 0);
        // quit does not call hooks
        assertTrue(pool.preDebt() == false);
        assertTrue(pool.postDebt() == false);

        (npink, npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 50 * WAD);
        assertEq(npart, 50 * WAD);
        assertTrue(newPool.preDebt() == false);
        assertTrue(newPool.postDebt() == false);

        // file new pool
        hub.file(ilk, "pool", address(newPool));

        // test unwind/wind
        plan.setTargetAssets(45 * WAD);
        hub.exec(ilk);

        (opink, opart) = vat.urns(ilk, address(pool));
        assertEq(opink, 0);
        assertEq(opart, 0);

        (npink, npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 45 * WAD);
        assertEq(npart, 45 * WAD);

        plan.setTargetAssets(100 * WAD);
        hub.exec(ilk);

        (opink, opart) = vat.urns(ilk, address(pool));
        assertEq(opink, 0);
        assertEq(opart, 0);

        (npink, npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 100 * WAD);
        assertEq(npart, 100 * WAD);
    }

    function test_plan_upgrade() public {
        _windSystem(); // Tests that the current pool has ink/art

        // Setup new plan
        PlanMock newPlan = new PlanMock();
        newPlan.setTargetAssets(100 * WAD);

        hub.file(ilk, "plan", address(newPlan));

        (, ID3MPlan _plan, , , , ) = hub.ilks(ilk);
        assertEq(address(_plan), address(newPlan));

        hub.exec(ilk);

        // New Plan should determine the pool position
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 100 * WAD);
        assertEq(art, 100 * WAD);
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function test_hub_upgrade_same_d3ms() public {
        _windSystem(); // Tests that the current pool has ink/art

        // Setup New hub
        D3MHub newHub = new D3MHub(address(daiJoin));
        newHub.file("vow", vow);
        newHub.file("end", address(end));

        newHub.file(ilk, "pool", address(pool));
        newHub.file(ilk, "plan", address(plan));
        newHub.file(ilk, "tau", 7 days);

        // Update permissions on d3ms
        pool.file("hub", address(newHub));

        // Update Permissions in Vat
        vat.deny(address(hub));
        vat.rely(address(newHub));

        // Clean up old hub
        hub.file(ilk, "pool", address(0));
        hub.file(ilk, "plan", address(0));
        hub.file(ilk, "tau", 0);

        // Ensure new hub operation
        plan.setTargetAssets(100 * WAD);
        newHub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 100 * WAD);
        assertEq(art, 100 * WAD);
        assertTrue(pool.preDebt());
        assertTrue(pool.postDebt());
    }

    function testFail_hub_upgrade_kills_old_hub() public {
        _windSystem(); // Tests that the current pool has ink/art

        // Setup New hub
        D3MHub newHub = new D3MHub(address(daiJoin));
        newHub.file("vow", vow);
        newHub.file("end", address(end));

        newHub.file(ilk, "pool", address(pool));
        newHub.file(ilk, "plan", address(plan));
        newHub.file(ilk, "tau", 7 days);

        // Update permissions on d3ms
        pool.file("hub", address(newHub));

        // Update Permissions in Vat
        vat.deny(address(hub));
        vat.rely(address(newHub));

        // Clean up old hub
        hub.file(ilk, "pool", address(0));
        hub.file(ilk, "plan", address(0));
        hub.file(ilk, "tau", 0);

        // Ensure old hub revert
        hub.exec(ilk);
    }

    function test_hub_upgrade_new_d3ms() public {
        _windSystem(); // Tests that the current pool has ink/art

        // Setup New hub and D3M
        D3MHub newHub = new D3MHub(address(daiJoin));
        newHub.file("vow", vow);
        newHub.file("end", address(end));
        vat.rely(address(newHub));

        // Setup new pool
        PoolMock newPool = new PoolMock(
            address(vat),
            address(newHub),
            address(dai),
            address(testGem)
        );

        // Setup new plan
        PlanMock newPlan = new PlanMock();
        newPlan.setTargetAssets(100 * WAD);

        // Create D3M in New Hub
        newHub.file(ilk, "pool", address(newPool));
        newHub.file(ilk, "plan", address(newPlan));
        (, , , uint256 tau, , ) = hub.ilks(ilk);
        newHub.file(ilk, "tau", tau);

        (uint256 opink, uint256 opart) = vat.urns(ilk, address(pool));
        assertGt(opink, 0);
        assertGt(opart, 0);

        (uint256 npink, uint256 npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 0);
        assertEq(npart, 0);
        assertTrue(newPool.preDebt() == false);
        assertTrue(newPool.postDebt() == false);

        newPool.file("hub", address(newHub));

        // Transition Balances
        pool.quit(address(newPool));
        vat.grab(
            ilk,
            address(pool),
            address(newPool),
            address(newPool),
            -int256(opink),
            -int256(opart)
        );
        vat.grab(
            ilk,
            address(newPool),
            address(newPool),
            address(newPool),
            int256(opink),
            int256(opart)
        );

        // Ensure we quit our position
        (opink, opart) = vat.urns(ilk, address(pool));
        assertEq(opink, 0);
        assertEq(opart, 0);
        // quit does not call hooks
        assertTrue(pool.preDebt() == false);
        assertTrue(pool.postDebt() == false);

        (npink, npart) = vat.urns(ilk, address(newPool));
        assertEq(npink, 50 * WAD);
        assertEq(npart, 50 * WAD);
        assertTrue(newPool.preDebt() == false);
        assertTrue(newPool.postDebt() == false);

        // Clean up after transition
        hub.cage(ilk);
        vat.deny(address(hub));

        // Ensure new hub operation
        newPlan.setTargetAssets(200 * WAD);
        newHub.exec(ilk);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(newPool));
        assertEq(ink, 200 * WAD);
        assertEq(art, 200 * WAD);
        assertTrue(newPool.preDebt());
        assertTrue(newPool.postDebt());
    }

    function test_exec_lock_protection() public {
        // Store memory slot 0x3
        vm.store(address(hub), bytes32(uint256(3)), bytes32(uint256(1)));
        assertEq(hub.locked(), 1);

        assertRevert(address(hub), abi.encodeWithSignature("exec(bytes32)", ilk), "D3MHub/system-locked");
    }

    function test_exit_lock_protection() public {
        // Store memory slot 0x3
        vm.store(address(hub), bytes32(uint256(3)), bytes32(uint256(1)));
        assertEq(hub.locked(), 1);

        assertRevert(address(hub), abi.encodeWithSignature("exit(bytes32,address,uint256)", ilk, address(this), 1), "D3MHub/system-locked");
    }

    function test_unwind_due_to_by_pool_loss() public {
        _windSystem(); // winds to 50 * WAD

        // Set debt ceiling to 60 to limit loss
        vat.file(ilk, "line", 60 * RAD);

        // Simulate a loss event by removing the tokens
        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(dai.balanceOf(address(pool)), 50 * WAD);
        assertEq(pool.assetBalance(), 50 * WAD);

        address(dai).setBalance(address(pool), 20 * WAD); // Lost 30 tokens

        assertEq(dai.balanceOf(address(pool)), 20 * WAD);
        assertEq(pool.assetBalance(), 20 * WAD);
        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);

        // This should force unwind
        hub.exec(ilk);

        assertEq(pool.assetBalance(), 0);
        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 30 * WAD);
        assertEq(art, 30 * WAD);
    }

    function test_exec_fixInk_full_under_debt_ceiling() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        pool.accrueInterest(10 * WAD);
        assertEq(pool.assetBalance(), 60 * WAD);
        assertEq(pool.maxWithdraw(), 50 * WAD);

        vat.file(ilk, "line", 55 * RAD);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(vat.dai(vow), prevDai + 10 * RAD);
        assertEq(testGem.balanceOf(address(pool)), 10 * WAD);
    }

    function test_exec_fixInk_limited_under_debt_ceiling_nothing_to_withdraw() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        address(testGem).setBalance(address(pool), 10 * WAD);
        assertEq(pool.assetBalance(), 60 * WAD);
        pool.decreaseIdleLiquidity(50 * WAD);
        assertEq(pool.maxWithdraw(), 0);

        vat.file(ilk, "line", 55 * RAD);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 55 * WAD);
        assertEq(art, 55 * WAD);
        assertEq(vat.dai(vow), prevDai + 5 * RAD);
        assertEq(testGem.balanceOf(address(pool)), 60 * WAD);
    }

    function test_exec_fixInk_limited_under_debt_ceiling_something_to_withdraw() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        address(testGem).setBalance(address(pool), 10 * WAD);
        assertEq(pool.assetBalance(), 60 * WAD);
        pool.decreaseIdleLiquidity(47 * WAD);
        assertEq(pool.maxWithdraw(), 3 * WAD);

        vat.file(ilk, "line", 55 * RAD);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 55 * WAD);
        assertEq(art, 55 * WAD);
        assertEq(vat.dai(vow), prevDai + 8 * RAD);
        assertEq(testGem.balanceOf(address(pool)), 57 * WAD);
    }

    function test_exec_fixInk_full_at_debt_ceiling() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        pool.accrueInterest(10 * WAD);
        assertEq(pool.assetBalance(), 60 * WAD);
        assertEq(pool.maxWithdraw(), 50 * WAD);

        vat.file(ilk, "line", 50 * RAD);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(vat.dai(vow), prevDai + 10 * RAD);
        assertEq(testGem.balanceOf(address(pool)), 10 * WAD);
    }

    function test_exec_fixInk_limited_at_debt_ceiling_nothing_to_withdraw() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        pool.accrueInterest(10 * WAD);
        assertEq(pool.assetBalance(), 60 * WAD);
        pool.decreaseIdleLiquidity(50 * WAD);
        assertEq(pool.maxWithdraw(), 0);

        vat.file(ilk, "line", 50 * RAD);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(vat.dai(vow), prevDai);
        assertEq(testGem.balanceOf(address(pool)), 60 * WAD);
    }

    function test_exec_fixInk_limited_at_debt_ceiling_something_to_withdraw() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        pool.accrueInterest(10 * WAD);
        assertEq(pool.assetBalance(), 60 * WAD);
        pool.decreaseIdleLiquidity(47 * WAD);
        assertEq(pool.maxWithdraw(), 3 * WAD);

        vat.file(ilk, "line", 50 * RAD);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(vat.dai(vow), prevDai + 3 * RAD);
        assertEq(testGem.balanceOf(address(pool)), 57 * WAD);
    }

    function test_exec_fixInk_full_above_debt_ceiling() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        pool.accrueInterest(10 * WAD);
        assertEq(pool.assetBalance(), 60 * WAD);
        pool.decreaseIdleLiquidity(40 * WAD);
        assertEq(pool.maxWithdraw(), 10 * WAD);

        vat.file(ilk, "line", 45 * RAD);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(vat.dai(vow), prevDai + 10 * RAD);
        assertEq(testGem.balanceOf(address(pool)), 50 * WAD);
    }

    function test_exec_fixInk_limited_above_debt_ceiling_nothing_to_withdraw() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        pool.accrueInterest(10 * WAD);
        assertEq(pool.assetBalance(), 60 * WAD);
        pool.decreaseIdleLiquidity(50 * WAD);
        assertEq(pool.maxWithdraw(), 0);

        vat.file(ilk, "line", 45 * RAD);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(vat.dai(vow), prevDai);
        assertEq(testGem.balanceOf(address(pool)), 60 * WAD);
    }

    function test_exec_fixInk_limited_above_debt_ceiling_something_to_withdraw() public {
        _windSystem();
        // interest is determined by the difference in gem balance to dai debt
        // by giving extra gems to the Join we simulate interest
        pool.accrueInterest(10 * WAD);
        assertEq(pool.assetBalance(), 60 * WAD);
        pool.decreaseIdleLiquidity(47 * WAD);
        assertEq(pool.maxWithdraw(), 3 * WAD);

        vat.file(ilk, "line", 45 * RAD);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        uint256 prevDai = vat.dai(vow);

        hub.exec(ilk);

        (ink, art) = vat.urns(ilk, address(pool));
        assertEq(ink, 50 * WAD);
        assertEq(art, 50 * WAD);
        assertEq(vat.dai(vow), prevDai + 3 * RAD);
        assertEq(testGem.balanceOf(address(pool)), 57 * WAD);
    }

    function test_exec_different_art_Art() public {
        vat.slip(ilk, address(this), int256(1));
        vat.frob(ilk, address(this), address(this), address(this), int256(1), int256(1));
        assertRevert(address(hub), abi.encodeWithSignature("exec(bytes32)", bytes32("fake-ilk")), "D3MHub/rate-not-one");
    }

    function test_culled_not_reverting_different_art_Art() public {
        vat.slip(ilk, address(this), int256(1));
        vat.frob(ilk, address(this), address(this), address(this), int256(1), int256(1));
        hub.cage(ilk);
        hub.cull(ilk);
        hub.exec(ilk);
    }

    function test_system_caged_not_reverting_different_art_Art() public {
        vat.slip(ilk, address(this), int256(1));
        vat.frob(ilk, address(this), address(this), address(this), int256(1), int256(1));
        end.cage();
        end.cage(ilk);
        hub.exec(ilk);
    }

    function test_cage_ilk_after_uncull() public {
        _windSystem();
        hub.cage(ilk);
        hub.cull(ilk);
        end.cage();
        hub.uncull(ilk);
        end.cage(ilk);
    }

    function test_cage_ilk_before_uncull() public {
        _windSystem();
        hub.cage(ilk);
        hub.cull(ilk);
        end.cage();
        assertRevert(address(end), abi.encodeWithSignature("cage(bytes32)", ilk), "D3MOracle/ilk-culled-in-shutdown");
    }

}
