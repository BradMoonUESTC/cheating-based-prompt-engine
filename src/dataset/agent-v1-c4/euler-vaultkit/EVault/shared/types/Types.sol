// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../IEVault.sol";

import "./VaultStorage.sol";
import "./Snapshot.sol";
import "./UserStorage.sol";

import "./Shares.sol";
import "./Assets.sol";
import "./Owed.sol";
import "./ConfigAmount.sol";
import "./Flags.sol";
import "./AmountCap.sol";

/// @notice In this file, custom types are defined and linked globally with their libraries and operators

type Shares is uint112;

type Assets is uint112;

type Owed is uint144;

type AmountCap is uint16;

type ConfigAmount is uint16;

type Flags is uint32;

using SharesLib for Shares global;
using {
    addShares as +, subShares as -, eqShares as ==, neqShares as !=, gtShares as >, ltShares as <
} for Shares global;

using AssetsLib for Assets global;
using {
    addAssets as +,
    subAssets as -,
    eqAssets as ==,
    neqAssets as !=,
    gtAssets as >,
    gteAssets as >=,
    ltAssets as <,
    lteAssets as <=
} for Assets global;

using OwedLib for Owed global;
using {addOwed as +, subOwed as -, eqOwed as ==, neqOwed as !=, gtOwed as >, ltOwed as <} for Owed global;

using ConfigAmountLib for ConfigAmount global;
using {
    gtConfigAmount as >, gteConfigAmount as >=, ltConfigAmount as <, lteConfigAmount as <=
} for ConfigAmount global;

using AmountCapLib for AmountCap global;
using FlagsLib for Flags global;

/// @title TypesLib
/// @notice Library for casting basic types' amounts into custom types
library TypesLib {
    function toShares(uint256 amount) internal pure returns (Shares) {
        if (amount > MAX_SANE_AMOUNT) revert Errors.E_AmountTooLargeToEncode();
        return Shares.wrap(uint112(amount));
    }

    function toAssets(uint256 amount) internal pure returns (Assets) {
        if (amount > MAX_SANE_AMOUNT) revert Errors.E_AmountTooLargeToEncode();
        return Assets.wrap(uint112(amount));
    }

    function toOwed(uint256 amount) internal pure returns (Owed) {
        if (amount > MAX_SANE_DEBT_AMOUNT) revert Errors.E_DebtAmountTooLargeToEncode();
        return Owed.wrap(uint144(amount));
    }

    function toConfigAmount(uint16 amount) internal pure returns (ConfigAmount) {
        if (amount > CONFIG_SCALE) revert Errors.E_ConfigAmountTooLargeToEncode();
        return ConfigAmount.wrap(amount);
    }
}
