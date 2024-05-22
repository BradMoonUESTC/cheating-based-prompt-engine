// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../Errors.sol";

/// @title AddressUtils Library
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice The library provides a helper function for checking if provided address is a contract (has code)
library AddressUtils {
    function checkContract(address addr) internal view returns (address) {
        if (addr.code.length == 0) revert Errors.E_BadAddress();

        return addr;
    }
}
