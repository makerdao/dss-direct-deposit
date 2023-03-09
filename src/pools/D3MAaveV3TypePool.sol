// SPDX-FileCopyrightText: © 2021 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
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

import "./ID3MPool.sol";

interface TokenLike {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function decimals() external view returns (uint8);
}

interface VatLike {
    function live() external view returns (uint256);
    function hope(address) external;
    function nope(address) external;
}

interface D3mHubLike {
    function vat() external view returns (address);
    function end() external view returns (EndLike);
}

interface EndLike {
    function Art(bytes32) external view returns (uint256);
}

interface ATokenLike is TokenLike {
    function scaledBalanceOf(address) external view returns (uint256);
    function scaledTotalSupply() external view returns (uint256);
    function getIncentivesController() external view returns (address);
}

interface PoolLike {

    // Need to use a struct as too many variables to return on the stack
    struct ReserveData {
        //stores the reserve configuration
        uint256 configuration;
        //the liquidity index. Expressed in ray
        uint128 liquidityIndex;
        //the current supply rate. Expressed in ray
        uint128 currentLiquidityRate;
        //variable borrow index. Expressed in ray
        uint128 variableBorrowIndex;
        //the current variable borrow rate. Expressed in ray
        uint128 currentVariableBorrowRate;
        //the current stable borrow rate. Expressed in ray
        uint128 currentStableBorrowRate;
        //timestamp of last update
        uint40 lastUpdateTimestamp;
        //the id of the reserve. Represents the position in the list of the active reserves
        uint16 id;
        //aToken address
        address aTokenAddress;
        //stableDebtToken address
        address stableDebtTokenAddress;
        //variableDebtToken address
        address variableDebtTokenAddress;
        //address of the interest rate strategy
        address interestRateStrategyAddress;
        //the current treasury balance, scaled
        uint128 accruedToTreasury;
        //the outstanding unbacked aTokens minted through the bridging feature
        uint128 unbacked;
        //the outstanding debt borrowed against this asset in isolation mode
        uint128 isolationModeTotalDebt;
    }
    
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external;
    function getReserveNormalizedIncome(address asset) external view returns (uint256);
    function getReserveData(address asset) external view returns (ReserveData memory);
    function flashLoanSimple(address receiverAddress, address asset, uint256 amount, bytes calldata params, uint16 referralCode) external;
}

interface RewardsClaimerLike {
    function claimRewards(address[] calldata assets, uint256 amount, address to, address reward) external returns (uint256);
}

contract D3MAaveV3TypePool is ID3MPool {

    mapping (address => uint256) public wards;
    address                      public hub;
    address                      public king; // Who gets the rewards
    uint256                      public exited;

    bytes32    public immutable ilk;
    VatLike    public immutable vat;
    PoolLike   public immutable pool;
    ATokenLike public immutable stableDebt;
    ATokenLike public immutable variableDebt;
    ATokenLike public immutable adai;
    TokenLike  public immutable dai; // Asset

    uint256 internal constant FLASHLOAN_ENABLED_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF7FFFFFFFFFFFFFFF;
    uint256 internal constant SUPPLY_CAP_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFF000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant SUPPLY_CAP_START_BIT_POSITION = 116;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event Collect(address indexed king, address indexed gift, uint256 amt);

    constructor(bytes32 ilk_, address hub_, address dai_, address pool_) {
        ilk = ilk_;
        dai = TokenLike(dai_);
        pool = PoolLike(pool_);

        // Fetch the reserve data from Aave
        PoolLike.ReserveData memory data = pool.getReserveData(dai_);
        require(data.aTokenAddress               != address(0), "D3MAaveV3TypePool/invalid-adai");
        require(data.stableDebtTokenAddress      != address(0), "D3MAaveV3TypePool/invalid-stableDebt");
        require(data.variableDebtTokenAddress    != address(0), "D3MAaveV3TypePool/invalid-variableDebt");

        adai = ATokenLike(data.aTokenAddress);
        stableDebt = ATokenLike(data.stableDebtTokenAddress);
        variableDebt = ATokenLike(data.variableDebtTokenAddress);

        dai.approve(pool_, type(uint256).max);

        hub = hub_;
        vat = VatLike(D3mHubLike(hub_).vat());
        vat.hope(hub_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MAaveV3TypePool/not-authorized");
        _;
    }

    modifier onlyHub {
        require(msg.sender == hub, "D3MAaveV3TypePool/only-hub");
        _;
    }

    // --- Math ---
    uint256 internal constant RAY = 10 ** 27;
    function _rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * RAY) / y;
    }
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }
    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

    // --- Admin ---
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, address data) external auth {
        require(vat.live() == 1, "D3MAaveV3TypePool/no-file-during-shutdown");
        if (what == "hub") {
            vat.nope(hub);
            hub = data;
            vat.hope(data);
        } else if (what == "king") king = data;
        else revert("D3MAaveV3TypePool/file-unrecognized-param");
        emit File(what, data);
    }

    // Deposits Dai to Aave in exchange for adai which is received by this contract
    // Aave: https://docs.aave.com/developers/core-contracts/pool#supply
    function deposit(uint256 wad) external override onlyHub {
        uint256 scaledPrev = adai.scaledBalanceOf(address(this));

        pool.supply(address(dai), wad, address(this), 0);

        // Verify the correct amount of adai shows up
        uint256 interestIndex = pool.getReserveNormalizedIncome(address(dai));
        uint256 scaledAmount = _rdiv(wad, interestIndex);
        require(adai.scaledBalanceOf(address(this)) >= (scaledPrev + scaledAmount), "D3MAaveV3TypePool/incorrect-adai-balance-received");
    }

    // Withdraws Dai from Aave in exchange for adai
    // Aave: https://docs.aave.com/developers/core-contracts/pool#withdraw
    function withdraw(uint256 wad) external override onlyHub {
        uint256 prevDai = dai.balanceOf(msg.sender);

        pool.withdraw(address(dai), wad, msg.sender);

        require(dai.balanceOf(msg.sender) == prevDai + wad, "D3MAaveV3TypePool/incorrect-dai-balance-received");
    }

    function exit(address dst, uint256 wad) external override onlyHub {
        uint256 exited_ = exited;
        exited = exited_ + wad;
        uint256 amt = wad * assetBalance() / (D3mHubLike(hub).end().Art(ilk) - exited_);
        require(adai.transfer(dst, amt), "D3MAaveV3TypePool/transfer-failed");
    }

    function quit(address dst) external override auth {
        require(vat.live() == 1, "D3MAaveV3TypePool/no-quit-during-shutdown");
        require(adai.transfer(dst, adai.balanceOf(address(this))), "D3MAaveV3TypePool/transfer-failed");
    }

    function preDebtChange() external override {
        // Execute a 1 wei flash loan to trigger an index update on everything
        // If the fee is less than 100% than the fee should always round down to zero
        // Note: we can ignore indicies being up to date if the supply cap is 0
        PoolLike.ReserveData memory data = pool.getReserveData(address(dai));
        if (
            // The next two lines can be slightly optimized, but it's easier to read like this
            (data.configuration & ~FLASHLOAN_ENABLED_MASK) != 0 &&
            (data.configuration & ~SUPPLY_CAP_MASK) != 0 &&
            dai.balanceOf(address(adai)) > 0
        ) {
            pool.flashLoanSimple(address(this), address(dai), 1, "", 0);
        }
    }
    function executeOperation(
        address,
        uint256,
        uint256,
        address,
        bytes calldata
    ) external pure returns (bool) {
        // Flashloan callback just immediately returns
        return true;
    }

    function postDebtChange() external override {}

    // --- Balance of the underlying asset (Dai)
    function assetBalance() public view override returns (uint256) {
        return adai.balanceOf(address(this));
    }

    function maxDeposit() external view override returns (uint256) {
        // Supply cap logic adapted from https://github.com/aave/aave-v3-core/blob/94e571f3a7465201881a59555314cd550ccfda57/contracts/protocol/libraries/logic/ValidationLogic.sol#L71
        // Reserve configuration logic from https://github.com/aave/aave-v3-core/blob/94e571f3a7465201881a59555314cd550ccfda57/contracts/protocol/libraries/configuration/ReserveConfiguration.sol#L426
        PoolLike.ReserveData memory data = pool.getReserveData(address(dai));
        uint256 supplyCap = ((data.configuration & ~SUPPLY_CAP_MASK) >> SUPPLY_CAP_START_BIT_POSITION) * (10 ** dai.decimals());
        if (supplyCap == 0) return type(uint256).max;
        uint256 supplyUsed = _divup((adai.scaledTotalSupply() + uint256(data.accruedToTreasury)) * data.liquidityIndex, RAY);   // Over-estimate supply used to deal with rounding errors
        if (supplyCap >= supplyUsed) {
            return supplyCap - supplyUsed;
        } else {
            return 0;
        }
    }

    function maxWithdraw() external view override returns (uint256) {
        return _min(dai.balanceOf(address(adai)), assetBalance());
    }

    function redeemable() external view override returns (address) {
        return address(adai);
    }

    // --- Collect any rewards ---
    function collect(address gift) external returns (uint256 amt) {
        require(king != address(0), "D3MAaveV3TypePool/king-not-set");

        address[] memory assets = new address[](1);
        assets[0] = address(adai);

        RewardsClaimerLike rewardsClaimer = RewardsClaimerLike(adai.getIncentivesController());

        amt = rewardsClaimer.claimRewards(assets, type(uint256).max, king, gift);
        emit Collect(king, gift, amt);
    }
}
