// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVCClient} from "./EVCClient.sol";
import {Cache} from "./Cache.sol";
import {ProxyUtils} from "./lib/ProxyUtils.sol";
import {RevertBytes} from "./lib/RevertBytes.sol";
import {AddressUtils} from "./lib/AddressUtils.sol";

import {IProtocolConfig} from "../../ProtocolConfig/IProtocolConfig.sol";
import {IBalanceTracker} from "../../interfaces/IBalanceTracker.sol";
import {ISequenceRegistry} from "../../interfaces/ISequenceRegistry.sol";

import "./types/Types.sol";

/// @title Base
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Base contract for EVault modules with top level modifiers and utilities
abstract contract Base is EVCClient, Cache {
    IProtocolConfig internal immutable protocolConfig;
    ISequenceRegistry immutable sequenceRegistry;
    IBalanceTracker internal immutable balanceTracker;
    address internal immutable permit2;

    /// @title Integrations
    /// @notice Struct containing addresses of all of the contracts which EVault integrates with
    struct Integrations {
        // Ethereum Vault Connector's address
        address evc;
        // Address of the contract handling protocol level configurations
        address protocolConfig;
        // Address of the contract providing a unique ID used in setting the vault's name and symbol
        address sequenceRegistry;
        // Address of the contract which is called when user balances change
        address balanceTracker;
        // Address of Uniswap's Permit2 contract
        address permit2;
    }

    constructor(Integrations memory integrations) EVCClient(integrations.evc) {
        protocolConfig = IProtocolConfig(AddressUtils.checkContract(integrations.protocolConfig));
        sequenceRegistry = ISequenceRegistry(AddressUtils.checkContract(integrations.sequenceRegistry));
        balanceTracker = IBalanceTracker(integrations.balanceTracker);
        permit2 = integrations.permit2;
    }

    modifier reentrantOK() {
        _;
    } // documentation only

    modifier nonReentrant() {
        if (vaultStorage.reentrancyLocked) revert E_Reentrancy();

        vaultStorage.reentrancyLocked = true;
        _;
        vaultStorage.reentrancyLocked = false;
    }

    modifier nonReentrantView() {
        if (vaultStorage.reentrancyLocked) {
            address hookTarget = vaultStorage.hookTarget;

            // The hook target is allowed to bypass the RO-reentrancy lock. The hook target can either be a msg.sender
            // when the view function is inlined in the EVault.sol or the hook target should be taken from the trailing
            // data appended by the delegateToModuleView function used by useView modifier. In the latter case, it is
            // safe to consume the trailing data as we know we are inside useView because msg.sender == address(this)
            if (msg.sender != hookTarget && !(msg.sender == address(this) && ProxyUtils.useViewCaller() == hookTarget))
            {
                revert E_Reentrancy();
            }
        }
        _;
    }

    // Generate a vault snapshot and store it.
    // Queue vault and maybe account checks in the EVC (caller, current, onBehalfOf or none).
    // If needed, revert if this contract is not the controller of the authenticated account.
    // Returns the VaultCache and active account.
    function initOperation(uint32 operation, address accountToCheck)
        internal
        virtual
        returns (VaultCache memory vaultCache, address account)
    {
        vaultCache = updateVault();
        account = EVCAuthenticateDeferred(CONTROLLER_NEUTRAL_OPS & operation == 0);

        callHook(vaultCache.hookedOps, operation, account);
        EVCRequireStatusChecks(accountToCheck == CHECKACCOUNT_CALLER ? account : accountToCheck);

        // The snapshot is used only to verify that supply increased when checking the supply cap, and to verify that
        // the borrows increased when checking the borrowing cap. Caps are not checked when the capped variables
        // decrease (become safer). For this reason, the snapshot is disabled if both caps are disabled.
        // The snapshot is cleared during the vault status check hence the vault status check must not be forgiven.
        if (
            !vaultCache.snapshotInitialized
                && !(vaultCache.supplyCap == type(uint256).max && vaultCache.borrowCap == type(uint256).max)
        ) {
            vaultStorage.snapshotInitialized = vaultCache.snapshotInitialized = true;
            snapshot.set(vaultCache.cash, vaultCache.totalBorrows.toAssetsUp());
        }
    }

    // Checks whether the operation is disabled and returns the result of the check.
    // An operation is considered disabled if a hook has been installed for it and the
    // hook target is zero address.
    function isOperationDisabled(Flags hookedOps, uint32 operation) internal view returns (bool) {
        return hookedOps.isSet(operation) && vaultStorage.hookTarget == address(0);
    }

    // Checks whether a hook has been installed for the operation and if so, invokes the hook target.
    // If the hook target is zero address, this will revert.
    function callHook(Flags hookedOps, uint32 operation, address caller) internal virtual {
        if (hookedOps.isNotSet(operation)) return;

        invokeHookTarget(caller);
    }

    // Same as callHook, but acquires the reentrancy lock when calling the hook
    function callHookWithLock(Flags hookedOps, uint32 operation, address caller) internal virtual {
        if (hookedOps.isNotSet(operation)) return;

        invokeHookTargetWithLock(caller);
    }

    function invokeHookTarget(address caller) private {
        address hookTarget = vaultStorage.hookTarget;

        if (hookTarget == address(0)) revert E_OperationDisabled();

        (bool success, bytes memory data) = hookTarget.call(abi.encodePacked(msg.data, caller));

        if (!success) RevertBytes.revertBytes(data);
    }

    function invokeHookTargetWithLock(address caller) private nonReentrant {
        invokeHookTarget(caller);
    }

    function logVaultStatus(VaultCache memory a, uint256 interestRate) internal {
        emit VaultStatus(
            a.totalShares.toUint(),
            a.totalBorrows.toAssetsUp().toUint(),
            a.accumulatedFees.toUint(),
            a.cash.toUint(),
            a.interestAccumulator,
            interestRate,
            block.timestamp
        );
    }
}
