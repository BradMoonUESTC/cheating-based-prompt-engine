// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Library of Constants used in Panoptic.
/// @author Axicon Labs Limited
/// @notice This library provides constants used in Panoptic.
library Constants {
    /// @notice Fixed point multiplier: 2**96
    uint256 internal constant FP96 = 0x1000000000000000000000000;

    /// @notice Minimum possible price tick in a Uniswap V3 pool
    int24 internal constant MIN_V3POOL_TICK = -887272;

    /// @notice Maximum possible price tick in a Uniswap V3 pool
    int24 internal constant MAX_V3POOL_TICK = 887272;

    /// @notice Minimum possible sqrtPriceX96 in a Uniswap V3 pool
    uint160 internal constant MIN_V3POOL_SQRT_RATIO = 4295128739;

    /// @notice Maximum possible sqrtPriceX96 in a Uniswap V3 pool
    uint160 internal constant MAX_V3POOL_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;
}
