// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {MintableBaseToken} from "./MintableBaseToken.sol";

contract ULP is MintableBaseToken {
    constructor() MintableBaseToken("Universal LP", "ULP", 0) {}

    function id() external pure returns (string memory _name) {
        return "ULP";
    }
}
