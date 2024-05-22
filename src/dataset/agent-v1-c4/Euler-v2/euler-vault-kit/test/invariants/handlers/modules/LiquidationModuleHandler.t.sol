// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

// Interfaces
import {ILiquidation} from "../../../../src/EVault/IEVault.sol";

/// @title LiquidationModuleHandler
/// @notice Handler test contract for the VaultRegularBorrowable actions
contract LiquidationModuleHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function liquidate(uint256 repayAssets, uint256 minYieldBalance, uint256 i) external setup {
        bool success;
        bytes memory returnData;

        address target = address(eTST);

        address violator = _getRandomActor(i);

        bool violatorStatus = isAccountHealthyLiquidation(violator);

        {
            address collateral = _getRandomAccountCollateral(i, address(actor));

            _before();
            (success, returnData) = actor.proxy(
                target,
                abi.encodeWithSelector(
                    ILiquidation.liquidate.selector, violator, collateral, repayAssets, minYieldBalance
                )
            );
        }
        if (success) {
            _after();

            /// @dev LM_INVARIANT_A
            if (repayAssets != 0) {
                assertFalse(violatorStatus, LM_INVARIANT_A);
            }
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _getActorWithDebt() internal view returns (address) {
        address _actor = address(actor);
        for (uint256 k; k < NUMBER_OF_ACTORS; k++) {
            if (_actor != actorAddresses[k] && eTST.debtOf(address(actorAddresses[k])) > 0) {
                return address(actorAddresses[k]);
            }
        }
        return address(0);
    }
}
