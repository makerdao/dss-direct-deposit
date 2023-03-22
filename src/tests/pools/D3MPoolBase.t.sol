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
        hub = new HubMock(address(vat));
        dai = new TokenMock(18);
        end = new EndMock();
        contractName = _contractName;
    }

    function setPoolContract(ID3MPool _pool) internal {
        pool = _pool;
    }

    function test_auth() public {
        checkAuth(address(pool), contractName);
    }

    function test_file_hub() public {
        checkFileUint(address(pool), contractName, ["hub"]);
    }

    function test_file_hub_vat_hoped() public {
        assertEq(vat.can(address(pool), address(hub)), 1);
        assertEq(vat.can(address(pool), TEST_ADDRESS), 0);
        FileLike(address(pool)).file("hub", TEST_ADDRESS);
        assertEq(vat.can(address(pool), address(hub)), 0);
        assertEq(vat.can(address(pool), TEST_ADDRESS), 1);
    }

    function test_sets_creator_as_ward() public {
        assertEq(WardsAbstract(address(pool)).wards(address(this)), 1);
    }

    function test_auth_modifier() public {
        WardsAbstract(address(pool)).deny(address(this));

        bytes[] memory funcs = new bytes[](2);
        funcs[0] = abi.encodeWithSelector(ID3MPool.exit.selector, 0, 0, 0);
        funcs[1] = abi.encodeWithSelector(ID3MPool.quit.selector, 0, 0, 0);

        for (uint256 i = 0; i < funcs.length; i++) {
            assertRevert(address(pool), funcs[i], abi.encodePacked(contractName, "/not-authorized"));
        }
    }

    function test_onlyHub_modifier() public {
        bytes[] memory funcs = new bytes[](3);
        funcs[0] = abi.encodeWithSelector(ID3MPool.deposit.selector, 0, 0, 0);
        funcs[1] = abi.encodeWithSelector(ID3MPool.withdraw.selector, 0, 0, 0);
        funcs[2] = abi.encodeWithSelector(ID3MPool.exit.selector, 0, 0, 0);

        for (uint256 i = 0; i < funcs.length; i++) {
            assertRevert(address(pool), funcs[i], abi.encodePacked(contractName, "/only-hub"));
        }
    }

    function test_quit_vat_caged() public {
        vat.cage();
        vm.expectRevert(abi.encodePacked(contractName, "/no-quit-during-shutdown"));
        pool.quit(address(this));
    }

    function test_exit() public {
        TokenMock redeemableToken = TokenMock(pool.redeemable());
        redeemableToken.mint(address(pool), 1000 ether);
        end.setArt(100 ether);

        assertEq(redeemableToken.balanceOf(TEST_ADDRESS), 0);
        assertEq(redeemableToken.balanceOf(address(pool)), 1000 ether);
        assertEq(ExitLike(address(pool)).exited(), 0);

        vm.prank(address(hub)); pool.exit(TEST_ADDRESS, 10 ether);  // Exit 10%

        assertEq(redeemableToken.balanceOf(TEST_ADDRESS), 100 ether);
        assertEq(redeemableToken.balanceOf(address(pool)), 900 ether);
        assertEq(ExitLike(address(pool)).exited(), 10 ether);

        vm.prank(address(hub)); pool.exit(TEST_ADDRESS, 20 ether);  // Exit another 20%

        assertEq(redeemableToken.balanceOf(TEST_ADDRESS), 300 ether);
        assertEq(redeemableToken.balanceOf(address(pool)), 700 ether);
        assertEq(ExitLike(address(pool)).exited(), 30 ether);
    }

}
