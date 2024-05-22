// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../../src/EVault/shared/Constants.sol";

// Base Contracts
import {HandlerAggregator} from "../HandlerAggregator.t.sol";

/// @title InterestInvariants
/// @notice Implements Invariants related to the interest
/// @dev Inherits HandlerAggregator for checking actions in assertion testing mode
abstract contract InterestInvariants is HandlerAggregator {
    function assert_I_INVARIANT_A() internal {
        (uint256 min, uint256 max) = protocolConfig.interestFeeRange(address(eTST));
        assertLe(eTST.interestFee(), max, I_INVARIANT_A);
        assertGe(eTST.interestFee(), min, I_INVARIANT_A);
    }

    function assert_I_INVARIANT_B() internal {
        assertLe(eTST.getLastInterestAccumulatorUpdate(), block.timestamp, BASE_INVARIANT_B);
    }

    function assert_I_INVARIANT_D() internal {
        assertLe(eTST.interestRate(), MAX_ALLOWED_INTEREST_RATE, I_INVARIANT_D);
    }

    //////////////////////////////////////////////////////////////////////////////////////////////
    //                                        HELPERS                                           //
    //////////////////////////////////////////////////////////////////////////////////////////////
}
