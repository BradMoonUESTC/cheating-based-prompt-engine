// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {VaultStorage, Snapshot} from "./types/Types.sol";

/// @title Storage
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Contract that defines the EVault's data storage
abstract contract Storage {
    /// @notice Flag indicating if the vault has been initialized
    bool internal initialized;

    /// @notice Snapshot of vault's cash and borrows created at the beginning of an operation or a batch of operations
    /// @dev The snapshot is separate from VaultStorage, because it could be implemented as transient storage
    Snapshot internal snapshot;

    /// @notice A singleton VaultStorage
    VaultStorage internal vaultStorage;
}
