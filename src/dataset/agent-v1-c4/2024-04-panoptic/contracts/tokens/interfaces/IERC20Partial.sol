// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Partial definition of the ERC20 interface as defined in the EIP
/// @dev Does not include return values as certain tokens such as USDT fail to implement them.
/// @dev Since the return value is not expected, this interface works with both compliant and non-compliant tokens.
/// @dev Clients are recommended to consume and handle the return of negative success values.
/// @dev However, we cannot productively handle a failed approval and such a situation would surely cause a revert later in execution.
/// @dev In addition, no notable instances exist of tokens that both i) contain a failure case for `approve` and ii) return `false` instead of reverting.
/// @author Axicon Labs Limited
interface IERC20Partial {
    /// @notice Returns the amount of tokens owned by `account`.
    /// @dev This function is unchanged from the EIP
    /// @param account The address to query the balance of
    /// @return The amount of tokens owned by `account`
    function balanceOf(address account) external view returns (uint256);

    /// @notice Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @dev While this function is specified to return a boolean value in the EIP, this interface does not expect one
    /// @param spender The address which will spend the funds
    /// @param amount The amount of tokens allowed to be spent
    function approve(address spender, uint256 amount) external;

    /// @notice Transfers tokens from the caller to another user.
    /// @param to The user to transfer tokens to
    /// @param amount The amount of tokens to transfer
    function transfer(address to, uint256 amount) external;
}
