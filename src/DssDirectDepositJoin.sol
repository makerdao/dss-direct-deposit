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
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function scaledBalanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
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
    function fork(bytes32, address, address, int256, int256) external;
    function suck(address, address, uint256) external;
}

interface EndLike {
    function debt() external view returns (uint256);
    function skim(bytes32, address) external;
}

interface DssDirectDepositTargetLike {
    function rewardsClaimer() external view returns (address);
    function getMaxBar() external view returns (uint256);
    function validTarget(address) external view returns (bool);
    function calcSupplies(uint256, uint256) external view returns (uint256, uint256);
    function supply(address, uint256) external;
    function withdraw(address, uint256) external;
    function getNormalizedBalanceOf(address) external view returns(uint256);
    function getNormalizedAmount(address, uint256) external view returns(uint256);
    function cage() external;
}

interface RewardsClaimerLike {
    function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);
}

contract DssDirectDepositJoin {

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
        require(wards[msg.sender] == 1, "DssDirectDepositJoin/not-authorized");
        _;
    }

    ChainlogLike public immutable chainlog;
    VatLike public immutable vat;
    bytes32 public immutable ilk;
    DssDirectDepositTargetLike public d3mTarget;
    TokenLike public immutable dai;
    DaiJoinLike public immutable daiJoin;
    TokenLike public immutable gem;
    uint256 public immutable dec;

    uint256 public tau;             // Time until you can write off the debt [sec]
    uint256 public bar;             // Target Interest Rate [ray]
    uint256 public live = 1;
    uint256 public culled;
    uint256 public tic;             // Timestamp when the system is caged
    address public king;            // Who gets the rewards

    enum Mode{ NORMAL, MODULE_CULLED, MCD_CAGED }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, uint256 data);
    event Wind(uint256 amount);
    event Unwind(uint256 amount);
    event Reap(uint256 amt);
    event Collect(address indexed king, address[] assets, uint256 amt);
    event Cage();
    event Cull();
    event Uncull();

    constructor(address chainlog_, bytes32 ilk_, address target_, address gem_) public {
        address vat_ = ChainlogLike(chainlog_).getAddress("MCD_VAT");
        address daiJoin_ = ChainlogLike(chainlog_).getAddress("MCD_JOIN_DAI");
        TokenLike dai_ = dai = TokenLike(DaiJoinLike(daiJoin_).dai());

        chainlog = ChainlogLike(chainlog_);
        vat = VatLike(vat_);
        ilk = ilk_;
        d3mTarget = DssDirectDepositTargetLike(target_);
        gem = TokenLike(gem_);
        dec = TokenLike(gem_).decimals();
        daiJoin = DaiJoinLike(daiJoin_);
        
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        // Auths
        VatLike(vat_).hope(daiJoin_);
        TokenLike(gem_).approve(address(target_), type(uint256).max);
        dai_.approve(address(target_), type(uint256).max);
        dai_.approve(daiJoin_, type(uint256).max);
    }

    // --- Math ---
    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "DssDirectDepositJoin/overflow");
    }
    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "DssDirectDepositJoin/underflow");
    }
    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "DssDirectDepositJoin/overflow");
    }
    uint256 constant RAY  = 10 ** 27;
    function _rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, y) / RAY;
    }
    function _rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = _mul(x, RAY) / y;
    }
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external auth {
        if (what == "bar") {
            require(data <= d3mTarget.getMaxBar(), "DssDirectDepositJoin/above-max-interest");

            bar = data;
        } else if (what == "tau" ) {
            require(live == 1, "DssDirectDepositJoin/not-live");

            tau = data;
        } else revert("DssDirectDepositJoin/file-unrecognized-param");

        emit File(what, data);
    }

    function file(bytes32 what, address data) external auth {
        require(vat.live() == 1, "DssDirectDepositJoin/no-file-during-shutdown");

        if (what == "king") king = data;
        else if (what == "target") d3mTarget = DssDirectDepositTargetLike(data);
        else revert("DssDirectDepositJoin/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Deposit controls ---
    function _wind(uint256 amount) internal {
        // IMPORTANT: this function assumes Vat rate of this ilk will always be == 1 * RAY (no fees).
        // That's why this module converts normalized debt (art) to Vat DAI generated with a simple RAY multiplication or division
        // This module will have an unintended behaviour if rate is changed to some other value.

        // Wind amount is limited by the debt ceiling
        (uint256 Art,,, uint256 line,) = vat.ilks(ilk);
        uint256 lineWad = line / RAY; // Round down to always be under the actual limit
        if (_add(Art, amount) > lineWad) {
            amount = _sub(lineWad, Art);
        }

        if (amount == 0) {
            emit Wind(0);
            return;
        }

        require(int256(amount) >= 0, "DssDirectDepositJoin/overflow");

        uint256 scaledPrev = d3mTarget.getNormalizedBalanceOf(address(this));

        vat.slip(ilk, address(this), int256(amount));
        vat.frob(ilk, address(this), address(this), address(this), int256(amount), int256(amount));
        // normalized debt == erc20 DAI to join (Vat rate for this ilk fixed to 1 RAY)
        daiJoin.exit(address(this), amount);
        d3mTarget.supply(address(dai), amount);

        // Verify the correct amount of gem shows up
        uint256 scaledAmount = d3mTarget.getNormalizedAmount(address(dai), amount);
        require(d3mTarget.getNormalizedBalanceOf(address(this)) >= _add(scaledPrev, scaledAmount), "DssDirectDepositJoin/no-receive-gem-tokens");

        emit Wind(amount);
    }

    function _unwind(uint256 supplyReduction, uint256 availableLiquidity, Mode mode) internal {
        // IMPORTANT: this function assumes Vat rate of this ilk will always be == 1 * RAY (no fees).
        // That's why it converts normalized debt (art) to Vat DAI generated with a simple RAY multiplication or division
        // This module will have an unintended behaviour if rate is changed to some other value.

        address end;
        uint256 gemBalance = gem.balanceOf(address(this));
        uint256 daiDebt;
        if (mode == Mode.NORMAL) {
            // Normal mode or module just caged (no culled)
            // debt is obtained from CDP art
            (,daiDebt) = vat.urns(ilk, address(this));
        } else if (mode == Mode.MODULE_CULLED) {
            // Module shutdown and culled
            // debt is obtained from free collateral owned by this contract
            daiDebt = vat.gem(ilk, address(this));
        } else {
            // MCD caged
            // debt is obtained from free collateral owned by the End module
            end = chainlog.getAddress("MCD_END");
            EndLike(end).skim(ilk, address(this));
            daiDebt = vat.gem(ilk, address(end));
        }

        // Unwind amount is limited by how much:
        // - max reduction desired
        // - liquidity available
        // - gem we have to withdraw
        // - dai debt tracked in vat (CDP or free)
        uint256 amount = _min(
                            _min(
                                _min(
                                    supplyReduction,
                                    availableLiquidity
                                ),
                                gemBalance
                            ),
                            daiDebt
                        );

        // Determine the amount of fees to bring back
        uint256 fees = 0;
        if (gemBalance > daiDebt) {
            fees = gemBalance - daiDebt;

            if (_add(amount, fees) > availableLiquidity) {
                // Don't need safe-math because this is constrained above
                fees = availableLiquidity - amount;
            }
        }

        if (amount == 0 && fees == 0) {
            emit Unwind(0);
            return;
        }

        require(amount <= 2 ** 255, "DssDirectDepositJoin/overflow");

        // To save gas you can bring the fees back with the unwind
        uint256 total = _add(amount, fees);
        d3mTarget.withdraw(address(dai), total);
        daiJoin.join(address(this), total);

        // normalized debt == erc20 DAI to join (Vat rate for this ilk fixed to 1 RAY)

        address vow = chainlog.getAddress("MCD_VOW");
        if (mode == Mode.NORMAL) {
            vat.frob(ilk, address(this), address(this), address(this), -int256(amount), -int256(amount));
            vat.slip(ilk, address(this), -int256(amount));
            vat.move(address(this), vow, _mul(fees, RAY));
        } else if (mode == Mode.MODULE_CULLED) {
            vat.slip(ilk, address(this), -int256(amount));
            vat.move(address(this), vow, _mul(total, RAY));
        } else {
            // This can be done with the assumption that the price of 1 aDai equals 1 DAI.
            // That way we know that the prev End.skim call kept its gap[ilk] emptied as the CDP was always collateralized.
            // Otherwise we couldn't just simply take away the collateral from the End module as the next line will be doing.
            vat.slip(ilk, end, -int256(amount));
            vat.move(address(this), vow, _mul(total, RAY));
        }

        emit Unwind(amount);
    }

    function exec() external {
        uint256 availableLiquidity = dai.balanceOf(address(gem));

        if (vat.live() == 0) {
            // MCD caged
            require(EndLike(chainlog.getAddress("MCD_END")).debt() == 0, "DssDirectDepositJoin/end-debt-already-set");
            require(culled == 0, "DssDirectDepositJoin/module-has-to-be-unculled-first");
            _unwind(
                type(uint256).max,
                availableLiquidity,
                Mode.MCD_CAGED
            );
        } else if (live == 0) {
            // This module caged
            _unwind(
                type(uint256).max,
                availableLiquidity,
                culled == 1
                ? Mode.MODULE_CULLED
                : Mode.NORMAL
            );
        } else {
            // Normal path
            (uint256 supplyAmount, uint256 targetSupply) = d3mTarget.calcSupplies(availableLiquidity, bar);

            if (targetSupply > supplyAmount) {
                _wind(targetSupply - supplyAmount);
            } else if (targetSupply < supplyAmount) {
                _unwind(
                    supplyAmount - targetSupply,
                    availableLiquidity,
                    Mode.NORMAL
                );
            }
        }
    }

    // --- Collect Interest ---
    function reap() external {
        require(vat.live() == 1, "DssDirectDepositJoin/no-reap-during-shutdown");
        require(live == 1, "DssDirectDepositJoin/no-reap-during-cage");
        uint256 gemBalance = gem.balanceOf(address(this));
        (, uint256 daiDebt) = vat.urns(ilk, address(this));
        if (gemBalance > daiDebt) {
            uint256 fees = gemBalance - daiDebt;
            uint256 availableLiquidity = dai.balanceOf(address(gem));
            if (fees > availableLiquidity) {
                fees = availableLiquidity;
            }
            d3mTarget.withdraw(address(dai), fees);
            daiJoin.join(address(chainlog.getAddress("MCD_VOW")), fees);
            Reap(fees);
        }
    }

    // --- Collect any rewards ---
    function collect(address[] memory assets, uint256 amount) external returns (uint256 amt) {
        require(king != address(0), "DssDirectDepositJoin/king-not-set");

        amt = RewardsClaimerLike(d3mTarget.rewardsClaimer()).claimRewards(assets, amount, king);
        Collect(king, assets, amt);
    }

    // --- Allow DAI holders to exit during global settlement ---
    function exit(address usr, uint256 wad) external {
        require(wad <= 2 ** 255, "DssDirectDepositJoin/overflow");
        vat.slip(ilk, msg.sender, -int256(wad));
        require(gem.transfer(usr, wad), "DssDirectDepositJoin/failed-transfer");
    }

    // --- Shutdown ---
    function cage() external {
        require(vat.live() == 1, "DssDirectDepositJoin/no-cage-during-shutdown");
        // Can shut this down if we are authed
        // or if the interest rate strategy changes
        require(
            wards[msg.sender] == 1 ||
            address(d3mTarget) == address(0) ||
            !d3mTarget.validTarget()
        , "DssDirectDepositJoin/not-authorized");

        live = 0;
        d3mTarget.cage();
        tic = block.timestamp;
        emit Cage();
    }

    // --- Write-off ---
    function cull() external {
        require(vat.live() == 1, "DssDirectDepositJoin/no-cull-during-shutdown");
        require(live == 0, "DssDirectDepositJoin/live");
        require(_add(tic, tau) <= block.timestamp || wards[msg.sender] == 1, "DssDirectDepositJoin/unauthorized-cull");
        require(culled == 0, "DssDirectDepositJoin/already-culled");

        (uint256 ink, uint256 art) = vat.urns(ilk, address(this));
        require(ink <= 2 ** 255, "DssDirectDepositJoin/overflow");
        require(art <= 2 ** 255, "DssDirectDepositJoin/overflow");
        vat.grab(ilk, address(this), address(this), chainlog.getAddress("MCD_VOW"), -int256(ink), -int256(art));

        culled = 1;
        emit Cull();
    }

    // --- Rollback Write-off (only if General Shutdown happened) ---
    // This function is required to have the collateral back in the vault so it can be taken by End module
    // and eventually be shared to DAI holders (as any other collateral) or maybe even unwinded
    function uncull() external {
        require(culled == 1, "DssDirectDepositJoin/not-prev-culled");
        require(vat.live() == 0, "DssDirectDepositJoin/no-uncull-normal-operation");

        uint256 wad = vat.gem(ilk, address(this));
        require(wad < 2 ** 255, "DssDirectDepositJoin/overflow");
        address vow = chainlog.getAddress("MCD_VOW");
        vat.suck(vow, vow, _mul(wad, RAY)); // This needs to be done to make sure we can deduct sin[vow] and vice in the next call
        vat.grab(ilk, address(this), address(this), vow, int256(wad), int256(wad));

        culled = 0;
        emit Uncull();
    }

    // --- Emergency Quit Everything ---
    function quit(address who) external auth {
        require(vat.live() == 1, "DssDirectDepositJoin/no-quit-during-shutdown");

        // Send all gem in the contract to who
        require(gem.transfer(who, gem.balanceOf(address(this))), "DssDirectDepositJoin/failed-transfer");

        if (culled == 1) {
            // Culled - just zero out the gems
            uint256 wad = vat.gem(ilk, address(this));
            require(wad <= 2 ** 255, "DssDirectDepositJoin/overflow");
            vat.slip(ilk, address(this), -int256(wad));
        } else {
            // Regular operation - transfer the debt position (requires who to accept the transfer)
            (uint256 ink, uint256 art) = vat.urns(ilk, address(this));
            require(ink < 2 ** 255, "DssDirectDepositJoin/overflow");
            require(art < 2 ** 255, "DssDirectDepositJoin/overflow");
            vat.fork(ilk, address(this), who, int256(ink), int256(art));
        }
    }
}
