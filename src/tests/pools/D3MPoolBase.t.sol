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

import "dss-test/DssTest.sol";
import "dss-interfaces/Interfaces.sol";

import { ID3MPool } from"../../pools/ID3MPool.sol";

import { VatMock } from "../mocks/VatMock.sol";
import { HubMock } from "../mocks/HubMock.sol";
import { TokenMock } from "../mocks/TokenMock.sol";
import { EndMock } from "../mocks/EndMock.sol";

interface ExitLike {
    function exited() external view returns (uint256);
}

// Specification checks for all D3M pools
abstract contract D3MPoolBaseTest is DssTest {

    VatMock public vat;
    HubMock public hub;
    TokenMock public dai;
    EndMock public end;
    string public contractName;

    ID3MPool private pool;      // Override with stronger type in child contract

    function baseInit(string memory _contractName) internal {
        vat = new VatMock();
        end = new EndMock();
        hub = new HubMock(address(vat), address(end));
        dai = new TokenMock(18);
        contractName = _contractName;
    }

    function setPoolContract(ID3MPool _pool) internal {
        pool = _pool;
    }

    function test_auth() public virtual {
        checkAuth(address(pool), contractName);
    }

    function test_file_hub() public virtual {
        checkFileAddress(address(pool), contractName, ["hub"]);
    }

    function test_file_hub_vat_hoped() public virtual {
        assertEq(vat.can(address(pool), address(hub)), 1);
        assertEq(vat.can(address(pool), TEST_ADDRESS), 0);
        FileLike(address(pool)).file("hub", TEST_ADDRESS);
        assertEq(vat.can(address(pool), address(hub)), 0);
        assertEq(vat.can(address(pool), TEST_ADDRESS), 1);
    }

    function test_sets_creator_as_ward() public virtual {
        assertEq(WardsAbstract(address(pool)).wards(address(this)), 1);
    }

    function test_auth_modifier() public virtual {
        WardsAbstract(address(pool)).deny(address(this));

        checkModifier(address(pool), string(abi.encodePacked(contractName, "/not-authorized")), [
            ID3MPool.quit.selector
        ]);
    }

    function test_onlyHub_modifier() public virtual {
        checkModifier(address(pool), string(abi.encodePacked(contractName, "/only-hub")), [
            ID3MPool.deposit.selector,
            ID3MPool.withdraw.selector,
            ID3MPool.exit.selector
        ]);
    }

    function test_cannot_file_hub_vat_caged() public {
        vat.cage();

        vm.expectRevert(abi.encodePacked(contractName, "/no-file-during-shutdown"));
        FileLike(address(pool)).file("hub", TEST_ADDRESS);
    }

    function test_quit_vat_caged() public virtual {
        vat.cage();
        vm.expectRevert(abi.encodePacked(contractName, "/no-quit-during-shutdown"));
        pool.quit(address(this));
    }

    function test_exit() public virtual {
        TokenMock redeemableToken = TokenMock(pool.redeemable());
        GodMode.setBalance(address(dai), address(pool), 1000 ether);
        vm.prank(address(hub)); pool.deposit(1000 ether);
        uint256 initialBalance = redeemableToken.balanceOf(address(pool));
        end.setArt(100 ether);

        assertEq(redeemableToken.balanceOf(TEST_ADDRESS), 0);
        assertEq(ExitLike(address(pool)).exited(), 0);

        vm.prank(address(hub)); pool.exit(TEST_ADDRESS, 10 ether);  // Exit 10%

        assertApproxEqAbs(redeemableToken.balanceOf(TEST_ADDRESS), initialBalance * 10 / 100, 10);
        assertApproxEqAbs(redeemableToken.balanceOf(address(pool)), initialBalance * 90 / 100, 10);
        assertEq(ExitLike(address(pool)).exited(), 10 ether);

        vm.prank(address(hub)); pool.exit(TEST_ADDRESS, 20 ether);  // Exit another 20%

        assertApproxEqAbs(redeemableToken.balanceOf(TEST_ADDRESS), initialBalance * 30 / 100, 10);
        assertApproxEqAbs(redeemableToken.balanceOf(address(pool)), initialBalance * 70 / 100, 10);
        assertEq(ExitLike(address(pool)).exited(), 30 ether);
    }

}
