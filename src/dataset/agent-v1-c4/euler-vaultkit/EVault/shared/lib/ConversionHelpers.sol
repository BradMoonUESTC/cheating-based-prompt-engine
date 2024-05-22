// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {VaultCache} from "../types/VaultCache.sol";

/// @title ConversionHelpers Library
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice The library provides a helper function for conversions between shares and assets
library ConversionHelpers {
    // virtual deposit used in conversions between shares and assets, serving as exchange rate manipulation mitigation
    uint256 internal constant VIRTUAL_DEPOSIT_AMOUNT = 1e6;

    function conversionTotals(VaultCache memory vaultCache)
        internal
        pure
        returns (uint256 totalAssets, uint256 totalShares)
    {
        unchecked {
            totalAssets =
                vaultCache.cash.toUint() + vaultCache.totalBorrows.toAssetsUp().toUint() + VIRTUAL_DEPOSIT_AMOUNT;
            totalShares = vaultCache.totalShares.toUint() + VIRTUAL_DEPOSIT_AMOUNT;
        }
    }
}
