// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Storage} from "./Storage.sol";
import "./types/Types.sol";

/// @title LTVUtils
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Overridable getters for LTV configuration
abstract contract LTVUtils is Storage {
    function getLTV(address collateral, bool liquidation) internal view virtual returns (ConfigAmount) {
        return vaultStorage.ltvLookup[collateral].getLTV(liquidation);
    }

    function isRecognizedCollateral(address collateral) internal view virtual returns (bool) {
        return vaultStorage.ltvLookup[collateral].isRecognizedCollateral();
    }
}
