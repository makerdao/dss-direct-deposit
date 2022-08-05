// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.14;

import "./VatMock.sol";
import "./DaiMock.sol";

contract DaiJoinMock {
    VatMock public vat;
    DaiMock public dai;

    constructor(address vat_, address dai_) {
        vat = VatMock(vat_);
        dai = DaiMock(dai_);
    }
    uint256 internal constant RAY = 10 ** 27;
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked{
            require(y == 0 || (z = x * y) / y == x);
        }
    }
    function join(address usr, uint256 wad) external {
        vat.move(address(this), usr, mul(RAY, wad));
        dai.burn(msg.sender, wad);
    }
    function exit(address usr, uint256 wad) external {
        vat.move(msg.sender, address(this), mul(RAY, wad));
        dai.mint(usr, wad);
    }
}
