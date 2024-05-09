// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

library Errors {
    string public constant VAULT_INVALID_MAXLEVERAGE = "0";
    string public constant VAULT_INVALID_TAX_BASIS_POINTS = "1";
    string public constant VAULT_INVALID_STABLE_TAX_BASIS_POINTS = "2";
    string public constant VAULT_INVALID_MINT_BURN_FEE_BASIS_POINTS = "3";
    string public constant VAULT_INVALID_SWAP_FEE_BASIS_POINTS = "4";
    string public constant VAULT_INVALID_STABLE_SWAP_FEE_BASIS_POINTS = "5";
    string public constant VAULT_INVALID_MARGIN_FEE_BASIS_POINTS = "6";
    string public constant VAULT_INVALID_LIQUIDATION_FEE_ETH = "7";
    string public constant VAULT_INVALID_BORROWING_INTERVALE = "8";
    string public constant VAULT_INVALID_BORROWING_RATE_FACTOR = "9";
    string public constant VAULT_INVALID_STABLE_BORROWING_RATE_FACTOR = "10";
    string public constant VAULT_TOKEN_NOT_WHITELISTED = "11";
    string public constant VAULT_INVALID_TOKEN_AMOUNT = "12";
    string public constant VAULT_INVALID_ETHG_AMOUNT = "13";
    string public constant VAULT_INVALID_REDEMPTION_AMOUNT = "14";
    string public constant VAULT_INVALID_AMOUNT_OUT = "15";
    string public constant VAULT_SWAPS_NOT_ENABLED = "16";
    string public constant VAULT_TOKEN_IN_NOT_WHITELISTED = "17";
    string public constant VAULT_TOKEN_OUT_NOT_WHITELISTED = "18";
    string public constant VAULT_INVALID_TOKENS = "19";
    string public constant VAULT_INVALID_AMOUNT_IN = "20";
    string public constant VAULT_LEVERAGE_NOT_ENABLED = "21";
    string public constant VAULT_INSUFFICIENT_COLLATERAL_FOR_FEES = "22";
    string public constant VAULT_INVALID_POSITION_SIZE = "23";
    string public constant VAULT_EMPTY_POSITION = "24";
    string public constant VAULT_POSITION_SIZE_EXCEEDED = "25";
    string public constant VAULT_POSITION_COLLATERAL_EXCEEDED = "26";
    string public constant VAULT_INVALID_LIQUIDATOR = "27";
    string public constant VAULT_POSITION_CAN_NOT_BE_LIQUIDATED = "28";
    string public constant VAULT_INVALID_POSITION = "29";
    string public constant VAULT_INVALID_AVERAGE_PRICE = "30";
    string public constant VAULT_COLLATERAL_SHOULD_BE_WITHDRAWN = "31";
    string public constant VAULT_SIZE_MUST_BE_MORE_THAN_COLLATERAL = "32";
    string public constant VAULT_INVALID_MSG_SENDER = "33";
    string public constant VAULT_MISMATCHED_TOKENS = "34";
    string public constant VAULT_COLLATERAL_TOKEN_NOT_WHITELISTED = "35";
    string public constant VAULT_COLLATERAL_TOKEN_MUST_NOT_BE_A_STABLE_TOKEN =
        "36";
    string public constant VAULT_COLLATERAL_TOKEN_MUST_BE_STABLE_TOKEN = "37";
    string public constant VAULT_INDEX_TOKEN_MUST_NOT_BE_STABLE_TOKEN = "38";
    string public constant VAULT_INDEX_TOKEN_NOT_SHORTABLE = "39";
    string public constant VAULT_INVALID_INCREASE = "40";
    string public constant VAULT_RESERVE_EXCEEDS_POOL = "41";
    string public constant VAULT_MAX_ETHG_EXCEEDED = "42";
    string public constant VAULT_FORBIDDEN = "43";
    string public constant VAULT_MAX_GAS_PRICE_EXCEEDED = "44";
    string public constant VAULT_POOL_AMOUNT_LESS_THAN_BUFFER_AMOUNT = "45";
    string public constant VAULT_POOL_AMOUNT_EXCEEDED = "46";
    string public constant VAULT_MAX_SHORTS_EXCEEDED = "47";
    string public constant VAULT_INSUFFICIENT_RESERVE = "48";
    string public constant VAULT_NFT_USER_NOT_EXIST = "49";
    string public constant VAULT_NFT_NOT_EXIST = "50";
    string public constant VAULT_NOT_SWAPER = "51";

    string public constant MATH_MULTIPLICATION_OVERFLOW = "52";
    string public constant MATH_DIVISION_BY_ZERO = "53";

    string public constant INVALID_CALLER = "54";

    // Funding Fee Error
    string public constant EMPTY_OPEN_INTEREST = "60";
}
