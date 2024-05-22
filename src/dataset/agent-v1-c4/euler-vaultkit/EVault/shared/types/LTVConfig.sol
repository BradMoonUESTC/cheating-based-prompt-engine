// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ConfigAmount} from "./Types.sol";

/// @title LTVConfig
/// @notice This packed struct is used to store LTV configuration of a collateral
struct LTVConfig {
    // Packed slot: 2 + 2 + 2 + 6 + 4 + 1 = 17
    // The value of borrow LTV for originating positions
    ConfigAmount borrowLTV;
    // The value of fully converged liquidation LTV
    ConfigAmount liquidationLTV;
    // The initial value of liquidation LTV, when the ramp began
    ConfigAmount initialLiquidationLTV;
    // The timestamp when the liquidation LTV is considered fully converged
    uint48 targetTimestamp;
    // The time it takes for the liquidation LTV to converge from the initial value to the fully converged value
    uint32 rampDuration;
    // A flag indicating the LTV configuration was initialized for the collateral
    bool initialized;
}

/// @title LTVConfigLib
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Library for getting and setting the LTV configurations
library LTVConfigLib {
    // Is the collateral considered safe to liquidate
    function isRecognizedCollateral(LTVConfig memory self) internal pure returns (bool) {
        return self.targetTimestamp != 0;
    }

    // Get current LTV of the collateral. When liquidation LTV is lowered, it is ramped down to the target value over a
    // period of time.
    function getLTV(LTVConfig memory self, bool liquidation) internal view returns (ConfigAmount) {
        if (!liquidation) {
            return self.borrowLTV;
        }

        if (block.timestamp >= self.targetTimestamp || self.liquidationLTV >= self.initialLiquidationLTV) {
            return self.liquidationLTV;
        }

        uint256 currentLiquidationLTV = self.initialLiquidationLTV.toUint16();

        unchecked {
            uint256 targetLiquidationLTV = self.liquidationLTV.toUint16();
            uint256 timeRemaining = self.targetTimestamp - block.timestamp;

            // targetLiquidationLTV < initialLiquidationLTV and timeRemaining <= rampDuration
            currentLiquidationLTV = targetLiquidationLTV
                + (currentLiquidationLTV - targetLiquidationLTV) * timeRemaining / self.rampDuration;
        }

        // because ramping happens only when liquidation LTV decreases, it's safe to down-cast the new value
        return ConfigAmount.wrap(uint16(currentLiquidationLTV));
    }

    function setLTV(LTVConfig memory self, ConfigAmount borrowLTV, ConfigAmount liquidationLTV, uint32 rampDuration)
        internal
        view
        returns (LTVConfig memory newLTV)
    {
        newLTV.borrowLTV = borrowLTV;
        newLTV.liquidationLTV = liquidationLTV;
        newLTV.initialLiquidationLTV = self.getLTV(true);
        newLTV.targetTimestamp = uint48(block.timestamp + rampDuration);
        newLTV.rampDuration = rampDuration;
        newLTV.initialized = true;
    }

    // When LTV is cleared, the collateral can't be liquidated, as it's deemed unsafe
    function clear(LTVConfig storage self) internal {
        self.borrowLTV = ConfigAmount.wrap(0);
        self.liquidationLTV = ConfigAmount.wrap(0);
        self.initialLiquidationLTV = ConfigAmount.wrap(0);
        self.targetTimestamp = 0;
        self.rampDuration = 0;
    }
}

using LTVConfigLib for LTVConfig global;
