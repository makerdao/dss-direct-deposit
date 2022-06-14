// SPDX-FileCopyrightText: © 2021-2022 Dai Foundation <www.daifoundation.org>
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

pragma solidity ^0.8.14;

import { D3MHub } from "../D3MHub.sol";
import { D3MMom } from "../D3MMom.sol";
import { D3MTrueFiV1Pool } from "./D3MTrueFiV1Pool.sol";

import {
    DaiLike,
    PortfolioFactoryLike,
    PortfolioLike,
    ERC20Like,
    VatLike,
    TokenLike,
    WhitelistVerifierLike
} from "../tests/interfaces/interfaces.sol";

import { D3MTrueFiV1Plan } from "../plans/D3MTrueFiV1Plan.sol";
import { AddressRegistry }   from "../tests/integration/AddressRegistry.sol";
import { D3MPoolBaseTest, Hevm } from "./D3MPoolBase.t.sol";

contract D3MTrueFiV1PoolTest is AddressRegistry, D3MPoolBaseTest {
    PortfolioFactoryLike portfolioFactory;
    PortfolioLike portfolio;
    address constant BORROWER = 0x4E02FBA7b1ad4E54F6e5Edd8Fee6D7e67E4a214a; // random address

    function setUp() public override {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

        dai = DaiLike(DAI);
        vat = VAT;
        hub = address(new D3MHub(vat, DAI_JOIN));

        _setUpTrueFiDaiPortfolio();

        d3mTestPool = address(new D3MTrueFiV1Pool(address(dai), address(portfolio), hub));
        // set address of d3mTestPool to true in whitelist mapping in global whitelist lender verifier
        hevm.store(GLOBAL_WHITELIST_LENDER_VERIFIER, keccak256(abi.encode(d3mTestPool, 2)), bytes32(uint256(1)));
        _mintTokens(DAI, address(d3mTestPool), 5 ether);

        // set address of second lender to true in whitelist mapping in global whitelist lender verifier
        hevm.store(GLOBAL_WHITELIST_LENDER_VERIFIER, keccak256(abi.encode(this, 2)), bytes32(uint256(1)));
        _mintTokens(DAI, address(this), 10 ether);
        dai.approve(address(portfolio), 10 ether);
    }

    function test_deposit_transfers_funds() public {
        uint256 fundsBefore = dai.balanceOf(d3mTestPool);
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);
        uint256 fundsAfter = dai.balanceOf(d3mTestPool);

        assertEq(portfolio.value(), 1 ether);
        assertEq(fundsAfter, fundsBefore - 1 ether);
    }

    function test_deposit_issues_shares() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);
        assertEq(uint256(ERC20Like(portfolio).balanceOf(d3mTestPool)), 1 ether);
    }

    function testFail_deposit_requires_auth() public {
        D3MTrueFiV1Pool(d3mTestPool).deny(address(this));

        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);
    }

    function test_max_deposit_equals_max_size() public {
        assertEq(D3MTrueFiV1Pool(d3mTestPool).maxDeposit(), portfolio.maxSize());
    }

    function test_max_desposit_equals_value_minus_deposited_funds() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);
        assertEq(D3MTrueFiV1Pool(d3mTestPool).maxDeposit(), portfolio.maxSize() - 1 ether);
    }

    function test_withdraw_returns_funds() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);

        uint256 fundsBefore = dai.balanceOf(d3mTestPool);
        hevm.warp(block.timestamp + 30 days + 1 days);
        D3MTrueFiV1Pool(d3mTestPool).withdraw(1 ether);
        uint256 fundsAfter = dai.balanceOf(d3mTestPool);

        assertEq(fundsAfter, fundsBefore + 1 ether);
    }

    function test_withdraw_burns_shares() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);

        hevm.warp(block.timestamp + 30 days + 1 days);
        D3MTrueFiV1Pool(d3mTestPool).withdraw(1 ether);

        assertEq(ERC20Like(portfolio).balanceOf(d3mTestPool), 0);
    }

    function testFail_withdraw_requires_auth() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);

        D3MTrueFiV1Pool(d3mTestPool).deny(address(this));
        D3MTrueFiV1Pool(d3mTestPool).withdraw(1 ether);
    }

    function test_max_withdraw_is_0_when_portfolio_not_closed() public {
        assertEq(D3MTrueFiV1Pool(d3mTestPool).maxWithdraw(), 0);
    }

    function test_max_withdraw_is_asset_balance() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);

        hevm.warp(block.timestamp + 30 days + 1 days);
        assertEq(D3MTrueFiV1Pool(d3mTestPool).maxWithdraw(), 1 ether);
    }

    function test_max_withdraw_is_liquid_value() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(2 ether);

        portfolio.createBulletLoan(30 days, BORROWER, 1 ether, 2 ether);
        hevm.warp(block.timestamp + 30 days + 1 days);
        assertEq(D3MTrueFiV1Pool(d3mTestPool).maxWithdraw(), portfolio.liquidValue());
    }

    function test_active_returns_true() public {
        assertTrue(D3MTrueFiV1Pool(d3mTestPool).active());
    }

    function testFail_recoverTokens_requires_auth() public {
        D3MTrueFiV1Pool(d3mTestPool).deny(address(this));
        D3MTrueFiV1Pool(d3mTestPool).recoverTokens(address(dai), address(this), 1 ether);
    }

    function test_recovers_tokens() public {
        ERC20Like wbtc = ERC20Like(WBTC);
        _mintTokens(address(wbtc), d3mTestPool, 1 ether);
        assertEq(wbtc.balanceOf(d3mTestPool), 1 ether);

        D3MTrueFiV1Pool(d3mTestPool).recoverTokens(address(wbtc), address(this), 1 ether);
        assertEq(wbtc.balanceOf(d3mTestPool), 0);
        assertEq(wbtc.balanceOf(address(this)), 1 ether);
    }

    function testFail_cannot_transfer_shares() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);
        D3MTrueFiV1Pool(d3mTestPool).transfer(BORROWER, 1 ether);
    }

    function testFail_cannot_transfer_all_shares() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);
        D3MTrueFiV1Pool(d3mTestPool).transferAll(BORROWER);
    }
    
    function test_asset_balance_initially_zero() public {
        assertEq(D3MTrueFiV1Pool(d3mTestPool).assetBalance(), 0);
    }

    function test_asset_balance_is_correct_with_1_lender() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(2 ether);
        assertEq(D3MTrueFiV1Pool(d3mTestPool).assetBalance(), 2 ether);
    }

    function test_asset_balance_is_correct_with_2_lender() public {
        portfolio.deposit(6 ether, "0x");
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);
        assertEq(D3MTrueFiV1Pool(d3mTestPool).assetBalance(), 1 ether);
    }

    function test_asset_balance_is_0_when_someone_else_deposited() public {
        portfolio.deposit(6 ether, "0x");
        assertEq(D3MTrueFiV1Pool(d3mTestPool).assetBalance(), 0);
    }

    function test_asset_balance_is_correct_after_withdraw() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(3 ether);

        hevm.warp(block.timestamp + 40 days);
        
        D3MTrueFiV1Pool(d3mTestPool).withdraw(1 ether);
        assertEq(D3MTrueFiV1Pool(d3mTestPool).assetBalance(), 2 ether);
    }

    function test_asset_balance_is_correct_after_multiple_deposits() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);
        D3MTrueFiV1Pool(d3mTestPool).deposit(2 ether);
        assertEq(D3MTrueFiV1Pool(d3mTestPool).assetBalance(), 4 ether);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _setUpTrueFiDaiPortfolio() internal {
        portfolioFactory = PortfolioFactoryLike(MANAGED_PORTFOLIO_FACTORY_PROXY);

        // Whitelist this address in managed portfolio factory so we can create portfolio
        hevm.store(MANAGED_PORTFOLIO_FACTORY_PROXY, keccak256(abi.encode(address(this), 6)), bytes32(uint256(1)));

        portfolioFactory.createPortfolio("TrueFi-D3M-DAI", "TDD", ERC20Like(DAI), WhitelistVerifierLike(GLOBAL_WHITELIST_LENDER_VERIFIER), 30 days, 1_000_000 ether, 20);
        
        uint256 portfoliosCount = portfolioFactory.getPortfolios().length;
        portfolio = PortfolioLike(portfolioFactory.getPortfolios()[portfoliosCount - 1]);
    }

    function _mintTokens(address token, address account, uint256 amount) internal {
        uint256 slot;

        if      (token == DAI)  slot = 2;
        else if (token == WBTC) slot = 0;

        hevm.store(
            token,
            keccak256(abi.encode(account, slot)),
            bytes32(ERC20Like(token).balanceOf(address(account)) + amount)
        );
    }
}