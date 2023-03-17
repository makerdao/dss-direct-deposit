// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
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

import "./ID3MPlan.sol";

interface VatLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
}

/**
 *  @title D3M ALM Controller V1
 *  @notice Allocates/liquidates debt to multiple investment vehicles to enforce a fixed buffer on a particular ilk.
 */
contract D3MALMControllerV1Plan is ID3MPlan {

    mapping (address => uint256) public wards;

    VatLike public immutable vat;
    bytes32 public immutable ilk;

    uint256 constant RAY = 10 ** 27;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);

    constructor(address vat_, bytes32 ilk_) {
        vat = VatLike(vat_);
        ilk = ilk_;
        
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "D3MDebtCeilingPlan/not-authorized");
        _;
    }

    // --- Admin ---
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "enabled") {
            require(data <= 1, "D3MDebtCeilingPlan/invalid-value");
            enabled = data;
        } else revert("D3MDebtCeilingPlan/file-unrecognized-param");
        emit File(what, data);
    }

    function getTargetAssets(uint256) external override view returns (uint256) {
        (,,, uint256 line,) = vat.ilks(ilk);
        return line / RAY;
    }

    function active() public view override returns (bool) {
        if (enabled == 0) return false;
        (,,, uint256 line,) = vat.ilks(ilk);
        return line > 0;
    }

    function disable() external override auth {
        enabled = 0;
        emit Disable();
    }
}
