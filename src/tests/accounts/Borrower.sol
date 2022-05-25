// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.12;

import { ERC20Like, LoanFactoryLike, LoanLike } from "../interfaces/interfaces.sol";

contract Borrower {

    function makePayment(address loan) external {
        LoanLike(loan).makePayment();
    }

    function drawdown(address loan, uint256 drawdownAmount) external {
        LoanLike(loan).drawdown(drawdownAmount);
    }

    function approve(address token, address account, uint256 amt) external {
        ERC20Like(token).approve(account, amt);
    }

    function createLoan(
        address loanFactory,
        address liquidityAsset,
        address collateralAsset,
        address flFactory,
        address clFactory,
        uint256[5] memory specs,
        address[3] memory calcs
    )
        external returns (address loan)
    {
        return LoanFactoryLike(loanFactory).createLoan(liquidityAsset, collateralAsset, flFactory, clFactory, specs, calcs);
    }

}
