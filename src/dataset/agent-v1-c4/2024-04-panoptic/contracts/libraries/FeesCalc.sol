// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

// Interfaces
import {IUniswapV3Pool} from "univ3-core/interfaces/IUniswapV3Pool.sol";
// Libraries
import {Math} from "@libraries/Math.sol";
import {PanopticMath} from "@libraries/PanopticMath.sol";
// Custom types
import {LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";
import {LiquidityChunk} from "@types/LiquidityChunk.sol";
import {TokenId} from "@types/TokenId.sol";

/// @title Library for Fee Calculations.
/// @author Axicon Labs Limited
/// @notice Compute fees accumulated within option position legs (a leg is a liquidity chunk).
/// @dev Some options positions involve moving liquidity chunks to the AMM/Uniswap. Those chunks can then earn AMM swap fees.
//
//          When price tick moves within
//          this liquidity chunk == an option leg within a `tokenId` option position:
//          Fees accumulate.
//                ◄────────────►
//     liquidity  ┌───┼────────┐
//          ▲     │   │        │
//          │     │   :        ◄──────Liquidity chunk
//          │     │   │        │      (an option position leg)
//          │   ┌─┴───┼────────┴─┐
//          │   │     │          │
//          │   │     :          │
//          │   │     │          │
//          │   │     :          │
//          │   │     │          │
//          └───┴─────┴──────────┴────► price
//                    ▲
//                    │
//            Current price tick
//              of the AMM
//
library FeesCalc {
    /// @notice Calculate NAV of user's option portfolio at a given tick.
    /// @param atTick The tick to calculate the value at
    /// @param userBalance The position balance array for the user (left=tokenId, right=positionSize)
    /// @param positionIdList A list of all positions the user holds on that pool
    /// @return value0 The amount of token0 owned by portfolio
    /// @return value1 The amount of token1 owned by portfolio
    function getPortfolioValue(
        int24 atTick,
        mapping(TokenId tokenId => LeftRightUnsigned balance) storage userBalance,
        TokenId[] calldata positionIdList
    ) external view returns (int256 value0, int256 value1) {
        for (uint256 k = 0; k < positionIdList.length; ) {
            TokenId tokenId = positionIdList[k];
            uint128 positionSize = userBalance[tokenId].rightSlot();
            uint256 numLegs = tokenId.countLegs();
            for (uint256 leg = 0; leg < numLegs; ) {
                LiquidityChunk liquidityChunk = PanopticMath.getLiquidityChunk(
                    tokenId,
                    leg,
                    positionSize
                );

                (uint256 amount0, uint256 amount1) = Math.getAmountsForLiquidity(
                    atTick,
                    liquidityChunk
                );

                if (tokenId.isLong(leg) == 0) {
                    unchecked {
                        value0 += int256(amount0);
                        value1 += int256(amount1);
                    }
                } else {
                    unchecked {
                        value0 -= int256(amount0);
                        value1 -= int256(amount1);
                    }
                }

                unchecked {
                    ++leg;
                }
            }
            unchecked {
                ++k;
            }
        }
    }

    /// @notice Calculate the AMM Swap/trading fees for a `liquidityChunk` of each token.
    /// @dev Read from the uniswap pool and compute the accumulated fees from swapping activity.
    /// @param univ3pool The AMM/Uniswap pool where fees are collected from
    /// @param currentTick The current price tick
    /// @param tickLower The lower tick of the chunk to calculate fees for
    /// @param tickUpper The upper tick of the chunk to calculate fees for
    /// @param liquidity The liquidity amount of the chunk to calculate fees for
    /// @return The fees collected from the AMM for each token (LeftRight-packed) with token0 in the right slot and token1 in the left slot
    function calculateAMMSwapFees(
        IUniswapV3Pool univ3pool,
        int24 currentTick,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public view returns (LeftRightSigned) {
        // extract the amount of AMM fees collected within the liquidity chunk`
        // note: the fee variables are *per unit of liquidity*; so more "rate" variables
        (
            uint256 ammFeesPerLiqToken0X128,
            uint256 ammFeesPerLiqToken1X128
        ) = _getAMMSwapFeesPerLiquidityCollected(univ3pool, currentTick, tickLower, tickUpper);

        // Use the fee growth (rate) variable to compute the absolute fees accumulated within the chunk:
        //   ammFeesToken0X128 * liquidity / (2**128)
        // to store the (absolute) fees as int128:
        return
            LeftRightSigned
                .wrap(0)
                .toRightSlot(int128(int256(Math.mulDiv128(ammFeesPerLiqToken0X128, liquidity))))
                .toLeftSlot(int128(int256(Math.mulDiv128(ammFeesPerLiqToken1X128, liquidity))));
    }

    /// @notice Calculates the fee growth that has occurred (per unit of liquidity) in the AMM/Uniswap for an
    /// option position's tick range.
    /// @dev Extracts the feeGrowth from the uniswap v3 pool.
    /// @param univ3pool The AMM pool where the leg is deployed
    /// @param currentTick The current price tick in the AMM
    /// @param tickLower The lower tick of the option position leg (a liquidity chunk)
    /// @param tickUpper The upper tick of the option position leg (a liquidity chunk)
    /// @return feeGrowthInside0X128 the fee growth in the AMM of token0
    /// @return feeGrowthInside1X128 the fee growth in the AMM of token1
    function _getAMMSwapFeesPerLiquidityCollected(
        IUniswapV3Pool univ3pool,
        int24 currentTick,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        // Get feesGrowths from the option position's lower+upper ticks
        // lowerOut0: For token0: fee growth per unit of liquidity on the _other_ side of tickLower (relative to currentTick)
        // only has relative meaning, not absolute — the value depends on when the tick is initialized
        // (...)
        // upperOut1: For token1: fee growth on the _other_ side of tickUpper (again: relative to currentTick)
        // the point is: the range covered by lowerOut0 changes depending on where currentTick is.
        (, , uint256 lowerOut0, uint256 lowerOut1, , , , ) = univ3pool.ticks(tickLower);
        (, , uint256 upperOut0, uint256 upperOut1, , , , ) = univ3pool.ticks(tickUpper);

        // compute the effective feeGrowth, depending on whether price is above/below/within range
        unchecked {
            if (currentTick < tickLower) {
                /**
                  Diagrams shown for token0, and applies for token1 the same
                  L = lowerTick, U = upperTick

                    liquidity         lowerOut0 (all fees collected in this price tick range for token0)
                        ▲            ◄──────────────^v───► (to MAX_TICK)
                        │
                        │                      upperOut0
                        │                     ◄─────^v───►
                        │           ┌────────┐
                        │           │ chunk  │
                        │           │        │
                        └─────▲─────┴────────┴────────► price tick
                              │     L        U
                              │
                           current
                            tick
                */
                feeGrowthInside0X128 = lowerOut0 - upperOut0; // fee growth inside the chunk
                feeGrowthInside1X128 = lowerOut1 - upperOut1;
            } else if (currentTick >= tickUpper) {
                /**
                    liquidity
                        ▲           upperOut0
                        │◄─^v─────────────────────►
                        │     
                        │     lowerOut0  ┌────────┐
                        │◄─^v───────────►│ chunk  │
                        │                │        │
                        └────────────────┴────────┴─▲─────► price tick
                                         L        U │
                                                    │
                                                 current
                                                  tick
                 */
                feeGrowthInside0X128 = upperOut0 - lowerOut0;
                feeGrowthInside1X128 = upperOut1 - lowerOut1;
            } else {
                /**
                  current AMM tick is within the option position range (within the chunk)

                     liquidity
                        ▲        feeGrowthGlobal0X128 = global fee growth
                        │                             = (all fees collected for the entire price range for token 0)
                        │
                        │                        
                        │     lowerOut0  ┌──────────────┐ upperOut0
                        │◄─^v───────────►│              │◄─────^v───►
                        │                │     chunk    │
                        │                │              │
                        └────────────────┴───────▲──────┴─────► price tick
                                         L       │      U
                                                 │
                                              current
                                               tick
                */
                feeGrowthInside0X128 = univ3pool.feeGrowthGlobal0X128() - lowerOut0 - upperOut0;
                feeGrowthInside1X128 = univ3pool.feeGrowthGlobal1X128() - lowerOut1 - upperOut1;
            }
        }
    }
}
