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
    LenderVerifierLike,
    VatLike,
    TokenLike
} from "../tests/interfaces/interfaces.sol";

import { D3MTrueFiV1Plan } from "../plans/D3MTrueFiV1Plan.sol";
import { AddressRegistry }   from "../tests/integration/AddressRegistry.sol";
import { D3MPoolBaseTest, Hevm } from "./D3MPoolBase.t.sol";

contract FakeLenderVerifier is LenderVerifierLike {
    function isAllowed(
        address lender,
        uint256 amount,
        bytes memory signature
    ) external view returns (bool) {
        return true;
    }

    function setLenderWhitelistStatus(
        address portfolio,
        address lender,
        bool status
    ) external {}
}

contract D3MTrueFiV1PoolTest is AddressRegistry, D3MPoolBaseTest {
    PortfolioFactoryLike portfolioFactory;
    PortfolioLike portfolio;

    function setUp() public override {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

        dai = DaiLike(DAI);
        vat = VAT;
        hub = address(new D3MHub(vat, DAI_JOIN));

        _setUpTrueFiDaiPortfolio();

        d3mTestPool = address(new D3MTrueFiV1Pool(address(dai), address(portfolio), hub));
    }

    function test_deposit_transfers_funds() public {
        uint256 fundsBefore = dai.balanceOf(address(this));
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);
        uint256 fundsAfter = dai.balanceOf(address(this));

        assertEq(uint256(PortfolioLike(portfolio).value()), 1 ether);
        assertEq(fundsAfter, fundsBefore - 1 ether);
    }

    function test_deposit_issues_lp_tokens() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);
        assertEq(uint256(ERC20Like(portfolio).balanceOf(address(this))), 1 ether);
    }

    function test_withdraw_returns_funds() public {
        D3MTrueFiV1Pool(d3mTestPool).deposit(1 ether);

        uint256 fundsBefore = dai.balanceOf(address(this));
        D3MTrueFiV1Pool(d3mTestPool).withdraw(1 ether);
        uint256 fundsAfter = dai.balanceOf(address(this));

        assertEq(fundsAfter, fundsBefore + 1 ether);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _setUpTrueFiDaiPortfolio() internal {
        portfolioFactory = PortfolioFactoryLike(MANAGED_PORTFOLIO_FACTORY_PROXY);

        // Grant address(this) auth access to factory
        hevm.store(MANAGED_PORTFOLIO_FACTORY_PROXY, bytes32(uint256(0)), bytes32(uint256(uint160(address(this)))));
        portfolioFactory.setIsWhitelisted(address(this), true);

        LenderVerifierLike fakeLenderVerifier = new FakeLenderVerifier();
        portfolioFactory.createPortfolio("TrueFi-D3M-DAI", "TDD", ERC20Like(DAI), fakeLenderVerifier, 60 * 60 * 24 * 30, 1_000_000 ether, 20);
        uint256 portfoliosCount = portfolioFactory.getPortfolios().length;
        portfolio = PortfolioLike(portfolioFactory.getPortfolios()[portfoliosCount - 1]);

        // LenderVerifierLike(WHITELIST_LENDER_VERIFIER).setLenderWhitelistStatus(address(portfolio), address(this), true);
        _mintTokens(DAI, address(this), 100 ether);
    }

    function _mintTokens(address token, address account, uint256 amount) internal {
        uint256 slot;

        if      (token == DAI)  slot = 2;

        hevm.store(
            token,
            keccak256(abi.encode(account, slot)),
            bytes32(TokenLike(token).balanceOf(address(account)) + amount)
        );
    }
}