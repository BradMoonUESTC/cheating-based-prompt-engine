// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {HandlerAggregator} from "../HandlerAggregator.t.sol";

import "forge-std/console.sol";

// Contracts

/// @title TokenModuleInvariants
/// @notice Implements Invariants for the ERC20 functionality of the vault
/// @dev Inherits HandlerAggregator to check actions in assertion testing mode
abstract contract TokenModuleInvariants is HandlerAggregator {
    function assert_TM_INVARIANT_A() internal {
        uint256 extrabalance = eTST.balanceOf(eTST.feeReceiver()) + eTST.balanceOf(eTST.protocolFeeReceiver());
        assertApproxEqAbs(
            eTST.totalSupply(),
            ghost_sumSharesBalances + eTST.accumulatedFees() + extrabalance,
            NUMBER_OF_ACTORS,
            TM_INVARIANT_A
        );
    }

    function assert_TM_INVARIANT_B(address _account) internal {
        assertEq(eTST.balanceOf(_account), ghost_sumSharesBalancesPerUser[_account], TM_INVARIANT_B);
    }

    function assert_TM_INVARIANT_C(uint256 _sumBalances) internal {
        uint256 extrabalance = eTST.balanceOf(eTST.feeReceiver()) + eTST.balanceOf(eTST.protocolFeeReceiver());
        assertEq(eTST.totalSupply(), _sumBalances + eTST.accumulatedFees() + extrabalance, TM_INVARIANT_C);
    }
}
