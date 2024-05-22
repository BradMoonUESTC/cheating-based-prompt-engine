// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {console} from "forge-std/console.sol";

/// @title VaultBaseGetters
/// @dev This contract provides getters for the private variables in VaultBase, via storage access
contract VaultBaseGetters {
    uint256 internal constant REENTRANCY_LOCK_SLOT = 0;
    uint256 internal constant SNAPSHOT_SLOT = 1;

    /// @notice Gets the reentrancy lock
    function getReentrancyLock() external view returns (uint256 lock) {
        uint256 slot = REENTRANCY_LOCK_SLOT;

        assembly {
            lock := sload(slot)
        }
    }

    /// @notice Gets the snapshot length, using assembly to read from storage
    function getSnapshotLength() external view returns (uint256 snapshotLength) {
        uint256 slot = SNAPSHOT_SLOT;

        assembly {
            snapshotLength := sload(slot)
        }
    }

    /// @notice Gets the snapshot, using assembly to read bytes from storage
    function getSnapshot() external view returns (bytes memory snapshot) {
        uint256 slot = SNAPSHOT_SLOT;

        // Declared outside of the assembly block for easier debugging
        uint256 length;
        uint256 bytesLength;
        uint256 slotContent;
        uint256 slotData;

        assembly {
            // Calculate slot where data starts
            mstore(0, slot)
            slotData := keccak256(0, 0x20)

            slotContent := sload(slot)

            if gt(slotContent, 0) {
                // Load the length of the bytes
                bytesLength := sub(slotContent, 0x21)

                // Calculate the number of 32-byte chunks
                length := div(add(bytesLength, 0x1f), 0x20)

                // Update the free memory pointer
                mstore(0x40, add(snapshot, add(mul(length, 0x20), 0x20)))

                // Store the length of the bytes in memory
                let pointer := snapshot
                mstore(pointer, bytesLength)

                for { let i := 0 } lt(i, length) { i := add(i, 1) } {
                    // Calculate the next slot to read
                    let dataSlot := add(slotData, i)
                    // Read the data from the slot
                    let data := sload(dataSlot)

                    // Calculate the next memory pointer & store the data
                    pointer := add(pointer, 0x20)
                    mstore(pointer, data)
                }
            }
        }
    }
}
