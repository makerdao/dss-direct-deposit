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
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface DaiJoinLike {
    function dai() external view returns (address);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

interface CanLike {
    function hope(address) external;
    function nope(address) external;
}

interface d3mHubLike {
    function vat() external view returns (address);
}

interface DssDirectDepositPlanLike {
    function calcSupplies(uint256, uint256) external view returns (uint256, uint256);
    function maxBar() external view returns (uint256);
}

abstract contract DssDirectDepositPoolBase {
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
        require(wards[msg.sender] == 1, "DssDirectDepositTestJoin/not-authorized");
        _;
    }

    TokenLike   public immutable asset; // Dai
    DaiJoinLike public immutable daiJoin;

    address public immutable hub;
    address public immutable pool;
    address public           share;
    address public           plan; // How we calculate target debt
    uint256 public           bar;  // Target Interest Rate [ray]
    uint256 public           live = 1;


    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    // --- EIP-4626 Events ---
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    constructor(address hub_, address daiJoin_, address pool_) internal {

        pool = pool_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        daiJoin = DaiJoinLike(daiJoin_);
        TokenLike dai_ = asset = TokenLike(DaiJoinLike(daiJoin_).dai());
        dai_.approve(daiJoin_, type(uint256).max);


        hub = hub_;
        wards[hub_] = 1;
        emit Rely(hub_);
        CanLike(d3mHubLike(hub_).vat()).hope(hub_);
    }

    // --- Admin ---
    function file(bytes32 what, uint256 data) external virtual auth {
        if (what == "bar") {
            require(data <= DssDirectDepositPlanLike(plan).maxBar(), "DssDirectDepositTestPool/above-max-interest");

            bar = data;
        }
    }

    function file(bytes32 what, address data) public virtual auth {
        require(live == 1, "DssDirectDepositPoolBase/no-file-not-live");

        if (what == "share") {
            if (share != address(0)) TokenLike(share).approve(hub, 0);
            share = data;
            TokenLike(data).approve(hub, type(uint256).max);
        } else if (what == "plan") plan = data;
    }

    function hope(address dst, address who) external auth {
        CanLike(dst).hope(who);
    }

    function nope(address dst, address who) external auth {
        CanLike(dst).nope(who);
    }

    function validTarget() external view virtual returns (bool);

    function calcSupplies(uint256 availableLiquidity) external view virtual returns (uint256, uint256);

    function deposit(uint256 amt) external virtual;

    function withdraw(uint256 amt) external virtual;

    function collect(address[] memory assets, uint256 amount) external virtual returns (uint256 amt); // should use auth

    function transferShares(address, uint256) external virtual returns(bool);

    function assetBalance() external view virtual returns(uint256);

    function shareBalance() external view virtual returns(uint256);

    function maxWithdraw() external view virtual returns(uint256);

    function convertToShares(uint256 amt) external virtual returns(uint256);

    function convertToAssets(uint256 amt) external virtual returns(uint256);

    function cage() external virtual auth {
        live = 0;
    }
}
