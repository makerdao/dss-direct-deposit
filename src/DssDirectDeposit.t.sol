pragma solidity 0.6.12;

import "ds-test/test.sol";
import "dss-interfaces/Interfaces.sol";

import "./DssDirectDeposit.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external view returns (bytes32);
}

contract DssDirectDepositTest is DSTest {

    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    Hevm hevm;

    VatAbstract vat;
    LendingPoolLike pool;
    InterestRateStrategyLike interestStrategy;
    DaiAbstract dai;
    DaiJoinAbstract daiJoin;
    DSTokenAbstract adai;

    bytes32 constant ilk = "DD-DAI-A";
    DssDirectDeposit deposit;
    DSValue pip;

    // Allow for a 1 BPS margin of error on interest rates
    uint256 constant INTEREST_RATE_TOLERANCE = RAY / 10000;

    function setUp() public {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

        vat = VatAbstract(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        pool = LendingPoolLike(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        adai = DSTokenAbstract(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
        dai = DaiAbstract(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        daiJoin = DaiJoinAbstract(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
        interestStrategy = InterestRateStrategyLike(0xfffE32106A68aA3eD39CcCE673B646423EEaB62a);

        // Give this contract admin access on the vat
        hevm.store(
            address(vat),
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        assertEq(vat.wards(address(this)), 1);
        
        deposit = new DssDirectDeposit(address(vat), ilk, address(pool), address(adai), address(daiJoin));

        // Init new collateral
        pip = new DSValue();

        vat.rely(address(deposit));
        vat.init(ilk);
        vat.file(ilk, "line", 500_000_000 * RAD);
    }

    function assertEqInterest(uint256 a, uint256 b) internal {
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > INTEREST_RATE_TOLERANCE) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_decimal_uint("  Expected", b, 27);
            emit log_named_decimal_uint("    Actual", a, 27);
            fail();
        }
    }

    function getBorrowRate() public returns (uint256 borrowRate) {
        (,,,, borrowRate,,,,,,,) = pool.getReserveData(address(dai));
    }

    function test_target() public {
        uint256 currBorrowRate = getBorrowRate();

        // Reduce borrow rate by 25%
        uint256 targetBorrowRate = currBorrowRate * 75 / 100;

        deposit.file("bar", targetBorrowRate);

        deposit.exec();

        assertEqInterest(getBorrowRate(), targetBorrowRate);
    }
    
}
