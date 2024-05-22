// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title PriceOracleHandler
/// @notice Handler test contract for the  PriceOracle actions
contract PriceOracleHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice This function simulates changes in the interest rate model
    function setPrice(uint256 i, uint256 price) external {
        address baseAsset = _getRandomBaseAsset(i);

        oracle.setPrice(baseAsset, unitOfAccount, price);
    }

    /*  
    /// @notice This function simulates changes in the interest rate model
    function setResolvedAsset(uint256 i) external {
        address vaultAddress = address(eTST);

        oracle.setResolvedAsset(vaultAddress);
    } */

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
