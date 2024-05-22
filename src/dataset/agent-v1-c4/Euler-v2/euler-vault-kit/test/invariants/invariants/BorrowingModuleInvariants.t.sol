// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import "forge-std/console.sol";

// Contracts
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../../src/EVault/shared/Constants.sol";

// Base Contracts
import {HandlerAggregator} from "../HandlerAggregator.t.sol";

/// @title BorrowingModuleInvariants
/// @notice Implements Invariants for the protocol borrowing module
/// @dev Inherits HandlerAggregator for checking actions in assertion testing mode
abstract contract BorrowingModuleInvariants is HandlerAggregator {
    function assert_BM_INVARIANT_A(address _borrower) internal {
        assertGe(eTST.totalBorrows(), eTST.debtOf(_borrower), BM_INVARIANT_A);
    }

    function assert_BM_INVARIANT_B() internal {
        assertApproxEqAbs(eTST.totalBorrows(), _getDebtSum(), NUMBER_OF_ACTORS, BM_INVARIANT_B);
    }

    function assert_BM_INVARIANT_C() internal {
        uint256 _debtSum = _getDebtSum();
        if (_debtSum == 0) {
            assertEq(eTST.totalBorrows(), 0, BM_INVARIANT_C);
        }

        if (eTST.totalBorrows() == 0) {
            assertEq(_debtSum, 0, BM_INVARIANT_C);
        }
    }

    function assert_BM_INVARIANT_J(address _actor) internal {
        //If debt has no decimals
        if (eTST.debtOfExact(_actor) % (1 << INTERNAL_DEBT_PRECISION_SHIFT) == 0) {
            // Debt of actor with 31 bits of precision should be equal to debt of actor exact
            assertEq(eTST.debtOf(_actor) << INTERNAL_DEBT_PRECISION_SHIFT, eTST.debtOfExact(_actor), BM_INVARIANT_J);
        } else {
            // If it has decimals, debtOf should be equal that debtOfExact rounded to the next integer
            assertEq(
                eTST.debtOf(_actor), (eTST.debtOfExact(_actor) >> INTERNAL_DEBT_PRECISION_SHIFT) + 1, BM_INVARIANT_J
            );
        }
    }

    //////////////////////////////////////////////////////////////////////////////////////////////
    //                                       DISCARDED                                          //
    //////////////////////////////////////////////////////////////////////////////////////////////

    /*     function assert_BM_INVARIANT_F() internal {
        if (eTST.totalBorrows() > 0) {
            assertGt(
                ERC20(address(eTST.asset())).balanceOf(_vault),
                0,
                BM_INVARIANT_F
            );
        }
    } */

    //////////////////////////////////////////////////////////////////////////////////////////////
    //                                        HELPERS                                           //
    //////////////////////////////////////////////////////////////////////////////////////////////

    function _getDebtSum() internal view returns (uint256 totalDebt) {
        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            totalDebt += eTST.debtOf(address(actorAddresses[i]));
        }
    }
}
