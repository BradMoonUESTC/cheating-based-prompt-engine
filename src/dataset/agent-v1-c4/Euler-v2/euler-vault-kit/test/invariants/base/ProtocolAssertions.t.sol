// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Base
import {BaseTest} from "./BaseTest.t.sol";
import {StdAsserts} from "../utils/StdAsserts.sol";

/// @title ProtocolAssertions
/// @notice Helper contract for protocol specific assertions
abstract contract ProtocolAssertions is StdAsserts, BaseTest {
    /// @notice Returns true if an account is healthy (liability <= collateral)
    function isAccountHealthy(uint256 _liability, uint256 _collateral) internal pure returns (bool) {
        return _liability <= _collateral;
    }

    /// @notice Checks whether the account is healthy from a BORROWING perspective
    function isAccountHealthy(address _account) internal view returns (bool) {
        (uint256 collateralValue, uint256 liabilityValue) = _getAccountLiquidity(_account, false);
        /// @dev not checking for a liquidatable account, just an unhealthy one
        return isAccountHealthy(liabilityValue, collateralValue);
    }

    /// @notice Checks whether the account is healthy from a LIQUIDATION perspective
    function isAccountHealthyLiquidation(address _account) internal view returns (bool) {
        (uint256 collateralValue, uint256 liabilityValue) = _getAccountLiquidity(_account, true);
        /// @dev checking for a liquidatable account, just an unhealthy one
        return isAccountHealthy(liabilityValue, collateralValue) && liabilityValue > 0;
    }

    /// @notice Checks whether the account is healthy
    function assertAccountIsHealthy(address _account) internal {
        assertTrue(isAccountHealthy(_account), "Account is unhealthy for BORROWING");
    }

    /// @notice Checks whether the account is healthy from a LIQUIDATION perspective
    function assertAccountIsHealthyLiquidation(address _account) internal {
        assertTrue(isAccountHealthyLiquidation(_account), "Account is unhealthy for LIQUIDATION");
    }
}
