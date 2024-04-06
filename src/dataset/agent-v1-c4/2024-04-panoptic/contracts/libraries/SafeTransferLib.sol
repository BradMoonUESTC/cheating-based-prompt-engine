// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// Libraries
import {Errors} from "@libraries/Errors.sol";

/// @notice Safe ERC20 transfer library that gracefully handles missing return values.
/// @author Axicon Labs Limited
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/SafeTransferLib.sol)
/// @dev Caution! This library won't check that a token has code, responsibility is delegated to the caller.
library SafeTransferLib {
    /*//////////////////////////////////////////////////////////////
                            ERC20 OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Safely transfers ERC20 tokens from one address to another.
    /// @param token The address of the ERC20 token
    /// @param from The address to transfer tokens from
    /// @param to The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        bool success;

        assembly ("memory-safe") {
            // Get free memory pointer - we will store our calldata in scratch space starting at the offset specified here.
            let p := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(p, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(add(4, p), from) // Append the "from" argument.
            mstore(add(36, p), to) // Append the "to" argument.
            mstore(add(68, p), amount) // Append the "amount" argument.

            success := and(
                // Set success to whether the call reverted, if not we check it either
                // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                // We use 100 because that's the total length of our calldata (4 + 32 * 3)
                // Counterintuitively, this call() must be positioned after the or() in the
                // surrounding and() because and() evaluates its arguments from right to left.
                call(gas(), token, 0, p, 100, 0, 32)
            )
        }

        if (!success) revert Errors.TransferFailed();
    }

    /// @notice Safely transfers ERC20 tokens to a specified address.
    /// @param token The address of the ERC20 token
    /// @param to The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    function safeTransfer(address token, address to, uint256 amount) internal {
        bool success;

        assembly ("memory-safe") {
            // Get free memory pointer - we will store our calldata in scratch space starting at the offset specified here.
            let p := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(p, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(4, p), to) // Append the "to" argument.
            mstore(add(36, p), amount) // Append the "amount" argument.

            success := and(
                // Set success to whether the call reverted, if not we check it either
                // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                // We use 68 because that's the total length of our calldata (4 + 32 * 2)
                // Counterintuitively, this call() must be positioned after the or() in the
                // surrounding and() because and() evaluates its arguments from right to left.
                call(gas(), token, 0, p, 68, 0, 32)
            )
        }

        if (!success) revert Errors.TransferFailed();
    }
}
