// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

/// @title IPermit2
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice A minimal interface of the Uniswap's Permit2 contract
interface IPermit2 {
    /// @notice Transfer tokens between two accounts
    /// @param from The account to send the tokens from
    /// @param to The account to send the tokens to
    /// @param amount Amount of tokens to send
    /// @param token Address of the token contract
    function transferFrom(address from, address to, uint160 amount, address token) external;
}
