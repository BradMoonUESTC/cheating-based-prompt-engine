// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

// Interfaces
import {CollateralTracker} from "@contracts/CollateralTracker.sol";
import {IUniswapV3Pool} from "univ3-core/interfaces/IUniswapV3Pool.sol";
// Libraries
import {Constants} from "@libraries/Constants.sol";
import {Errors} from "@libraries/Errors.sol";
import {Math} from "@libraries/Math.sol";
// Custom types
import {LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";
import {LiquidityChunk} from "@types/LiquidityChunk.sol";
import {TokenId} from "@types/TokenId.sol";

/// @title Compute general math quantities relevant to Panoptic and AMM pool management.
/// @author Axicon Labs Limited
library PanopticMath {
    // Used for safecasting
    using Math for uint256;

    /// @notice This is equivalent to type(uint256).max — used in assembly blocks as a replacement.
    uint256 internal constant MAX_UINT256 = 2 ** 256 - 1;

    /// @notice masks 16-bit tickSpacing out of 64-bit [16-bit tickspacing][48-bit poolPattern] format poolId
    uint64 internal constant TICKSPACING_MASK = 0xFFFF000000000000;

    /*//////////////////////////////////////////////////////////////
                              MATH HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Given an address to a Uniswap v3 pool, return its 64-bit ID as used in the `TokenId` of Panoptic.
    /// @dev Example:
    ///      the 64 bits are the 48 *last* (most significant) bits - and thus corresponds to the *first* 12 hex characters (reading left to right)
    ///      of the Uniswap v3 pool address, with the tickSpacing written in the highest 16 bits (i.e, max tickSpacing is 32768)
    ///      e.g.:
    ///        univ3pool   = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8
    ///        tickSpacing = 60
    ///      the returned id is then:
    ///        poolPattern = 0x00008ad599c3A0ff
    ///        tickSpacing = 0x003c000000000000    +
    ///        --------------------------------------------
    ///        poolId      = 0x003c8ad599c3A0ff
    ///
    /// @param univ3pool The address of the Uniswap v3 pool to get the ID of
    /// @return A uint64 representing a fingerprint of the uniswap v3 pool address
    function getPoolId(address univ3pool) internal view returns (uint64) {
        unchecked {
            int24 tickSpacing = IUniswapV3Pool(univ3pool).tickSpacing();
            uint64 poolId = uint64(uint160(univ3pool) >> 112);
            poolId += uint64(uint24(tickSpacing)) << 48;
            return poolId;
        }
    }

    /// @notice Increments the pool pattern (first 48 bits) of a poolId by 1.
    /// @param poolId The 64-bit pool ID
    /// @return The provided `poolId` with its pool pattern slot incremented by 1
    function incrementPoolPattern(uint64 poolId) internal pure returns (uint64) {
        unchecked {
            // increment
            return (poolId & TICKSPACING_MASK) + (uint48(poolId) + 1);
        }
    }

    /// @notice Get the number of leading hex characters in an address.
    ///     0x0000bababaab...     0xababababab...
    ///          ▲                 ▲
    ///          │                 │
    ///     4 leading hex      0 leading hex
    ///    character zeros    character zeros
    ///
    /// @param addr The address to get the number of leading zero hex characters for
    /// @return The number of leading zero hex characters in the address
    function numberOfLeadingHexZeros(address addr) external pure returns (uint256) {
        unchecked {
            return addr == address(0) ? 40 : 39 - Math.mostSignificantNibble(uint160(addr));
        }
    }

    /*//////////////////////////////////////////////////////////////
                          ORACLE CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Update an existing account's "positions hash" with a new single position `tokenId`.
    /// @notice The positions hash contains a single fingerprint of all positions created by an account/user as well as a tally of the positions.
    /// @dev The combined hash is the XOR of all individual position hashes.
    /// @param existingHash The existing position hash containing all historical N positions created and the count of the positions
    /// @param tokenId The new position to add to the existing hash: existingHash = uint248(existingHash) ^ hashOf(tokenId)
    /// @param addFlag Whether to mint (add) the tokenId to the count of positions or burn (subtract) it from the count (existingHash >> 248) +/- 1
    /// @return newHash The new positionHash with the updated hash
    function updatePositionsHash(
        uint256 existingHash,
        TokenId tokenId,
        bool addFlag
    ) internal pure returns (uint256) {
        // add the XOR`ed hash of the single option position `tokenId` to the `existingHash`
        // @dev 0 ^ x = x

        unchecked {
            // update hash by taking the XOR of the new tokenId
            uint248 updatedHash = uint248(existingHash) ^
                (uint248(uint256(keccak256(abi.encode(tokenId)))));
            // increment the top 8 bit if addflag=true, decrement otherwise
            return
                addFlag
                    ? uint256(updatedHash) + (((existingHash >> 248) + 1) << 248)
                    : uint256(updatedHash) + (((existingHash >> 248) - 1) << 248);
        }
    }

    /// @notice Returns the median of the last `cardinality` average prices over `period` observations from `univ3pool`.
    /// @dev Used when we need a manipulation-resistant TWAP price.
    /// @dev Uniswap observations snapshot the closing price of the last block before the first interaction of a given block.
    /// @dev The maximum frequency of observations is 1 per block, but there is no guarantee that the pool will be observed at every block.
    /// @dev Each period has a minimum length of blocktime * period, but may be longer if the Uniswap pool is relatively inactive.
    /// @dev The final price used in the array (of length `cardinality`) is the average of all observations comprising `period` (which is itself a number of observations).
    /// @dev Thus, the minimum total time window is `cardinality` * `period` * `blocktime`.
    /// @param univ3pool The Uniswap pool to get the median observation from
    /// @param observationIndex The index of the last observation in the pool
    /// @param observationCardinality The number of observations in the pool
    /// @param cardinality The number of `periods` to in the median price array, should be odd.
    /// @param period The number of observations to average to compute one entry in the median price array
    /// @return The median of `cardinality` observations spaced by `period` in the Uniswap pool
    function computeMedianObservedPrice(
        IUniswapV3Pool univ3pool,
        uint256 observationIndex,
        uint256 observationCardinality,
        uint256 cardinality,
        uint256 period
    ) external view returns (int24) {
        unchecked {
            int256[] memory tickCumulatives = new int256[](cardinality + 1);

            uint256[] memory timestamps = new uint256[](cardinality + 1);
            // get the last 4 timestamps/tickCumulatives (if observationIndex < cardinality, the index will wrap back from observationCardinality)
            for (uint256 i = 0; i < cardinality + 1; ++i) {
                (timestamps[i], tickCumulatives[i], , ) = univ3pool.observations(
                    uint256(
                        (int256(observationIndex) - int256(i * period)) +
                            int256(observationCardinality)
                    ) % observationCardinality
                );
            }

            int256[] memory ticks = new int256[](cardinality);
            // use cardinality periods given by cardinality + 1 accumulator observations to compute the last cardinality observed ticks spaced by period
            for (uint256 i = 0; i < cardinality; ++i) {
                ticks[i] =
                    (tickCumulatives[i] - tickCumulatives[i + 1]) /
                    int256(timestamps[i] - timestamps[i + 1]);
            }

            // get the median of the 3 calculated ticks
            return int24(Math.sort(ticks)[cardinality / 2]);
        }
    }

    /// @notice Takes a packed structure representing a sorted 7-slot ring buffer of ticks and returns the median of those values.
    /// @dev Also inserts the latest Uniswap observation into the buffer, resorts, and returns if the last entry is at least `period` seconds old.
    /// @param observationIndex The index of the last observation in the Uniswap pool
    /// @param observationCardinality The number of observations in the Uniswap pool
    /// @param period The minimum time in seconds that must have passed since the last observation was inserted into the buffer
    /// @param medianData The packed structure representing the sorted 7-slot ring buffer of ticks
    /// @param univ3pool The Uniswap pool to retrieve observations from
    /// @return medianTick The median of the provided 7-slot ring buffer of ticks in `medianData`
    /// @return updatedMedianData The updated 7-slot ring buffer of ticks with the latest observation inserted if the last entry is at least `period` seconds old (returns 0 otherwise)
    function computeInternalMedian(
        uint256 observationIndex,
        uint256 observationCardinality,
        uint256 period,
        uint256 medianData,
        IUniswapV3Pool univ3pool
    ) external view returns (int24 medianTick, uint256 updatedMedianData) {
        unchecked {
            // return the average of the rank 3 and 4 values
            medianTick =
                (int24(uint24(medianData >> ((uint24(medianData >> (192 + 3 * 3)) % 8) * 24))) +
                    int24(uint24(medianData >> ((uint24(medianData >> (192 + 3 * 4)) % 8) * 24)))) /
                2;

            // only proceed if last entry is at least MEDIAN_PERIOD seconds old
            if (block.timestamp >= uint256(uint40(medianData >> 216)) + period) {
                int24 lastObservedTick;
                {
                    (uint256 timestamp_old, int56 tickCumulative_old, , ) = univ3pool.observations(
                        uint256(
                            int256(observationIndex) - int256(1) + int256(observationCardinality)
                        ) % observationCardinality
                    );

                    (uint256 timestamp_last, int56 tickCumulative_last, , ) = univ3pool
                        .observations(observationIndex);
                    lastObservedTick = int24(
                        (tickCumulative_last - tickCumulative_old) /
                            int256(timestamp_last - timestamp_old)
                    );
                }

                uint24 orderMap = uint24(medianData >> 192);

                uint24 newOrderMap;
                uint24 shift = 1;
                bool below = true;
                uint24 rank;
                int24 entry;
                for (uint8 i; i < 8; ++i) {
                    // read the rank from the existing ordering
                    rank = (orderMap >> (3 * i)) % 8;

                    if (rank == 7) {
                        shift -= 1;
                        continue;
                    }

                    // read the corresponding entry
                    entry = int24(uint24(medianData >> (rank * 24)));
                    if ((below) && (lastObservedTick > entry)) {
                        shift += 1;
                        below = false;
                    }

                    newOrderMap = newOrderMap + ((rank + 1) << (3 * (i + shift - 1)));
                }

                updatedMedianData =
                    (block.timestamp << 216) +
                    (uint256(newOrderMap) << 192) +
                    uint256(uint192(medianData << 24)) +
                    uint256(uint24(lastObservedTick));
            }
        }
    }

    /// @notice Computes the twap of a Uniswap V3 pool using data from its oracle.
    /// @dev Note that our definition of TWAP differs from a typical mean of prices over a time window.
    /// @dev We instead observe the average price over a series of time intervals, and define the TWAP as the median of those averages.
    /// @param univ3pool The Uniswap pool from which to compute the TWAP.
    /// @param twapWindow The time window to compute the TWAP over.
    /// @return twapTick The final calculated TWAP tick.
    function twapFilter(IUniswapV3Pool univ3pool, uint32 twapWindow) external view returns (int24) {
        uint32[] memory secondsAgos = new uint32[](20);

        int256[] memory twapMeasurement = new int256[](19);

        unchecked {
            // construct the time stots
            for (uint256 i = 0; i < 20; ++i) {
                secondsAgos[i] = uint32(((i + 1) * twapWindow) / 20);
            }

            // observe the tickCumulative at the 20 pre-defined time slots
            (int56[] memory tickCumulatives, ) = univ3pool.observe(secondsAgos);

            // compute the average tick per 30s window
            for (uint256 i = 0; i < 19; ++i) {
                twapMeasurement[i] = int24(
                    (tickCumulatives[i] - tickCumulatives[i + 1]) / int56(uint56(twapWindow / 20))
                );
            }

            // sort the tick measurements
            int256[] memory sortedTicks = Math.sort(twapMeasurement);

            // Get the median value
            return int24(sortedTicks[10]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         LIQUIDITY CALCULATION
    //////////////////////////////////////////////////////////////*/

    /// @notice For a given option position (`tokenId`), leg index within that position (`legIndex`), and `positionSize` get the tick range spanned and its
    /// liquidity (share ownership) in the Univ3 pool; this is a liquidity chunk.
    ///          Liquidity chunk  (defined by tick upper, tick lower, and its size/amount: the liquidity)
    ///   liquidity    │
    ///         ▲      │
    ///         │     ┌▼┐
    ///         │  ┌──┴─┴──┐
    ///         │  │       │
    ///         │  │       │
    ///         └──┴───────┴────► price
    ///         Uniswap v3 Pool
    /// @param tokenId The option position id
    /// @param legIndex The leg index of the option position, can be {0,1,2,3}
    /// @param positionSize The number of contracts held by this leg
    /// @return A LiquidityChunk with `tickLower`, `tickUpper`, and `liquidity`
    function getLiquidityChunk(
        TokenId tokenId,
        uint256 legIndex,
        uint128 positionSize
    ) internal pure returns (LiquidityChunk) {
        // get the tick range for this leg
        (int24 tickLower, int24 tickUpper) = tokenId.asTicks(legIndex);

        // Get the amount of liquidity owned by this leg in the univ3 pool in the above tick range
        // Background:
        //
        //  In Uniswap v3, the amount of liquidity received for a given amount of token0 when the price is
        //  not in range is given by:
        //     Liquidity = amount0 * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
        //  For token1, it is given by:
        //     Liquidity = amount1 / (sqrt(upper) - sqrt(lower))
        //
        //  However, in Panoptic, each position has a asset parameter. The asset is the "basis" of the position.
        //  In TradFi, the asset is always cash and selling a $1000 put requires the user to lock $1000, and selling
        //  a call requires the user to lock 1 unit of asset.
        //
        //  Because Uni v3 chooses token0 and token1 from the alphanumeric order, there is no consistency as to whether token0 is
        //  stablecoin, ETH, or an ERC20. Some pools may want ETH to be the asset (e.g. ETH-DAI) and some may wish the stablecoin to
        //  be the asset (e.g. DAI-ETH) so that K asset is moved for puts and 1 asset is moved for calls.
        //  But since the convention is to force the order always we have no say in this.
        //
        //  To solve this, we encode the asset value in tokenId. This parameter specifies which of token0 or token1 is the
        //  asset, such that:
        //     when asset=0, then amount0 moved at strike K =1.0001**currentTick is 1, amount1 moved to strike K is 1/K
        //     when asset=1, then amount1 moved at strike K =1.0001**currentTick is K, amount0 moved to strike K is 1
        //
        //  The following function takes this into account when computing the liquidity of the leg and switches between
        //  the definition for getLiquidityForAmount0 or getLiquidityForAmount1 when relevant.
        //
        //
        uint256 amount = uint256(positionSize) * tokenId.optionRatio(legIndex);
        if (tokenId.asset(legIndex) == 0) {
            return Math.getLiquidityForAmount0(tickLower, tickUpper, amount);
        } else {
            return Math.getLiquidityForAmount1(tickLower, tickUpper, amount);
        }
    }

    /// @notice Extract the tick range specified by `strike` and `width` for the given `tickSpacing`, if valid.
    /// @param strike The strike price of the option
    /// @param width The width of the option
    /// @param tickSpacing The tick spacing of the underlying Uniswap v3 pool
    /// @return tickLower The lower tick of the liquidity chunk
    /// @return tickUpper The upper tick of the liquidity chunk
    function getTicks(
        int24 strike,
        int24 width,
        int24 tickSpacing
    ) internal pure returns (int24 tickLower, int24 tickUpper) {
        unchecked {
            // The max/min ticks that can be initialized are the closest multiple of tickSpacing to the actual max/min tick abs()=887272
            // Dividing and multiplying by tickSpacing rounds down and forces the tick to be a multiple of tickSpacing
            int24 minTick = (Constants.MIN_V3POOL_TICK / tickSpacing) * tickSpacing;
            int24 maxTick = (Constants.MAX_V3POOL_TICK / tickSpacing) * tickSpacing;

            (int24 rangeDown, int24 rangeUp) = PanopticMath.getRangesFromStrike(width, tickSpacing);

            (tickLower, tickUpper) = (strike - rangeDown, strike + rangeUp);

            // Revert if the upper/lower ticks are not multiples of tickSpacing
            // Revert if the tick range extends from the strike outside of the valid tick range
            // These are invalid states, and would revert silently later in `univ3Pool.mint`
            if (
                tickLower % tickSpacing != 0 ||
                tickUpper % tickSpacing != 0 ||
                tickLower < minTick ||
                tickUpper > maxTick
            ) revert Errors.TicksNotInitializable();
        }
    }

    /// @notice Returns the distances of the upper and lower ticks from the strike for a position with the given width and tickSpacing.
    /// @dev Given `r = (width * tickSpacing) / 2`, `tickLower = strike - floor(r)` and `tickUpper = strike + ceil(r)`.
    /// @param width The width of the leg.
    /// @param tickSpacing The tick spacing of the underlying pool.
    /// @return The lower tick of the range
    /// @return The upper tick of the range
    function getRangesFromStrike(
        int24 width,
        int24 tickSpacing
    ) internal pure returns (int24, int24) {
        return (
            (width * tickSpacing) / 2,
            int24(int256(Math.unsafeDivRoundingUp(uint24(width) * uint24(tickSpacing), 2)))
        );
    }

    /*//////////////////////////////////////////////////////////////
                         TOKEN CONVERSION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Compute the amount of funds that are underlying this option position. This is useful when exercising a position.
    /// @param tokenId The option position id
    /// @param positionSize The number of contracts of this option
    /// @return longAmounts Left-right packed word where the right contains the total contract size and the left total notional
    /// @return shortAmounts Left-right packed word where the right contains the total contract size and the left total notional
    function computeExercisedAmounts(
        TokenId tokenId,
        uint128 positionSize
    ) internal pure returns (LeftRightSigned longAmounts, LeftRightSigned shortAmounts) {
        uint256 numLegs = tokenId.countLegs();
        for (uint256 leg = 0; leg < numLegs; ) {
            // Compute the amount of funds that have been removed from the Panoptic Pool
            (LeftRightSigned longs, LeftRightSigned shorts) = _calculateIOAmounts(
                tokenId,
                positionSize,
                leg
            );

            longAmounts = longAmounts.add(longs);
            shortAmounts = shortAmounts.add(shorts);

            unchecked {
                ++leg;
            }
        }
    }

    /// @notice Adds required collateral and collateral balance from collateralTracker0 and collateralTracker1 and converts to single values in terms of `tokenType`.
    /// @param tokenData0 LeftRight type container holding the collateralBalance (right slot) and requiredCollateral (left slot) for a user in CollateralTracker0 (expressed in terms of token0)
    /// @param tokenData1 LeftRight type container holding the collateralBalance (right slot) and requiredCollateral (left slot) for a user in CollateralTracker0 (expressed in terms of token1)
    /// @param tokenType The type of token (token0 or token1) to express collateralBalance and requiredCollateral in
    /// @param sqrtPriceX96 The sqrt price at which to convert between token0/token1
    /// @return The total combined balance of token0 and token1 for a user in terms of tokenType
    /// @return The combined collateral requirement for a user in terms of tokenType
    function convertCollateralData(
        LeftRightUnsigned tokenData0,
        LeftRightUnsigned tokenData1,
        uint256 tokenType,
        uint160 sqrtPriceX96
    ) internal pure returns (uint256, uint256) {
        if (tokenType == 0) {
            return (
                tokenData0.rightSlot() + convert1to0(tokenData1.rightSlot(), sqrtPriceX96),
                tokenData0.leftSlot() + convert1to0(tokenData1.leftSlot(), sqrtPriceX96)
            );
        } else {
            return (
                tokenData1.rightSlot() + convert0to1(tokenData0.rightSlot(), sqrtPriceX96),
                tokenData1.leftSlot() + convert0to1(tokenData0.leftSlot(), sqrtPriceX96)
            );
        }
    }

    /// @notice Adds required collateral and collateral balance from collateralTracker0 and collateralTracker1 and converts to single values in terms of `tokenType`.
    /// @param tokenData0 LeftRight type container holding the collateralBalance (right slot) and requiredCollateral (left slot) for a user in CollateralTracker0 (expressed in terms of token0)
    /// @param tokenData1 LeftRight type container holding the collateralBalance (right slot) and requiredCollateral (left slot) for a user in CollateralTracker0 (expressed in terms of token1)
    /// @param tokenType The type of token (token0 or token1) to express collateralBalance and requiredCollateral in
    /// @param tick The tick at which to convert between token0/token1
    /// @return The total combined balance of token0 and token1 for a user in terms of tokenType
    /// @return The combined collateral requirement for a user in terms of tokenType
    function convertCollateralData(
        LeftRightUnsigned tokenData0,
        LeftRightUnsigned tokenData1,
        uint256 tokenType,
        int24 tick
    ) internal pure returns (uint256, uint256) {
        return
            convertCollateralData(tokenData0, tokenData1, tokenType, Math.getSqrtRatioAtTick(tick));
    }

    /// @notice Compute the notional amount given an incoming total number of `contracts` deployed between `tickLower` and `tickUpper`.
    /// @dev The notional value of an option is the value of the crypto assets that are controlled (rather than the cost of the transaction).
    /// @dev Example: Notional value in an option refers to the value that the option controls.
    /// @dev For example, token ABC is trading for $20 with a particular ABC call option costing $1.50.
    /// @dev One option controls 100 underlying tokens. A trader purchases the option for $1.50 x 100 = $150.
    /// @dev The notional value of the option is $20 x 100 = $2,000 --> (underlying price) * (contract/position size).
    /// @dev Thus, `contracts` refer to "100" in this example. The $20 is the strike price. We get the strike price from `tickLower` and `tickUpper`.
    /// @dev From TradFi: [https://www.investopedia.com/terms/n/notionalvalue.asp](https://www.investopedia.com/terms/n/notionalvalue.asp).
    /// @param contractSize The total number of contracts (position size) between `tickLower` and `tickUpper
    /// @param tickLower The lower price tick of the position. The strike price can be recovered from this + `tickUpper`
    /// @param tickUpper The upper price tick of the position. The strike price can be recovered from this + `tickLower`
    /// @param asset The asset for that leg (token0=0, token1=1)
    /// @return The notional value of the option position
    function convertNotional(
        uint128 contractSize,
        int24 tickLower,
        int24 tickUpper,
        uint256 asset
    ) internal pure returns (uint128) {
        unchecked {
            uint256 notional = asset == 0
                ? convert0to1(contractSize, Math.getSqrtRatioAtTick((tickUpper + tickLower) / 2))
                : convert1to0(contractSize, Math.getSqrtRatioAtTick((tickUpper + tickLower) / 2));

            if (notional == 0 || notional > type(uint128).max) revert Errors.InvalidNotionalValue();

            return uint128(notional);
        }
    }

    /// @notice Convert an amount of token0 into an amount of token1 given the sqrtPriceX96 in a Uniswap pool defined as sqrt(1/0)*2^96.
    /// @dev Uses reduced precision after tick 443636 in order to accomodate the full range of tick.s
    /// @param amount The amount of token0 to convert into token1
    /// @param sqrtPriceX96 The square root of the price at which to convert `amount` of token0 into token1
    /// @return The converted `amount` of token0 represented in terms of token1
    function convert0to1(uint256 amount, uint160 sqrtPriceX96) internal pure returns (uint256) {
        unchecked {
            // the tick 443636 is the maximum price where (price) * 2**192 fits into a uint256 (< 2**256-1)
            // above that tick, we are forced to reduce the amount of decimals in the final price by 2**64 to 2**128
            if (sqrtPriceX96 < type(uint128).max) {
                return Math.mulDiv192(amount, uint256(sqrtPriceX96) ** 2);
            } else {
                return Math.mulDiv128(amount, Math.mulDiv64(sqrtPriceX96, sqrtPriceX96));
            }
        }
    }

    /// @notice Convert an amount of token1 into an amount of token0 given the sqrtPriceX96 in a Uniswap pool defined as sqrt(1/0)*2^96.
    /// @dev Uses reduced precision after tick 443636 in order to accomodate the full range of ticks.
    /// @param amount The amount of token1 to convert into token0
    /// @param sqrtPriceX96 The square root of the price at which to convert `amount` of token1 into token0
    /// @return The converted `amount` of token1 represented in terms of token0
    function convert1to0(uint256 amount, uint160 sqrtPriceX96) internal pure returns (uint256) {
        unchecked {
            // the tick 443636 is the maximum price where (price) * 2**192 fits into a uint256 (< 2**256-1)
            // above that tick, we are forced to reduce the amount of decimals in the final price by 2**64 to 2**128
            if (sqrtPriceX96 < type(uint128).max) {
                return Math.mulDiv(amount, 2 ** 192, uint256(sqrtPriceX96) ** 2);
            } else {
                return Math.mulDiv(amount, 2 ** 128, Math.mulDiv64(sqrtPriceX96, sqrtPriceX96));
            }
        }
    }

    /// @notice Convert an amount of token0 into an amount of token1 given the sqrtPriceX96 in a Uniswap pool defined as sqrt(1/0)*2^96.
    /// @dev Uses reduced precision after tick 443636 in order to accomodate the full range of ticks.
    /// @param amount The amount of token0 to convert into token1
    /// @param sqrtPriceX96 The square root of the price at which to convert `amount` of token0 into token1
    /// @return The converted `amount` of token0 represented in terms of token1
    function convert0to1(int256 amount, uint160 sqrtPriceX96) internal pure returns (int256) {
        unchecked {
            // the tick 443636 is the maximum price where (price) * 2**192 fits into a uint256 (< 2**256-1)
            // above that tick, we are forced to reduce the amount of decimals in the final price by 2**64 to 2**128
            if (sqrtPriceX96 < type(uint128).max) {
                int256 absResult = Math
                    .mulDiv192(Math.absUint(amount), uint256(sqrtPriceX96) ** 2)
                    .toInt256();
                return amount < 0 ? -absResult : absResult;
            } else {
                int256 absResult = Math
                    .mulDiv128(Math.absUint(amount), Math.mulDiv64(sqrtPriceX96, sqrtPriceX96))
                    .toInt256();
                return amount < 0 ? -absResult : absResult;
            }
        }
    }

    /// @notice Convert an amount of token0 into an amount of token1 given the sqrtPriceX96 in a Uniswap pool defined as sqrt(1/0)*2^96.
    /// @dev Uses reduced precision after tick 443636 in order to accomodate the full range of ticks.
    /// @param amount The amount of token0 to convert into token1
    /// @param sqrtPriceX96 The square root of the price at which to convert `amount` of token0 into token1
    /// @return The converted `amount` of token0 represented in terms of token1
    function convert1to0(int256 amount, uint160 sqrtPriceX96) internal pure returns (int256) {
        unchecked {
            // the tick 443636 is the maximum price where (price) * 2**192 fits into a uint256 (< 2**256-1)
            // above that tick, we are forced to reduce the amount of decimals in the final price by 2**64 to 2**128
            if (sqrtPriceX96 < type(uint128).max) {
                int256 absResult = Math
                    .mulDiv(Math.absUint(amount), 2 ** 192, uint256(sqrtPriceX96) ** 2)
                    .toInt256();
                return amount < 0 ? -absResult : absResult;
            } else {
                int256 absResult = Math
                    .mulDiv(
                        Math.absUint(amount),
                        2 ** 128,
                        Math.mulDiv64(sqrtPriceX96, sqrtPriceX96)
                    )
                    .toInt256();
                return amount < 0 ? -absResult : absResult;
            }
        }
    }

    /// @notice Compute the amount of token0 and token1 moved. Given an option position `tokenId`, leg index `legIndex`, and how many contracts are in the leg `positionSize`.
    /// @param tokenId The option position identifier
    /// @param positionSize The number of option contracts held in this position (each contract can control multiple tokens)
    /// @param legIndex The leg index of the option contract, can be {0,1,2,3}
    /// @return A LeftRight encoded variable containing the amount0 and the amount1 value controlled by this option position's leg
    function getAmountsMoved(
        TokenId tokenId,
        uint128 positionSize,
        uint256 legIndex
    ) internal pure returns (LeftRightUnsigned) {
        // get the tick range for this leg in order to get the strike price (the underlying price)
        (int24 tickLower, int24 tickUpper) = tokenId.asTicks(legIndex);

        uint128 amount0;
        uint128 amount1;
        if (tokenId.asset(legIndex) == 0) {
            amount0 = positionSize * uint128(tokenId.optionRatio(legIndex));

            amount1 = Math
                .getAmount1ForLiquidity(Math.getLiquidityForAmount0(tickLower, tickUpper, amount0))
                .toUint128();
        } else {
            amount1 = positionSize * uint128(tokenId.optionRatio(legIndex));

            amount0 = Math
                .getAmount0ForLiquidity(Math.getLiquidityForAmount1(tickLower, tickUpper, amount1))
                .toUint128();
        }

        return LeftRightUnsigned.wrap(0).toRightSlot(amount0).toLeftSlot(amount1);
    }

    /// @notice Compute the amount of funds that are moved to and removed from the Panoptic Pool.
    /// @param tokenId The option position identifier
    /// @param positionSize The number of positions minted
    /// @param legIndex The leg index minted in this position, can be {0,1,2,3}
    /// @return longs A LeftRight-packed word containing the total amount of long positions
    /// @return shorts A LeftRight-packed word containing the amount of short positions
    function _calculateIOAmounts(
        TokenId tokenId,
        uint128 positionSize,
        uint256 legIndex
    ) internal pure returns (LeftRightSigned longs, LeftRightSigned shorts) {
        // compute amounts moved
        LeftRightUnsigned amountsMoved = getAmountsMoved(tokenId, positionSize, legIndex);

        bool isShort = tokenId.isLong(legIndex) == 0;

        // if token0
        if (tokenId.tokenType(legIndex) == 0) {
            if (isShort) {
                // if option is short, increment shorts by contracts
                shorts = shorts.toRightSlot(Math.toInt128(amountsMoved.rightSlot()));
            } else {
                // is option is long, increment longs by contracts
                longs = longs.toRightSlot(Math.toInt128(amountsMoved.rightSlot()));
            }
        } else {
            if (isShort) {
                // if option is short, increment shorts by notional
                shorts = shorts.toLeftSlot(Math.toInt128(amountsMoved.leftSlot()));
            } else {
                // if option is long, increment longs by notional
                longs = longs.toLeftSlot(Math.toInt128(amountsMoved.leftSlot()));
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                       REVOKE/REFUND COMPUTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check that the account is liquidatable, get the split of bonus0 and bonus1 amounts.
    /// @param tokenData0 Leftright encoded word with balance of token0 in the right slot, and required balance in left slot
    /// @param tokenData1 Leftright encoded word with balance of token1 in the right slot, and required balance in left slot
    /// @param sqrtPriceX96Twap The sqrt(price) of the TWAP tick before liquidation used to evaluate solvency
    /// @param sqrtPriceX96Final The current sqrt(price) of the AMM after liquidating a user
    /// @param netExchanged The net exchanged value of the closed portfolio
    /// @param premia Premium across all positions being liquidated present in tokenData
    /// @return bonus0 Bonus amount for token0
    /// @return bonus1 Bonus amount for token1
    /// @return The LeftRight-packed protocol loss for both tokens, i.e., the delta between the user's balance and expended tokens
    function getLiquidationBonus(
        LeftRightUnsigned tokenData0,
        LeftRightUnsigned tokenData1,
        uint160 sqrtPriceX96Twap,
        uint160 sqrtPriceX96Final,
        LeftRightSigned netExchanged,
        LeftRightSigned premia
    ) external pure returns (int256 bonus0, int256 bonus1, LeftRightSigned) {
        unchecked {
            // compute bonus as min(collateralBalance/2, required-collateralBalance)
            {
                // compute the ratio of token0 to total collateral requirements
                // evaluate at TWAP price to keep consistentcy with solvency calculations
                uint256 required0 = PanopticMath.convert0to1(
                    tokenData0.leftSlot(),
                    sqrtPriceX96Twap
                );
                uint256 required1 = tokenData1.leftSlot();
                uint256 requiredRatioX128 = (required0 << 128) / (required0 + required1);

                (uint256 balanceCross, uint256 thresholdCross) = PanopticMath.convertCollateralData(
                    tokenData0,
                    tokenData1,
                    0,
                    sqrtPriceX96Twap
                );

                uint256 bonusCross = Math.min(balanceCross / 2, thresholdCross - balanceCross);

                // convert that bonus to tokens 0 and 1
                bonus0 = int256(Math.mulDiv128(bonusCross, requiredRatioX128));

                bonus1 = int256(
                    PanopticMath.convert0to1(
                        Math.mulDiv128(bonusCross, 2 ** 128 - requiredRatioX128),
                        sqrtPriceX96Final
                    )
                );
            }

            // negative premium (owed to the liquidatee) is credited to the collateral balance
            // this is already present in the netExchanged amount, so to avoid double-counting we remove it from the balance
            int256 balance0 = int256(uint256(tokenData0.rightSlot())) -
                Math.max(premia.rightSlot(), 0);
            int256 balance1 = int256(uint256(tokenData1.rightSlot())) -
                Math.max(premia.leftSlot(), 0);

            int256 paid0 = bonus0 + int256(netExchanged.rightSlot());
            int256 paid1 = bonus1 + int256(netExchanged.leftSlot());

            // note that "balance0" and "balance1" are the liquidatee's original balances before token delegation by a liquidator
            // their actual balances at the time of computation may be higher, but these are a buffer representing the amount of tokens we
            // have to work with before cutting into the liquidator's funds
            if (!(paid0 > balance0 && paid1 > balance1)) {
                // liquidatee cannot pay back the liquidator fully in either token, so no protocol loss can be avoided
                if ((paid0 > balance0)) {
                    // liquidatee has insufficient token0 but some token1 left over, so we use what they have left to mitigate token0 losses
                    // we do this by substituting an equivalent value of token1 in our refund to the liquidator, plus a bonus, for the token0 we convert
                    // we want to convert the minimum amount of tokens required to achieve the lowest possible protocol loss (to avoid overpaying on the conversion bonus)
                    // the maximum level of protocol loss mitigation that can be achieved is the liquidatee's excess token1 balance: balance1 - paid1
                    // and paid0 - balance0 is the amount of token0 that the liquidatee is missing, i.e the protocol loss
                    // if the protocol loss is lower than the excess token1 balance, then we can fully mitigate the loss and we should only convert the loss amount
                    // if the protocol loss is higher than the excess token1 balance, we can only mitigate part of the loss, so we should convert only the excess token1 balance
                    // thus, the value converted should be min(balance1 - paid1, paid0 - balance0)
                    bonus1 += Math.min(
                        balance1 - paid1,
                        PanopticMath.convert0to1(paid0 - balance0, sqrtPriceX96Final)
                    );
                    bonus0 -= Math.min(
                        PanopticMath.convert1to0(balance1 - paid1, sqrtPriceX96Final),
                        paid0 - balance0
                    );
                }
                if ((paid1 > balance1)) {
                    // liquidatee has insufficient token1 but some token0 left over, so we use what they have left to mitigate token1 losses
                    // we do this by substituting an equivalent value of token0 in our refund to the liquidator, plus a bonus, for the token1 we convert
                    // we want to convert the minimum amount of tokens required to achieve the lowest possible protocol loss (to avoid overpaying on the conversion bonus)
                    // the maximum level of protocol loss mitigation that can be achieved is the liquidatee's excess token0 balance: balance0 - paid0
                    // and paid1 - balance1 is the amount of token1 that the liquidatee is missing, i.e the protocol loss
                    // if the protocol loss is lower than the excess token0 balance, then we can fully mitigate the loss and we should only convert the loss amount
                    // if the protocol loss is higher than the excess token0 balance, we can only mitigate part of the loss, so we should convert only the excess token0 balance
                    // thus, the value converted should be min(balance0 - paid0, paid1 - balance1)
                    bonus0 += Math.min(
                        balance0 - paid0,
                        PanopticMath.convert1to0(paid1 - balance1, sqrtPriceX96Final)
                    );
                    bonus1 -= Math.min(
                        PanopticMath.convert0to1(balance0 - paid0, sqrtPriceX96Final),
                        paid1 - balance1
                    );
                }
            }

            paid0 = bonus0 + int256(netExchanged.rightSlot());
            paid1 = bonus1 + int256(netExchanged.leftSlot());
            return (
                bonus0,
                bonus1,
                LeftRightSigned.wrap(0).toRightSlot(int128(balance0 - paid0)).toLeftSlot(
                    int128(balance1 - paid1)
                )
            );
        }
    }

    /// @notice Haircut/clawback any premium paid by `liquidatee` on `positionIdList` over the protocol loss threshold during a liquidation.
    /// @dev Note that the storage mapping provided as the `settledTokens` parameter WILL be modified on the caller by this function.
    /// @param liquidatee The address of the user being liquidated
    /// @param positionIdList The list of position ids being liquidated
    /// @param premiasByLeg The premium paid (or received) by the liquidatee for each leg of each position
    /// @param collateralRemaining The remaining collateral after the liquidation (negative if protocol loss)
    /// @param sqrtPriceX96Final The sqrt price at which to convert between token0/token1 when awarding the bonus
    /// @param collateral0 The collateral tracker for token0
    /// @param collateral1 The collateral tracker for token1
    /// @param settledTokens The per-chunk accumulator of settled tokens in storage from which to subtract the haircut premium
    /// @return The delta in bonus0 for the liquidator post-haircut
    /// @return The delta in bonus1 for the liquidator post-haircut
    function haircutPremia(
        address liquidatee,
        TokenId[] memory positionIdList,
        LeftRightSigned[4][] memory premiasByLeg,
        LeftRightSigned collateralRemaining,
        CollateralTracker collateral0,
        CollateralTracker collateral1,
        uint160 sqrtPriceX96Final,
        mapping(bytes32 chunkKey => LeftRightUnsigned settledTokens) storage settledTokens
    ) external returns (int256, int256) {
        unchecked {
            // get the amount of premium paid by the liquidatee
            LeftRightSigned longPremium;
            for (uint256 i = 0; i < positionIdList.length; ++i) {
                TokenId tokenId = positionIdList[i];
                uint256 numLegs = tokenId.countLegs();
                for (uint256 leg = 0; leg < numLegs; ++leg) {
                    if (tokenId.isLong(leg) == 1) {
                        longPremium = longPremium.sub(premiasByLeg[i][leg]);
                    }
                }
            }
            // Ignore any surplus collateral - the liquidatee is either solvent or it converts to <1 unit of the other token
            int256 collateralDelta0 = -Math.min(collateralRemaining.rightSlot(), 0);
            int256 collateralDelta1 = -Math.min(collateralRemaining.leftSlot(), 0);
            int256 haircut0;
            int256 haircut1;
            // if the premium in the same token is not enough to cover the loss and there is a surplus of the other token,
            // the liquidator will provide the tokens (reflected in the bonus amount) & receive compensation in the other token
            if (
                longPremium.rightSlot() < collateralDelta0 &&
                longPremium.leftSlot() > collateralDelta1
            ) {
                int256 protocolLoss1 = collateralDelta1;
                (collateralDelta0, collateralDelta1) = (
                    -Math.min(
                        collateralDelta0 - longPremium.rightSlot(),
                        PanopticMath.convert1to0(
                            longPremium.leftSlot() - collateralDelta1,
                            sqrtPriceX96Final
                        )
                    ),
                    Math.min(
                        longPremium.leftSlot() - collateralDelta1,
                        PanopticMath.convert0to1(
                            collateralDelta0 - longPremium.rightSlot(),
                            sqrtPriceX96Final
                        )
                    )
                );

                haircut0 = longPremium.rightSlot();
                haircut1 = protocolLoss1 + collateralDelta1;
            } else if (
                longPremium.leftSlot() < collateralDelta1 &&
                longPremium.rightSlot() > collateralDelta0
            ) {
                int256 protocolLoss0 = collateralDelta0;
                (collateralDelta0, collateralDelta1) = (
                    Math.min(
                        longPremium.rightSlot() - collateralDelta0,
                        PanopticMath.convert1to0(
                            collateralDelta1 - longPremium.leftSlot(),
                            sqrtPriceX96Final
                        )
                    ),
                    -Math.min(
                        collateralDelta1 - longPremium.leftSlot(),
                        PanopticMath.convert0to1(
                            longPremium.rightSlot() - collateralDelta0,
                            sqrtPriceX96Final
                        )
                    )
                );

                haircut0 = collateralDelta0 + protocolLoss0;
                haircut1 = longPremium.leftSlot();
            } else {
                // for each token, haircut until the protocol loss is mitigated or the premium paid is exhausted
                haircut0 = Math.min(collateralDelta0, longPremium.rightSlot());
                haircut1 = Math.min(collateralDelta1, longPremium.leftSlot());

                collateralDelta0 = 0;
                collateralDelta1 = 0;
            }

            {
                address _liquidatee = liquidatee;
                if (haircut0 != 0) collateral0.exercise(_liquidatee, 0, 0, 0, int128(haircut0));
                if (haircut1 != 0) collateral1.exercise(_liquidatee, 0, 0, 0, int128(haircut1));
            }

            for (uint256 i = 0; i < positionIdList.length; i++) {
                TokenId tokenId = positionIdList[i];
                LeftRightSigned[4][] memory _premiasByLeg = premiasByLeg;
                for (uint256 leg = 0; leg < tokenId.countLegs(); ++leg) {
                    if (tokenId.isLong(leg) == 1) {
                        mapping(bytes32 chunkKey => LeftRightUnsigned settledTokens)
                            storage _settledTokens = settledTokens;

                        // calculate amounts to revoke from settled and subtract from haircut req
                        uint256 settled0 = Math.unsafeDivRoundingUp(
                            uint128(-_premiasByLeg[i][leg].rightSlot()) * uint256(haircut0),
                            uint128(longPremium.rightSlot())
                        );
                        uint256 settled1 = Math.unsafeDivRoundingUp(
                            uint128(-_premiasByLeg[i][leg].leftSlot()) * uint256(haircut1),
                            uint128(longPremium.leftSlot())
                        );

                        bytes32 chunkKey = keccak256(
                            abi.encodePacked(
                                tokenId.strike(0),
                                tokenId.width(0),
                                tokenId.tokenType(0)
                            )
                        );

                        // The long premium is not commited to storage during the liquidation, so we add the entire adjusted amount
                        // for the haircut directly to the accumulator
                        settled0 = Math.max(
                            0,
                            uint128(-_premiasByLeg[i][leg].rightSlot()) - settled0
                        );
                        settled1 = Math.max(
                            0,
                            uint128(-_premiasByLeg[i][leg].leftSlot()) - settled1
                        );

                        _settledTokens[chunkKey] = _settledTokens[chunkKey].add(
                            LeftRightUnsigned.wrap(0).toRightSlot(uint128(settled0)).toLeftSlot(
                                uint128(settled1)
                            )
                        );
                    }
                }
            }

            return (collateralDelta0, collateralDelta1);
        }
    }

    /// @notice Returns the original delegated value to a user at a certain tick based on the available collateral from the exercised user.
    /// @param refunder Address of the user the refund is coming from (the force exercisee)
    /// @param refundValues Token values to refund at the given tick(atTick) rightSlot = token0 left = token1
    /// @param atTick Tick to convert values at. This can be the current tick or some TWAP/median tick
    /// @param collateral0 CollateralTracker for token0
    /// @param collateral1 CollateralTracker for token1
    /// @return The LeftRight-packed amount of token0/token1 to refund to the user.
    function getRefundAmounts(
        address refunder,
        LeftRightSigned refundValues,
        int24 atTick,
        CollateralTracker collateral0,
        CollateralTracker collateral1
    ) external view returns (LeftRightSigned) {
        uint160 sqrtPriceX96 = Math.getSqrtRatioAtTick(atTick);
        unchecked {
            // if the refunder lacks sufficient token0 to pay back the refundee, have them pay back the equivalent value in token1
            // note: it is possible for refunds to be negative when the exercise fee is higher than the delegated amounts. This is expected behavior
            int256 balanceShortage = refundValues.rightSlot() -
                int256(collateral0.convertToAssets(collateral0.balanceOf(refunder)));

            if (balanceShortage > 0) {
                return
                    LeftRightSigned
                        .wrap(0)
                        .toRightSlot(int128(refundValues.rightSlot() - balanceShortage))
                        .toLeftSlot(
                            int128(
                                int256(
                                    PanopticMath.convert0to1(uint256(balanceShortage), sqrtPriceX96)
                                ) + refundValues.leftSlot()
                            )
                        );
            }

            balanceShortage =
                refundValues.leftSlot() -
                int256(collateral1.convertToAssets(collateral1.balanceOf(refunder)));

            if (balanceShortage > 0) {
                return
                    LeftRightSigned
                        .wrap(0)
                        .toLeftSlot(int128(refundValues.leftSlot() - balanceShortage))
                        .toRightSlot(
                            int128(
                                int256(
                                    PanopticMath.convert1to0(uint256(balanceShortage), sqrtPriceX96)
                                ) + refundValues.rightSlot()
                            )
                        );
            }
        }

        // otherwise, we can just refund the original amounts requested with no problems
        return refundValues;
    }
}
