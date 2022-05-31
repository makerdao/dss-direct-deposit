// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2022 Dai Foundation
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

interface AuthLike {
    function wards(address) external view returns (uint256);
}

interface TokenLike {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface DaiLike is TokenLike {
    function allowance(address, address) external returns (uint256);
} // declared for dai-specific expansions

interface DaiJoinLike {
    function join(address, uint256) external;
}

interface EndLike {
    function wait() external view returns (uint256);
    function cage() external;
    function cage(bytes32) external;
    function skim(bytes32, address) external;
    function thaw() external;
}

interface SpotLike {
    function file(bytes32, bytes32, address) external;
    function file(bytes32, bytes32, uint256) external;
    function poke(bytes32) external;
}

interface VatLike {
    function debt() external view returns (uint256);
    function rely(address) external;
    function hope(address) external;
    function urns(bytes32, address) external view returns (uint256, uint256);
    function gem(bytes32, address) external view returns (uint256);
    function dai(address) external view returns (uint256);
    function sin(address) external view returns (uint256);
    function Line() external view returns (uint256);
    function init(bytes32) external;
    function file(bytes32, uint256) external;
    function file(bytes32, bytes32, uint256) external;
    function cage() external;
    function frob(bytes32, address, address, address, int256, int256) external;
    function grab(bytes32, address, address, address, int256, int256) external;
}

interface VowLike {
    function flapper() external view returns (address);
    function Sin() external view returns (uint256);
    function Ash() external view returns (uint256);
    function heal(uint256) external;
}

interface CanLike {
    function hope(address) external;
    function nope(address) external;
}

interface d3mHubLike {
    function vat() external view returns (address);
}

/*************/
/*** Maple ***/
/*************/

interface BPoolFactoryLike {
    function newBPool() external returns (address);
}

interface BPoolLike {
    function balanceOf(address) external view returns (uint256);
    function bind(address, uint256, uint256) external;
    function finalize() external;
    function getSpotPrice(address, address) external returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

interface ERC20Like {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function totalSupply() external view returns (uint256);
}

interface LoanFactoryLike {
    function createLoan(address, address, address, address, uint256[5] memory, address[3] memory) external returns (address);
}

interface LoanLike {
    function collateralRequiredForDrawdown(uint256) external view returns (uint256);
    function drawdown(uint256) external;
    function getNextPayment() external returns (uint256, uint256, uint256);
    function nextPaymentDue() external returns (uint256);
    function makePayment() external;
}

interface MapleGlobalsLike {
    function setLiquidityAsset(address, bool) external;
    function setCollateralAsset(address, bool) external;
    function setPoolDelegateAllowlist(address, bool) external;
    function setPriceOracle(address, address) external;
    function setValidBalancerPool(address, bool) external;
}

interface MaplePoolFactoryLike {
    function createPool(address, address, address, address, uint256, uint256, uint256) external returns (address);
}

interface MaplePoolLike {
    function balanceOf(address) external view returns (uint256);
    function claim(address, address) external returns (uint256[7] memory);
    function getInitialStakeRequirements() external view returns (uint256, uint256, bool, uint256, uint256);
    function getPoolSharesRequired(address, address, address, address, uint256) external view returns(uint256, uint256);
    function finalize() external;
    function fundLoan(address, address, uint256) external;
    function liquidityLocker() external view returns (address);
    function stakeLocker() external returns (address);
    function setAllowList(address, bool) external;
    function superFactory() external view returns (address);
    function withdrawableFundsOf(address) external view returns (uint256);
    function withdrawCooldown(address) external view returns (uint256);
}

interface StakeLockerLike {
    function stake(uint256) external;
}
