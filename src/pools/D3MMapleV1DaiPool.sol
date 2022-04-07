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

import "../bases/D3MPoolBase.sol";

interface PoolLike is TokenLike {
    function deposit(uint256 amount) external;
    function depositDate(address) external view returns (uint256);
    function intendToWithdraw() external;
    function liquidityCap() external view returns (uint256);
    function liquidityLocker() external view returns (address);
    function lockupPeriod() external view returns (uint256);
    function principalOut() external view returns (uint256);
    function recognizableLossesOf(address) external view returns (uint256);
    function superFactory() external view returns (address);
    function withdraw(uint256) external;
    function withdrawCooldown(address) external view returns (uint256);
    function withdrawFunds() external;
    function withdrawableFundsOf(address) external view returns (uint256);
}

interface PoolFactoryLike {
    function globals() external view returns (address);
}

interface MapleGlobalsLike {
    function getLpCooldownParams() external view returns (uint256, uint256);
}

contract D3MMapleV1DaiPool is D3MPoolBase {

    PoolLike public immutable pool;

    address public king;  // Who gets the rewards

    constructor(address hub_, address dai_, address pool_) public D3MPoolBase(hub_, dai_) {
        pool = PoolLike(pool_);

        TokenLike(dai_).approve(pool_, type(uint256).max);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Admin ---
    function file(bytes32 what, address data) public override auth {
        require(live == 1, "D3MMapleV1DaiPool/no-file-not-live");

        if (what == "king") king = data;
        else super.file(what, data);
    }

    function validTarget() external view override returns (bool) {
        return true;
    }

    function deposit(uint256 amt) external override auth {
        pool.deposit(amt);  // Deposit DAI, recieve LP tokens 1-to-1

        // TODO: Emit deposit event if we decide to leave it in base
    }

    function withdraw(uint256 amt) external override auth {
        // `withdraw` claims interest and recognizes any losses, so use DAI balance change to transfer to hub.
        uint256 preDaiBalance = asset.balanceOf(address(this));
        pool.withdraw(amt);
        asset.transfer(hub, asset.balanceOf(address(this)) - preDaiBalance);

        // TODO: Emit withdraw event if we decide to leave it in base
    }

    // --- Collect any rewards ---
    function collect() external auth {
        // TODO pull MPL rewards and hand them to the king
    }

    function transferShares(address dst, uint256 amt) external override returns (bool) {
        return pool.transfer(dst, amt);
    }

    function assetBalance() public view override returns (uint256) {
        return shareBalance() + pool.withdrawableFundsOf(address(this)) + pool.recognizableLossesOf(address(this));
    }

    function shareBalance() public view override returns (uint256) {
        return pool.balanceOf(address(this));
    }

    function maxWithdraw() external view override returns (uint256) {
        ( uint256 cooldown, uint256 withdrawWindow ) = MapleGlobalsLike(PoolFactoryLike(pool.superFactory()).globals()).getLpCooldownParams();

        bool pastLockup           = pool.depositDate(address(this)) + pool.lockupPeriod() <= block.timestamp;
        bool withinWithdrawWindow = block.timestamp - (pool.withdrawCooldown(address(this)) + cooldown) <= withdrawWindow;  // This condition relies on overflows, so must keep 0.6 or use unchecked

        if (!pastLockup || !withinWithdrawWindow) return uint256(0);

        uint256 totalLiquidity = asset.balanceOf(pool.liquidityLocker());

        return totalLiquidity > assetBalance() ? assetBalance() : totalLiquidity;
    }

    function convertToShares(uint256 amt) external view override returns (uint256) {
        // TODO convert amt in units of DAI to the shares in the pool
    }
}
