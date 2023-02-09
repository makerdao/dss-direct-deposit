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

// aDai: https://etherscan.io/address/0x028171bCA77440897B824Ca71D1c56caC55b68A3
interface ATokenLike is TokenLike {
    function scaledBalanceOf(address) external view returns (uint256);
    function getIncentivesController() external view returns (address);
}

// Aave Lending Pool v2: https://etherscan.io/address/0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9
interface LendingPoolV2Like {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external;
    function getReserveNormalizedIncome(address asset) external view returns (uint256);
    function getReserveData(address asset) external view returns (
        uint256, // configuration
        uint128, // the liquidity index. Expressed in ray
        uint128, // variable borrow index. Expressed in ray
        uint128, // the current supply rate. Expressed in ray
        uint128, // the current variable borrow rate. Expressed in ray
        uint128, // the current stable borrow rate. Expressed in ray
        uint40,  // last updated timestamp
        address, // address of the adai interest bearing token
        address, // address of the stable debt token
        address, // address of the variable debt token
        address, // address of the interest rate strategy
        uint8    // the id of the reserve
    );
}

// Aave Lending Pool v3
// Interface changed slightly from v2 to v3
interface LendingPoolV3Like {

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
    
    function getReserveData(address asset) external view returns (ReserveData memory);
}

// Aave Incentives Controller V2: https://etherscan.io/address/0xd784927ff2f95ba542bfc824c8a8a98f3495f6b5
interface RewardsClaimerV2Like {
    function REWARD_TOKEN() external returns (address);
    function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);
}

// Aave Incentives Controller V3: https://etherscan.io/address/0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb
interface RewardsClaimerV3Like {
    function claimRewards(address[] calldata assets, uint256 amount, address to, address reward) external returns (uint256);
}

contract D3MAavePool is ID3MPool {

    enum AaveVersion {
        V2,
        V3
    }

    mapping (address => uint256) public wards;
    address                      public hub;
    address                      public king; // Who gets the rewards
    uint256                      public exited;

    AaveVersion public immutable version;
    bytes32     public immutable ilk;
    VatLike     public immutable vat;
    address     public immutable pool;
    ATokenLike  public immutable stableDebt;
    ATokenLike  public immutable variableDebt;
    ATokenLike  public immutable adai;
    TokenLike   public immutable dai; // Asset

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event Collect(address indexed king, address indexed gift, uint256 amt);

    constructor(AaveVersion version_, bytes32 ilk_, address hub_, address dai_, address pool_) {
        version = version_;
        ilk = ilk_;
        dai = TokenLike(dai_);
        pool = pool_;

        // Fetch the reserve data from Aave
        (address adai_, address stableDebt_, address variableDebt_) = getReserveDataAddresses();
        require(adai_         != address(0), "D3MAavePool/invalid-adai");
        require(stableDebt_   != address(0), "D3MAavePool/invalid-stableDebt");
        require(variableDebt_ != address(0), "D3MAavePool/invalid-variableDebt");

        adai = ATokenLike(adai_);
        stableDebt = ATokenLike(stableDebt_);
        variableDebt = ATokenLike(variableDebt_);

        dai.approve(pool_, type(uint256).max);

        hub = hub_;
        vat = VatLike(D3mHubLike(hub_).vat());
        vat.hope(hub_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function getReserveDataAddresses() internal view returns (address adai_, address stableDebt_, address variableDebt_) {
         if (version == AaveVersion.V3) {
            LendingPoolV3Like.ReserveData memory data = LendingPoolV3Like(pool).getReserveData(address(dai));
            adai_ = data.aTokenAddress;
            stableDebt_ = data.stableDebtTokenAddress;
            variableDebt_ = data.variableDebtTokenAddress;
        } else {
            (,,,,,,, adai_, stableDebt_, variableDebt_,,) = LendingPoolV2Like(pool).getReserveData(address(dai));
        }
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MAavePool/not-authorized");
        _;
    }

    modifier onlyHub {
        require(msg.sender == hub, "D3MAavePool/only-hub");
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
        require(vat.live() == 1, "D3MAavePool/no-file-during-shutdown");
        if (what == "hub") {
            vat.nope(hub);
            hub = data;
            vat.hope(data);
        } else if (what == "king") king = data;
        else revert("D3MAavePool/file-unrecognized-param");
        emit File(what, data);
    }

    // Deposits Dai to Aave in exchange for adai which is received by this contract
    // Aave: https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#deposit
    function deposit(uint256 wad) external override onlyHub {
        uint256 scaledPrev = adai.scaledBalanceOf(address(this));

        LendingPoolV2Like(pool).deposit(address(dai), wad, address(this), 0);

        // Verify the correct amount of adai shows up
        uint256 interestIndex = LendingPoolV2Like(pool).getReserveNormalizedIncome(address(dai));
        uint256 scaledAmount = _rdiv(wad, interestIndex);
        require(adai.scaledBalanceOf(address(this)) >= (scaledPrev + scaledAmount), "D3MAavePool/incorrect-adai-balance-received");
    }

    // Withdraws Dai from Aave in exchange for adai
    // Aave: https://docs.aave.com/developers/v/2.0/the-core-protocol/lendingpool#withdraw
    function withdraw(uint256 wad) external override onlyHub {
        uint256 prevDai = dai.balanceOf(msg.sender);

        LendingPoolV2Like(pool).withdraw(address(dai), wad, msg.sender);

        require(dai.balanceOf(msg.sender) == prevDai + wad, "D3MAavePool/incorrect-dai-balance-received");
    }

    function exit(address dst, uint256 wad) external override onlyHub {
        uint256 exited_ = exited;
        exited = exited_ + wad;
        uint256 amt = wad * assetBalance() / (D3mHubLike(hub).end().Art(ilk) - exited_);
        require(adai.transfer(dst, amt), "D3MAavePool/transfer-failed");
    }

    function quit(address dst) external override auth {
        require(vat.live() == 1, "D3MAavePool/no-quit-during-shutdown");
        require(adai.transfer(dst, adai.balanceOf(address(this))), "D3MAavePool/transfer-failed");
    }

    function preDebtChange() external override {}

    function postDebtChange() external override {}

    // --- Balance of the underlying asset (Dai)
    function assetBalance() public view override returns (uint256) {
        return adai.balanceOf(address(this));
    }

    function maxDeposit() external pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw() external view override returns (uint256) {
        return _min(dai.balanceOf(address(adai)), assetBalance());
    }

    function redeemable() external view override returns (address) {
        return address(adai);
    }

    // --- Collect any rewards ---
    function collect() external returns (uint256 amt) {
        require(king != address(0), "D3MAavePool/king-not-set");
        require(version == AaveVersion.V2, "D3MAavePool/only-v2");

        address[] memory assets = new address[](1);
        assets[0] = address(adai);

        RewardsClaimerV2Like rewardsClaimer = RewardsClaimerV2Like(adai.getIncentivesController());

        amt = rewardsClaimer.claimRewards(assets, type(uint256).max, king);
        address gift = rewardsClaimer.REWARD_TOKEN();
        emit Collect(king, gift, amt);
    }
    function collect(address reward) external returns (uint256 amt) {
        require(king != address(0), "D3MAavePool/king-not-set");
        require(version == AaveVersion.V3, "D3MAavePool/only-v3");

        address[] memory assets = new address[](1);
        assets[0] = address(adai);

        RewardsClaimerV3Like rewardsClaimer = RewardsClaimerV3Like(adai.getIncentivesController());

        amt = rewardsClaimer.claimRewards(assets, type(uint256).max, king, reward);
        emit Collect(king, reward, amt);
    }
}
