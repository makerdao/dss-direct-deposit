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

import "./ID3MPool.sol";

interface CanLike {
    function hope(address) external;
    function nope(address) external;
}

interface D3mHubLike {
    function vat() external view returns (address);
}

interface TokenLike {
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

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

contract D3MMapleV1DaiPool is ID3MPool {

    TokenLike public immutable asset; // Dai
    PoolLike  public immutable pool;

    address public king;  // Who gets the rewards

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "D3MAaveDaiPool/not-authorized");
        _;
    }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Collect();
    event File(bytes32 indexed what, address data);

    constructor(address hub_, address dai_, address pool_) public {
        pool  = PoolLike(pool_);
        asset = TokenLike(dai_);

        CanLike(D3mHubLike(hub_).vat()).hope(hub_);

        TokenLike(dai_).approve(pool_, type(uint256).max);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- Admin ---
    function file(bytes32 what, address data) external auth {
        if (what == "king") king = data;
        else revert("D3MMapleV1DaiPool/file-unrecognized-param");
        emit File(what, data);
    }

    function active() external view override returns (bool) {
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
        asset.transfer(msg.sender, asset.balanceOf(address(this)) - preDaiBalance);

        // TODO: Emit withdraw event if we decide to leave it in base
    }

    // --- Collect any rewards ---
    function collect() external {
        // TODO pull MPL rewards and hand them to the king

        emit Collect();
    }

    function transfer(address dst, uint256 amt) external override returns (bool) {
        return pool.transfer(dst, amt);
    }

    function transferAll(address dst) external override returns (bool) {
        return pool.transfer(dst, assetBalance());
    }

    function accrueIfNeeded() external override {}

    function assetBalance() public view override returns (uint256) {
        return pool.balanceOf(address(this)) + pool.withdrawableFundsOf(address(this)) - pool.recognizableLossesOf(address(this));
    }

    function maxWithdraw() external view override returns (uint256) {
        ( uint256 cooldown, uint256 withdrawWindow ) = MapleGlobalsLike(PoolFactoryLike(pool.superFactory()).globals()).getLpCooldownParams();

        bool pastLockup           = pool.depositDate(address(this)) + pool.lockupPeriod() <= block.timestamp;
        bool withinWithdrawWindow = block.timestamp - (pool.withdrawCooldown(address(this)) + cooldown) <= withdrawWindow;  // This condition relies on overflows, so must keep 0.6 or use unchecked

        if (!pastLockup || !withinWithdrawWindow) return uint256(0);

        uint256 totalLiquidity = asset.balanceOf(pool.liquidityLocker());

        return totalLiquidity > assetBalance() ? assetBalance() : totalLiquidity;
    }

    function maxDeposit() external view override returns (uint256) {
        return pool.liquidityCap() - (pool.principalOut() + asset.balanceOf(pool.liquidityLocker()));
    }

    function recoverTokens(address token, address dst, uint256 amt) external override auth returns (bool) {
        return TokenLike(token).transfer(dst, amt);
    }
}
