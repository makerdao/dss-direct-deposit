// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
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

pragma solidity >=0.8.0;

/**
    @title D3M Pool Interface
    @notice Pool contracts are contracts that the Hub uses to standardize
    interactions with external Pools.
    @dev Implementing contracts will hold any balance provided by the external
    pool as well as the balance in the Vat. This interface aims to use EIP-4626
    guidelines for assets/shares/maxWithdraw etc.
*/
interface ID3MPool {
    /**
        @notice Deposit assets (Dai) in the external pool.
        @dev If the external pool requires a different amount to be passed in, the
        conversion should occur here as the Hub passes Dai [wad] amounts.
        msg.sender must be the hub.
        @param wad amount in asset (Dai) terms that we want to deposit
    */
    function deposit(uint256 wad) external;

    /**
        @notice Withdraw assets (Dai) from the external pool.
        @dev If the external pool requires a different amount to be passed in
        the conversion should occur here as the Hub passes Dai [wad] amounts.
        msg.sender must be the hub.
        @param wad amount in asset (Dai) terms that we want to withdraw
    */
    function withdraw(uint256 wad) external;

     /**
        @notice Exit proportional amount of shares.
        @dev If the external pool/token contract requires a different amount to be
        passed in the conversion should occur here as the Hub passes Gem [wad]
        amounts. msg.sender must be the hub.
        @param dst address that should receive the redeemable tokens
        @param wad amount in Gem terms that we want to withdraw
    */
    function exit(address dst, uint256 wad) external;

    /**
        @notice Transfer all assets from this pool.
        @dev msg.sender must be authorized.
        @param dst address that should receive the assets.
    */
    function quit(address dst) external;

    /**
        @notice Some external pools require actions before debt changes
    */
    function preDebtChange() external;

    /**
        @notice Some external pools require actions after debt changes
    */
    function postDebtChange() external;

    /**
        @notice Balance of assets this pool "owns".
        @dev This could be greater than the amount the pool can withdraw due to
        lack of liquidity.
        @return uint256 number of assets in Dai [wad]
    */
    function assetBalance() external view returns (uint256);

    /**
        @notice Maximum number of assets the pool could deposit at present.
        @return uint256 number of assets in Dai [wad]
    */
    function maxDeposit() external view returns (uint256);

    /**
        @notice Maximum number of assets the pool could withdraw at present.
        @return uint256 number of assets in Dai [wad]
    */
    function maxWithdraw() external view returns (uint256);

    /// @notice returns address of redeemable tokens (if any)
    function redeemable() external view returns (address);
}
