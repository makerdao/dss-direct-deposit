// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
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

interface TokenLike {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface DaiJoinLike {
    function wards(address) external view returns (uint256);
    function rely(address usr) external;
    function deny(address usr) external;
    function vat() external view returns (address);
    function dai() external view returns (address);
    function live() external view returns (uint256);
    function cage() external;
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

interface VatLike {
    function hope(address) external;
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
    function gem(bytes32, address) external view returns (uint256);
    function live() external view returns (uint256);
    function slip(bytes32, address, int256) external;
    function move(address, address, uint256) external;
    function frob(bytes32, address, address, address, int256, int256) external;
    function grab(bytes32, address, address, address, int256, int256) external;
}

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

interface ATokenLike is TokenLike {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

interface RewardsClaimerLike {
    function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);
    function getRewardsBalance(address[] calldata assets, address user) external view returns (uint256);
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

    ChainlogLike public immutable chainlog;
    VatLike public immutable vat;
    bytes32 public immutable ilk;
    LendingPoolLike public immutable pool;
    InterestRateStrategyLike public immutable interestStrategy;
    RewardsClaimerLike public immutable rewardsClaimer;
    ATokenLike public immutable adai;
    TokenLike public immutable dai;
    DaiJoinLike public immutable daiJoin;
    uint256 public immutable tau;

    uint256 public bar;         // Target Interest Rate [ray]
    uint256 public live = 1;
    uint256 public culled;
    uint256 public tic;         // Time until you can write off the debt [sec]
    address public king;        // Who gets the rewards

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, uint256 data);
    event Wind(uint256 amount);
    event Unwind(uint256 amount);
    event Reap();
    event Cage();
    event Cull();

    constructor(address chainlog_, bytes32 ilk_, address pool_, address interestStrategy_, address adai_, address _rewardsClaimer, uint256 tau_) public {
        address vat_ = ChainlogLike(chainlog_).getAddress("MCD_VAT");
        address daiJoin_ = ChainlogLike(chainlog_).getAddress("MCD_JOIN_DAI");

        // Sanity checks
        (,,,,,,,,,, address strategy,) = LendingPoolLike(pool_).getReserveData(ATokenLike(adai_).UNDERLYING_ASSET_ADDRESS());
        require(strategy != address(0), "DssDirectDepositAaveDai/invalid-atoken");
        require(interestStrategy_ == strategy, "DssDirectDepositAaveDai/interest-strategy-doesnt-match");
        require(ATokenLike(adai_).UNDERLYING_ASSET_ADDRESS() == DaiJoinLike(daiJoin_).dai(), "DssDirectDepositAaveDai/must-be-dai");

        chainlog = ChainlogLike(chainlog_);
        vat = VatLike(vat_);
        ilk = ilk_;
        pool = LendingPoolLike(pool_);
        adai = ATokenLike(adai_);
        daiJoin = DaiJoinLike(daiJoin_);
        interestStrategy = InterestRateStrategyLike(interestStrategy_);
        rewardsClaimer = RewardsClaimerLike(_rewardsClaimer);
        TokenLike dai_ = dai = TokenLike(DaiJoinLike(daiJoin_).dai());
        tau = tau_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        // Auths
        VatLike(vat_).hope(daiJoin_);
        dai_.approve(pool_, uint256(-1));
        dai_.approve(daiJoin_, uint256(-1));
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
        require(live == 1, "DssDirectDepositAaveDai/not-live");

        if (what == "bar") {
            require(data > 0, "DssDirectDepositAaveDai/target-interest-zero");
            require(data <= interestStrategy.getMaxVariableBorrowRate(), "DssDirectDepositAaveDai/above-max-interest");

            bar = data;
        } else revert("DssDirectDepositAaveDai/file-unrecognized-param");

        emit File(what, data);
    }
    function file(bytes32 what, address data) external auth {
        if (what == "king") king = data;
        else revert("DssDirectDepositAaveDai/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Deposit controls ---
    function wind(uint256 amount) external auth {
        require(live == 1, "DssDirectDepositAaveDai/not-live");

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

    function unwind(uint256 amount, uint256 fees) external {
        require(wards[msg.sender] == 1 || live == 0, "DssDirectDepositAaveDai/not-authorized");

        _unwind(amount, fees);
    }
    function _unwind(uint256 amount, uint256 fees) internal {
        require(amount <= 2 ** 255, "DssDirectDepositAaveDai/overflow");

        // To save gas you can bring the fees back with the unwind
        uint256 total = add(amount, fees);
        pool.withdraw(address(dai), total, address(this));
        daiJoin.join(address(this), total);
        if (culled == 0) {
            vat.frob(ilk, address(this), address(this), address(this), -int256(amount), -int256(amount));
        }
        vat.slip(ilk, address(this), -int256(amount));
        vat.move(address(this), chainlog.getAddress("MCD_VOW"), mul(culled == 1 ? total : fees, RAY));

        emit Unwind(amount);
    }

    // --- Automated Rate Targetting ---
    function calculateTargetSupply(uint256 targetInterestRate) public view returns (uint256) {
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
        if (live == 0) targetSupply = 0;    // Unwind only when caged

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

            // Unwind amount is limited by how much adai we have to withdraw
            uint256 adaiBalance = adai.balanceOf(address(this));
            if (adaiBalance < unwindTargetAmount) unwindTargetAmount = adaiBalance;

            // Unwind amount is limited by how much debt there is
            (uint256 daiDebt,) = vat.urns(ilk, address(this));
            if (culled == 1) daiDebt = vat.gem(ilk, address(this));
            if (daiDebt < unwindTargetAmount) unwindTargetAmount = daiDebt;

            // Unwind amount is limited by available liquidity in the pool
            uint256 availableLiquidity = dai.balanceOf(address(adai));
            if (availableLiquidity < unwindTargetAmount) unwindTargetAmount = availableLiquidity;
            
            // Determine the amount of fees to bring back
            uint256 fees = 0;
            if (adaiBalance > daiDebt) {
                fees = adaiBalance - daiDebt;

                if (add(unwindTargetAmount, fees) > availableLiquidity) {
                    // Don't need safe-math because this is constrained above
                    fees = availableLiquidity - unwindTargetAmount;
                }
            }

            if (unwindTargetAmount > 0 || fees > 0) _unwind(unwindTargetAmount, fees);
        }
    }

    // --- Collect Interest ---
    function reap() external {
        uint256 adaiBalance = adai.balanceOf(address(this));
        (, uint256 daiDebt) = vat.urns(ilk, address(this));
        if (adaiBalance > daiDebt) {
            uint256 fees = adaiBalance - daiDebt;
            uint256 availableLiquidity = dai.balanceOf(address(adai));
            if (fees > availableLiquidity) {
                fees = availableLiquidity;
            }
            pool.withdraw(address(dai), fees, address(this));
            daiJoin.join(address(this), fees);
            vat.move(address(this), chainlog.getAddress("MCD_VOW"), mul(fees, RAY));
        }
    }

    // --- Collect any rewards ---
    function collect(address[] memory assets, uint256 amount) external returns (uint256) {
        require(king != address(0), "DssDirectDepositAaveDai/king-not-set");

        return rewardsClaimer.claimRewards(assets, amount, king);
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

        live = 0;
        tic = block.timestamp;
        emit Cage();
    }

    // --- Write-off ---
    function cull() external {
        require(live == 0, "DssDirectDepositAaveDai/live");
        require(add(tic, tau) <= block.timestamp, "DssDirectDepositAaveDai/early-cull");
        require(culled == 0, "DssDirectDepositAaveDai/already-culled");

        (uint256 ink, uint256 art) = vat.urns(ilk, address(this));
        require(ink <= 2 ** 255, "DssDirectDepositAaveDai/overflow");
        require(art <= 2 ** 255, "DssDirectDepositAaveDai/overflow");
        vat.grab(ilk, address(this), address(this), address(chainlog.getAddress("MCD_VOW")), -int256(ink), -int256(art));
        culled = 1;
        emit Cull();
    }

}
