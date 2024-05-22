// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import {HandlerAggregator} from "../HandlerAggregator.t.sol";

// Types
import {Snapshot, Assets} from "../../../src/EVault/shared/types/Types.sol";

/// @title BaseInvariants
/// @notice Implements Invariants for the protocol
/// @dev Inherits HandlerAggregator to check actions in assertion testing mode
abstract contract BaseInvariants is HandlerAggregator {
    function assert_BASE_INVARIANT_A() internal {
        assertEq(eTST.getReentrancyLock(), false, BASE_INVARIANT_A);
    }

    function assert_BASE_INVARIANT_B() internal {
        Snapshot memory _snapshot = eTST.getSnapshot();
        assertEq(_snapshot.stamp, 1, BASE_INVARIANT_B);
        assertEq(Assets.unwrap(_snapshot.cash), 0, BASE_INVARIANT_B);
        assertEq(Assets.unwrap(_snapshot.borrows), 0, BASE_INVARIANT_B);
    }
}
