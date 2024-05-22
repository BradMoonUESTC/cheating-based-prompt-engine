// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Flags} from "./Types.sol";

/// @title FlagsLib
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Library for `Flags` custom type
library FlagsLib {
    /// @dev Are *all* of the flags in bitMask set?
    function isSet(Flags self, uint32 bitMask) internal pure returns (bool) {
        return (Flags.unwrap(self) & bitMask) == bitMask;
    }

    /// @dev Are *none* of the flags in bitMask set?
    function isNotSet(Flags self, uint32 bitMask) internal pure returns (bool) {
        return (Flags.unwrap(self) & bitMask) == 0;
    }

    function toUint32(Flags self) internal pure returns (uint32) {
        return Flags.unwrap(self);
    }
}
