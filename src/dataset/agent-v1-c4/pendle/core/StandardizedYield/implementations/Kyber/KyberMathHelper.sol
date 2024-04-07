// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../../../interfaces/Kyber/IKyberElasticPool.sol";
import "../../../../interfaces/Kyber/IKyberElasticFactory.sol";
import "./libraries/ReinvestmentMath.sol";
import "./libraries/TickMath.sol";
import "./libraries/SwapMath.sol";
import "./libraries/LiqDeltaMath.sol";
import "./libraries/LiquidityMath.sol";
import "./libraries/QtyDeltaMath.sol";
import {MathConstants as C} from "./libraries/MathConstants.sol";
import "../../../libraries/math/PMath.sol";

import "../../../libraries/BoringOwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract KyberMathHelper is BoringOwnableUpgradeable, UUPSUpgradeable {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeCast for int128;
    using PMath for int24;
    using PMath for int256;
    using PMath for uint256;

    uint256 public constant DEFAULT_NUMBER_OF_ITERS = 30;

    address public immutable factory;

    uint256 public numBinarySearchIter;

    constructor(address _factory) initializer {
        factory = _factory;
    }

    function _authorizeUpgrade(address) internal virtual override onlyOwner {}

    function initialize() external initializer {
        __BoringOwnable_init();
        numBinarySearchIter = DEFAULT_NUMBER_OF_ITERS;
    }

    function setNumBinarySearchIter(uint256 newNumBinarySearchIter) external onlyOwner {
        numBinarySearchIter = newNumBinarySearchIter;
    }

    struct BinarySearchParams {
        uint256 low;
        uint256 high;
        uint160 lowerSqrtP;
        uint160 upperSqrtP;
        uint256 guess;
        uint256 amountOut;
        int24 newTick;
        uint160 currentSqrtP;
        uint128 liq0;
        uint128 liq1;
    }

    function previewDeposit(
        address kyberPool,
        int24 tickLower,
        int24 tickUpper,
        bool isToken0,
        uint256 amountIn
    ) external view returns (uint256) {
        uint256 amountToSwap = getSingleSidedSwapAmount(kyberPool, amountIn, isToken0, tickLower, tickUpper);
        (uint256 amountOut, , uint160 newSqrtP) = _simulateSwapExactIn(
            kyberPool,
            amountToSwap,
            _getExtCache(kyberPool, isToken0)
        );
        return
            LiquidityMath.getLiquidityFromQties(
                newSqrtP,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                amountIn - amountToSwap,
                amountOut
            );
    }

    /**
     * @dev preview redeem function is intentionally left incorrect
     * as it uses the old state of the pool to calculate the final swap
     * instead of the state of the pool after removing liquidity
     */
    function previewRedeem(
        address kyberPool,
        int24 tickLower,
        int24 tickUpper,
        bool isToken0,
        uint256 amountShares
    ) external view returns (uint256) {
        (uint256 amount0, uint256 amount1) = _simulateBurn(kyberPool, tickLower, tickUpper, amountShares);

        (uint256 amountOut, , ) = _simulateSwapExactIn(
            kyberPool,
            isToken0 ? amount1 : amount0,
            _getExtCache(kyberPool, isToken0)
        );

        return (isToken0 ? amount0 : amount1) + amountOut;
    }

    function getSingleSidedSwapAmount(
        address kyberPool,
        uint256 startAmount,
        bool isToken0,
        int24 tickLower,
        int24 tickUpper
    ) public view returns (uint256 amountToSwap) {
        BinarySearchParams memory params;

        params.low = 0;
        params.high = startAmount;
        params.lowerSqrtP = TickMath.getSqrtRatioAtTick(tickLower);
        params.upperSqrtP = TickMath.getSqrtRatioAtTick(tickUpper);
        ExternalCache memory ext = _getExtCache(kyberPool, isToken0);

        for (uint256 iter = 0; iter < numBinarySearchIter && params.low != params.high; ++iter) {
            // First 2 iterations are reserved for 2 bounds (0) and (startAmount)
            // If either of the bounds satisfies, the loop should ends itself with low != high condition
            if (iter == 0) {
                params.guess = 0;
            } else if (iter == 1) {
                params.guess = startAmount;
            } else {
                params.guess = (params.low + params.high) / 2;
            }

            (params.amountOut, params.newTick, params.currentSqrtP) = _simulateSwapExactIn(
                kyberPool,
                params.guess,
                ext
            );

            if (isToken0) {
                if (params.newTick < tickLower) {
                    params.high = params.guess;
                } else if (params.newTick >= tickUpper) {
                    params.low = params.guess;
                } else {
                    uint128 liq0 = LiquidityMath.getLiquidityFromQty0(
                        params.currentSqrtP,
                        params.upperSqrtP,
                        startAmount - params.guess
                    );
                    uint128 liq1 = LiquidityMath.getLiquidityFromQty1(
                        params.lowerSqrtP,
                        params.currentSqrtP,
                        params.amountOut
                    );
                    if (liq0 < liq1) {
                        params.high = params.guess;
                    } else {
                        params.low = params.guess;
                    }
                }
            } else {
                if (params.newTick < tickLower) {
                    params.low = params.guess;
                } else if (params.newTick >= tickUpper) {
                    params.high = params.guess;
                } else {
                    uint128 liq0 = LiquidityMath.getLiquidityFromQty0(
                        params.currentSqrtP,
                        params.upperSqrtP,
                        params.amountOut
                    );
                    uint128 liq1 = LiquidityMath.getLiquidityFromQty1(
                        params.lowerSqrtP,
                        params.currentSqrtP,
                        startAmount - params.guess
                    );
                    if (liq1 < liq0) {
                        params.high = params.guess;
                    } else {
                        params.low = params.guess;
                    }
                }
            }
        }
        amountToSwap = params.high;
    }

    // temporary swap variables, some of which will be used to update the pool state
    struct SwapData {
        int256 specifiedAmount; // the specified amount (could be tokenIn or tokenOut)
        int256 returnedAmount; // the opposite amout of sourceQty
        uint160 sqrtP; // current sqrt(price), multiplied by 2^96
        int24 currentTick; // the tick associated with the current price
        int24 nextTick; // the next initialized tick
        uint160 nextSqrtP; // the price of nextTick
        bool isToken0; // true if specifiedAmount is in token0, false if in token1
        bool isExactInput; // true = input qty, false = output qty
        uint128 baseL; // the cached base pool liquidity without reinvestment liquidity
        uint128 reinvestL; // the cached reinvestment liquidity
        uint160 startSqrtP; // the start sqrt price before each iteration
        /// ---------------- PENDLE additional data --------------------------
        uint256 feeUnit;
        uint256 reinvestLLast;
    }

    // variables below are loaded only when crossing a tick
    struct SwapCache {
        uint256 rTotalSupply; // cache of total reinvestment token supply
        uint128 reinvestLLast; // collected liquidity
        uint256 feeGrowthGlobal; // cache of fee growth of the reinvestment token, multiplied by 2^96
        uint128 secondsPerLiquidityGlobal; // all-time seconds per liquidity, multiplied by 2^96
        uint24 governmentFeeUnits; // governmentFeeUnits to be charged
        uint256 governmentFee; // qty of reinvestment token for government fee
        uint256 lpFee; // qty of reinvestment token for liquidity provider
    }

    struct ExternalCache {
        uint256 rTotalSupply;
        uint256 feeGrowthGlobal;
        uint24 governmentFeeUnits; // governmentFeeUnits to be charged
        uint256 governmentFee; // qty of reinvestment token for government fee
        uint128 baseL;
        uint128 reinvestL;
        uint128 reinvestLLast;
        uint160 sqrtP;
        int24 currentTick;
        int24 nextTick;
        uint256 feeUnit;
        bool willUpTick;
        bool isToken0;
    }

    function _simulateSwapExactIn(
        address kyberPool,
        uint256 swapQty,
        ExternalCache memory ext
    ) internal view returns (uint256 amountOut, int24 newTick, uint160 newSqrtP) {
        SwapData memory swapData = SwapData({
            specifiedAmount: swapQty.Int(),
            returnedAmount: 0,
            sqrtP: ext.sqrtP,
            currentTick: ext.currentTick,
            nextTick: ext.nextTick,
            nextSqrtP: 0,
            isToken0: ext.isToken0,
            isExactInput: true,
            baseL: ext.baseL,
            reinvestL: ext.reinvestL,
            startSqrtP: 0,
            feeUnit: ext.feeUnit,
            reinvestLLast: ext.reinvestLLast
        });

        bool willUpTick = ext.willUpTick;

        SwapCache memory cache;
        while (swapData.specifiedAmount != 0) {
            int24 tempNextTick = swapData.nextTick;
            if (willUpTick && tempNextTick > C.MAX_TICK_DISTANCE + swapData.currentTick) {
                tempNextTick = swapData.currentTick + C.MAX_TICK_DISTANCE;
            } else if (!willUpTick && tempNextTick < swapData.currentTick - C.MAX_TICK_DISTANCE) {
                tempNextTick = swapData.currentTick - C.MAX_TICK_DISTANCE;
            }

            swapData.startSqrtP = swapData.sqrtP;
            swapData.nextSqrtP = TickMath.getSqrtRatioAtTick(tempNextTick);

            {
                uint160 targetSqrtP = swapData.nextSqrtP;

                int256 usedAmount;
                int256 returnedAmount;
                uint256 deltaL;
                (usedAmount, returnedAmount, deltaL, swapData.sqrtP) = SwapMath.computeSwapStep(
                    swapData.baseL + swapData.reinvestL,
                    swapData.sqrtP,
                    targetSqrtP,
                    swapData.feeUnit,
                    swapData.specifiedAmount,
                    swapData.isExactInput,
                    swapData.isToken0
                );

                swapData.specifiedAmount -= usedAmount;
                swapData.returnedAmount += returnedAmount;
                swapData.reinvestL += deltaL.toUint128();
            }

            // if price has not reached the next sqrt price
            if (swapData.sqrtP != swapData.nextSqrtP) {
                if (swapData.sqrtP != swapData.startSqrtP) {
                    // update the current tick data in case the sqrtP has changed
                    swapData.currentTick = TickMath.getTickAtSqrtRatio(swapData.sqrtP);
                }
                break;
            }
            swapData.currentTick = willUpTick ? tempNextTick : tempNextTick - 1;

            // if tempNextTick is not next initialized tick
            if (tempNextTick != swapData.nextTick) continue;

            if (cache.rTotalSupply == 0) {
                // load variables that are only initialized when crossing a tick
                cache.rTotalSupply = ext.rTotalSupply;
                cache.reinvestLLast = swapData.reinvestLLast.toUint128();
                cache.feeGrowthGlobal = ext.feeGrowthGlobal;

                // not sure if this is necessary for the amount out & current tick computation
                // let's ignore for now
                // cache.secondsPerLiquidityGlobal = _syncSecondsPerLiquidity(
                //     poolData.secondsPerLiquidityGlobal,
                //     swapData.baseL
                // );
                cache.governmentFeeUnits = ext.governmentFeeUnits;
            }

            // update rTotalSupply, feeGrowthGlobal and reinvestL
            uint256 rMintQty = ReinvestmentMath.calcrMintQty(
                swapData.reinvestL,
                cache.reinvestLLast,
                swapData.baseL,
                cache.rTotalSupply
            );

            if (rMintQty != 0) {
                cache.rTotalSupply += rMintQty;
                // overflow/underflow not possible bc governmentFeeUnits < 20000
                unchecked {
                    uint256 governmentFee = (rMintQty * cache.governmentFeeUnits) / C.FEE_UNITS;
                    cache.governmentFee += governmentFee;

                    uint256 lpFee = rMintQty - governmentFee;
                    cache.lpFee += lpFee;

                    cache.feeGrowthGlobal += FullMath.mulDivFloor(lpFee, C.TWO_POW_96, swapData.baseL);
                }
            }
            cache.reinvestLLast = swapData.reinvestL;

            (swapData.baseL, swapData.nextTick) = _updateLiquidityAndCrossTick(
                kyberPool,
                swapData.nextTick,
                swapData.baseL,
                cache.feeGrowthGlobal,
                cache.secondsPerLiquidityGlobal,
                willUpTick
            );
        }

        amountOut = swapData.returnedAmount.abs();
        newTick = swapData.currentTick;
        newSqrtP = swapData.sqrtP;
    }

    function _simulateBurn(
        address kyberPool,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity
    ) internal view returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtP, int24 currentTick, , ) = IKyberElasticPool(kyberPool).getPoolState();

        if (currentTick < tickLower) {
            amount0 = QtyDeltaMath
                .calcRequiredQty0(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidity.Uint128(),
                    false
                )
                .abs();
        } else if (currentTick >= tickUpper) {
            amount1 = QtyDeltaMath
                .calcRequiredQty1(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidity.Uint128(),
                    false
                )
                .abs();
        } else {
            amount0 = QtyDeltaMath
                .calcRequiredQty0(sqrtP, TickMath.getSqrtRatioAtTick(tickUpper), liquidity.Uint128(), false)
                .abs();
            amount1 = QtyDeltaMath
                .calcRequiredQty1(TickMath.getSqrtRatioAtTick(tickLower), sqrtP, liquidity.Uint128(), false)
                .abs();
        }
    }

    function _updateLiquidityAndCrossTick(
        address kyberPool,
        int24 nextTick,
        uint128 currentLiquidity,
        uint256,
        uint128,
        bool willUpTick
    ) internal view returns (uint128 newLiquidity, int24 newNextTick) {
        (, int128 liquidityNet, , ) = IKyberElasticPool(kyberPool).ticks(nextTick);
        if (willUpTick) {
            (, newNextTick) = IKyberElasticPool(kyberPool).initializedTicks(nextTick);
        } else {
            (newNextTick, ) = IKyberElasticPool(kyberPool).initializedTicks(nextTick);
            liquidityNet = -liquidityNet;
        }
        newLiquidity = LiqDeltaMath.applyLiquidityDelta(
            currentLiquidity,
            liquidityNet >= 0 ? uint128(liquidityNet) : liquidityNet.revToUint128(),
            liquidityNet >= 0
        );
    }

    function _getExtCache(address kyberPool, bool isToken0) internal view returns (ExternalCache memory ext) {
        bool willUpTick = !isToken0;
        (ext.baseL, ext.reinvestL, ext.reinvestLLast) = IKyberElasticPool(kyberPool).getLiquidityState();
        (ext.sqrtP, ext.currentTick, ext.nextTick, ) = IKyberElasticPool(kyberPool).getPoolState();
        if (willUpTick) {
            (, ext.nextTick) = IKyberElasticPool(kyberPool).initializedTicks(ext.nextTick);
        }
        ext.feeUnit = IKyberElasticPool(kyberPool).swapFeeUnits();

        ext.rTotalSupply = IKyberElasticPool(kyberPool).totalSupply();
        ext.feeGrowthGlobal = IKyberElasticPool(kyberPool).getFeeGrowthGlobal();
        (, ext.governmentFeeUnits) = IKyberElasticFactory(factory).feeConfiguration();
    }
}
