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
import { D3MTrueFiV1Plan } from "./D3MTrueFiV1Plan.sol";

import {
    DaiLike,
    PortfolioFactoryLike,
    PortfolioLike,
    ERC20Like,
    WhitelistVerifierLike
} from "../tests/interfaces/interfaces.sol";

import { D3MTrueFiV1Plan } from "../plans/D3MTrueFiV1Plan.sol";
import { AddressRegistry }   from "../tests/integration/AddressRegistry.sol";
import { D3MPlanBaseTest, Hevm } from "./D3MPlanBase.t.sol";

contract D3MTrueFiV1PlanTest is AddressRegistry, D3MPlanBaseTest {
    PortfolioFactoryLike portfolioFactory;
    PortfolioLike portfolio;

    function setUp() public override {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));
        dai = DaiLike(DAI);

        _setUpTrueFiDaiPortfolio();

        d3mTestPlan = address(new D3MTrueFiV1Plan(address(portfolio)));
    }

    function test_sets_portfolio() public {
        assertEq(address(D3MTrueFiV1Plan(d3mTestPlan).portfolio()), address(portfolio));
    }

    function test_creator_as_ward() public {
        assertEq(D3MTrueFiV1Plan(d3mTestPlan).wards(address(this)), 1);
    }
    
    function test_can_file_cap() public {
        assertEq(D3MTrueFiV1Plan(d3mTestPlan).cap(), 0);

        D3MTrueFiV1Plan(d3mTestPlan).file("cap", 1);

        assertEq(D3MTrueFiV1Plan(d3mTestPlan).cap(), 1);
    }

    function testFail_cannot_file_unknown_uint_param() public {
        D3MTrueFiV1Plan(d3mTestPlan).file("bad", 1);
    }

    function testFail_cannot_file_without_auth() public {
        D3MTrueFiV1Plan(d3mTestPlan).deny(address(this));

        D3MTrueFiV1Plan(d3mTestPlan).file("bar", 1);
    }

    function test_is_active_while_portfolio_is_open() public {
        assertTrue(D3MTrueFiV1Plan(d3mTestPlan).active());
    }

    function test_is_inactive_while_portfolio_is_closed() public {
        hevm.warp(block.timestamp + 30 days + 1 seconds);
        assertTrue(!D3MTrueFiV1Plan(d3mTestPlan).active());
    }

    function test_is_inactive_while_portfolio_is_frozen() public {
        _mintDai(address(this), 2000 ether);
        dai.approve(address(portfolio), 2000 ether);
        portfolio.deposit(2000 ether, "0x");

        portfolio.createBulletLoan(1 days, address(this), 1000 ether, 1100 ether);
        uint256 loanId = portfolio.getOpenLoanIds()[0];
        hevm.warp(block.timestamp + 1 days + 1 seconds);
        portfolio.markLoanAsDefaulted(loanId);

        assertTrue(!D3MTrueFiV1Plan(d3mTestPlan).active());
    }

    /*****************************/
    /*** Overridden Base tests ***/
    /*****************************/

    function test_implements_getTargetAssets() public override {
        D3MTrueFiV1Plan(d3mTestPlan).file("cap", 1);
        uint256 result = D3MTrueFiV1Plan(d3mTestPlan).getTargetAssets(2);

        assertEq(result, 1);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _setUpTrueFiDaiPortfolio() internal {
        portfolioFactory = PortfolioFactoryLike(MANAGED_PORTFOLIO_FACTORY_PROXY);

                // Whitelist this address in managed portfolio factory so we can create portfolio
        hevm.store(MANAGED_PORTFOLIO_FACTORY_PROXY, keccak256(abi.encode(address(this), 6)), bytes32(uint256(1)));
        hevm.store(GLOBAL_WHITELIST_LENDER_VERIFIER, keccak256(abi.encode(address(this), 2)), bytes32(uint256(1)));

        portfolioFactory.createPortfolio("TrueFi-D3M-DAI", "TDD", ERC20Like(DAI), WhitelistVerifierLike(GLOBAL_WHITELIST_LENDER_VERIFIER), 30 days, 1_000_000 ether, 20);

        uint256 portfoliosCount = portfolioFactory.getPortfolios().length;
        portfolio = PortfolioLike(portfolioFactory.getPortfolios()[portfoliosCount - 1]);
    }

    function _mintDai(address account, uint256 amount) internal {
        uint256 slot = 2;

        hevm.store(
            address(dai),
            keccak256(abi.encode(account, slot)),
            bytes32(dai.balanceOf(address(account)) + amount)
        );
    }
}