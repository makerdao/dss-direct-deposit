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

import "./DssDirectDepositTestGem.sol";

interface RewardsClaimerLike {
    function claimRewards(address[] memory assets, uint256 amount, address to) external returns (uint256);
}

interface d3mJoinLike {
    function vat() external view returns (address);
    function gem() external view returns (address);
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

contract DssDirectDepositTestPool {
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

    RewardsClaimerLike public immutable rewardsClaimer;
    TokenLike          public immutable dai;
    DaiJoinLike        public immutable daiJoin;

    address public immutable hub;
    address public immutable pool;
    address public           gem;

    // test helper variables
    uint256 maxBar;
    uint256 supplyAmount;
    uint256 targetSupply;

    bool    isValidTarget;

    uint256 public live = 1;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    constructor(address hub_, address daiJoin_, address pool_, address _rewardsClaimer) public {

        pool = pool_;
        rewardsClaimer = RewardsClaimerLike(_rewardsClaimer);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        daiJoin = DaiJoinLike(daiJoin_);
        TokenLike dai_ = dai = TokenLike(DaiJoinLike(daiJoin_).dai());
        dai_.approve(daiJoin_, type(uint256).max);


        hub = hub_;
        wards[hub_] = 1;
        emit Rely(hub_);
        CanLike(d3mJoinLike(hub_).vat()).hope(hub_);
    }

    // --- Testing Admin ---
    function file(bytes32 what, uint256 data) external auth {
        if (what == "maxBar") {
            maxBar = data;
        } else if (what == "supplyAmount") {
            supplyAmount = data;
        } else if (what == "targetSupply") {
            targetSupply = data;
        }
    }

    function file(bytes32 what, bool data) external auth {
        if (what == "isValidTarget") {
            isValidTarget = data;
        }
    }

    function file(bytes32 what, address data) external auth {
        if (what == "gem") {
            if (gem != address(0)) TokenLike(gem).approve(hub, 0);
            gem = data;
            TokenLike(data).approve(hub, type(uint256).max);
        }
    }

    // --- Admin ---
    function hope(address dst, address who) external auth {
        CanLike(dst).hope(who);
    }

    function nope(address dst, address who) external auth {
        CanLike(dst).nope(who);
    }

    function getMaxBar() external view returns (uint256) {
        return maxBar;
    }

    function validTarget() external view returns (bool) {
        return isValidTarget;
    }

    function calcSupplies(uint256 availableLiquidity, uint256 bar) external view returns (uint256, uint256) {
        availableLiquidity;

        return (supplyAmount, bar > 0 ? targetSupply : 0);
    }

    function supply(uint256 amt) external {
        daiJoin.exit(address(this), amt);
        DssDirectDepositTestGem(gem).mint(address(this), amt);
        TokenLike(dai).transfer(gem, amt);
    }

    function withdraw(uint256 amt) external {
        DssDirectDepositTestGem(gem).burn(address(this), amt);
        TokenLike(dai).transferFrom(gem, address(this), amt);
        daiJoin.join(address(this), amt);
    }

    function collect(address[] memory assets, uint256 amount, address dst) external auth returns (uint256 amt) {
        amt = rewardsClaimer.claimRewards(assets, amount, dst);
    }

    function gemBalanceOf() external view returns(uint256) {
        return TokenLike(gem).balanceOf(address(this));
    }

    function getNormalizedBalanceOf() external view returns(uint256) {
        return TokenLike(gem).balanceOf(address(this));
    }

    function getNormalizedAmount(uint256 amt) external pure returns(uint256) {
        return amt;
    }

    function cage() external auth {
        live = 0;
    }

}
