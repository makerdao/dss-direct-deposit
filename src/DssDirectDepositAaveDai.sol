pragma solidity 0.6.12;

import "dss-interfaces/ERC/GemAbstract.sol";
import "dss-interfaces/dss/DaiAbstract.sol";
import "dss-interfaces/dss/DaiJoinAbstract.sol";
import "dss-interfaces/dss/VatAbstract.sol";

interface LendingPoolLike {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external;
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external;
    function getReserveData(address asset) external view returns (
        uint256,    // Configuration
        uint128,    // the liquidity index. Expressed in ray
        uint128,    // variable borrow index. Expressed in ray
        uint128,    // the current supply rate. Expressed in ray
        uint128,    // the current variable borrow rate. Expressed in ray
        uint128,    // the current stable borrow rate. Expressed in ray
        uint40,
        address,
        address,
        address,
        address,    // address of the interest rate strategy
        uint8
    );
}

interface InterestRateStrategyLike {
    function OPTIMAL_UTILIZATION_RATE() external view returns (uint256);
    function EXCESS_UTILIZATION_RATE() external view returns (uint256);
    function variableRateSlope1() external view returns (uint256);
    function variableRateSlope2() external view returns (uint256);
    function baseVariableBorrowRate() external view returns (uint256);
    function getMaxVariableBorrowRate() external view returns (uint256);
    function calculateInterestRates(
        address reserve,
        uint256 availableLiquidity,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 averageStableBorrowRate,
        uint256 reserveFactor
    ) external returns (
        uint256,
        uint256,
        uint256
    );
}

interface ATokenLike is GemAbstract {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

contract DssDirectDepositAaveDai {

    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external auth {
        wards[usr] = 1;

        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;

        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "DssDirectDepositAaveDai/not-authorized");
        _;
    }

    VatAbstract public immutable vat;
    bytes32 public immutable ilk;
    LendingPoolLike public immutable pool;
    InterestRateStrategyLike public immutable interestStrategy;
    ATokenLike public immutable adai;
    DaiAbstract public immutable dai;
    DaiJoinAbstract public immutable daiJoin;
    address public immutable vow;
    uint256 public immutable tau;

    uint256 public bar;         // Target Interest Rate [ray]
    bool public live = true;
    bool public culled;
    uint256 public tic;         // Time until you can write off the debt [sec]

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event Wind(uint256 amount);
    event Unwind(uint256 amount);
    event Reap();
    event Cage();
    event Cull();

    constructor(address vat_, bytes32 ilk_, address pool_, address interestStrategy_, address adai_, address daiJoin_, address vow_, uint256 tau_) public {
        // Sanity checks
        (,,,,,,,,,, address strategy,) = LendingPoolLike(pool_).getReserveData(ATokenLike(adai_).UNDERLYING_ASSET_ADDRESS());
        require(strategy != address(0), "DssDirectDepositAaveDai/invalid-atoken");
        require(interestStrategy_ == strategy, "DssDirectDepositAaveDai/interest-strategy-doesnt-match");
        require(ATokenLike(adai_).UNDERLYING_ASSET_ADDRESS() == DaiJoinAbstract(daiJoin_).dai(), "DssDirectDepositAaveDai/must-be-dai");

        vat = VatAbstract(vat_);
        ilk = ilk_;
        pool = LendingPoolLike(pool_);
        adai = ATokenLike(adai_);
        daiJoin = DaiJoinAbstract(daiJoin_);
        interestStrategy = InterestRateStrategyLike(interestStrategy_);
        dai = DaiAbstract(DaiJoinAbstract(daiJoin_).dai());
        vow = vow_;
        tau = tau_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        // Auths
        VatAbstract(vat_).hope(daiJoin_);
        DaiAbstract(DaiJoinAbstract(daiJoin_).dai()).approve(pool_, uint256(-1));
        DaiAbstract(DaiJoinAbstract(daiJoin_).dai()).approve(daiJoin_, uint256(-1));
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
    uint256 constant RAY  = 10 ** 27;
    function rmul(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = mul(x, y) / RAY;
    }
    function rdiv(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = mul(x, RAY) / y;
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external auth {
        require(live, "DssDirectDepositAaveDai/not-live");

        if (what == "bar") {
            require(data > 0, "DssDirectDepositAaveDai/target-interest-zero");
            require(data <= interestStrategy.getMaxVariableBorrowRate(), "DssDirectDepositAaveDai/above-max-interest");

            bar = data;
        } else revert("DssDirectDepositAaveDai/file-unrecognized-param");

        emit File(what, data);
    }

    // --- Deposit controls ---
    function wind(uint256 amount) external auth {
        require(live, "DssDirectDepositAaveDai/not-live");

        _wind(amount);
    }
    function _wind(uint256 amount) internal {
        require(int256(amount) >= 0, "DssDirectDepositAaveDai/overflow");

        vat.slip(ilk, address(this), int256(amount));
        vat.frob(ilk, address(this), address(this), address(this), int256(amount), int256(amount));
        daiJoin.exit(address(this), amount);
        pool.deposit(address(dai), amount, address(this), 0);

        emit Wind(amount);
    }

    function unwind(uint256 amount) external {
        require(wards[msg.sender] == 1 || !live, "DssDirectDepositAaveDai/not-authorized");

        _unwind(amount);
    }
    function _unwind(uint256 amount) internal {
        require(amount <= 2 ** 255, "DssDirectDepositAaveDai/overflow");
        
        // To save gas bring the fees back with the unwind amount
        uint256 adaiBalance = adai.balanceOf(address(this));
        (, uint256 daiDebt) = vat.urns(ilk, address(this));
        if (culled) daiDebt = vat.gem(ilk, address(this));
        uint256 fees = 0;
        if (adaiBalance > daiDebt) {
            fees = adaiBalance - daiDebt;
        }
        uint256 total = add(amount, fees);
        pool.withdraw(address(dai), total, address(this));
        daiJoin.join(address(this), total);
        if (!culled) {
            vat.frob(ilk, address(this), address(this), address(this), -int256(amount), -int256(amount));
        }
        vat.slip(ilk, address(this), -int256(amount));
        vat.move(address(this), vow, mul(culled ? total : fees, RAY));

        emit Unwind(amount);
    }

    // --- Automated Rate Targetting ---
    function calculateTargetSupply(uint256 targetInterestRate) public returns (uint256) {
        require(targetInterestRate > 0, "DssDirectDepositAaveDai/target-interest-zero");
        require(targetInterestRate <= interestStrategy.getMaxVariableBorrowRate(), "DssDirectDepositAaveDai/above-max-interest");

        // Do inverse calculation of interestStrategy
        uint256 supplyAmount = adai.totalSupply();
        uint256 borrowAmount = sub(supplyAmount, dai.balanceOf(address(adai)));
        uint256 targetUtil;
        if (targetInterestRate > interestStrategy.variableRateSlope1()) {
            // Excess interest rate
            uint256 r = targetInterestRate - interestStrategy.baseVariableBorrowRate() - interestStrategy.variableRateSlope1();
            targetUtil = add(rdiv(rmul(interestStrategy.EXCESS_UTILIZATION_RATE(), r), interestStrategy.variableRateSlope2()), interestStrategy.OPTIMAL_UTILIZATION_RATE());
        } else {
            // Optimal interst rate
            targetUtil = rdiv(rmul(sub(targetInterestRate, interestStrategy.baseVariableBorrowRate()), interestStrategy.OPTIMAL_UTILIZATION_RATE()), interestStrategy.variableRateSlope1());
        }
        return rdiv(borrowAmount, targetUtil);
    }
    function exec() external {
        require(bar > 0, "DssDirectDepositAaveDai/bar-not-set");

        uint256 supplyAmount = adai.totalSupply();
        uint256 targetSupply = calculateTargetSupply(bar);
        if (!live) targetSupply = 0;    // Unwind only when caged

        if (targetSupply > supplyAmount) {
            uint256 windTargetAmount = targetSupply - supplyAmount;

            // Wind amount is limited by the debt ceiling
            (uint256 Art,,, uint256 line,) = vat.ilks(ilk);
            uint256 lineWad = line / RAY;      // Round down to always be under the actual limit
            uint256 newDebt = add(Art, windTargetAmount);
            if (newDebt > lineWad) windTargetAmount = sub(lineWad, Art);

            if (windTargetAmount > 0) _wind(windTargetAmount);
        } else if (targetSupply < supplyAmount) {
            uint256 unwindTargetAmount = supplyAmount - targetSupply;

            // Unwind amount is limited by how much adai we have
            uint256 adaiBalance = adai.balanceOf(address(this));
            if (adaiBalance < unwindTargetAmount) unwindTargetAmount = adaiBalance;

            // Unwind amount is limited by how much debt there is
            (uint256 ink,) = vat.urns(ilk, address(this));
            if (culled) ink = vat.gem(ilk, address(this));
            if (ink < unwindTargetAmount) unwindTargetAmount = ink;

            // Unwind amount is limited by available liquidity in the pool
            uint256 availableLiquidity = dai.balanceOf(address(adai));
            if (availableLiquidity < unwindTargetAmount) unwindTargetAmount = availableLiquidity;

            if (unwindTargetAmount > 0) _unwind(unwindTargetAmount);
        }
    }

    // --- Collect Interest ---
    function reap() external {
        uint256 adaiBalance = adai.balanceOf(address(this));
        (, uint256 daiDebt) = vat.urns(ilk, address(this));
        if (adaiBalance > daiDebt) {
            uint256 fees = adaiBalance - daiDebt;
            pool.withdraw(address(dai), fees, address(this));
            daiJoin.join(address(this), fees);
            vat.move(address(this), vow, mul(fees, RAY));
        }
    }

    // --- Shutdown ---
    function cage() external {
        // Can shut this down if we are authed, if the vat was caged
        // or if the interest rate strategy changes
        (,,,,,,,,,, address strategy,) = pool.getReserveData(address(dai));
        require(
            wards[msg.sender] == 1 ||
            vat.live() == 0 ||
            strategy != address(interestStrategy)
        , "DssDirectDepositAaveDai/not-authorized");

        live = false;
        tic = block.timestamp;
        emit Cage();
    }

    // --- Write-off ---
    function cull() external {
        require(!live, "DssDirectDepositAaveDai/live");
        require(add(tic, tau) <= block.timestamp, "DssDirectDepositAaveDai/early-cull");
        require(!culled, "DssDirectDepositAaveDai/already-culled");

        (uint256 ink, uint256 art) = vat.urns(ilk, address(this));
        require(ink <= 2 ** 255, "DssDirectDepositAaveDai/overflow");
        require(art <= 2 ** 255, "DssDirectDepositAaveDai/overflow");
        vat.grab(ilk, address(this), address(this), address(vow), -int256(ink), -int256(art));
        culled = true;
        emit Cull();
    }

}
