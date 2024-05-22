// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "./IIRM.sol";

/// @title IRMLinearKink
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Implementation of an interest rate model, where interest rate grows linearly with utilization, and spikes
/// after reaching kink
contract IRMLinearKink is IIRM {
    /// @notice Base interest rate applied when utilization is equal zero
    uint256 public immutable baseRate;
    /// @notice Slope of the function before the kink
    uint256 public immutable slope1;
    /// @notice Slope of the function after the kink
    uint256 public immutable slope2;
    /// @notice Utilization at which the slope of the interest rate function changes. In type(uint32).max scale.
    uint256 public immutable kink;

    constructor(uint256 baseRate_, uint256 slope1_, uint256 slope2_, uint256 kink_) {
        baseRate = baseRate_;
        slope1 = slope1_;
        slope2 = slope2_;
        kink = kink_;
    }

    /// @inheritdoc IIRM
    function computeInterestRate(address vault, uint256 cash, uint256 borrows)
        external
        view
        override
        returns (uint256)
    {
        if (msg.sender != vault) revert E_IRMUpdateUnauthorized();

        return computeInterestRateInternal(vault, cash, borrows);
    }

    /// @inheritdoc IIRM
    function computeInterestRateView(address vault, uint256 cash, uint256 borrows)
        external
        view
        override
        returns (uint256)
    {
        return computeInterestRateInternal(vault, cash, borrows);
    }

    function computeInterestRateInternal(address, uint256 cash, uint256 borrows) internal view returns (uint256) {
        uint256 totalAssets = cash + borrows;

        uint32 utilization = totalAssets == 0
            ? 0 // empty pool arbitrarily given utilization of 0
            : uint32(borrows * type(uint32).max / totalAssets);

        uint256 ir = baseRate;

        if (utilization <= kink) {
            ir += utilization * slope1;
        } else {
            ir += kink * slope1;

            uint256 utilizationOverKink;
            unchecked {
                utilizationOverKink = utilization - kink;
            }
            ir += slope2 * utilizationOverKink;
        }

        return ir;
    }
}
