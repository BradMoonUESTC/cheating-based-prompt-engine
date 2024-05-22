// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Shares, Assets, TypesLib} from "./Types.sol";
import {VaultCache} from "./VaultCache.sol";
import {ConversionHelpers} from "../lib/ConversionHelpers.sol";

/// @title SharesLib
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Library for `Shares` custom type, which is used to store vault's shares balances
library SharesLib {
    function toUint(Shares self) internal pure returns (uint256) {
        return Shares.unwrap(self);
    }

    function isZero(Shares self) internal pure returns (bool) {
        return Shares.unwrap(self) == 0;
    }

    function toAssetsDown(Shares amount, VaultCache memory vaultCache) internal pure returns (Assets) {
        (uint256 totalAssets, uint256 totalShares) = ConversionHelpers.conversionTotals(vaultCache);
        unchecked {
            return TypesLib.toAssets(amount.toUint() * totalAssets / totalShares);
        }
    }

    function toAssetsUp(Shares amount, VaultCache memory vaultCache) internal pure returns (Assets) {
        (uint256 totalAssets, uint256 totalShares) = ConversionHelpers.conversionTotals(vaultCache);
        unchecked {
            // totalShares >= VIRTUAL_DEPOSIT_AMOUNT > 1
            return TypesLib.toAssets((amount.toUint() * totalAssets + (totalShares - 1)) / totalShares);
        }
    }

    function mulDiv(Shares self, uint256 multiplier, uint256 divisor) internal pure returns (Shares) {
        return TypesLib.toShares(uint256(Shares.unwrap(self)) * multiplier / divisor);
    }

    function subUnchecked(Shares self, Shares b) internal pure returns (Shares) {
        unchecked {
            return Shares.wrap(uint112(self.toUint() - b.toUint()));
        }
    }
}

function addShares(Shares a, Shares b) pure returns (Shares) {
    return TypesLib.toShares(uint256(Shares.unwrap(a)) + uint256(Shares.unwrap(b)));
}

function subShares(Shares a, Shares b) pure returns (Shares) {
    return Shares.wrap((Shares.unwrap(a) - Shares.unwrap(b)));
}

function eqShares(Shares a, Shares b) pure returns (bool) {
    return Shares.unwrap(a) == Shares.unwrap(b);
}

function neqShares(Shares a, Shares b) pure returns (bool) {
    return Shares.unwrap(a) != Shares.unwrap(b);
}

function gtShares(Shares a, Shares b) pure returns (bool) {
    return Shares.unwrap(a) > Shares.unwrap(b);
}

function ltShares(Shares a, Shares b) pure returns (bool) {
    return Shares.unwrap(a) < Shares.unwrap(b);
}
