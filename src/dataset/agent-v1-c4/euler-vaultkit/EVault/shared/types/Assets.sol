// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Assets, Shares, Owed, TypesLib} from "./Types.sol";
import {VaultCache} from "./VaultCache.sol";
import {ConversionHelpers} from "../lib/ConversionHelpers.sol";
import "../Constants.sol";

/// @title AssetsLib
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Custom type `Assets` represents amounts of the vault's underlying asset
library AssetsLib {
    function toUint(Assets self) internal pure returns (uint256) {
        return Assets.unwrap(self);
    }

    function isZero(Assets self) internal pure returns (bool) {
        return Assets.unwrap(self) == 0;
    }

    function toSharesDown(Assets amount, VaultCache memory vaultCache) internal pure returns (Shares) {
        return TypesLib.toShares(toSharesDownUint(amount, vaultCache));
    }

    function toSharesDownUint(Assets amount, VaultCache memory vaultCache) internal pure returns (uint256) {
        (uint256 totalAssets, uint256 totalShares) = ConversionHelpers.conversionTotals(vaultCache);
        unchecked {
            return amount.toUint() * totalShares / totalAssets;
        }
    }

    function toSharesUp(Assets amount, VaultCache memory vaultCache) internal pure returns (Shares) {
        (uint256 totalAssets, uint256 totalShares) = ConversionHelpers.conversionTotals(vaultCache);
        unchecked {
            // totalAssets >= VIRTUAL_DEPOSIT_AMOUNT > 1
            return TypesLib.toShares((amount.toUint() * totalShares + (totalAssets - 1)) / totalAssets);
        }
    }

    function toOwed(Assets self) internal pure returns (Owed) {
        unchecked {
            return TypesLib.toOwed(self.toUint() << INTERNAL_DEBT_PRECISION_SHIFT);
        }
    }

    function addUnchecked(Assets self, Assets b) internal pure returns (Assets) {
        unchecked {
            return Assets.wrap(uint112(self.toUint() + b.toUint()));
        }
    }

    function subUnchecked(Assets self, Assets b) internal pure returns (Assets) {
        unchecked {
            return Assets.wrap(uint112(self.toUint() - b.toUint()));
        }
    }
}

function addAssets(Assets a, Assets b) pure returns (Assets) {
    return TypesLib.toAssets(a.toUint() + b.toUint());
}

function subAssets(Assets a, Assets b) pure returns (Assets) {
    return Assets.wrap((Assets.unwrap(a) - Assets.unwrap(b)));
}

function eqAssets(Assets a, Assets b) pure returns (bool) {
    return Assets.unwrap(a) == Assets.unwrap(b);
}

function neqAssets(Assets a, Assets b) pure returns (bool) {
    return Assets.unwrap(a) != Assets.unwrap(b);
}

function gtAssets(Assets a, Assets b) pure returns (bool) {
    return Assets.unwrap(a) > Assets.unwrap(b);
}

function gteAssets(Assets a, Assets b) pure returns (bool) {
    return Assets.unwrap(a) >= Assets.unwrap(b);
}

function ltAssets(Assets a, Assets b) pure returns (bool) {
    return Assets.unwrap(a) < Assets.unwrap(b);
}

function lteAssets(Assets a, Assets b) pure returns (bool) {
    return Assets.unwrap(a) <= Assets.unwrap(b);
}
