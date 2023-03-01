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

pragma solidity ^0.8.0;

import { D3MDeployBase, D3MDeploy } from "./D3MDeployBase.s.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";

contract D3MDeployAaveV2Script is D3MDeployBase {
    using stdJson for string;
    using ScriptTools for string;

    function run() external {
        _setup();

        vm.startBroadcast();

        d3m = D3MDeploy.deployAave(
            msg.sender,
            admin,
            ilk,
            address(dss.vat),
            hub,
            address(dss.dai),
            config.readAddress("lendingPool")
        );

        vm.stopBroadcast();

        _export();
    }
}
