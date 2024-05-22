// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {IBalanceForwarder} from "../IEVault.sol";
import {Base} from "../shared/Base.sol";

import "../shared/types/Types.sol";

/// @title BalanceForwarderModule
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice An EVault module handling communication with a balance tracker contract.
abstract contract BalanceForwarderModule is IBalanceForwarder, Base {
    /// @inheritdoc IBalanceForwarder
    function balanceTrackerAddress() public view virtual reentrantOK returns (address) {
        return address(balanceTracker);
    }

    /// @inheritdoc IBalanceForwarder
    function balanceForwarderEnabled(address account) public view virtual nonReentrantView returns (bool) {
        return vaultStorage.users[account].isBalanceForwarderEnabled();
    }

    /// @inheritdoc IBalanceForwarder
    function enableBalanceForwarder() public virtual nonReentrant {
        if (address(balanceTracker) == address(0)) revert E_NotSupported();

        address account = EVCAuthenticate();
        UserStorage storage user = vaultStorage.users[account];

        bool wasBalanceForwarderEnabled = user.isBalanceForwarderEnabled();

        user.setBalanceForwarder(true);
        balanceTracker.balanceTrackerHook(account, user.getBalance().toUint(), false);

        if (!wasBalanceForwarderEnabled) emit BalanceForwarderStatus(account, true);
    }

    /// @inheritdoc IBalanceForwarder
    function disableBalanceForwarder() public virtual nonReentrant {
        if (address(balanceTracker) == address(0)) revert E_NotSupported();

        address account = EVCAuthenticate();
        UserStorage storage user = vaultStorage.users[account];

        bool wasBalanceForwarderEnabled = user.isBalanceForwarderEnabled();

        user.setBalanceForwarder(false);
        balanceTracker.balanceTrackerHook(account, 0, false);

        if (wasBalanceForwarderEnabled) emit BalanceForwarderStatus(account, false);
    }
}

/// @dev Deployable module contract
contract BalanceForwarder is BalanceForwarderModule {
    constructor(Integrations memory integrations) Base(integrations) {}
}
