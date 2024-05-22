// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// Implementation internals

// asset amounts are shifted left by this number of bits for increased precision of debt tracking.
uint256 constant INTERNAL_DEBT_PRECISION_SHIFT = 31;
// max amount for Assets and Shares custom types based on a uint112.
uint256 constant MAX_SANE_AMOUNT = type(uint112).max;
// max debt amount fits in uint144 (112 + 31 bits).
// Last 31 bits are zeros to ensure max debt rounded up equals max sane amount.
uint256 constant MAX_SANE_DEBT_AMOUNT = uint256(MAX_SANE_AMOUNT) << INTERNAL_DEBT_PRECISION_SHIFT;
// proxy trailing calldata length in bytes.
// Three addresses, 20 bytes each: vault underlying asset, oracle and unit of account.
uint256 constant PROXY_METADATA_LENGTH = 60;
// gregorian calendar
uint256 constant SECONDS_PER_YEAR = 365.2425 * 86400;
// max interest rate accepted from IRM. 1,000,000% APY: floor(((1000000 / 100 + 1)**(1/(86400*365.2425)) - 1) * 1e27)
uint256 constant MAX_ALLOWED_INTEREST_RATE = 291867278914945094175;
// max valid value of the ConfigAmount custom type, signifying 100%
uint16 constant CONFIG_SCALE = 1e4;

// Account status checks special values

// no account status checks should be scheduled
address constant CHECKACCOUNT_NONE = address(0);
// account status check should be scheduled for the authenticated account
address constant CHECKACCOUNT_CALLER = address(1);

// Operations

uint32 constant OP_DEPOSIT = 1 << 0;
uint32 constant OP_MINT = 1 << 1;
uint32 constant OP_WITHDRAW = 1 << 2;
uint32 constant OP_REDEEM = 1 << 3;
uint32 constant OP_TRANSFER = 1 << 4;
uint32 constant OP_SKIM = 1 << 5;
uint32 constant OP_BORROW = 1 << 6;
uint32 constant OP_REPAY = 1 << 7;
uint32 constant OP_REPAY_WITH_SHARES = 1 << 8;
uint32 constant OP_PULL_DEBT = 1 << 9;
uint32 constant OP_CONVERT_FEES = 1 << 10;
uint32 constant OP_LIQUIDATE = 1 << 11;
uint32 constant OP_FLASHLOAN = 1 << 12;
uint32 constant OP_TOUCH = 1 << 13;
uint32 constant OP_VAULT_STATUS_CHECK = 1 << 14;
// Delimiter of possible operations
uint32 constant OP_MAX_VALUE = 1 << 15;

// Config Flags

// When flag is set, debt socialization during liquidation is disabled
uint32 constant CFG_DONT_SOCIALIZE_DEBT = 1 << 0;
// When flag is set, asset is considered to be compatible with EVC sub-accounts and protections
// against sending assets to sub-accounts are disabled
uint32 constant CFG_EVC_COMPATIBLE_ASSET = 1 << 1;
// Delimiter of possible config flags
uint32 constant CFG_MAX_VALUE = 1 << 2;

// EVC authentication

// in order to perform these operations, the account doesn't need to have the vault installed as a controller
uint32 constant CONTROLLER_NEUTRAL_OPS = OP_DEPOSIT | OP_MINT | OP_WITHDRAW | OP_REDEEM | OP_TRANSFER | OP_SKIM
    | OP_REPAY | OP_REPAY_WITH_SHARES | OP_CONVERT_FEES | OP_FLASHLOAN | OP_TOUCH | OP_VAULT_STATUS_CHECK;
