pragma solidity 0.6.12;

import "ds-test/test.sol";
import "dss-interfaces/Interfaces.sol";

import "./DssDirectDeposit.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external view returns (bytes32);
}

interface LendingPoolLike {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function getReserveData(address asset) external view returns (
        uint256,    // Configuration
        uint128,    //the liquidity index. Expressed in ray
        uint128,    //variable borrow index. Expressed in ray
        uint128,    //the current supply rate. Expressed in ray
        uint128,    //the current variable borrow rate. Expressed in ray
        uint128,    //the current stable borrow rate. Expressed in ray
        uint40,
        address,
        address,
        address,
        address,    //address of the interest rate strategy
        uint8
    );
}

contract DssDirectDepositTest is DSTest {

    Hevm hevm;

    DssDirectDeposit deposit;
    LendingPoolLike pool;
    DaiAbstract dai;
    DSTokenAbstract adai;

    function setUp() public {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

        deposit = new DssDirectDeposit();
        pool = LendingPoolLike(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        adai = DSTokenAbstract(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
        dai = DaiAbstract(0x6B175474E89094C44Da98b954EedeAC495271d0F);

        // Mint ourselves 100B DAI
        giveTokens(DSTokenAbstract(address(dai)), 100_000_000_000 ether);

        dai.approve(address(pool), uint256(-1));
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

    function test_set_aave_interest_rate() public {
        (,,,, uint256 borrowRate,,,,,,,) = pool.getReserveData(address(dai));
        log_named_decimal_uint("origBorrowRate", borrowRate, 27);

        pool.deposit(address(dai), 1_000_000 ether, address(this), 0);

        (,,,, borrowRate,,,,,,,) = pool.getReserveData(address(dai));
        log_named_decimal_uint("newBorrowRate", borrowRate, 27);

        log_named_decimal_uint("adai", adai.balanceOf(address(this)), 18);

        assertTrue(false);
    }
    
}
