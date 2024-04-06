// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {FullMath} from "v3-core/libraries/FullMath.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {PositionUtils} from "../testUtils/PositionUtils.sol";
import "forge-std/Test.sol";

contract PositionAmountsTest is Test, PositionUtils {
    function test_Success_getLiquidityForAmountAtRatio_OTMBelow() public {
        uint160 CT = TickMath.getSqrtRatioAtTick(-100);
        uint160 TL = TickMath.getSqrtRatioAtTick(0);
        uint160 TU = TickMath.getSqrtRatioAtTick(100);

        uint128 L = PositionUtils.getLiquidityForAmountAtRatio(CT, TL, TU, 0, 10 ** 18);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(CT, TL, TU, L);

        assertApproxEqAbs(amount0, 10 ** 18, 10);
        assertApproxEqAbs(amount1, 0, 10);
    }

    function test_Success_getLiquidityForAmountAtRatio_OTMAbove() public {
        uint160 CT = TickMath.getSqrtRatioAtTick(0);
        uint160 TL = TickMath.getSqrtRatioAtTick(-100);
        uint160 TU = TickMath.getSqrtRatioAtTick(-50);

        uint128 L = PositionUtils.getLiquidityForAmountAtRatio(CT, TL, TU, 0, 10 ** 18);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(CT, TL, TU, L);

        assertApproxEqAbs(amount0, 0, 10);
        assertApproxEqAbs(amount1, 10 ** 18, 10);
    }

    function test_Success_getLiquidityForAmountAtRatio_OTMBetween(
        int256 tickUpper,
        int256 tickLower,
        int256 currentTick,
        uint256 amount
    ) public {
        currentTick = bound(currentTick, -200_000 + 1, 200_000 - 1);
        tickLower = bound(tickLower, currentTick - 2048, currentTick - 1);
        tickUpper = bound(tickUpper, currentTick + 1, currentTick + 2048);

        uint160 CT = TickMath.getSqrtRatioAtTick(int24(currentTick));
        uint160 TL = TickMath.getSqrtRatioAtTick(int24(tickLower));
        uint160 TU = TickMath.getSqrtRatioAtTick(int24(tickUpper));

        uint256 amt = bound(amount, 10 ** 18, 10 ** 30);

        uint128 L = PositionUtils.getLiquidityForAmountAtRatio(CT, TL, TU, 0, amt);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(CT, TL, TU, L);

        uint256 priceX128 = FullMath.mulDiv(CT, CT, 2 ** 64);

        assertApproxEqAbs(
            amount0 + FullMath.mulDiv(amount1, 2 ** 128, priceX128),
            amt,
            amt / 10000
        );
    }
}
