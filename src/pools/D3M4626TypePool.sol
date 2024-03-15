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
import "forge-std/interfaces/IERC4626.sol";

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

contract D3M4626TypePool is ID3MPool {
    /* EVENTS */

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);

    /* CONSTANTS */

    IERC20 public immutable dai;
    IERC4626 public immutable vault;
    VatLike public immutable vat;
    bytes32 public immutable ilk;

    /* STORAGE */

    address public hub;
    uint256 public exited;
    mapping(address => uint256) public wards;

    /* CONSTRUCTOR */

    constructor(address newDai, address newVault, address newHub, bytes32 newIlk) {
        require(newDai != address(0), "D3M4626TypePool/zero-address");
        require(newHub != address(0), "D3M4626TypePool/zero-address");
        require(newVault != address(0), "D3M4626TypePool/zero-address");
        require(newIlk != bytes32(0), "D3M4626TypePool/zero-bytes32");
        require(IERC4626(newVault).asset() == address(newDai), "D3M4626TypePool/vault-asset-is-not-dai");

        dai = IERC20(newDai);
        vault = IERC4626(newVault);
        hub = newHub;
        ilk = newIlk;
        vat = VatLike(D3mHubLike(hub).vat());

        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        dai.approve(address(vault), type(uint256).max);
    }

    /* MODIFIERS */

    modifier onlyHub() {
        require(msg.sender == address(hub), "D3M4626TypePool/only-hub");
        _;
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "D3M4626TypePool/not-authorized");
        _;
    }

    /* ONLY HUB */

    /// @inheritdoc ID3MPool
    function deposit(uint256 assets) external override onlyHub {
        vault.deposit(assets, address(this));
    }

    /// @inheritdoc ID3MPool
    function withdraw(uint256 assets) external override onlyHub {
        vault.withdraw(assets, msg.sender, address(this));
    }

    /// @inheritdoc ID3MPool
    function exit(address dst, uint256 wad) external override onlyHub {
        uint256 exited_ = exited;
        exited = exited_ + wad;
        uint256 amt = wad * vault.balanceOf(address(this)) / (D3mHubLike(hub).end().Art(ilk) - exited_);
        require(vault.transfer(dst, amt), "D3M4626TypePool/transfer-failed");
    }

    /* ONLY AUTHORIZED */

    /// @inheritdoc ID3MPool
    function quit(address dst) external auth {
        require(vat.live() == 1, "D3M4626TypePool/no-quit-during-shutdown");
        require(vault.transfer(dst, vault.balanceOf(address(this))), "D3M4626TypePool/transfer-failed");
    }

    function rely(address usr) public auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, address data) external auth {
        require(vat.live() == 1, "D3M4626TypePool/no-file-during-shutdown");
        if (what == "hub") {
            vat.nope(hub);
            hub = data;
            vat.hope(data);
        } else revert("D3M4626TypePool/file-unrecognized-param");
        emit File(what, data);
    }

    /* EXTERNAL */

    /// @inheritdoc ID3MPool
    function preDebtChange() external override {}

    /// @inheritdoc ID3MPool
    function postDebtChange() external override {}

    /// @inheritdoc ID3MPool
    function assetBalance() external view returns (uint256) {
        return vault.convertToAssets(vault.balanceOf(address(this)));
    }

    /// @inheritdoc ID3MPool
    function maxDeposit() external view returns (uint256) {
        return vault.maxDeposit(address(this));
    }

    /// @inheritdoc ID3MPool
    function maxWithdraw() external view returns (uint256) {
        return vault.maxWithdraw(address(this));
    }

    /// @inheritdoc ID3MPool
    function redeemable() external view returns (address) {
        return address(vault);
    }
}
