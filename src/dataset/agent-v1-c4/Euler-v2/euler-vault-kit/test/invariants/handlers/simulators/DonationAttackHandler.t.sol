// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {TestERC20} from "../../Setup.t.sol";

// Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title DonationAttackHandler
/// @notice Handler test contract for the  DonationAttack actions
contract DonationAttackHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice This function transfers any amount of assets to a contract in the system
    /// @dev Flashloan simulator
    function donate(uint256 amount, uint256 j) external {
        address vaultAddress = address(eTST);

        TestERC20 _token = TestERC20(_getRandomBaseAsset(j));

        _token.mint(address(this), amount);

        _token.transfer(vaultAddress, amount);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
