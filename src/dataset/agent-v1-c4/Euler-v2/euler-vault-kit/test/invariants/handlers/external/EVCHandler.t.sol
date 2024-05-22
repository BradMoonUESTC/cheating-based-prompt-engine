// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";

// Testing contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler, EnumerableSet} from "../../base/BaseHandler.t.sol";

/// @title EVCHandler
/// @notice Handler test contract for the EVC actions
contract EVCHandler is BaseHandler {
    using EnumerableSet for EnumerableSet.AddressSet;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function setAccountOperator(uint256 i, uint256 j, bool authorised) external setup {
        bool success;
        bytes memory returnData;

        address account = _getRandomActor(i);

        address operator = _getRandomActor(j);

        (success, returnData) = actor.proxy(
            address(evc),
            abi.encodeWithSelector(EthereumVaultConnector.setAccountOperator.selector, account, operator, authorised)
        );

        if (success) {
            assert(true);
        }
    }

    // COLLATERAL

    function enableCollateral(uint256 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        address vaultAddress = address(assetTST);

        (success, returnData) = actor.proxy(
            address(evc),
            abi.encodeWithSelector(EthereumVaultConnector.enableCollateral.selector, account, vaultAddress)
        );

        if (success) {
            ghost_accountCollaterals[address(actor)].add(vaultAddress);
        }
    }

    function disableCollateral(uint256 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        address vaultAddress = address(assetTST);

        (success, returnData) = actor.proxy(
            address(evc),
            abi.encodeWithSelector(EthereumVaultConnector.disableCollateral.selector, account, vaultAddress)
        );

        if (success) {
            ghost_accountCollaterals[address(actor)].remove(vaultAddress);
        }
    }

    function reorderCollaterals(uint256 i, uint8 index1, uint8 index2) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        (success, returnData) = actor.proxy(
            address(evc),
            abi.encodeWithSelector(EthereumVaultConnector.reorderCollaterals.selector, account, index1, index2)
        );

        if (success) {
            assert(true);
        }
    }

    // CONTROLLER

    function enableController(uint256 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        (success, returnData) = actor.proxy(
            address(evc),
            abi.encodeWithSelector(EthereumVaultConnector.enableController.selector, account, address(eTST))
        );

        if (success) {
            assert(true);
        }
    }

    function disableControllerEVC(uint256 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        address[] memory controllers = evc.getControllers(account);

        (success, returnData) = actor.proxy(
            address(evc), abi.encodeWithSelector(EthereumVaultConnector.disableController.selector, account)
        );

        address[] memory controllersAfter = evc.getControllers(account);
        if (controllers.length == 0) {
            assertTrue(success);
            assertTrue(controllersAfter.length == 0);
        } else {
            assertEq(controllers.length, controllersAfter.length);
        }
    }

    function requireAccountStatusCheck(uint256 i) external setup {
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        returnData = evc.call(
            address(evc),
            address(0),
            0,
            abi.encodeWithSelector(EthereumVaultConnector.requireAccountStatusCheck.selector, account)
        );
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
