pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./DssDirectDeposit.sol";

contract DssDirectDepositTest is DSTest {
    DssDirectDeposit deposit;

    function setUp() public {
        deposit = new DssDirectDeposit();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
