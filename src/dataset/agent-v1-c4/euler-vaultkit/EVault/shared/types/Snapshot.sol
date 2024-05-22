// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Assets} from "./Types.sol";

/// @title Snapshot
/// @notice This struct is used to store a snapshot of the vault's cash and total borrows at the beginning of an
/// operation (or a batch thereof)
struct Snapshot {
    // Packed slot: 14 + 14 + 4 = 32
    // vault's cash holdings
    Assets cash;
    // vault's total borrows in assets, in regular precision
    Assets borrows;
    // stamp occupies the rest of the storage slot and makes sure the slot is non-zero for gas savings
    uint32 stamp;
}

/// @title SnapshotLib
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Library for working with the `Snapshot` struct
library SnapshotLib {
    uint32 private constant STAMP = 1; // non zero initial value of the snapshot slot to save gas on SSTORE

    function set(Snapshot storage self, Assets cash, Assets borrows) internal {
        self.cash = cash;
        self.borrows = borrows;
        self.stamp = STAMP;
    }

    function reset(Snapshot storage self) internal {
        self.set(Assets.wrap(0), Assets.wrap(0));
    }
}

using SnapshotLib for Snapshot global;
