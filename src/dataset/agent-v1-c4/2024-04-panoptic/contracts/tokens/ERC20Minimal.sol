// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Minimal efficient ERC20 implementation without metadata
/// @author Axicon Labs Limited
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/v7/src/tokens/ERC20.sol)
/// @dev The metadata must be set in the inheriting contract.
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
abstract contract ERC20Minimal {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when tokens are transferred
    /// @param from The sender of the tokens
    /// @param to The recipient of the tokens
    /// @param amount The amount of tokens transferred
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when a user approves another user to spend tokens on their behalf
    /// @param owner The user who approved the spender
    /// @param spender The user who was approved to spend tokens
    /// @param amount The amount of tokens approved to spend
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The total supply of tokens.
    /// @dev This cannot exceed the max uint256 value.
    uint256 public totalSupply;

    /// @notice Token balances for each user
    mapping(address account => uint256 balance) public balanceOf;

    /// @notice Stored allowances for each user.
    /// @dev Indexed by owner, then by spender.
    mapping(address owner => mapping(address spender => uint256 allowance)) public allowance;

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Approves a user to spend tokens on the caller's behalf.
    /// @param spender The user to approve
    /// @param amount The amount of tokens to approve
    /// @return Whether the approval succeeded
    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    /// @notice Transfers tokens from the caller to another user.
    /// @param to The user to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return Whether the transfer succeeded
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    /// @notice Transfers tokens from one user to another.
    /// @dev Supports token approvals.
    /// @param from The user to transfer tokens from
    /// @param to The user to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return Whether the transfer succeeded
    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /// @notice Internal utility to transfer tokens from one user to another.
    /// @param from The user to transfer tokens from
    /// @param to The user to transfer tokens to
    /// @param amount The amount of tokens to transfer
    function _transferFrom(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal utility to mint tokens to a user's account.
    /// @param to The user to mint tokens to
    /// @param amount The amount of tokens to mint
    function _mint(address to, uint256 amount) internal {
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }
        totalSupply += amount;

        emit Transfer(address(0), to, amount);
    }

    /// @notice Internal utility to burn tokens from a user's account.
    /// @param from The user to burn tokens from
    /// @param amount The amount of tokens to burn
    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }
}
