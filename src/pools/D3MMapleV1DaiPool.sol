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

import "./D3MPoolBase.sol";

interface PoolLike is TokenLike {
    function deposit(uint256 amount) external;
    function intendToWithdraw() external;
    function liquidityCap() external view returns (uint256);
    function liquidityLocker() external view returns (address);
    function principalOut() external view returns (uint256);
    function superFactory() external view returns (address);
    function withdraw(uint256) external;
    function withdrawCooldown(address) external view returns (uint256);
    function withdrawFunds() external;
    function withdrawableFundsOf(address) external view returns (uint256);
}

contract D3MMapleV1DaiPool is D3MPoolBase {

    PoolLike public immutable pool;

    address public king;    // Who gets the rewards

    constructor(address hub_, address dai_, address pool_) public D3MPoolBase(hub_, dai_) {
        pool = PoolLike(pool_);

        TokenLike(dai_).approve(pool_, type(uint256).max);
    }

    // --- Admin ---
    function file(bytes32 what, address data) external auth {
        require(live == 1, "D3MMapleV1DaiPool/no-file-not-live");

        if (what == "king") king = data;
        else revert("D3MMapleV1DaiPool/file-unrecognized-param");
        emit File(what, data);
    }

    function validTarget() external view override returns (bool) {
        return true;
    }

    function deposit(uint256 amt) external override auth {
        // TODO confirm deposit is in units of DAI
        pool.deposit(amt);
        // TODO: emit deposit event if we decide to leave it in base
    }

    function withdraw(uint256 amt) external override auth {
        // TODO confirm withdraw is in units of DAI
        pool.withdraw(amt);
        asset.transfer(hub, amt);
        // TODO: emit withdraw event if we decide to leave it in base
    }

    // --- Collect any rewards ---
    function collect() external {
        // TODO pull MPL rewards and hand them to the king
    }

    function transfer(address dst, uint256 amt) external override returns (bool) {
        return pool.transfer(dst, amt);
    }

    function assetBalance() external view override returns (uint256) {
        // TODO return the total position size in units of underlying asset (DAI)
    }

    function shareBalance() public view override returns (uint256) {
        return pool.balanceOf(address(this));
    }

    function maxWithdraw() external view override returns (uint256) {
        // TODO what is the maximum available for withdraw in underlying asset (DAI)
        // Should take into account anything that blocks this from happening (cooldowns, liquidity, etc)
    }

    function convertToShares(uint256 amt) external view override returns (uint256) {
        // TODO convert amt in units of DAI to the shares in the pool
    }
}
