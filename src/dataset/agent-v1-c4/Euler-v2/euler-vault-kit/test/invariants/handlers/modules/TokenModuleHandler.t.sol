// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

// Interfaces
import {IERC20} from "../../../../src/EVault/IEVault.sol";

/// @title  TokenModuleHandler
/// @notice Handler test contract for ERC20 contacts
contract TokenModuleHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function approveTo(uint256 i, uint256 amount) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address spender = _getRandomActor(i);

        address target = address(eTST);

        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(IERC20.approve.selector, spender, amount));

        if (success) {
            assert(true);
        }
    }

    /*     function transfer(address to, uint256 amount) external setup {
        bool success;
        bytes memory returnData;

        address target = address(eTST);

        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));

        if (success) {
            ghost_sumSharesBalancesPerUser[address(actor)] -= amount;
            ghost_sumSharesBalancesPerUser[to] += amount;
        }
    } */

    function transferTo(uint256 i, uint256 amount) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address to = _getRandomActor(i);

        address target = address(eTST);

        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));

        if (success) {
            ghost_sumSharesBalancesPerUser[address(actor)] -= amount;
            ghost_sumSharesBalancesPerUser[to] += amount;
        }
    }

    /*     function transferFrom(uint256 i, address to, uint256 amount) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address from = _getRandomActor(i);

        address target = address(eTST);

        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));

        if (success) {
            ghost_sumSharesBalancesPerUser[from] -= amount;
            ghost_sumSharesBalancesPerUser[to] += amount;
        }
    } */

    function transferFromTo(uint256 i, uint256 u, uint256 amount) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address from = _getRandomActor(i);
        // Get one of the three actors randomly
        address to = _getRandomActor(u);

        address target = address(eTST);

        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));

        if (success) {
            ghost_sumSharesBalancesPerUser[from] -= amount;
            ghost_sumSharesBalancesPerUser[to] += amount;
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
