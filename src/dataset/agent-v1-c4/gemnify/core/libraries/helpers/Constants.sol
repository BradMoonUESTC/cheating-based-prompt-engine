// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library Constants {
    // public
    uint256 public constant PERCENTAGE_FACTOR = 1e4;
    uint256 public constant PRICE_PRECISION = 1e30;
    uint256 public constant ETHG_DECIMALS = 18;
    uint256 public constant ULP_PRECISION = 1e18;

    // Vault
    uint256 public constant BORROWING_RATE_PRECISION = 1000000;
    uint256 public constant MIN_LEVERAGE = 1e4; // 1x
    uint256 public constant MAX_FEE_BASIS_POINTS = 500; // 5%
    uint256 public constant MAX_LIQUIDATION_FEE_ETH = (100 * PRICE_PRECISION);
    uint256 public constant MIN_BORROWING_RATE_INTERVAL = 1 hours;
    uint256 public constant MAX_BORROWING_RATE_FACTOR = 1e4; // 1%

    // UlpManager
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours;

    // ShortsTracker
    uint256 public constant MAX_INT256 = uint256(type(int256).max);

    // VaultPriceFeed
    uint256 public constant ONE_ETH = PRICE_PRECISION;
    uint256 public constant MAX_SPREAD_BASIS_POINTS = 50;
    uint256 public constant MAX_ADJUSTMENT_INTERVAL = 2 hours;
    uint256 public constant MAX_ADJUSTMENT_BASIS_POINTS = 20;

    // FastPrieFeed
    uint256 public constant CUMULATIVE_DELTA_PRECISION = 10 * 1000 * 1000;
    uint256 public constant MAX_REF_PRICE = type(uint160).max;
    uint256 public constant MAX_CUMULATIVE_REF_DELTA = type(uint32).max;
    uint256 public constant MAX_CUMULATIVE_FAST_DELTA = type(uint32).max;
    // uint256(~0) is 256 bits of 1s
    // shift the 1s by (256 - 32) to get (256 - 32) 0s followed by 32 1s
    uint256 public constant BITMASK_32 = uint256(int256(~0)) >> (256 - 32);
    uint256 public constant MAX_PRICE_DURATION = 30 minutes;

    // Reward
    uint256 public constant BONUS_DURATION = 365 days;
}
