// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

/// @title Events
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This contract implements the events for the Ethereum Vault Connector.
contract Events {
    /// @notice Emitted when an owner is registered for an address prefix.
    /// @param addressPrefix The address prefix for which the owner is registered.
    /// @param owner The address of the owner registered.
    event OwnerRegistered(bytes19 indexed addressPrefix, address indexed owner);

    /// @notice Emitted when the lockdown mode status is changed for an address prefix.
    /// @param addressPrefix The address prefix for which the lockdown mode status is changed.
    /// @param enabled True if the lockdown mode is enabled, false otherwise.
    event LockdownModeStatus(bytes19 indexed addressPrefix, bool enabled);

    /// @notice Emitted when the permit disabled mode status is changed for an address prefix.
    /// @param addressPrefix The address prefix for which the permit disabled mode status is changed.
    /// @param enabled True if the permit disabled mode is enabled, false otherwise.
    event PermitDisabledModeStatus(bytes19 indexed addressPrefix, bool enabled);

    /// @notice Emitted when the nonce status is updated for a given address prefix and nonce namespace.
    /// @param addressPrefix The prefix of the address for which the nonce status is updated.
    /// @param nonceNamespace The namespace of the nonce being updated.
    /// @param oldNonce The previous nonce value before the update.
    /// @param newNonce The new nonce value after the update.
    event NonceStatus(
        bytes19 indexed addressPrefix, uint256 indexed nonceNamespace, uint256 oldNonce, uint256 newNonce
    );

    /// @notice Emitted when a nonce is used for an address prefix and nonce namespace as part of permit execution.
    /// @param addressPrefix The address prefix for which the nonce is used.
    /// @param nonceNamespace The namespace of the nonce used.
    /// @param nonce The nonce that was used.
    event NonceUsed(bytes19 indexed addressPrefix, uint256 indexed nonceNamespace, uint256 nonce);

    /// @notice Emitted when the operator status is changed for an address prefix.
    /// @param addressPrefix The address prefix for which the operator status is changed.
    /// @param operator The address of the operator.
    /// @param accountOperatorAuthorized The new authorization bitfield of the operator.
    event OperatorStatus(bytes19 indexed addressPrefix, address indexed operator, uint256 accountOperatorAuthorized);

    /// @notice Emitted when the collateral status is changed for an account.
    /// @param account The account for which the collateral status is changed.
    /// @param collateral The address of the collateral.
    /// @param enabled True if the collateral is enabled, false otherwise.
    event CollateralStatus(address indexed account, address indexed collateral, bool enabled);

    /// @notice Emitted when the controller status is changed for an account.
    /// @param account The account for which the controller status is changed.
    /// @param controller The address of the controller.
    /// @param enabled True if the controller is enabled, false otherwise.
    event ControllerStatus(address indexed account, address indexed controller, bool enabled);

    /// @notice Emitted when an external call is made through the EVC.
    /// @param caller The address of the caller.
    /// @param onBehalfOfAddressPrefix The address prefix of the account on behalf of which the call is made.
    /// @param onBehalfOfAccount The account on behalf of which the call is made.
    /// @param targetContract The target contract of the call.
    /// @param selector The selector of the function called on the target contract.
    event CallWithContext(
        address indexed caller,
        bytes19 indexed onBehalfOfAddressPrefix,
        address onBehalfOfAccount,
        address indexed targetContract,
        bytes4 selector
    );

    /// @notice Emitted when an account status check is performed.
    /// @param account The account for which the status check is performed.
    /// @param controller The controller performing the status check.
    event AccountStatusCheck(address indexed account, address indexed controller);

    /// @notice Emitted when a vault status check is performed.
    /// @param vault The vault for which the status check is performed.
    event VaultStatusCheck(address indexed vault);
}
