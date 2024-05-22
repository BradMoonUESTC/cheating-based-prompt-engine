// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import {ProtocolAssertions} from "./ProtocolAssertions.t.sol";

// Test Contracts
import {InvariantsSpec} from "../InvariantsSpec.t.sol";

/// @title BaseHooks
/// @notice Contains common logic for all handlers
/// @dev inherits all suite assertions since per-action assertions are implemented in the handlers
/// @dev inherits the Invariant Specifications contract
contract BaseHooks is ProtocolAssertions, InvariantsSpec {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         HELPERS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Calculates the exchange rate for the eTST vault
    function _calculateExchangeRate() internal view returns (uint256) {
        return (eTST.totalAssets() + VIRTUAL_DEPOSIT_AMOUNT) / (eTST.totalSupply() + VIRTUAL_DEPOSIT_AMOUNT);
    }

    function _getHealthScore(uint256 liabilityValue, uint256 collateralValue) internal pure returns (uint256) {
        return liabilityValue == 0 ? 1e18 : collateralValue * 1e18 / liabilityValue;
    }
}
