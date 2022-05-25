// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021-2022 Dai Foundation
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

import { D3MMapleV1DaiPlan } from "../plans/D3MMapleV1DaiPlan.sol";

import { Borrower }     from "../tests/accounts/Borrower.sol";
import { PoolDelegate } from "../tests/accounts/PoolDelegate.sol";

import {
    BPoolLike,
    BPoolFactoryLike,
    DaiLike,
    LoanLike,
    MapleGlobalsLike,
    PoolLike,
    TokenLike
} from "../tests/interfaces/interfaces.sol";

import { D3MTestGem } from "../tests/stubs/D3MTestGem.sol";

import { DssDirectDepositHub } from "../DssDirectDepositHub.sol";
import { D3MMom }              from "../D3MMom.sol";

import { AddressRegistry }                         from "./AddressRegistry.sol";
import { D3MMapleV1DaiPool }                       from "./D3MMapleV1DaiPool.sol";
import { Hevm, D3MPoolBaseTest, FakeHub, FakeVat } from "./D3MPoolBase.t.sol";

contract D3MMapleV1DaiPoolTest is AddressRegistry, D3MPoolBaseTest {

    bytes32 constant ilk = "DD-DAI-B";

    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    address[3] calcs;

    TokenLike constant mpl = TokenLike(MPL);

    PoolDelegate poolDelegate;
    PoolLike     maplePool;

    D3MMapleV1DaiPlan   plan;
    D3MMapleV1DaiPool   d3mPool;
    D3MMom              mom;
    DssDirectDepositHub hub;

    uint256 start;

    function setUp() public override {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

        dai = DaiLike(DAI);

        start = block.timestamp;

        calcs = [REPAYMENT_CALC, LATEFEE_CALC, PREMIUM_CALC];

        _setUpMapleDaiPool();

        hub     = new DssDirectDepositHub(VAT, DAI_JOIN);
        plan    = new D3MMapleV1DaiPlan(DAI, address(maplePool));
        d3mPool = new D3MMapleV1DaiPool(address(hub), address(dai), address(maplePool));
        mom     = new D3MMom();

        d3mTestPool = address(d3mPool);

        d3mPool.rely(address(plan));
        plan.rely(address(mom));

        // Add Maker D3M as sole lender in new Maple maplePool
        poolDelegate.setAllowList(address(maplePool), address(d3mPool), true);
    }

    function test_sets_dai_value() public {

    }

    function test_can_file_king() public {

    }

    function testFail_cannot_file_king_no_auth() public {
        fail();
    }

    function testFail_cannot_file_unknown_param() public {
        fail();
    }

    function test_deposit_calls_lending_pool_deposit() public {

    }

    function testFail_deposit_requires_auth() public {
        fail();
    }

    function test_withdraw_calls_lending_pool_withdraw() public {

    }

    function testFail_withdraw_requires_auth() public {
        fail();
    }

    function test_collect_claims_for_king() public {

    }

    function testFail_collect_no_king() public {
        fail();
    }

    function test_transfer_adai() public {

    }

    function testFail_transfer_no_auth() public {
        fail();
    }

    function test_transferAll_moves_balance() public {

    }

    function testFail_transferAll_no_auth() public {
        fail();
    }

    function test_assetBalance_gets_adai_balanceOf_pool() public {

    }

    function test_maxWithdraw_gets_available_assets_assetBal() public {

    }

    function test_maxWithdraw_gets_available_assets_daiBal() public {

    }

    function test_maxDeposit_returns_max_uint() public {

    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _mintTokens(address token, address account, uint256 amount) internal {
        uint256 slot;

        if      (token == DAI)  slot = 2;
        else if (token == MPL)  slot = 0;
        else if (token == WBTC) slot = 0;

        hevm.store(
            token,
            keccak256(abi.encode(account, slot)),
            bytes32(TokenLike(token).balanceOf(address(account)) + amount)
        );
    }

    function _setUpMapleDaiPool() internal {

        /*********************/
        /*** Set up actors ***/
        /*********************/

        // Grant address(this) auth access to globals
        hevm.store(MAPLE_GLOBALS, bytes32(uint256(1)), bytes32(uint256(uint160(address(this)))));

        poolDelegate = new PoolDelegate();

        /************************************/
        /*** Set up MPL/DAI Balancer Pool ***/
        /************************************/

        BPoolLike usdcBPool = BPoolLike(USDC_BALANCER_POOL);

        uint256 daiAmount = 300_000 * WAD;
        uint256 mplAmount = daiAmount * WAD / (usdcBPool.getSpotPrice(USDC, MPL) * WAD / 10 ** 6);  // $100k of MPL

        _mintTokens(DAI, address(this), daiAmount);
        _mintTokens(MPL, address(this), mplAmount);

        // Initialize MPL/DAI Balancer Pool
        BPoolLike bPool = BPoolLike(BPoolFactoryLike(BPOOL_FACTORY).newBPool());
        dai.approve(address(bPool), type(uint256).max);
        mpl.approve(address(bPool), type(uint256).max);
        bPool.bind(DAI, daiAmount, 5 ether);
        bPool.bind(MPL, mplAmount, 5 ether);
        bPool.finalize();

        // Transfer all BPT to Pool Delegate for initial staking
        bPool.transfer(address(poolDelegate), 40 * WAD);  // Pool Delegate gets enought BPT to stake

        /*************************/
        /*** Configure Globals ***/
        /*************************/

        MapleGlobalsLike globals = MapleGlobalsLike(MAPLE_GLOBALS);

        globals.setLiquidityAsset(DAI, true);
        globals.setPoolDelegateAllowlist(address(poolDelegate), true);
        globals.setValidBalancerPool(address(bPool), true);
        globals.setPriceOracle(DAI, USD_ORACLE);

        /*******************************************************/
        /*** Set up new DAI liquidity maplePool, closed to public ***/
        /*******************************************************/

        // Create a DAI maplePool with a 5m liquidity cap
        maplePool = PoolLike(poolDelegate.createPool(POOL_FACTORY, DAI, address(bPool), SL_FACTORY, LL_FACTORY, 1000, 1000, 5_000_000 ether));

        // Stake BPT for insurance and finalize maplePool
        poolDelegate.approve(address(bPool), maplePool.stakeLocker(), type(uint256).max);
        poolDelegate.stake(maplePool.stakeLocker(), bPool.balanceOf(address(poolDelegate)));
        poolDelegate.finalize(address(maplePool));
    }

    function _createLoan(Borrower borrower, uint256[5] memory specs) internal returns (address loan) {
        return borrower.createLoan(LOAN_FACTORY, DAI, WBTC, FL_FACTORY, CL_FACTORY, specs, calcs);
    }

    function _fundLoanAndDrawdown(Borrower borrower, address loan, uint256 fundAmount) internal {
        poolDelegate.fundLoan(address(maplePool), loan, DL_FACTORY, fundAmount);

        uint256 collateralRequired = LoanLike(loan).collateralRequiredForDrawdown(fundAmount);

        if (collateralRequired > 0) {
            _mintTokens(WBTC, address(borrower), collateralRequired);
            borrower.approve(WBTC, loan, collateralRequired);
        }

        borrower.drawdown(loan, fundAmount);
    }

    function _makePayment(address loan, address borrower) internal {
        ( uint256 paymentAmount, , ) = LoanLike(loan).getNextPayment();
        _mintTokens(DAI, borrower, paymentAmount);
        Borrower(borrower).approve(DAI, loan, paymentAmount);
        Borrower(borrower).makePayment(loan);
    }

}
