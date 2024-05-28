pragma solidity >=0.7.0 <0.9.0;
library Constants {
    // common
    uint32 constant ONE_HUNDRED_PERCENT = 1_000;
    uint128 constant MIN_TRANSACTION_VALUE = 0.01 ever;
    uint64 constant MAX_UINT_64 = 2**64 - 1;
    // StEverVault
    uint128 constant INCREASE_STRATEGY_TOTAL_ASSETS_CORRECTION = 0.3 ever;
        // Emergency
    uint64 constant TIME_AFTER_EMERGENCY_CAN_BE_ACTIVATED = 7 days;
    uint64 constant TIME_AFTER_EMERGENCY_CAN_BE_ACTIVATED_MAX = 365 days;

    // DePooLStrategyFactory
    uint128 constant MAX_STRATEGY_PER_UPGRADE = 50;
    // StEverAccount
    uint128 constant MAX_PENDING_COUNT = 50;
}

library PlatformType {
    uint8 constant ACCOUNT = 0;
    uint8 constant CLUSTER = 1;
}