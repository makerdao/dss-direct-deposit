pragma solidity 0.6.12;

import "ds-test/test.sol";
import "dss-interfaces/Interfaces.sol";
import "ds-value/value.sol";

import "./DssDirectDeposit.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external view returns (bytes32);
}

interface AuthLike {
    function wards(address) external returns (uint256);
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
    SpotAbstract spot;
    DSTokenAbstract weth;
    address vow;

    bytes32 constant ilk = "DD-DAI-A";
    DssDirectDeposit deposit;
    DSValue pip;

    // Allow for a 1 BPS margin of error on interest rates
    uint256 constant INTEREST_RATE_TOLERANCE = RAY / 10000;
    uint256 constant EPSILON_TOLERANCE = 4;

    function setUp() public {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

        vat = VatAbstract(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        pool = LendingPoolLike(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        adai = DSTokenAbstract(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
        dai = DaiAbstract(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        daiJoin = DaiJoinAbstract(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
        interestStrategy = InterestRateStrategyLike(0xfffE32106A68aA3eD39CcCE673B646423EEaB62a);
        spot = SpotAbstract(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);
        weth = DSTokenAbstract(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        vow = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;

        // Force give admin access to this contract via hevm magic
        giveAuthAccess(address(vat), address(this));
        giveAuthAccess(address(spot), address(this));
        
        deposit = new DssDirectDeposit(address(vat), ilk, address(pool), address(interestStrategy), address(adai), address(daiJoin), vow);

        // Init new collateral
        pip = new DSValue();
        pip.poke(bytes32(WAD));
        spot.file(ilk, "pip", address(pip));
        spot.file(ilk, "mat", RAY);
        spot.poke(ilk);

        vat.rely(address(deposit));
        vat.init(ilk);
        vat.file(ilk, "line", 500_000_000 * RAD);

        // Give us a bunch of WETH and deposit into Aave
        uint256 amt = 1_000_000 * WAD;
        giveTokens(weth, amt);
        weth.approve(address(pool), uint256(-1));
        dai.approve(address(pool), uint256(-1));
        pool.deposit(address(weth), amt, address(this), 0);
    }

    // --- Math ---
    function add(uint256 x, uint256 y) public pure returns (uint256 z) {
        require((z = x + y) >= x, "DssDirectDeposit/overflow");
    }
    function sub(uint256 x, uint256 y) public pure returns (uint256 z) {
        require((z = x - y) <= x, "DssDirectDeposit/underflow");
    }
    function mul(uint256 x, uint256 y) public pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "DssDirectDeposit/overflow");
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

    function getBorrowRate() public returns (uint256 borrowRate) {
        (,,,, borrowRate,,,,,,,) = pool.getReserveData(address(dai));
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
        uint256 currBorrowRate = getBorrowRate();

        // Reduce borrow rate by 25%
        uint256 targetBorrowRate = currBorrowRate * 75 / 100;

        deposit.file("bar", targetBorrowRate);
        deposit.exec();
        deposit.reap();     // Clear out interest to get rid of rounding errors
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        uint256 amountMinted = adai.balanceOf(address(deposit));
        assertTrue(amountMinted > 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertTrue(ink <= amountMinted);
        assertTrue(art <= amountMinted);
        assertEq(vat.gem(ilk, address(deposit)), 0);
        assertEq(vat.dai(address(deposit)), 0);
    }

    function test_target_increase() public {
        // Lower by 50%
        uint256 targetBorrowRate = getBorrowRate() * 50 / 100;
        deposit.file("bar", targetBorrowRate);
        deposit.exec();
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        // Raise by 25%
        targetBorrowRate = getBorrowRate() * 125 / 100;
        deposit.file("bar", targetBorrowRate);
        deposit.exec();
        assertEqInterest(getBorrowRate(), targetBorrowRate);

        uint256 amountMinted = adai.balanceOf(address(deposit));
        assertTrue(amountMinted > 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertTrue(ink <= amountMinted);
        assertTrue(art <= amountMinted);
        assertEq(vat.gem(ilk, address(deposit)), 0);
        assertEq(vat.dai(address(deposit)), 0);
    }

    function test_target_increase_insufficient_liquidity() public {
        uint256 currBorrowRate = getBorrowRate();

        // Attempt to increase by 25% (you can't)
        uint256 targetBorrowRate = currBorrowRate * 125 / 100;

        deposit.file("bar", targetBorrowRate);
        deposit.exec();
        assertEqInterest(getBorrowRate(), currBorrowRate);  // Unchanged

        assertEq(adai.balanceOf(address(deposit)), 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.gem(ilk, address(deposit)), 0);
        assertEq(vat.dai(address(deposit)), 0);
    }

    function test_cage_insufficient_liquidity() public {
        uint256 currentLiquidity = dai.balanceOf(address(adai));

        // Lower by 50%
        uint256 targetBorrowRate = getBorrowRate() * 50 / 100;
        deposit.file("bar", targetBorrowRate);
        deposit.exec();
        assertEqInterest(getBorrowRate(), targetBorrowRate);
        
        // Someone else borrows
        uint256 amountSupplied = adai.balanceOf(address(deposit));
        uint256 amountToBorrow = currentLiquidity + amountSupplied / 2;
        pool.borrow(address(dai), amountToBorrow, 2, 0, address(this));

        // Cage the system and start unwinding
        currentLiquidity = dai.balanceOf(address(adai));
        (uint256 pink, uint256 part) = vat.urns(ilk, address(deposit));
        deposit.cage();
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

    function test_hit_debt_ceiling() public {
        // Lower the debt ceiling to 100k
        uint256 debtCeiling = 100_000 * WAD;
        vat.file(ilk, "line", debtCeiling * RAY);

        uint256 currBorrowRate = getBorrowRate();

        // Set a super low target interest rate
        uint256 targetBorrowRate = currBorrowRate * 1 / 100;

        deposit.file("bar", targetBorrowRate);
        deposit.exec();
        deposit.reap();
        (uint256 ink, uint256 art) = vat.urns(ilk, address(deposit));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertTrue(getBorrowRate() > targetBorrowRate && getBorrowRate() < currBorrowRate);
        assertEq(adai.balanceOf(address(deposit)), debtCeiling);

        // Should be a no-op
        deposit.exec();

        // Raise it by a bit
        debtCeiling = 125_000 * WAD;
        vat.file(ilk, "line", debtCeiling * RAY);
        deposit.exec();
        deposit.reap();
        (ink, art) = vat.urns(ilk, address(deposit));
        assertEq(ink, debtCeiling);
        assertEq(art, debtCeiling);
        assertTrue(getBorrowRate() > targetBorrowRate && getBorrowRate() < currBorrowRate);
        assertEq(adai.balanceOf(address(deposit)), debtCeiling);
    }

    function test_collect_interest() public {
        uint256 targetBorrowRate = getBorrowRate() * 75 / 100;
        deposit.file("bar", targetBorrowRate);
        deposit.exec();

        hevm.warp(block.timestamp + 1 days);     // Collect one day of interest

        uint256 vowDai = vat.dai(vow);
        deposit.reap();

        log_named_decimal_uint("dai", vat.dai(vow) - vowDai, 18);

        assertTrue(vat.dai(vow) - vowDai > 0);
    }
    
}
