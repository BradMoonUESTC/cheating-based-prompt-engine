// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.23;

contract MockDecimals {
    uint8 public decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }
}
