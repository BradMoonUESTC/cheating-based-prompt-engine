// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import {IEVC} from "./interfaces/IEthereumVaultConnector.sol";

/// @title Errors
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This contract implements the error messages for the Ethereum Vault Connector.
contract Errors {
    /// @notice Error for when caller is not authorized to perform an operation.
    error EVC_NotAuthorized();
    /// @notice Error for when no account has been authenticated to act on behalf of.
    error EVC_OnBehalfOfAccountNotAuthenticated();
    /// @notice Error for when an operator's to be set is no different from the current one.
    error EVC_InvalidOperatorStatus();
    /// @notice Error for when a nonce is invalid or already used.
    error EVC_InvalidNonce();
    /// @notice Error for when an address parameter passed is invalid.
    error EVC_InvalidAddress();
    /// @notice Error for when a timestamp parameter passed is expired.
    error EVC_InvalidTimestamp();
    /// @notice Error for when a value parameter passed is invalid or exceeds current balance.
    error EVC_InvalidValue();
    /// @notice Error for when data parameter passed is empty.
    error EVC_InvalidData();
    /// @notice Error for when an action is prohibited due to the lockdown mode.
    error EVC_LockdownMode();
    /// @notice Error for when permit execution is prohibited due to the permit disabled mode.
    error EVC_PermitDisabledMode();
    /// @notice Error for when checks are in progress and reentrancy is not allowed.
    error EVC_ChecksReentrancy();
    /// @notice Error for when control collateral is in progress and reentrancy is not allowed.
    error EVC_ControlCollateralReentrancy();
    /// @notice Error for when there is a different number of controllers enabled than expected.
    error EVC_ControllerViolation();
    /// @notice Error for when a simulation batch is nested within another simulation batch.
    error EVC_SimulationBatchNested();
    /// @notice Auxiliary error to pass simulation batch results.
    error EVC_RevertedBatchResult(
        IEVC.BatchItemResult[] batchItemsResult,
        IEVC.StatusCheckResult[] accountsStatusResult,
        IEVC.StatusCheckResult[] vaultsStatusResult
    );
    /// @notice Panic error for when simulation does not behave as expected. Should never be observed.
    error EVC_BatchPanic();
    /// @notice Error for when an empty or undefined error is thrown.
    error EVC_EmptyError();
}
