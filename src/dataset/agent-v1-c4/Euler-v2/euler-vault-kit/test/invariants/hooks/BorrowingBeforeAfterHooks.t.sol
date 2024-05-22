// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import "../../../src/EVault/shared/types/Types.sol";
import "../../../src/EVault/shared/types/AmountCap.sol";

// Test Helpers
import {Pretty, Strings} from "../utils/Pretty.sol";

// Test Contracts
import {BaseHooks} from "../base/BaseHooks.t.sol";
import {ILiquidationModuleHandler} from "../handlers/interfaces/ILiquidationModuleHandler.sol";

/// @title Borrowing Before After Hooks
/// @notice Helper contract for before and after hooks
/// @dev This contract is inherited by handlers
abstract contract BorrowingBeforeAfterHooks is BaseHooks {
    using Strings for string;
    using Pretty for uint256;
    using Pretty for int256;
    using AmountCapLib for AmountCap;

    struct BorrowingVars {
        // Debt Accounting
        uint256 totalBorrowsBefore;
        uint256 totalBorrowsAfter;
        uint256 totalBorrowsExactBefore;
        uint256 totalBorrowsExactAfter;
        uint256 cashBefore;
        uint256 cashAfter;
        // Interest
        uint256 interestRateBefore;
        uint256 interestRateAfter;
        uint256 interestAccumulatorBefore;
        uint256 interestAccumulatorAfter;
        // User Debt
        uint256 userDebtBefore;
        uint256 userDebtAfter;
        // EVC
        bool controllerEnabledBefore;
        bool controllerEnabledAfter;
        // Liquidity
        uint256 liabilityValueBefore;
        uint256 liabilityValueAfter;
        uint256 collateralValueBefore;
        uint256 collateralValueAfter;
        // Borrow Cap
        uint256 borrowCapBefore;
        uint256 borrowCapAfter;
    }

    BorrowingVars borrowingVars;

    function _borrowingHooksBefore() internal {
        // Debt Accounting
        borrowingVars.totalBorrowsBefore = eTST.totalBorrows();
        borrowingVars.totalBorrowsExactBefore = eTST.totalBorrowsExact();
        borrowingVars.cashBefore = eTST.cash();
        // Interest
        borrowingVars.interestRateBefore = eTST.interestRate();
        borrowingVars.interestAccumulatorBefore = eTST.interestAccumulator();
        // User Debt
        borrowingVars.userDebtBefore = eTST.debtOf(address(actor));
        // EVC
        borrowingVars.controllerEnabledBefore = evc.isControllerEnabled(address(actor), address(eTST));
        // Liquidity
        (borrowingVars.collateralValueBefore, borrowingVars.liabilityValueBefore) =
            _getAccountLiquidity(address(actor), false);
        // Caps
        (, uint16 _borrowCap) = eTST.caps();
        borrowingVars.borrowCapBefore = AmountCap.wrap(_borrowCap).resolve();
    }

    function _borrowingHooksAfter() internal {
        // Debt Accounting
        borrowingVars.totalBorrowsAfter = eTST.totalBorrows();
        borrowingVars.totalBorrowsExactAfter = eTST.totalBorrowsExact();
        borrowingVars.cashAfter = eTST.cash();
        // Interest
        borrowingVars.interestRateAfter = eTST.interestRate();
        borrowingVars.interestAccumulatorAfter = eTST.interestAccumulator();
        // User Debt
        borrowingVars.userDebtAfter = eTST.debtOf(address(actor));
        // EVC
        borrowingVars.controllerEnabledAfter = evc.isControllerEnabled(address(actor), address(eTST));
        // Liquidity
        (borrowingVars.collateralValueAfter, borrowingVars.liabilityValueAfter) =
            _getAccountLiquidity(address(actor), false);
        // Caps
        (, uint16 _borrowCap) = eTST.caps();
        borrowingVars.borrowCapAfter = AmountCap.wrap(_borrowCap).resolve();
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                POST CONDITION INVARIANTS                                  //
    /////////////////////////////////////////////////////////////////////////////////////////////*/

    function assert_I_INVARIANT_E() internal {
        assertGe(borrowingVars.interestAccumulatorAfter, borrowingVars.interestAccumulatorBefore, I_INVARIANT_E);
    }

    function assert_BM_INVARIANT_H() internal {
        assertTrue(
            (borrowingVars.totalBorrowsAfter > borrowingVars.totalBorrowsBefore && borrowingVars.borrowCapAfter != 0)
                ? (borrowingVars.borrowCapAfter >= borrowingVars.totalBorrowsAfter)
                : true,
            BM_INVARIANT_I
        );
    }

    function assert_BM_INVARIANT_I() internal {
        if (borrowingVars.userDebtBefore > 0) {
            assertEq(borrowingVars.controllerEnabledAfter, true, BM_INVARIANT_J);
        }
    }

    function assert_LM_INVARIANT_C() internal {
        if (isAccountHealthy(borrowingVars.liabilityValueBefore, borrowingVars.collateralValueBefore)) {
            if (!isAccountHealthy(borrowingVars.liabilityValueAfter, borrowingVars.collateralValueAfter)) {
                assertEq(bytes32(msg.sig), bytes32(ILiquidationModuleHandler.liquidate.selector), LM_INVARIANT_C);
            }
        }
    }

    function assert_LM_INVARIANT_D() internal {
        if (!isAccountHealthy(borrowingVars.liabilityValueBefore, borrowingVars.collateralValueBefore)) {
            uint256 healthScoreBefore =
                _getHealthScore(borrowingVars.liabilityValueBefore, borrowingVars.collateralValueBefore);
            uint256 healthScoreAfter =
                _getHealthScore(borrowingVars.liabilityValueAfter, borrowingVars.collateralValueAfter);

            if (healthScoreBefore > healthScoreAfter) {
                assertEq(bytes32(msg.sig), bytes32(ILiquidationModuleHandler.liquidate.selector), LM_INVARIANT_D);
            }
        }
    }
}
