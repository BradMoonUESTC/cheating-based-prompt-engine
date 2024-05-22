// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20} from "../../IEVault.sol";
import {IPriceOracle} from "../../../interfaces/IPriceOracle.sol";

import {Assets, Owed, Shares, Flags} from "./Types.sol";

/// @title VaultCache
/// @notice This struct is used to hold all the most often used vault data in memory
struct VaultCache {
    // Proxy immutables

    // Vault's asset
    IERC20 asset;
    // Vault's pricing oracle
    IPriceOracle oracle;
    // Unit of account is the asset in which collateral and liability values are expressed
    address unitOfAccount;

    // Vault data

    // A timestamp of the last interest accumulator update
    uint48 lastInterestAccumulatorUpdate;
    // The amount of assets held directly by the vault
    Assets cash;
    // Sum of all user debts
    Owed totalBorrows;
    // Sum of all user shares
    Shares totalShares;
    // Interest fees accrued since the last fee conversion
    Shares accumulatedFees;
    // Current interest accumulator
    uint256 interestAccumulator;

    // Vault config

    // Current supply cap in asset units
    uint256 supplyCap;
    // Current borrow cap in asset units
    uint256 borrowCap;
    // A bitfield of operations which trigger a hook call
    Flags hookedOps;
    // A bitfield of vault configuration options
    Flags configFlags;

    // Runtime

    // A flag indicating if the vault snapshot has already been initialized for the currently executing batch
    bool snapshotInitialized;
}
