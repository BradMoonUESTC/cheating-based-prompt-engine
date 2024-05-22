// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Errors} from "./shared/Errors.sol";
import {Events} from "./shared/Events.sol";
import {IERC20, IEVault} from "./IEVault.sol";

/// @title DToken
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Contract implements read only ERC20 interface, and `Transfer` events, for EVault's debt
contract DToken is IERC20, Errors, Events {
    /// @notice The address of the EVault associated with this DToken
    address public immutable eVault;

    constructor() {
        eVault = msg.sender;
    }

    // ERC20 interface

    /// @notice The debt token (dToken) name
    /// @return The dToken name
    function name() external view returns (string memory) {
        return string.concat("Debt token of ", IEVault(eVault).name());
    }

    /// @notice The debt token (dToken) symbol
    /// @return The dToken symbol
    function symbol() external view returns (string memory) {
        return string.concat(IEVault(eVault).symbol(), "-DEBT");
    }

    /// @notice Decimals of the dToken, same as EVault's
    /// @return The dToken decimals
    function decimals() external view returns (uint8) {
        return IEVault(eVault).decimals();
    }

    /// @notice Return total supply of the DToken
    /// @return The dToken total supply
    function totalSupply() external view returns (uint256) {
        return IEVault(eVault).totalBorrows();
    }

    /// @notice Balance of a particular account, in dTokens
    /// @param owner The account to query
    /// @return The balance of the account
    function balanceOf(address owner) external view returns (uint256) {
        return IEVault(eVault).debtOf(owner);
    }

    /// @notice Retrieve the current allowance
    /// @return The allowance
    /// @dev Approvals are not supported by the dToken
    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    /// @notice Function required by the ERC20 interface
    /// @dev Approvals are not supported by the DToken
    function approve(address, uint256) external pure returns (bool) {
        revert E_NotSupported();
    }

    /// @notice Function required by the ERC20 interface
    /// @dev Transfers are not supported by the DToken directly
    function transfer(address, uint256) external pure returns (bool) {
        revert E_NotSupported();
    }

    /// @notice Function required by the ERC20 interface
    /// @dev Transfers are not supported by the DToken directly
    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert E_NotSupported();
    }

    // Events

    /// @notice Emit an ERC20 Transfer event
    /// @dev Only callable by the parent EVault
    function emitTransfer(address from, address to, uint256 value) external {
        if (msg.sender != eVault) revert E_Unauthorized();

        emit Transfer(from, to, value);
    }

    // Helpers

    /// @notice Return the address of the asset the debt is denominated in
    function asset() external view returns (address) {
        return IEVault(eVault).asset();
    }
}
