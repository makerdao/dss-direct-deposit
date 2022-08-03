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

import "./pools/ID3MPool.sol";
import "./plans/ID3MPlan.sol";

interface VatLike {
    function debt() external view returns (uint256);
    function hope(address) external;
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function Line() external view returns (uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
    function gem(bytes32, address) external view returns (uint256);
    function live() external view returns (uint256);
    function slip(bytes32, address, int256) external;
    function move(address, address, uint256) external;
    function frob(bytes32, address, address, address, int256, int256) external;
    function grab(bytes32, address, address, address, int256, int256) external;
    function suck(address, address, uint256) external;
}

interface EndLike {
    function debt() external view returns (uint256);
    function skim(bytes32, address) external;
}

interface DaiJoinLike {
    function vat() external view returns (address);
    function dai() external view returns (address);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

interface TokenLike {
    function approve(address, uint256) external returns (bool);
}

/**
    @title D3M Hub
    @notice This is the main D3M contract and is responsible for winding and
    unwinding pools, interacting with DSS and tracking the plans and pools and
    their states.
*/
contract D3MHub {

    // --- Auth ---
    /**
        @notice Maps address that have permission in the Pool.
        @dev 1 = allowed, 0 = no permission
        @return authorization 1 or 0
    */
    mapping (address => uint256) public wards;

    address public vow;
    EndLike public end;
    uint256 public locked;

    /// @notice maps ilk bytes32 to the D3M tracking struct.
    mapping (bytes32 => Ilk) public ilks;

    VatLike     public immutable vat;
    DaiJoinLike public immutable daiJoin;

    enum Mode { NORMAL, D3M_CULLED, MCD_CAGED }

    /**
        @notice Tracking struct for each of the D3M ilks.
        @param pool   Contract to access external pool and hold balances
        @param plan   Contract used to calculate target debt
        @param tau    Time until you can write off the debt [sec]
        @param culled Debt write off triggered (1 or 0)
        @param tic    Timestamp when the pool is caged
    */
    struct Ilk {
        ID3MPool pool;   // Access external pool and holds balances
        ID3MPlan plan;   // How we calculate target debt
        uint256  tau;    // Time until you can write off the debt [sec]
        uint256  culled; // Debt write off triggered
        uint256  tic;    // Timestamp when the d3m can be culled (tau + timestamp when caged)
    }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed ilk, bytes32 indexed what, address data);
    event File(bytes32 indexed ilk, bytes32 indexed what, uint256 data);
    event Wind(bytes32 indexed ilk, uint256 amt);
    event Unwind(bytes32 indexed ilk, uint256 amt);
    event Fees(bytes32 indexed ilk, uint256 amt);
    event Exit(bytes32 indexed ilk, address indexed usr, uint256 amt);
    event Cage(bytes32 indexed ilk);
    event Cull(bytes32 indexed ilk, uint256 ink, uint256 art);
    event Uncull(bytes32 indexed ilk, uint256 wad);

    /**
        @dev sets msg.sender as authed.
        @param daiJoin_ address of the DSS Dai Join contract
    */
    constructor(address daiJoin_) {
        daiJoin = DaiJoinLike(daiJoin_);
        vat = VatLike(daiJoin.vat());
        TokenLike(daiJoin.dai()).approve(daiJoin_, type(uint256).max);
        vat.hope(daiJoin_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /// @notice Modifier will revoke if msg.sender is not authorized.
    modifier auth {
        require(wards[msg.sender] == 1, "D3MHub/not-authorized");
        _;
    }

    /// @notice Mutex to prevent reentrancy on external functions
    modifier lock {
        require(locked == 0, "D3MHub/system-locked");
        locked = 1;
        _;
        locked = 0;
    }

    // --- Math ---
    uint256 internal constant RAY = 10 ** 27;
    uint256 internal constant MAXINT256 = uint256(type(int256).max);

    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }
    function _max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x >= y ? x : y;
    }
    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

    // --- Administration ---
    /**
        @notice Makes an address authorized to perform auth'ed functions.
        @dev msg.sender must be authorized.
        @param usr address to be authorized
    */
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    /**
        @notice De-authorizes an address from performing auth'ed functions.
        @dev msg.sender must be authorized.
        @param usr address to be de-authorized
    */
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    /**
        @notice update vow or end addresses.
        @dev msg.sender must be authorized.
        @param what name of what we are updating bytes32("vow"|"end")
        @param data address we are setting it to
    */
    function file(bytes32 what, address data) external auth {
        require(vat.live() == 1, "D3MHub/no-file-during-shutdown");

        if (what == "vow") vow = data;
        else if (what == "end") end = EndLike(data);
        else revert("D3MHub/file-unrecognized-param");
        emit File(what, data);
    }

    /**
        @notice update tau value for D3M ilk.
        @dev msg.sender must be authorized.
        @param ilk  bytes32 of the D3M ilk to be updated
        @param what bytes32("tau") or it will revert
        @param data number of seconds to wait after caging a pool to write off debt
    */
    function file(bytes32 ilk, bytes32 what, uint256 data) external auth {
        if (what == "tau") ilks[ilk].tau = data;
        else revert("D3MHub/file-unrecognized-param");

        emit File(ilk, what, data);
    }

    /**
        @notice update plan or pool addresses for D3M ilk.
        @dev msg.sender must be authorized.
        @param ilk  bytes32 of the D3M ilk to be updated
        @param what bytes32("pool"|"plan") or it will revert
        @param data address we are setting it to
    */
    function file(bytes32 ilk, bytes32 what, address data) external auth {
        require(vat.live() == 1, "D3MHub/no-file-during-shutdown");
        require(ilks[ilk].tic == 0, "D3MHub/pool-not-live");

        if (what == "pool") ilks[ilk].pool = ID3MPool(data);
        else if (what == "plan") ilks[ilk].plan = ID3MPlan(data);
        else revert("D3MHub/file-unrecognized-param");
        emit File(ilk, what, data);
    }

    // --- Deposit controls ---
    function _wind(bytes32 ilk, ID3MPool _pool, uint256 amount) internal {
        if (amount > 0) {
            vat.slip(ilk, address(_pool), int256(amount));
            vat.frob(ilk, address(_pool), address(_pool), address(this), int256(amount), int256(amount));
            // normalized debt == erc20 DAI (Vat rate for D3M ilks fixed to 1 RAY)
            daiJoin.exit(address(_pool), amount);
            _pool.deposit(amount);
        }

        emit Wind(ilk, amount);
    }

    function _unwind(bytes32 ilk, ID3MPool _pool, uint256 reduction, Mode mode, uint256 assetBalance) internal {
        uint256 amount = _min(
                            _min(
                                reduction, // max reduction desired
                                _pool.maxWithdraw() // max amount the pool allows to withdraw (for any reason)
                            ),
                            assetBalance // assets balance
                        );
        if (mode == Mode.NORMAL) {
            if (amount > 0) {
                require(amount <= MAXINT256, "D3MHub/overflow");

                _pool.withdraw(amount);
                daiJoin.join(address(this), amount);

                // assetsBalance == art tracked in vat (as _fix is called previously) => amount <= art
                vat.frob(ilk, address(_pool), address(_pool), address(this), -int256(amount), -int256(amount));
                vat.slip(ilk, address(_pool), -int256(amount));
            }
        } else if (mode == Mode.D3M_CULLED || mode == Mode.MCD_CAGED) {
            if (amount > 0) {
                address urn = mode == Mode.D3M_CULLED ? address(_pool) : address(end);

                uint256 toSlip = _min(vat.gem(ilk, urn), amount);
                require(toSlip <= MAXINT256, "D3MHub/overflow");

                _pool.withdraw(amount);
                daiJoin.join(address(this), amount);

                vat.slip(ilk, urn, -int256(toSlip));
                vat.move(address(this), vow, amount * RAY);
            }
        } else revert("D3MHub/unknown-mode");

        emit Unwind(ilk, amount);
    }

    function _fix(bytes32 ilk, address _pool, uint256 assets) internal returns (uint256 diff) {
        (uint256 ink, uint256 art) = vat.urns(ilk, _pool);
        if (assets > ink) {
            uint256 _diff = assets - ink;
            require(_diff <= MAXINT256, "D3MHub/overflow");
            vat.slip(ilk, address(_pool), int256(_diff));
            vat.frob(ilk, address(_pool), address(_pool), address(this), int256(_diff), 0);
            ink = assets;
            emit Fees(ilk, _diff);
        }
        if (art < ink) {
            address _vow = vow;
            diff = ink - art;
            require(diff <= MAXINT256, "D3MHub/overflow");
            vat.suck(_vow, _vow, diff * RAY); // This needs to be done to make sure we can deduct sin[vow] and vice in the next call
            vat.grab(ilk, _pool, _pool, _vow, 0, int256(diff));
        }
    }

    // Ilk Getters
    /**
        @notice Return pool of an ilk
        @param ilk   bytes32 of the D3M ilk
        @return pool address of pool contract
    */
    function pool(bytes32 ilk) external view returns (address) {
        return address(ilks[ilk].pool);
    }

    /**
        @notice Return plan of an ilk
        @param ilk   bytes32 of the D3M ilk
        @return plan address of plan contract
    */
    function plan(bytes32 ilk) external view returns (address) {
        return address(ilks[ilk].plan);
    }

    /**
        @notice Return tau of an ilk
        @param ilk  bytes32 of the D3M ilk
        @return tau sec until debt can be written off
    */
    function tau(bytes32 ilk) external view returns (uint256) {
        return ilks[ilk].tau;
    }

    /**
        @notice Return culled status of an ilk
        @param ilk  bytes32 of the D3M ilk
        @return culled whether or not the d3m has been culled
    */
    function culled(bytes32 ilk) external view returns (uint256) {
        return ilks[ilk].culled;
    }

    /**
        @notice Return tic of an ilk
        @param ilk  bytes32 of the D3M ilk
        @return tic timestamp of when d3m is caged
    */
    function tic(bytes32 ilk) external view returns (uint256) {
        return ilks[ilk].tic;
    }

    /**
        @notice Main function for updating a D3M position.
        Determines the current state and either winds or unwinds as necessary.
        @dev Winding the target position will be constrained by the Ilk debt
        ceiling, the overall DSS debt ceiling and the maximum deposit by the
        pool. Unwinding the target position will be constrained by the number
        of assets available to be withdrawn from the pool.
        @param ilk bytes32 of the D3M ilk name
    */
    function exec(bytes32 ilk) external lock {
        // IMPORTANT: this function assumes Vat rate of D3M ilks will always be == 1 * RAY (no fees).
        // That's why this module converts normalized debt (art) to Vat DAI generated with a simple RAY multiplication or division

        (uint256 Art, uint256 rate, uint256 spot, uint256 line,) = vat.ilks(ilk);
        require(rate == RAY, "D3MHub/rate-not-one");
        require(spot == RAY, "D3MHub/spot-not-one");

        ID3MPool _pool = ilks[ilk].pool;

        _pool.preDebtChange("exec");
        uint256 currentAssets = _pool.assetBalance();

        if (vat.live() == 0) {
            // MCD caged
            require(end.debt() == 0, "D3MHub/end-debt-already-set");
            require(ilks[ilk].culled == 0, "D3MHub/module-has-to-be-unculled-first");
            end.skim(ilk, address(_pool));
            _unwind(
                ilk,
                _pool,
                type(uint256).max,
                Mode.MCD_CAGED,
                currentAssets
            );
        } else if (ilks[ilk].tic != 0 || !ilks[ilk].plan.active()) {
            if (ilks[ilk].culled == 0) {
                _fix(ilk, address(_pool), currentAssets);
            }

            // pool caged
            _unwind(
                ilk,
                _pool,
                type(uint256).max,
                ilks[ilk].culled == 1
                ? Mode.D3M_CULLED
                : Mode.NORMAL,
                currentAssets
            );
        } else {
            Art += _fix(ilk, address(_pool), currentAssets);

            // Determine if it needs to unwind due to debt ceilings
            uint256 lineWad = line / RAY; // Round down to always be under the actual limit
            uint256 Line = vat.Line();
            uint256 debt = vat.debt();
            uint256 toUnwind;
            if (Art > lineWad) {
                unchecked {
                    toUnwind = Art - lineWad;
                }
            }
            if (debt > Line) {
                unchecked {
                    toUnwind = _max(toUnwind, _divup(debt - Line, RAY));
                }
            }

            // Determine if it needs to unwind due plan
            uint256 targetAssets = ilks[ilk].plan.getTargetAssets(currentAssets);
            if (targetAssets < currentAssets) {
                unchecked {
                    toUnwind = _max(toUnwind, currentAssets - targetAssets);
                }
            }

            if (toUnwind > 0) {
                _unwind(
                    ilk,
                    _pool,
                    toUnwind,
                    Mode.NORMAL,
                    currentAssets
                );
            } else {
                uint256 toWind;
                // All the subtractions are safe as otherwise toUnwind is > 0
                unchecked {
                    toWind = _min(
                                _min(
                                    _min(
                                        targetAssets - currentAssets,
                                        lineWad - Art
                                    ),
                                    (Line - debt) / RAY
                                ),
                                _pool.maxDeposit() // Determine if the pool limits our total deposits
                             );
                }
                require(Art + toWind <= MAXINT256, "D3MHub/wind-overflow");
                _wind(ilk, _pool, toWind);
            }
        }

        _pool.postDebtChange("exec");
    }

    /**
        @notice Allow Users to return vat gem for Pool Shares.
        This will only occur during Global Settlement when users receive
        collateral for their Dai.
        @param ilk bytes32 of the D3M ilk name
        @param usr address that should receive the shares from the pool
        @param wad amount of gems that the msg.sender is returning
    */
    function exit(bytes32 ilk, address usr, uint256 wad) external lock {
        require(wad <= MAXINT256, "D3MHub/overflow");
        vat.slip(ilk, msg.sender, -int256(wad));
        ilks[ilk].pool.transfer(usr, wad);
        emit Exit(ilk, usr, wad);
    }

    /**
        @notice Shutdown a pool.
        This starts the countdown to when the debt can be written off (cull).
        Once called, subsequent calls to `exec` will unwind as much of the
        position as possible.
        @dev msg.sender must be authorized.
        @param ilk bytes32 of the D3M ilk name
    */
    function cage(bytes32 ilk) external auth {
        require(vat.live() == 1, "D3MHub/no-cage-during-shutdown");
        require(ilks[ilk].tic == 0, "D3MHub/pool-already-caged");

        ilks[ilk].tic = block.timestamp + ilks[ilk].tau;
        emit Cage(ilk);
    }

    /**
        @notice Write off the debt for a caged pool.
        This must occur while vat is live. Can be triggered by auth or
        after tau number of seconds has passed since the pool was caged.
        @dev This will send the pool's debt to the vow as sin and convert its
        collateral to gems.
        @param ilk bytes32 of the D3M ilk name
    */
    function cull(bytes32 ilk) external {
        require(vat.live() == 1, "D3MHub/no-cull-during-shutdown");

        uint256 _tic = ilks[ilk].tic;
        require(_tic > 0, "D3MHub/pool-live");

        require(_tic <= block.timestamp || wards[msg.sender] == 1, "D3MHub/unauthorized-cull");
        require(ilks[ilk].culled == 0, "D3MHub/already-culled");

        ID3MPool _pool = ilks[ilk].pool;

        (uint256 ink, uint256 art) = vat.urns(ilk, address(_pool));
        require(ink <= MAXINT256, "D3MHub/overflow");
        require(art <= MAXINT256, "D3MHub/overflow");
        vat.grab(ilk, address(_pool), address(_pool), vow, -int256(ink), -int256(art));

        ilks[ilk].culled = 1;
        emit Cull(ilk, ink, art);
    }

    /**
        @notice Rollback Write-off (cull) if General Shutdown happened.
        This function is required to have the collateral back in the vault so it
        can be taken by End module and eventually be shared to DAI holders (as
        any other collateral) or maybe even unwinded.
        @dev This pulls gems from the pool and reopens the urn with the gem
        amount of ink/art.
        @param ilk bytes32 of the D3M ilk name
    */
    function uncull(bytes32 ilk) external {
        ID3MPool _pool = ilks[ilk].pool;

        require(ilks[ilk].culled == 1, "D3MHub/not-prev-culled");
        require(vat.live() == 0, "D3MHub/no-uncull-normal-operation");

        address _vow = vow;
        uint256 wad = vat.gem(ilk, address(_pool));
        require(wad <= MAXINT256, "D3MHub/overflow");
        vat.suck(_vow, _vow, wad * RAY); // This needs to be done to make sure we can deduct sin[vow] and vice in the next call
        vat.grab(ilk, address(_pool), address(_pool), _vow, int256(wad), int256(wad));

        ilks[ilk].culled = 0;
        emit Uncull(ilk, wad);
    }
}
