// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import "../../../../src/EVault/shared/Constants.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

// Interfaces
import {IGovernance} from "../../../../src/EVault/IEVault.sol";

/// @title GovernanceModuleHandler
/// @notice Handler test contract for the governance module actions
contract GovernanceModuleHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function convertFees() external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address target = address(eTST);

        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(IGovernance.convertFees.selector));

        if (success) {
            assert(true);
        }
    }

    function setLTV(uint256 i, uint16 borrowLTV, uint16 liquidationLTV, uint24 rampDuration) external {
        address collateral = _getRandomBaseAsset(i);

        eTST.setLTV(collateral, borrowLTV, liquidationLTV, rampDuration);

        assert(true);
    }

    function clearLTV(uint256 i) external {
        address collateral = _getRandomBaseAsset(i);

        eTST.clearLTV(collateral);

        assert(true);
    }

    function setInterestFee(uint16 interestFee) external {
        eTST.setInterestFee(interestFee);

        assert(true);
    }

    function setDebtSocialization(bool status) external {
        uint32 bitmask = eTST.configFlags();
        if (status) bitmask = removeConfiguration(bitmask, CFG_DONT_SOCIALIZE_DEBT);
        else bitmask = addConfiguration(bitmask, CFG_DONT_SOCIALIZE_DEBT);
        eTST.setConfigFlags(bitmask);
    }

    function setCaps(uint16 supplyCap, uint16 borrowCap) external {
        eTST.setCaps(supplyCap, borrowCap);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HELPERS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Function to add a configuration to the bitmask
    function addConfiguration(uint32 bitmask, uint32 configToAdd) internal pure returns (uint32) {
        return bitmask |= configToAdd;
    }

    // Function to remove a configuration from the bitmask
    function removeConfiguration(uint32 bitmask, uint32 configToRemove) internal pure returns (uint32) {
        return bitmask &= ~configToRemove;
    }
}
