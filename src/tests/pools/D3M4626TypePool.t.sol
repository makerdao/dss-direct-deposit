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

pragma solidity ^0.8.14;

import "./D3MPoolBase.t.sol";
import "../../pools/D3M4626TypePool.sol";
import {ERC20, ERC4626 as ERC4626Abstract} from "solmate/tokens/ERC4626.sol";

contract ERC4626 is ERC4626Abstract {
    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626Abstract(_asset, _name, _symbol) {}

    function totalAssets() public view virtual override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}

contract D3M4626TypePoolTest is D3MPoolBaseTest {
    
    D3M4626TypePool pool;
    ERC4626 vault;
    bytes32 constant ILK = "TEST-ILK";

    function setUp() public {
        baseInit("D3M4626TypePool");

        vault = new ERC4626(ERC20(address(dai)), "dai vault", "DV");

        setPoolContract(pool = new D3M4626TypePool(address(dai), address(vault), address(hub), ILK));

        pool.file("hub", address(hub));

        dai.approve(address(vault), type(uint256).max);
    }

    function invariant_dai_value() public {
        assertEq(address(pool.dai()), address(dai));
    }

    function invariant_vault_value() public {
        assertEq(address(pool.vault()), address(vault));
    }

    function invariant_vat_value() public {
        assertEq(address(pool.vat()), address(vat));
    }

    function invariant_ilk_value() public {
        assertEq(pool.ilk(), ILK);
    }

    function test_cannot_file_hub_no_auth() public {
        pool.deny(address(this));
        vm.expectRevert("D3M4626TypePool/not-authorized");
        pool.file("hub", address(123));
    }

    function test_deposit_calls_vault_deposit() public {
        deal(address(dai), address(pool), 1);
        vm.prank(address(hub)); pool.deposit(1);
        
        assertEq(pool.assetBalance(), 1);
        assertEq(dai.balanceOf(address(pool)), 0);
    }

    function test_withdraw_calls_vault_withdraw() public {
        deal(address(dai), address(pool), 1);
        vm.prank(address(hub)); pool.deposit(1);
        
        vm.prank(address(hub)); pool.withdraw(1);
        
        assertEq(pool.assetBalance(), 0);
        assertEq(dai.balanceOf(address(hub)), 1);
    }

    function test_withdraw_calls_vault_withdraw_vat_caged() public {
        deal(address(dai), address(pool), 1);
        vm.prank(address(hub)); pool.deposit(1);
        
        vat.cage();
        vm.prank(address(hub)); pool.withdraw(1);

        assertEq(pool.assetBalance(), 0);
        assertEq(dai.balanceOf(address(hub)), 1);
    }

    function test_redeemable_returns_adai() public {
        assertEq(pool.redeemable(), address(vault));
    }

    function test_exit_adai() public {
        deal(address(dai), address(this), 1e18);
        vault.deposit(1e18, address(this));
        uint256 tokens = vault.totalSupply();
        vault.transfer(address(pool), tokens);
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(vault.balanceOf(address(pool)), tokens);

        end.setArt(tokens);
        vm.prank(address(hub)); pool.exit(address(this), tokens);

        assertEq(vault.balanceOf(address(this)), tokens);
        assertEq(vault.balanceOf(address(pool)), 0);
    }

    function test_quit_moves_balance() public {
        deal(address(dai), address(this), 1e18);
        vault.deposit(1e18, address(this));
        vault.transfer(address(pool), vault.balanceOf(address(this)));
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(vault.balanceOf(address(pool)), 1e18);

        pool.quit(address(this));

        assertEq(vault.balanceOf(address(this)), 1e18);
        assertEq(vault.balanceOf(address(pool)), 0);
    }

    function test_assetBalance_gets_adai_balanceOf_pool() public {
        deal(address(dai), address(this), 1e18);
        vault.deposit(1e18, address(this));
        assertEq(pool.assetBalance(), 0);
        assertEq(vault.balanceOf(address(pool)), 0);

        vault.transfer(address(pool), 1e18);

        assertEq(pool.assetBalance(), 1e18);
        assertEq(vault.balanceOf(address(pool)), 1e18);
    }

    function test_maxWithdraw_gets_available_assets_assetBal() public {
        deal(address(dai), address(this), 1e18);
        dai.transfer(address(vault), 1e18);
        assertEq(dai.balanceOf(address(vault)), 1e18);
        assertEq(vault.balanceOf(address(pool)), 0);

        assertEq(pool.maxWithdraw(), 0);
    }

    function test_maxWithdraw_gets_available_assets_daiBal() public {
        deal(address(dai), address(this), 1e18);
        vault.deposit(1e18, address(this));
        vault.transfer(address(pool), 1e18);
        assertEq(dai.balanceOf(address(vault)), 1e18);
        assertEq(vault.balanceOf(address(pool)), 1e18);

        assertEq(pool.maxWithdraw(), 1e18);
    }

    function test_maxDeposit_returns_max_uint() public {
        assertEq(pool.maxDeposit(), type(uint256).max);
    }
}
