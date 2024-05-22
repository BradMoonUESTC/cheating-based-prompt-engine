// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

contract MockWrongEVC {
    function EVC() external pure returns (address) {
        return address(420);
    }
}
