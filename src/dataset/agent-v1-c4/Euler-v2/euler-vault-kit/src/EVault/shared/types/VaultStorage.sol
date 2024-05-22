// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Assets, Shares, Owed, AmountCap, ConfigAmount, Flags} from "./Types.sol";
import {LTVConfig} from "./LTVConfig.sol";
import {UserStorage} from "./UserStorage.sol";

/// @title VaultStorage
/// @notice This struct is used to hold all of the vault's permanent storage
/// @dev Note that snapshots are not a part of this struct, as they might be reimplemented as transient storage
struct VaultStorage {
    // Packed slot 6 + 14 + 2 + 2 + 4 + 1 + 1 = 30
    // A timestamp of the last interest accumulator update
    uint48 lastInterestAccumulatorUpdate;
    // The amount of assets held directly by the vault
    Assets cash;
    // Current supply cap in asset units
    AmountCap supplyCap;
    // Current borrow cap in asset units
    AmountCap borrowCap;
    // A bitfield of operations which trigger a hook call
    Flags hookedOps;
    // A vault global reentrancy protection flag
    bool reentrancyLocked;
    // A flag indicating if the vault snapshot has already been initialized for the currently executing batch
    bool snapshotInitialized;

    // Packed slot 14 + 18 = 32
    // Sum of all user shares
    Shares totalShares;
    // Sum of all user debts
    Owed totalBorrows;

    // Packed slot 14 + 2 + 2 + 4 = 22
    // Interest fees accrued since the last fee conversion
    Shares accumulatedFees;
    // Maximum liquidation discount
    ConfigAmount maxLiquidationDiscount;
    // Amount of time in seconds that must pass after a successful account status check before liquidation is possible
    uint16 liquidationCoolOffTime;
    // A bitfield of vault configuration options
    Flags configFlags;

    // Current interest accumulator
    uint256 interestAccumulator;

    // Packed slot 20 + 2 + 9 = 31
    // Address of the interest rate model contract. If not set, 0% interest is applied
    address interestRateModel;
    // Percentage of accrued interest that is directed to fees
    ConfigAmount interestFee;
    // Current interest rate applied to outstanding borrows
    uint72 interestRate;

    // Name of the shares token (eToken)
    string name;
    // Symbol of the shares token (eToken)
    string symbol;

    // Address of the vault's creator
    address creator;

    // Address of the vault's governor
    address governorAdmin;
    // Address which receives governor fees
    address feeReceiver;
    // Address which will be called for enabled hooks
    address hookTarget;

    // User accounts
    mapping(address account => UserStorage) users;

    // LTV configuration for collaterals
    mapping(address collateral => LTVConfig) ltvLookup;
    // List of addresses which were at any point configured as collateral
    address[] ltvList;
}
