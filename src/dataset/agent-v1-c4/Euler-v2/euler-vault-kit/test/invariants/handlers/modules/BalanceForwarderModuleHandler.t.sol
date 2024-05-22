// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

// Interfaces
import {IBalanceForwarder} from "../../../../src/EVault/IEVault.sol";

/// @title BalanceForwarderModuleHandler
/// @notice Handler test contract for the risk balance forwarder module actions
contract BalanceForwarderModuleHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function enableBalanceForwarder() external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address target = address(eTST);

        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(IBalanceForwarder.enableBalanceForwarder.selector));

        if (success) {
            assert(true);
        }
    }

    function disableBalanceForwarder() external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address target = address(eTST);

        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(IBalanceForwarder.disableBalanceForwarder.selector));

        if (success) {
            assert(true);
        }
    }
}
