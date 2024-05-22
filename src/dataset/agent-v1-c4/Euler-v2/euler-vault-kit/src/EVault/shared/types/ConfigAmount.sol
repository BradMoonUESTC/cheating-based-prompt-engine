// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ConfigAmount} from "./Types.sol";
import {Errors} from "../Errors.sol";
import "../Constants.sol";

/// @title ConfigAmountLib
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Library for `ConfigAmount` custom type
/// @dev ConfigAmounts are floating point values encoded in 16 bits with a 1e4 precision.
/// @dev The type is used to store protocol configuration values.
library ConfigAmountLib {
    function isZero(ConfigAmount self) internal pure returns (bool) {
        return self.toUint16() == 0;
    }

    function toUint16(ConfigAmount self) internal pure returns (uint16) {
        return ConfigAmount.unwrap(self);
    }
}

function gtConfigAmount(ConfigAmount a, ConfigAmount b) pure returns (bool) {
    return a.toUint16() > b.toUint16();
}

function gteConfigAmount(ConfigAmount a, ConfigAmount b) pure returns (bool) {
    return a.toUint16() >= b.toUint16();
}

function ltConfigAmount(ConfigAmount a, ConfigAmount b) pure returns (bool) {
    return a.toUint16() < b.toUint16();
}

function lteConfigAmount(ConfigAmount a, ConfigAmount b) pure returns (bool) {
    return a.toUint16() <= b.toUint16();
}
