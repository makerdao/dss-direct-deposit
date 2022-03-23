// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021-2022 Dai Foundation
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
    function transferFrom(address, address, uint256) external returns (bool);
    function scaledBalanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface DaiJoinLike {
    function dai() external view returns (address);
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

interface DssDirectDepositPoolLike {
    function king() external view returns (address);
    function getMaxBar() external view returns (uint256);
    function validTarget() external view returns (bool);
    function calcSupplies(uint256) external view returns (uint256, uint256);
    function deposit(uint256) external;
    function withdraw(uint256) external;
    function collect(address[] memory, uint256) external returns (uint256);
    function transferShares(address, uint256) external returns (bool);
    function assetBalance() external returns (uint256);
    function shareBalance() external returns (uint256);
    function convertToShares(uint256) external view returns(uint256);
    function convertToAssets(uint256) external view returns(uint256);
    function maxWithdraw() external view returns(uint256);
    function cage() external;
}

contract DssDirectDepositHub {

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
        require(wards[msg.sender] == 1, "DssDirectDepositHub/not-authorized");
        _;
    }

    struct Ilk {
        DssDirectDepositPoolLike pool;
        uint256                  tau; // Time until you can write off the debt [sec]
        uint256                  culled;
        uint256                  tic; // Timestamp when the pool is caged
    }

    ChainlogLike public immutable chainlog;
    VatLike public immutable vat;
    mapping (bytes32 => Ilk) public ilks;
    TokenLike public immutable dai;
    DaiJoinLike public immutable daiJoin;
    uint256 public live = 1;

    enum Mode{ NORMAL, MODULE_CULLED, MCD_CAGED }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed ilk, bytes32 indexed what, address data);
    event File(bytes32 indexed ilk, bytes32 indexed what, uint256 data);
    event Wind(bytes32 indexed ilk, uint256 amount);
    event Unwind(bytes32 indexed ilk, uint256 amount);
    event Reap(bytes32 indexed ilk, uint256 amt);
    event Collect(bytes32 indexed ilk, address indexed king, address[] assets, uint256 amt);
    event Cage();
    event Cage(bytes32 indexed ilk);
    event Cull(bytes32 indexed ilk);
    event Uncull(bytes32 indexed ilk);

    constructor(address chainlog_) public {
        address vat_ = ChainlogLike(chainlog_).getAddress("MCD_VAT");
        address daiJoin_ = ChainlogLike(chainlog_).getAddress("MCD_JOIN_DAI");

        chainlog = ChainlogLike(chainlog_);
        vat = VatLike(vat_);
        daiJoin = DaiJoinLike(daiJoin_);
        dai = TokenLike(DaiJoinLike(daiJoin_).dai());

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Math ---
    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "DssDirectDepositHub/overflow");
    }
    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "DssDirectDepositHub/underflow");
    }
    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "DssDirectDepositHub/overflow");
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
    function file(bytes32 ilk_, bytes32 what, uint256 data) external auth {
        Ilk storage ilk = ilks[ilk_];
        if (what == "tau" ) {
            require(live == 1, "DssDirectDepositHub/hub-not-live");
            require(ilk.tic == 0, "DssDirectDepositHub/join-not-live");

            ilk.tau = data;
        } else revert("DssDirectDepositHub/file-unrecognized-param");

        emit File(ilk_, what, data);
    }

    function file(bytes32 ilk, bytes32 what, address data) external auth {
        require(vat.live() == 1, "DssDirectDepositHub/no-file-during-shutdown");
        require(ilks[ilk].tic == 0, "DssDirectDepositHub/pool-not-live");

        if (what == "pool") ilks[ilk].pool = DssDirectDepositPoolLike(data);
        else revert("DssDirectDepositHub/file-unrecognized-param");
        emit File(ilk, what, data);
    }

    // --- Deposit controls ---
    function _wind(bytes32 ilk, DssDirectDepositPoolLike pool, uint256 amount) internal {
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
            emit Wind(ilk, 0);
            return;
        }

        require(int256(amount) >= 0, "DssDirectDepositHub/overflow");

        uint256 sharesPrev = pool.shareBalance();

        vat.slip(ilk, address(pool), int256(amount));
        vat.frob(ilk, address(pool), address(pool), address(pool), int256(amount), int256(amount));
        // normalized debt == erc20 DAI (Vat rate for this ilk fixed to 1 RAY)
        pool.deposit(amount);

        // Verify the correct amount of gem shows up
        uint256 newShares = pool.convertToShares(amount);
        require(pool.shareBalance() >= _add(sharesPrev, newShares), "DssDirectDepositHub/no-receive-gem-tokens");

        emit Wind(ilk, amount);
    }

    function _unwind(bytes32 ilk, DssDirectDepositPoolLike pool, uint256 supplyReduction, uint256 availableLiquidity, Mode mode) internal {
        // IMPORTANT: this function assumes Vat rate of this ilk will always be == 1 * RAY (no fees).
        // That's why it converts normalized debt (art) to Vat DAI generated with a simple RAY multiplication or division
        // This module will have an unintended behaviour if rate is changed to some other value.

        address end;
        uint256 assetBalance = pool.maxWithdraw();
        uint256 daiDebt;
        if (mode == Mode.NORMAL) {
            // Normal mode or module just caged (no culled)
            // debt is obtained from CDP art
            (,daiDebt) = vat.urns(ilk, address(pool));
        } else if (mode == Mode.MODULE_CULLED) {
            // Module shutdown and culled
            // debt is obtained from free collateral owned by this contract
            daiDebt = vat.gem(ilk, address(pool));
        } else {
            // MCD caged
            // debt is obtained from free collateral owned by the End module
            end = chainlog.getAddress("MCD_END");
            EndLike(end).skim(ilk, address(pool));
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
                                assetBalance
                            ),
                            daiDebt
                        );

        // Determine the amount of fees to bring back
        uint256 fees = 0;
        if (assetBalance > daiDebt) {
            fees = assetBalance - daiDebt;

            if (_add(amount, fees) > availableLiquidity) {
                // Don't need safe-math because this is constrained above
                fees = availableLiquidity - amount;
            }
        }

        if (amount == 0 && fees == 0) {
            emit Unwind(ilk, 0);
            return;
        }

        require(amount <= 2 ** 255, "DssDirectDepositHub/overflow");

        // To save gas you can bring the fees back with the unwind
        uint256 total = _add(amount, fees);
        pool.withdraw(total);

        // normalized debt == erc20 DAI to pool (Vat rate for this ilk fixed to 1 RAY)

        address vow = chainlog.getAddress("MCD_VOW");
        if (mode == Mode.NORMAL) {
            vat.frob(ilk, address(pool), address(pool), address(pool), -int256(amount), -int256(amount));
            vat.slip(ilk, address(pool), -int256(amount));
            vat.move(address(pool), vow, _mul(fees, RAY));
        } else if (mode == Mode.MODULE_CULLED) {
            vat.slip(ilk, address(pool), -int256(amount));
            vat.move(address(pool), vow, _mul(total, RAY));
        } else {
            // This can be done with the assumption that the price of 1 aDai equals 1 DAI.
            // That way we know that the prev End.skim call kept its gap[ilk] emptied as the CDP was always collateralized.
            // Otherwise we couldn't just simply take away the collateral from the End module as the next line will be doing.
            vat.slip(ilk, end, -int256(amount));
            vat.move(address(pool), vow, _mul(total, RAY));
        }

        emit Unwind(ilk, amount);
    }

    function exec(bytes32 ilk_) external {
        Ilk memory ilk = ilks[ilk_];

        uint256 availableAssets = ilk.pool.maxWithdraw();

        if (vat.live() == 0) {
            // MCD caged
            require(EndLike(chainlog.getAddress("MCD_END")).debt() == 0, "DssDirectDepositHub/end-debt-already-set");
            require(ilk.culled == 0, "DssDirectDepositHub/module-has-to-be-unculled-first");
            _unwind(
                ilk_,
                ilk.pool,
                type(uint256).max,
                availableAssets,
                Mode.MCD_CAGED
            );
        } else if (live == 0) {
            // This module caged
            _unwind(
                ilk_,
                ilk.pool,
                type(uint256).max,
                availableAssets,
                ilk.culled == 1
                ? Mode.MODULE_CULLED
                : Mode.NORMAL
            );
        } else {
            // Normal path
            (uint256 totalAssets, uint256 targetAssets) = ilk.pool.calcSupplies(availableAssets);

            if (targetAssets > totalAssets) {
                _wind(ilk_, ilk.pool, targetAssets - totalAssets);
            } else if (targetAssets < totalAssets) {
                _unwind(
                    ilk_,
                    ilk.pool,
                    totalAssets - targetAssets,
                    availableAssets,
                    Mode.NORMAL
                );
            }
        }
    }

    // --- Collect Interest ---
    function reap(bytes32 ilk_) external {
        Ilk memory ilk = ilks[ilk_];

        require(vat.live() == 1, "DssDirectDepositHub/no-reap-during-shutdown");
        require(live == 1, "DssDirectDepositHub/no-reap-during-cage");

        uint256 assetBalance = ilk.pool.convertToAssets(ilk.pool.shareBalance());
        (, uint256 daiDebt) = vat.urns(ilk_, address(ilk.pool));
        if (assetBalance > daiDebt) {
            uint256 fees = assetBalance - daiDebt;
            uint256 availableAssets = ilk.pool.assetBalance();
            if (fees > availableAssets) {
                fees = availableAssets;
            }
            ilk.pool.withdraw(fees);
            vat.move(address(ilk.pool), address(chainlog.getAddress("MCD_VOW")), _mul(RAY, fees));
            Reap(ilk_, fees);
        }
    }

    // --- Collect any rewards ---
    function collect(bytes32 ilk_, address[] memory assets, uint256 amount) external returns (uint256 amt) {
        Ilk memory ilk = ilks[ilk_];

        amt = ilk.pool.collect(assets, amount);
        Collect(ilk_, ilk.pool.king(), assets, amt);
    }

    // --- Allow DAI holders to exit during global settlement ---
    function exit(bytes32 ilk_, address usr, uint256 wad) external {
        require(wad <= 2 ** 255, "DssDirectDepositHub/overflow");
        vat.slip(ilk_, msg.sender, -int256(wad));
        Ilk memory ilk = ilks[ilk_];
        require(ilk.pool.transferShares(usr, ilk.pool.convertToShares(wad)), "DssDirectDepositHub/failed-transfer");
    }

    // --- Shutdown ---
    function cage(bytes32 ilk_) external {
        require(vat.live() == 1, "DssDirectDepositHub/no-cage-during-shutdown");

        Ilk storage ilk = ilks[ilk_];

        // Can shut joins down if we are authed
        // or if the interest rate strategy changes
        // or if the main module is caged
        require(
            wards[msg.sender] == 1 ||
            live == 0 ||
            !ilk.pool.validTarget()
        , "DssDirectDepositHub/not-authorized");

        ilk.pool.cage();
        ilk.tic = block.timestamp;
        emit Cage(ilk_);
    }

    function cage() external {
        require(wards[msg.sender] == 1 , "DssDirectDepositHub/not-authorized");
        require(vat.live() == 1, "DssDirectDepositHub/no-cage-during-shutdown");

        live = 0;
        emit Cage();
    }

    // --- Write-off ---
    function cull(bytes32 ilk_) external {
        require(vat.live() == 1, "DssDirectDepositHub/no-cull-during-shutdown");
        require(live == 0, "DssDirectDepositHub/live");
        Ilk storage ilk = ilks[ilk_];
        require(ilk.tic > 0, "DssDirectDepositHub/join-live");
        require(_add(ilk.tic, ilk.tau) <= block.timestamp || wards[msg.sender] == 1, "DssDirectDepositHub/unauthorized-cull");
        require(ilk.culled == 0, "DssDirectDepositHub/already-culled");

        (uint256 ink, uint256 art) = vat.urns(ilk_, address(ilk.pool));
        require(ink <= 2 ** 255, "DssDirectDepositHub/overflow");
        require(art <= 2 ** 255, "DssDirectDepositHub/overflow");
        vat.grab(ilk_, address(ilk.pool), address(ilk.pool), chainlog.getAddress("MCD_VOW"), -int256(ink), -int256(art));

        ilk.culled = 1;
        emit Cull(ilk_);
    }

    // --- Rollback Write-off (only if General Shutdown happened) ---
    // This function is required to have the collateral back in the vault so it can be taken by End module
    // and eventually be shared to DAI holders (as any other collateral) or maybe even unwinded
    function uncull(bytes32 ilk_) external {
        Ilk storage ilk = ilks[ilk_];

        require(ilk.culled == 1, "DssDirectDepositHub/not-prev-culled");
        require(vat.live() == 0, "DssDirectDepositHub/no-uncull-normal-operation");

        uint256 wad = vat.gem(ilk_, address(ilk.pool));
        require(wad < 2 ** 255, "DssDirectDepositHub/overflow");
        address vow = chainlog.getAddress("MCD_VOW");
        vat.suck(vow, vow, _mul(wad, RAY)); // This needs to be done to make sure we can deduct sin[vow] and vice in the next call
        vat.grab(ilk_, address(ilk.pool), address(ilk.pool), vow, int256(wad), int256(wad));

        ilk.culled = 0;
        emit Uncull(ilk_);
    }

    // --- Emergency Quit Everything ---
    function quit(bytes32 ilk_, address who) external auth {
        require(vat.live() == 1, "DssDirectDepositHub/no-quit-during-shutdown");

        Ilk memory ilk = ilks[ilk_];

        // Send all gem in the contract to who
        require(ilk.pool.transferShares(who, ilk.pool.shareBalance()), "DssDirectDepositHub/failed-transfer");

        if (ilk.culled == 1) {
            // Culled - just zero out the gems
            uint256 wad = vat.gem(ilk_, address(ilk.pool));
            require(wad <= 2 ** 255, "DssDirectDepositHub/overflow");
            vat.slip(ilk_, address(ilk.pool), -int256(wad));
        } else {
            // Regular operation - transfer the debt position (requires who to accept the transfer)
            (uint256 ink, uint256 art) = vat.urns(ilk_, address(ilk.pool));
            require(ink < 2 ** 255, "DssDirectDepositHub/overflow");
            require(art < 2 ** 255, "DssDirectDepositHub/overflow");
            vat.fork(ilk_, address(ilk.pool), who, int256(ink), int256(art));
        }
    }
}
