// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
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

pragma solidity 0.6.12;

import "ds-test/test.sol";
import "dss-interfaces/Interfaces.sol";
import "ds-value/value.sol";

import "./DssDirectDepositAaveDai.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external view returns (bytes32);
}

interface AuthLike {
    function wards(address) external returns (uint256);
}

contract DssDirectDepositAaveDaiTest is DSTest {

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    Hevm hevm;

    ChainlogAbstract chainlog;
    VatAbstract vat;
    LendingPoolLike pool;
    InterestRateStrategyLike interestStrategy;
    RewardsClaimerLike rewardsClaimer;
    DaiAbstract dai;
    DaiJoinAbstract daiJoin;
    DSTokenAbstract adai;
    DSTokenAbstract stkAave;
    SpotAbstract spot;
    DSTokenAbstract weth;
    address vow;
    address pauseProxy;

    bytes32 constant ilk = "DD-DAI-A";
    DssDirectDepositAaveDai deposit;
    DSValue pip;

    // Allow for a 1 BPS margin of error on interest rates
    uint256 constant INTEREST_RATE_TOLERANCE = RAY / 10000;
    uint256 constant EPSILON_TOLERANCE = 4;

    function setUp() public {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

        chainlog = ChainlogAbstract(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
        vat = VatAbstract(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        pool = LendingPoolLike(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        adai = DSTokenAbstract(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
        stkAave = DSTokenAbstract(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
        dai = DaiAbstract(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        daiJoin = DaiJoinAbstract(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
        interestStrategy = InterestRateStrategyLike(0xfffE32106A68aA3eD39CcCE673B646423EEaB62a);
        rewardsClaimer = RewardsClaimerLike(0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5);
        spot = SpotAbstract(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);
        weth = DSTokenAbstract(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        vow = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;
        pauseProxy = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

        // Force give admin access to this contract via hevm magic
        giveAuthAccess(address(vat), address(this));
        giveAuthAccess(address(spot), address(this));
        
        deposit = new DssDirectDepositAaveDai(address(chainlog), ilk, address(pool), address(rewardsClaimer), 7 days);

        // Init new collateral
        pip = new DSValue();
        pip.poke(bytes32(WAD));
        spot.file(ilk, "pip", address(pip));
        spot.file(ilk, "mat", RAY);
        spot.poke(ilk);

        vat.rely(address(deposit));
        vat.init(ilk);
        vat.file(ilk, "line", 5_000_000_000 * RAD);
        vat.file("Line", vat.Line() + 5_000_000_000 * RAD);

        // Give us a bunch of WETH and deposit into Aave
        uint256 amt = 1_000_000 * WAD;
        giveTokens(weth, amt);
        weth.approve(address(pool), uint256(-1));
        dai.approve(address(pool), uint256(-1));
        pool.deposit(address(weth), amt, address(this), 0);
    }

    // --- Math ---
    function add(uint256 x, uint256 y) public pure returns (uint256 z) {
        require((z = x + y) >= x, "DssDirectDepositAaveDai/overflow");
    }
    function sub(uint256 x, uint256 y) public pure returns (uint256 z) {
        require((z = x - y) <= x, "DssDirectDepositAaveDai/underflow");
    }
    function mul(uint256 x, uint256 y) public pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "DssDirectDepositAaveDai/overflow");
    }
    function rmul(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = mul(x, y) / RAY;
    }
    function rdiv(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = mul(x, RAY) / y;
    }

    function giveAuthAccess (address _base, address target) internal {
        AuthLike base = AuthLike(_base);

        // Edge case - ward is already set
        if (base.wards(target) == 1) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the ward storage slot
            bytes32 prevValue = hevm.load(
                address(base),
                keccak256(abi.encode(target, uint256(i)))
            );
            hevm.store(
                address(base),
                keccak256(abi.encode(target, uint256(i))),
                bytes32(uint256(1))
            );
            if (base.wards(target) == 1) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(base),
                    keccak256(abi.encode(target, uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function giveTokens(DSTokenAbstract token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (token.balanceOf(address(this)) == amount) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                address(token),
                keccak256(abi.encode(address(this), uint256(i)))
            );
            hevm.store(
                address(token),
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (token.balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function assertEqApprox(uint256 _a, uint256 _b, uint256 _tolerance) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > _tolerance) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function assertEqInterest(uint256 _a, uint256 _b) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > INTEREST_RATE_TOLERANCE) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_decimal_uint("  Expected", _b, 27);
            emit log_named_decimal_uint("    Actual", _a, 27);
            fail();
        }
    }

    // aTOKENs round against the depositor - we allow a rounding error of 1
    function assertEqRoundingAgainst(uint256 _a, uint256 _b) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > 1) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_decimal_uint("  Expected", _b, 27);
            emit log_named_decimal_uint("    Actual", _a, 27);
            fail();
        }
    }

    function getBorrowRate() public view returns (uint256 borrowRate) {
        (,,,, borrowRate,,,,,,,) = pool.getReserveData(address(dai));
    }

    // Set the borrow rate to a relative percent to what it currently is
    function set_rel_borrow_target(uint256 deltaBPS) internal returns (uint256 targetBorrowRate) {
        targetBorrowRate = getBorrowRate() * deltaBPS / 10000;
        deposit.file("bar", targetBorrowRate);
        deposit.exec();
    }

    function test_interest_rate_calc() public {
        // Confirm that the inverse function is correct by comparing all percentages
        for (uint256 i = 1; i <= 100 * interestStrategy.getMaxVariableBorrowRate() / RAY; i++) {
            uint256 targetSupply = deposit.calculateTargetSupply(i * RAY / 100);
            (,, uint256 varBorrow) = interestStrategy.calculateInterestRates(
                address(adai),
                targetSupply - (adai.totalSupply() - dai.balanceOf(address(adai))),
                0,
                adai.totalSupply() - dai.balanceOf(address(adai)),
                0,
                0
            );
            assertEqInterest(varBorrow, i * RAY / 100);
        }
    }

    function test_target_decrease() public {
        uint256 targetBorrowRate = set_rel_borrow_target(7500);
        deposit.reap();     // Clear out interest to get rid of rounding errors
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        uint256 amountMinted = adai.balanceOf(address(deposit));
        assertTrue(amountMinted > 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertTrue(ink <= amountMinted + 1);    // We allow a rounding error of 1 because aTOKENs round against the user
        assertTrue(art <= amountMinted + 1);
        assertEq(vat.gem(ilk, address(deposit)), 0);
        assertEq(vat.dai(address(deposit)), 0);
    }

    function test_target_increase() public {
        // Lower by 50%
        uint256 targetBorrowRate = set_rel_borrow_target(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Raise by 25%
        targetBorrowRate = set_rel_borrow_target(12500);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        uint256 amountMinted = adai.balanceOf(address(deposit));
        assertTrue(amountMinted > 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertTrue(ink <= amountMinted + 1);    // We allow a rounding error of 1 because aTOKENs round against the user
        assertTrue(art <= amountMinted + 1);
        assertEq(vat.gem(ilk, address(deposit)), 0);
        assertEq(vat.dai(address(deposit)), 0);
    }

    function test_target_increase_insufficient_liquidity() public {
        uint256 currBorrowRate = getBorrowRate();

        // Attempt to increase by 25% (you can't)
        set_rel_borrow_target(12500);
        assertEqInterest(getBorrowRate(), currBorrowRate);  // Unchanged

        assertEq(adai.balanceOf(address(deposit)), 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(deposit)), 0);
        assertEq(vat.dai(address(deposit)), 0);
    }

    function test_cage_temp_insufficient_liquidity() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = set_rel_borrow_target(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);
        
        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(deposit));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        pool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // Cage the system and start unwinding
        currentLiquidity = dai.balanceOf(address(adai));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(deposit));
        deposit.cage();
        assertEq(deposit.live(), 0);
        deposit.exec();

        // Should be no dai liquidity remaining as we attempt to fully unwind
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertEq(pink - ink, currentLiquidity);
        assertEq(part - art, currentLiquidity);
        assertEq(dai.balanceOf(address(adai)), 0);
        assertEq(getBorrowRate(), interestStrategy.getMaxVariableBorrowRate());

        // Someone else repays some Dai so we can unwind the rest
        hevm.warp(block.timestamp + 1 days);
        pool.repay(address(dai), amountToBorrow, 2, address(this));

        deposit.exec();
        assertEq(adai.balanceOf(address(deposit)), 0);
        assertTrue(dai.balanceOf(address(adai)) > 0);
    }

    function test_cage_perm_insufficient_liquidity() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = set_rel_borrow_target(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);
        
        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(deposit));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        pool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // Cage the system and start unwinding
        currentLiquidity = dai.balanceOf(address(adai));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(deposit));
        deposit.cage();
        assertEq(deposit.live(), 0);
        deposit.exec();

        // Should be no dai liquidity remaining as we attempt to fully unwind
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertTrue(ink > 0);
        assertTrue(art > 0);
        assertEq(pink - ink, currentLiquidity);
        assertEq(part - art, currentLiquidity);
        assertEq(dai.balanceOf(address(adai)), 0);
        assertEq(getBorrowRate(), interestStrategy.getMaxVariableBorrowRate());

        // In this case nobody deposits more DAI so we have to write off the bad debt
        hevm.warp(block.timestamp + 7 days);

        uint256 sin = vat.sin(vow);
        uint256 vowDai = vat.dai(vow);
        deposit.cull();
        (uint256 ink2, uint256 art2) = vat.urns(ilk, address(deposit));
        assertEq(deposit.culled(), 1);
        assertEq(ink2, 0);
        assertEq(art2, 0);
        assertEq(vat.gem(ilk, address(deposit)), ink);
        assertEq(vat.sin(vow), sin + art * RAY);
        assertEq(vat.dai(vow), vowDai);

        // Some time later the pool gets some liquidity
        hevm.warp(block.timestamp + 180 days);
        pool.repay(address(dai), amountToBorrow, 2, address(this));

        // Close out the remainder of the position
        uint256 adaiBalance = adai.balanceOf(address(deposit));
        assertTrue(adaiBalance >= art);
        deposit.exec();
        assertEq(adai.balanceOf(address(deposit)), 0);
        assertTrue(dai.balanceOf(address(adai)) > 0);
        assertEq(vat.sin(vow), sin + art * RAY);
        assertEq(vat.dai(vow), vowDai + adaiBalance * RAY);
        assertEq(vat.gem(ilk, address(deposit)), 0);
    }

    function test_hit_debt_ceiling() public {
        // Lower the debt ceiling to 100k
        uint256 debtCeiling = 100_000 * WAD;
        vat.file(ilk, "line", debtCeiling * RAY);

        uint256 currBorrowRate = getBorrowRate();

        // Set a super low target interest rate
        uint256 targetBorrowRate = set_rel_borrow_target(1);
        deposit.reap();
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertTrue(getBorrowRate() > targetBorrowRate && getBorrowRate() < currBorrowRate);
        assertEqRoundingAgainst(adai.balanceOf(address(deposit)), debtCeiling);    // We allow a rounding error of 1 because aTOKENs round against the user

        // Should be a no-op
        deposit.exec();

        // Raise it by a bit
        currBorrowRate = getBorrowRate();
        debtCeiling = 125_000 * WAD;
        vat.file(ilk, "line", debtCeiling * RAY);
        deposit.exec();
        deposit.reap();
        (ink, art) = vat.urns(ilk, address(deposit));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertTrue(getBorrowRate() > targetBorrowRate && getBorrowRate() < currBorrowRate);
        assertEqRoundingAgainst(adai.balanceOf(address(deposit)), debtCeiling);    // We allow a rounding error of 1 because aTOKENs round against the user
    }

    function test_collect_interest() public {
        set_rel_borrow_target(7500);

        hevm.warp(block.timestamp + 1 days);     // Collect one day of interest

        uint256 vowDai = vat.dai(vow);
        deposit.reap();

        log_named_decimal_uint("dai", vat.dai(vow) - vowDai, 18);

        assertTrue(vat.dai(vow) - vowDai > 0);
    }

    function test_insufficient_liquidity_for_unwind_fees() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));
        uint256 vowDai = vat.dai(vow);

        // Lower by 50%
        uint256 targetBorrowRate = set_rel_borrow_target(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);
        
        // Someone else borrows the exact amount previously available
        (uint256 amountSupplied,) = vat.urns(ilk, address(deposit));
        uint256 amountToBorrow = currentLiquidity;
        pool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // Accumulate a bunch of interest
        hevm.warp(block.timestamp + 180 days);
        uint256 feesAccrued = adai.balanceOf(address(deposit)) - amountSupplied;
        currentLiquidity = dai.balanceOf(address(adai));
        assertGt(feesAccrued, 0);
        assertEq(amountSupplied, currentLiquidity);
        assertGt(amountSupplied + feesAccrued, currentLiquidity);

        // Cage the system to trigger only unwinds
        deposit.cage();
        deposit.exec();

        // The full debt should be paid off, but we are still owed fees
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertGt(adai.balanceOf(address(deposit)), 0);
        assertEq(vat.dai(vow), vowDai);

        // Someone repays
        pool.repay(address(dai), amountToBorrow, 2, address(this));
        deposit.exec();

        (ink, art) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(adai.balanceOf(address(deposit)), 0);
        assertEqApprox(vat.dai(vow), vowDai + feesAccrued * RAY, RAY);
    }

    function test_insufficient_liquidity_for_reap_fees() public {
        // Lower by 50%
        uint256 targetBorrowRate = set_rel_borrow_target(5000);
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Accumulate a bunch of interest
        hevm.warp(block.timestamp + 180 days);

        // Someone else borrows almost all the liquidity
        pool.borrow(address(dai), dai.balanceOf(address(adai)) - 100 * WAD, 2, 0, address(this));

        // Reap the partial fees
        uint256 vowDai = vat.dai(vow);
        deposit.reap();
        assertEq(vat.dai(vow) - vowDai, 100 * RAD);
    }

    function test_collect_stkaave() public {
        set_rel_borrow_target(7500);
        
        hevm.warp(block.timestamp + 1 days);

        // Set the king
        deposit.file("king", address(pauseProxy));

        // Collect some stake rewards into the pause proxy
        address[] memory tokens = new address[](1);
        tokens[0] = address(adai);
        uint256 amountToClaim = rewardsClaimer.getRewardsBalance(tokens, address(deposit));
        if (amountToClaim == 0) return;     // Rewards are turned off - this is still an acceptable state
        uint256 amountClaimed = deposit.collect(tokens, uint256(-1));
        assertEq(amountClaimed, amountToClaim);
        assertEq(stkAave.balanceOf(address(pauseProxy)), amountClaimed);
        assertEq(rewardsClaimer.getRewardsBalance(tokens, address(deposit)), 0);
        
        hevm.warp(block.timestamp + 1 days);

        // Collect some more rewards
        uint256 amountToClaim2 = rewardsClaimer.getRewardsBalance(tokens, address(deposit));
        assertGt(amountToClaim2, 0);
        uint256 amountClaimed2 = deposit.collect(tokens, uint256(-1));
        assertEq(amountClaimed2, amountToClaim2);
        assertEq(stkAave.balanceOf(address(pauseProxy)), amountClaimed + amountClaimed2);
        assertEq(rewardsClaimer.getRewardsBalance(tokens, address(deposit)), 0);
    }

    function testFail_collect_stkaave_king_not_set() public {
        set_rel_borrow_target(7500);
        
        hevm.warp(block.timestamp + 1 days);

        // Collect some stake rewards into the pause proxy
        address[] memory tokens = new address[](1);
        tokens[0] = address(adai);
        uint256 amountToClaim = rewardsClaimer.getRewardsBalance(tokens, address(deposit));
        assertTrue(amountToClaim > 0);
        deposit.collect(tokens, uint256(-1));
    }
    
    function test_cage_exit() public {
        set_rel_borrow_target(7500);

        // Vat is caged for global settlement
        vat.cage();

        // Simulate DAI holder gets some gems from GS
        vat.grab(ilk, address(deposit), address(this), address(this), -int256(100 ether), -int256(0));

        // User can exit and get the aDAI
        deposit.exit(address(this), 100 ether);
        assertEqApprox(adai.balanceOf(address(this)), 100 ether, 1);     // Slight rounding error may occur
    }
    
    function testFail_shutdown_cant_cull() public {
        set_rel_borrow_target(7500);

        // Vat is caged for global settlement
        vat.cage();
        deposit.cage();

        hevm.warp(block.timestamp + deposit.tau());

        deposit.cull();
    }
    
    function test_quit_no_cull() public {
        set_rel_borrow_target(7500);

        deposit.cage();

        // Test that we can extract the whole position in emergency situations
        // aDAI should be sitting in the deposit contract, urn should be owned by deposit contract
        (uint256 pink, uint256 part) = vat.urns(ilk, address(deposit));
        uint256 pbal = adai.balanceOf(address(deposit));
        assertGt(pink, 0);
        assertGt(part, 0);
        assertGt(pbal, 0);

        vat.hope(address(deposit));     // Need to approve urn transfer
        deposit.quit(address(this));

        (uint256 nink, uint256 nart) = vat.urns(ilk, address(deposit));
        uint256 nbal = adai.balanceOf(address(deposit));
        assertEq(nink, 0);
        assertEq(nart, 0);
        assertEq(nbal, 0);

        (uint256 ink, uint256 art) = vat.urns(ilk, address(this));
        uint256 bal = adai.balanceOf(address(this));
        assertEq(ink, pink);
        assertEq(art, part);
        assertEq(bal, pbal);
    }
    
    function test_quit_cull() public {
        set_rel_borrow_target(7500);

        deposit.cage();

        hevm.warp(block.timestamp + deposit.tau());

        deposit.cull();

        // Test that we can extract the adai in emergency situations
        // aDAI should be sitting in the deposit contract, gems should be owned by deposit contract
        uint256 pgem = vat.gem(ilk, address(deposit));
        uint256 pbal = adai.balanceOf(address(deposit));
        assertGt(pgem, 0);
        assertGt(pbal, 0);

        deposit.quit(address(this));

        uint256 ngem = vat.gem(ilk, address(deposit));
        uint256 nbal = adai.balanceOf(address(deposit));
        assertEq(ngem, 0);
        assertEq(nbal, 0);

        uint256 gem = vat.gem(ilk, address(this));
        uint256 bal = adai.balanceOf(address(this));
        assertEq(gem, 0);
        assertEq(bal, pbal);
    }
    
    function testFail_quit_no_cage() public {
        set_rel_borrow_target(7500);
        
        deposit.quit(address(this));
    }
    
}
