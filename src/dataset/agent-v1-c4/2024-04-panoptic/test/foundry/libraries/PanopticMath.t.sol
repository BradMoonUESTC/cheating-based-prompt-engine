// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Foundry
import "forge-std/Test.sol";
// Internal
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {BitMath} from "v3-core/libraries/BitMath.sol";
import {Errors} from "@libraries/Errors.sol";
import {PanopticMathHarness} from "./harnesses/PanopticMathHarness.sol";
import {LiquidityChunk} from "@types/LiquidityChunk.sol";
import {TokenId} from "@types/TokenId.sol";
import {LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";
import {PanopticMath} from "@libraries/PanopticMath.sol";
import {Math} from "@libraries/Math.sol";
// Uniswap
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {FixedPoint96} from "v3-core/libraries/FixedPoint96.sol";
import {FixedPoint128} from "v3-core/libraries/FixedPoint128.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";
// Test util
import {PositionUtils} from "../testUtils/PositionUtils.sol";
import {UniPoolPriceMock} from "../testUtils/PriceMocks.sol";
import {UniPoolObservationMock} from "../testUtils/PriceMocks.sol";

import {LiquidityChunk, LiquidityChunkLibrary} from "@types/LiquidityChunk.sol";

/**
 * Test the PanopticMath functionality with Foundry and Fuzzing.
 *
 * @author Axicon Labs Limited
 */
contract PanopticMathTest is Test, PositionUtils {
    using Math for uint256;
    // harness
    PanopticMathHarness harness;

    // store a few different mainnet pairs - the pool used is part of the fuzz
    IUniswapV3Pool constant USDC_WETH_5 =
        IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    IUniswapV3Pool constant WBTC_ETH_30 =
        IUniswapV3Pool(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD);
    IUniswapV3Pool constant USDC_WETH_30 =
        IUniswapV3Pool(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8);
    IUniswapV3Pool[3] public pools = [USDC_WETH_5, WBTC_ETH_30, USDC_WETH_30];

    function setUp() public {
        harness = new PanopticMathHarness();
    }

    // use storage as temp to avoid stack to deeps
    IUniswapV3Pool selectedPool;
    int24 tickSpacing;
    int24 currentTick;

    int24 minTick;
    int24 maxTick;
    int24 lowerBound;
    int24 upperBound;
    int24 strikeOffset;

    function test_Success_getLiquidityChunk_asset0(
        uint256 optionRatioSeed,
        uint16 isLong,
        uint16 tokenType,
        int24 strike,
        int24 width,
        uint64 positionSize
    ) public {
        vm.assume(positionSize != 0);
        TokenId tokenId;

        // contruct a tokenId
        {
            uint16 optionRatio = uint16(bound(optionRatioSeed, 1, 127));

            // the following are all 1 bit so mask them:
            uint8 MASK = 0x1; // takes first 1 bit of the uint16
            isLong = isLong & MASK;
            tokenType = tokenType & MASK;

            // bound fuzzed tick
            selectedPool = pools[bound(positionSize, 0, 2)]; // reuse position size as seed
            tickSpacing = selectedPool.tickSpacing();

            width = int24(bound(width, 1, 2048));
            int24 oneSidedRange = (width * tickSpacing) / 2;

            (, currentTick, , , , , ) = selectedPool.slot0();
            (strikeOffset, minTick, maxTick) = PositionUtils.getContextFull(
                uint256(uint24(tickSpacing)),
                currentTick,
                width
            );

            lowerBound = int24(minTick + oneSidedRange - strikeOffset);
            upperBound = int24(maxTick - oneSidedRange - strikeOffset);

            // Set current tick and pool price
            currentTick = int24(bound(currentTick, minTick, maxTick));

            // bound strike
            strike = int24(bound(strike, lowerBound / tickSpacing, upperBound / tickSpacing));
            strike = int24(strike * tickSpacing + strikeOffset);

            tokenId = TokenId.wrap(uint256(uint24(tickSpacing)) << 48);
            tokenId = tokenId.addLeg(0, optionRatio, 0, isLong, tokenType, 0, strike, width);
        }

        (int24 tickLower, int24 tickUpper) = tokenId.asTicks(0);

        uint160 sqrtPriceBottom = (tokenId.width(0) == 4095)
            ? TickMath.getSqrtRatioAtTick(tokenId.strike(0))
            : TickMath.getSqrtRatioAtTick(tickLower);

        uint256 amount = uint256(positionSize) * tokenId.optionRatio(0);
        uint128 legLiquidity = LiquidityAmounts.getLiquidityForAmount0(
            sqrtPriceBottom,
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount
        );

        LiquidityChunk expectedLiquidityChunk = LiquidityChunkLibrary.createChunk(
            tickLower,
            tickUpper,
            legLiquidity
        );
        LiquidityChunk returnedLiquidityChunk = harness.getLiquidityChunk(tokenId, 0, positionSize);

        assertEq(
            LiquidityChunk.unwrap(expectedLiquidityChunk),
            LiquidityChunk.unwrap(returnedLiquidityChunk)
        );
    }

    function test_Success_getLiquidityChunk_asset1(
        uint256 optionRatioSeed,
        uint16 isLong,
        uint16 tokenType,
        int24 strike,
        int24 width,
        uint64 positionSize
    ) public {
        vm.assume(positionSize != 0);
        TokenId tokenId;

        // contruct a tokenId
        {
            uint256 optionRatio = bound(optionRatioSeed, 1, 127);

            // the following are all 1 bit so mask them:
            uint8 MASK = 0x1; // takes first 1 bit of the uint16
            isLong = isLong & MASK;
            tokenType = tokenType & MASK;

            // bound fuzzed tick
            selectedPool = pools[bound(positionSize, 0, 2)]; // reuse position size as seed
            tickSpacing = selectedPool.tickSpacing();

            width = int24(bound(width, 1, 2048));
            int24 oneSidedRange = (width * tickSpacing) / 2;

            (, currentTick, , , , , ) = selectedPool.slot0();
            (strikeOffset, minTick, maxTick) = PositionUtils.getContextFull(
                uint256(uint24(tickSpacing)),
                currentTick,
                width
            );

            lowerBound = int24(minTick + oneSidedRange - strikeOffset);
            upperBound = int24(maxTick - oneSidedRange - strikeOffset);

            // Set current tick and pool price
            currentTick = int24(bound(currentTick, minTick, maxTick));

            // bound strike
            strike = int24(bound(strike, lowerBound / tickSpacing, upperBound / tickSpacing));
            strike = int24(strike * tickSpacing + strikeOffset);

            tokenId = TokenId.wrap(uint256(uint24(tickSpacing)) << 48);
            tokenId = tokenId.addLeg(0, optionRatio, 1, isLong, tokenType, 0, strike, width);
        }

        (int24 tickLower, int24 tickUpper) = tokenId.asTicks(0);

        uint160 sqrtPriceTop = (tokenId.width(0) == 4095)
            ? TickMath.getSqrtRatioAtTick(tokenId.strike(0))
            : TickMath.getSqrtRatioAtTick(tickUpper);

        uint256 amount = uint256(positionSize) * tokenId.optionRatio(0);
        uint128 legLiquidity = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtRatioAtTick(tickLower),
            sqrtPriceTop,
            amount
        );

        LiquidityChunk expectedLiquidityChunk = LiquidityChunkLibrary.createChunk(
            tickLower,
            tickUpper,
            legLiquidity
        );
        LiquidityChunk returnedLiquidityChunk = harness.getLiquidityChunk(tokenId, 0, positionSize);

        assertEq(
            LiquidityChunk.unwrap(expectedLiquidityChunk),
            LiquidityChunk.unwrap(returnedLiquidityChunk)
        );
    }

    function test_Success_getPoolId(address univ3pool, uint256 _tickSpacing) public {
        vm.assume(
            univ3pool > address(10) &&
                univ3pool != address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D) &&
                univ3pool != address(0x000000000000000000636F6e736F6c652e6c6f67) &&
                univ3pool != address(harness)
        );
        _tickSpacing = bound(_tickSpacing, 0, uint16(type(int16).max));

        UniPoolPriceMock pm = new UniPoolPriceMock();
        vm.etch(univ3pool, address(pm).code);
        pm = UniPoolPriceMock(univ3pool);

        pm.construct(
            UniPoolPriceMock.Slot0({
                sqrtPriceX96: 0,
                tick: 0,
                observationIndex: 0,
                observationCardinality: 0,
                observationCardinalityNext: 0,
                feeProtocol: 0,
                unlocked: false
            }),
            address(0),
            address(0),
            0,
            int24(uint24(_tickSpacing))
        );
        uint64 poolPattern = uint64(uint160(univ3pool) >> 112);
        _tickSpacing <<= 48;
        assertEq(_tickSpacing + poolPattern, harness.getPoolId(univ3pool));
    }

    function test_Success_getTicks_normalTickRange(
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 poolSeed
    ) public {
        // bound fuzzed tick
        selectedPool = pools[bound(poolSeed, 0, 2)];
        tickSpacing = selectedPool.tickSpacing();

        // Width must be > 0 < 4096
        int24 width = int24(uint24(bound(widthSeed, 1, 4095)));

        // The position must not extend outside of the max/min tick
        int24 strike = int24(
            bound(
                strikeSeed,
                TickMath.MIN_TICK + (width * tickSpacing) / 2,
                TickMath.MAX_TICK - (width * tickSpacing) / 2
            )
        );

        vm.assume(strike + (((width * tickSpacing) / 2) % tickSpacing) == 0);
        vm.assume(strike - (((width * tickSpacing) / 2) % tickSpacing) == 0);

        // Test the asTicks function
        (int24 tickLower, int24 tickUpper) = harness.getTicks(strike, width, tickSpacing);

        // Ensure tick values returned are correct
        assertEq(tickLower, strike - (width * tickSpacing) / 2);
        assertEq(tickUpper, strike + (width * tickSpacing) / 2);
    }

    function test_Fail_getTicks_TicksNotInitializable(
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 poolSeed
    ) public {
        // bound fuzzed tick
        selectedPool = pools[bound(poolSeed, 0, 2)];
        tickSpacing = selectedPool.tickSpacing();
        // Width must be > 0 < 4096
        int24 width = int24(uint24(bound(widthSeed, 1, 4095)));

        // The position must not extend outside of the max/min tick
        int24 strike = int24(
            bound(
                strikeSeed,
                TickMath.MIN_TICK + (width * tickSpacing) / 2,
                TickMath.MAX_TICK - (width * tickSpacing) / 2
            )
        );

        vm.assume(
            (strike + (width * tickSpacing) / 2) % tickSpacing != 0 ||
                (strike - (width * tickSpacing) / 2) % tickSpacing != 0
        );

        vm.expectRevert(Errors.TicksNotInitializable.selector);
        // Test the asTicks function
        harness.getTicks(strike, width, tickSpacing);
    }

    function test_Fail_getTicks_belowMinTick(
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 poolSeed
    ) public {
        // bound fuzzed tick
        selectedPool = pools[bound(poolSeed, 0, 2)];
        tickSpacing = selectedPool.tickSpacing();
        // Width must be > 0 < 4096
        int24 width = int24(uint24(bound(widthSeed, 1, 4095)));
        int24 oneSidedRange = (width * tickSpacing) / 2;

        // The position must extend beyond the min tick
        int24 strike = int24(
            bound(strikeSeed, TickMath.MIN_TICK, TickMath.MIN_TICK + (width * tickSpacing) / 2 - 1)
        );

        // assume for now
        vm.assume(
            (strike - oneSidedRange) % tickSpacing == 0 ||
                (strike + oneSidedRange) % tickSpacing == 0
        );

        // Test the asTicks function
        vm.expectRevert(Errors.TicksNotInitializable.selector);
        harness.getTicks(strike, width, tickSpacing);
    }

    function test_Fail_getTicks_aboveMinTick(
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 poolSeed
    ) public {
        // bound fuzzed tick
        selectedPool = pools[bound(poolSeed, 0, 2)];
        tickSpacing = selectedPool.tickSpacing();
        // Width must be > 0 < 4095 (4095 is full range)
        int24 width = int24(int256(bound(widthSeed, 1, 4094)));
        int24 oneSidedRange = (width * tickSpacing) / 2;

        // The position must extend beyond the max tick
        int24 strike = int24(
            bound(strikeSeed, TickMath.MAX_TICK - (width * tickSpacing) / 2 + 1, TickMath.MAX_TICK)
        );

        // assume for now
        vm.assume(
            (strike - oneSidedRange) % tickSpacing == 0 ||
                (strike + oneSidedRange) % tickSpacing == 0
        );

        // Test the asTicks function
        vm.expectRevert(Errors.TicksNotInitializable.selector);
        harness.getTicks(strike, width, tickSpacing);
    }

    function test_Success_incrementPoolPattern(uint64 poolId) public {
        unchecked {
            uint48 pattern = uint48(poolId & 0x0000FFFFFFFFFFFF);
            pattern += 1;
            uint64 _tickSpacing = uint24(TokenId.wrap(uint256(poolId)).tickSpacing());
            _tickSpacing <<= 48;
            assertEq(harness.incrementPoolPattern(poolId), _tickSpacing + pattern);
        }
    }

    function test_Success_computeExercisedAmounts_emptyOldTokenId(
        uint256 optionRatioSeed,
        uint16 isLong,
        uint16 asset,
        uint16 tokenType,
        int24 strike,
        int24 width,
        uint64 positionSize
    ) public {
        vm.assume(positionSize != 0);
        TokenId tokenId;

        // contruct a tokenId
        {
            uint256 optionRatio = bound(optionRatioSeed, 1, 127);

            vm.assume(positionSize * uint128(optionRatio) < type(uint56).max);

            // the following are all 1 bit so mask them:
            uint8 MASK = 0x1; // takes first 1 bit of the uint16
            isLong = isLong & MASK;
            asset = asset & MASK;
            tokenType = tokenType & MASK;

            // bound fuzzed tick
            selectedPool = pools[bound(positionSize, 0, 2)]; // reuse position size as seed
            tickSpacing = selectedPool.tickSpacing();

            width = int24(bound(width, 1, 2048));
            int24 oneSidedRange = (width * tickSpacing) / 2;

            (, currentTick, , , , , ) = selectedPool.slot0();
            (strikeOffset, minTick, maxTick) = PositionUtils.getContextFull(
                uint256(uint24(tickSpacing)),
                currentTick,
                width
            );

            lowerBound = int24(minTick + oneSidedRange - strikeOffset);
            upperBound = int24(maxTick - oneSidedRange - strikeOffset);

            // Set current tick and pool price
            currentTick = int24(bound(currentTick, minTick, maxTick));

            // bound strike
            strike = int24(bound(strike, lowerBound / tickSpacing, upperBound / tickSpacing));
            strike = int24(strike * tickSpacing + strikeOffset);

            tokenId = TokenId.wrap(uint256(uint24(tickSpacing)) << 48);
            tokenId = tokenId.addLeg(0, optionRatio, asset, isLong, tokenType, 0, strike, width);
        }

        (LeftRightSigned expectedLongs, LeftRightSigned expectedShorts) = harness
            .calculateIOAmounts(tokenId, positionSize, 0);

        (LeftRightSigned returnedLongs, LeftRightSigned returnedShorts) = harness
            .computeExercisedAmounts(tokenId, positionSize);

        assertEq(LeftRightSigned.unwrap(expectedLongs), LeftRightSigned.unwrap(returnedLongs));
        assertEq(LeftRightSigned.unwrap(expectedShorts), LeftRightSigned.unwrap(returnedShorts));
    }

    function test_Success_numberOfLeadingHexZeros(address addr) public {
        uint256 expectedData = addr == address(0)
            ? 40
            : 39 - Math.mostSignificantNibble(uint160(addr));
        assertEq(expectedData, harness.numberOfLeadingHexZeros(addr));
    }

    function test_Success_updatePositionsHash_add(
        uint256 optionRatioSeed,
        uint16 isLong,
        uint16 asset,
        uint16 tokenType,
        int24 strike,
        int24 width,
        uint256 existingHash
    ) public {
        TokenId tokenId;

        // contruct a tokenId
        {
            uint256 optionRatio = bound(optionRatioSeed, 1, 127);

            // the following are all 1 bit so mask them:
            uint8 MASK = 0x1; // takes first 1 bit of the uint16
            isLong = isLong & MASK;
            asset = asset & MASK;
            tokenType = tokenType & MASK;

            // bound fuzzed tick
            selectedPool = pools[bound(optionRatio, 0, 2)]; // reuse optionRatio as seed
            tickSpacing = selectedPool.tickSpacing();

            width = int24(bound(width, 1, 2048));
            int24 oneSidedRange = (width * tickSpacing) / 2;

            (, currentTick, , , , , ) = selectedPool.slot0();
            (strikeOffset, minTick, maxTick) = PositionUtils.getContextFull(
                uint256(uint24(tickSpacing)),
                currentTick,
                width
            );

            lowerBound = int24(minTick + oneSidedRange - strikeOffset);
            upperBound = int24(maxTick - oneSidedRange - strikeOffset);

            // Set current tick and pool price
            currentTick = int24(bound(currentTick, minTick, maxTick));

            // bound strike
            strike = int24(bound(strike, lowerBound / tickSpacing, upperBound / tickSpacing));
            strike = int24(strike * tickSpacing + strikeOffset);

            tokenId = TokenId.wrap(uint256(uint24(tickSpacing)) << 48);
            tokenId = tokenId.addLeg(0, optionRatio, asset, isLong, tokenType, 0, strike, width);
        }

        uint248 updatedHash = uint248(existingHash) ^
            (uint248(uint256(keccak256(abi.encode(tokenId)))));
        uint256 expectedHash = uint256(updatedHash) + (((existingHash >> 248) + 1) << 248);

        uint256 returnedHash = harness.updatePositionsHash(existingHash, tokenId, true);

        assertEq(expectedHash, returnedHash);
    }

    function test_Success_updatePositionsHash_update(
        uint256 optionRatioSeed,
        uint16 isLong,
        uint16 asset,
        uint16 tokenType,
        int24 strike,
        int24 width,
        uint256 existingHash
    ) public {
        TokenId tokenId;

        // contruct a tokenId
        {
            uint256 optionRatio = bound(optionRatioSeed, 1, 127);

            // the following are all 1 bit so mask them:
            uint8 MASK = 0x1; // takes first 1 bit of the uint16
            isLong = isLong & MASK;
            asset = asset & MASK;
            tokenType = tokenType & MASK;

            // bound fuzzed tick
            selectedPool = pools[bound(optionRatio, 0, 2)]; // reuse optionRatio as seed
            tickSpacing = selectedPool.tickSpacing();

            width = int24(bound(width, 1, 2048));
            int24 oneSidedRange = (width * tickSpacing) / 2;

            (, currentTick, , , , , ) = selectedPool.slot0();
            (strikeOffset, minTick, maxTick) = PositionUtils.getContextFull(
                uint256(uint24(tickSpacing)),
                currentTick,
                width
            );

            lowerBound = int24(minTick + oneSidedRange - strikeOffset);
            upperBound = int24(maxTick - oneSidedRange - strikeOffset);

            // Set current tick and pool price
            currentTick = int24(bound(currentTick, minTick, maxTick));

            // bound strike
            strike = int24(bound(strike, lowerBound / tickSpacing, upperBound / tickSpacing));
            strike = int24(strike * tickSpacing + strikeOffset);

            tokenId = TokenId.wrap(uint256(uint24(tickSpacing)) << 48);
            tokenId = tokenId.addLeg(0, optionRatio, asset, isLong, tokenType, 0, strike, width);
        }

        uint256 expectedHash;
        uint256 returnedHash;
        unchecked {
            uint248 updatedHash = uint248(existingHash) ^
                (uint248(uint256(keccak256(abi.encode(tokenId)))));
            expectedHash = uint256(updatedHash) + (((existingHash >> 248) - 1) << 248);

            returnedHash = harness.updatePositionsHash(existingHash, tokenId, false);
        }

        assertEq(expectedHash, returnedHash);
    }

    function test_Success_getLastMedianObservation(
        uint256 observationIndex,
        int256[100] memory ticks,
        uint256[100] memory timestamps,
        uint256 observationCardinality,
        uint256 cardinality,
        uint256 period
    ) public {
        cardinality = bound(cardinality, 1, 50);
        cardinality = cardinality * 2 - 1;
        period = bound(period, 1, 100 / cardinality);
        observationCardinality = bound(observationCardinality, cardinality * period + 1, 65535);
        UniPoolObservationMock mockPool = new UniPoolObservationMock(observationCardinality);
        observationIndex = bound(observationIndex, 0, observationCardinality - 1);
        int56 tickCum;
        for (uint256 i = 0; i < cardinality + 1; ++i) {
            ticks[i] = int24(bound(ticks[i], type(int24).min, type(int24).max));
            if (i == 0) {
                timestamps[i] = bound(timestamps[i], 0, type(uint32).max - (cardinality - i));

                // assume tickCum will not overflow
                vm.assume(tickCum + ticks[i] * int256(timestamps[i]) < type(int56).max);

                tickCum += int56(ticks[i] * int256(timestamps[i]));
            } else {
                timestamps[i] = bound(
                    timestamps[i],
                    timestamps[i - 1] + 1,
                    type(uint32).max - (cardinality - i)
                );

                // assume tickCum will not overflow
                vm.assume(tickCum + ticks[i] * int256(timestamps[i]) < type(int56).max);

                tickCum += int56(ticks[i] * int256(timestamps[i] - timestamps[i - 1]));
            }

            mockPool.setObservation(
                uint256(
                    (int256(uint256(observationIndex)) -
                        (int256(cardinality) - int256(i)) *
                        int256(period)) + int256(uint256(observationCardinality))
                ) % observationCardinality,
                uint32(timestamps[i]),
                tickCum
            );
        }

        // use bubble sort to get the median tick
        // note: the 4th tick is not actually deconstructed anywhere, but it is used as the base accumulator value.
        int256[] memory sortedTicks = new int256[](cardinality);
        for (uint16 i = 0; i < cardinality; ++i) {
            sortedTicks[i] = ticks[i + 1];
        }
        sortedTicks = Math.sort(sortedTicks);
        for (uint16 i = 0; i < cardinality; ++i) {
            console2.log(
                "sortedTicks["
                "]: ",
                sortedTicks[i]
            );
        }
        assertEq(
            harness.computeMedianObservedPrice(
                IUniswapV3Pool(address(mockPool)),
                observationIndex,
                observationCardinality,
                cardinality,
                period
            ),
            sortedTicks[sortedTicks.length / 2]
        );
    }

    function test_Success_twapFilter(uint32 twapWindow) public {
        twapWindow = uint32(bound(twapWindow, 100, 10000));

        selectedPool = pools[bound(twapWindow, 0, 2)]; // reuse twapWindow as seed

        uint32[] memory secondsAgos = new uint32[](20);
        int256[] memory twapMeasurement = new int256[](19);

        for (uint32 i = 0; i < 20; ++i) {
            secondsAgos[i] = ((i + 1) * twapWindow) / uint32(20);
        }

        (int56[] memory tickCumulatives, ) = selectedPool.observe(secondsAgos);

        // compute the average tick per 30s window
        for (uint32 i = 0; i < 19; ++i) {
            twapMeasurement[i] =
                (tickCumulatives[i] - tickCumulatives[i + 1]) /
                int56(uint56(twapWindow / 20));
        }

        // sort the tick measurements
        int256[] memory sortedTicks = Math.sort(twapMeasurement);

        // Get the median value
        int256 twapTick = sortedTicks[10];

        assertEq(twapTick, harness.twapFilter(selectedPool, twapWindow));
    }

    function test_Success_convertCollateralData_Tick_tokenType0(
        int256 atTickSeed,
        uint128 balance0,
        uint128 required0,
        uint128 balance1,
        uint128 required1
    ) public {
        int24 atTick = int24(bound(atTickSeed, TickMath.MIN_TICK, TickMath.MAX_TICK));
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(atTick);

        (uint256 collateralBalance, uint256 requiredCollateral) = harness.convertCollateralData(
            LeftRightUnsigned.wrap(0).toRightSlot(balance0).toLeftSlot(required0),
            LeftRightUnsigned.wrap(0).toRightSlot(balance1).toLeftSlot(required1),
            0,
            sqrtPriceX96
        );
        assertEq(collateralBalance, balance0 + PanopticMath.convert1to0(balance1, sqrtPriceX96));
        assertEq(requiredCollateral, required0 + PanopticMath.convert1to0(required1, sqrtPriceX96));
    }

    function test_Success_convertCollateralData_Tick_tokenType1(
        int256 atTickSeed,
        uint128 balance0,
        uint128 required0,
        uint128 balance1,
        uint128 required1
    ) public {
        int24 atTick = int24(bound(atTickSeed, TickMath.MIN_TICK, TickMath.MAX_TICK));
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(atTick);

        (uint256 collateralBalance, uint256 requiredCollateral) = harness.convertCollateralData(
            LeftRightUnsigned.wrap(0).toRightSlot(balance0).toLeftSlot(required0),
            LeftRightUnsigned.wrap(0).toRightSlot(balance1).toLeftSlot(required1),
            1,
            sqrtPriceX96
        );
        assertEq(collateralBalance, balance1 + PanopticMath.convert0to1(balance0, sqrtPriceX96));
        assertEq(requiredCollateral, required1 + PanopticMath.convert0to1(required0, sqrtPriceX96));
    }

    function test_Success_convertCollateralData_sqrtPrice_tokenType0(
        uint256 sqrtPriceSeed,
        uint128 balance0,
        uint128 required0,
        uint128 balance1,
        uint128 required1
    ) public {
        uint160 sqrtPriceX96 = uint160(
            bound(sqrtPriceSeed, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO)
        );

        (uint256 collateralBalance, uint256 requiredCollateral) = harness.convertCollateralData(
            LeftRightUnsigned.wrap(0).toRightSlot(balance0).toLeftSlot(required0),
            LeftRightUnsigned.wrap(0).toRightSlot(balance1).toLeftSlot(required1),
            0,
            sqrtPriceX96
        );
        assertEq(collateralBalance, balance0 + PanopticMath.convert1to0(balance1, sqrtPriceX96));
        assertEq(requiredCollateral, required0 + PanopticMath.convert1to0(required1, sqrtPriceX96));
    }

    function test_Success_convertCollateralData_sqrtPrice_tokenType1(
        uint256 sqrtPriceSeed,
        uint128 balance0,
        uint128 required0,
        uint128 balance1,
        uint128 required1
    ) public {
        uint160 sqrtPriceX96 = uint160(
            bound(sqrtPriceSeed, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO)
        );

        (uint256 collateralBalance, uint256 requiredCollateral) = harness.convertCollateralData(
            LeftRightUnsigned.wrap(0).toRightSlot(balance0).toLeftSlot(required0),
            LeftRightUnsigned.wrap(0).toRightSlot(balance1).toLeftSlot(required1),
            1,
            sqrtPriceX96
        );
        assertEq(collateralBalance, balance1 + PanopticMath.convert0to1(balance0, sqrtPriceX96));
        assertEq(requiredCollateral, required1 + PanopticMath.convert0to1(required0, sqrtPriceX96));
    }

    function test_Success_convertNotional_asset0(
        int256 tickLower,
        int256 tickUpper,
        uint128 amount
    ) public {
        tickLower = bound(tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK);
        tickUpper = bound(tickUpper, TickMath.MIN_TICK, TickMath.MAX_TICK);

        uint256 sqrtRatio = uint256(
            TickMath.getSqrtRatioAtTick(int24((tickLower + tickUpper) / 2))
        );

        // make sure nothing overflows
        if (sqrtRatio < type(uint128).max) {
            uint256 priceX192 = uint256(sqrtRatio) ** 2;

            unchecked {
                uint256 mm = mulmod(priceX192, amount, type(uint256).max);
                uint256 prod0 = priceX192 * amount;
                vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < 2 ** 192);
            }
        } else {
            uint256 priceX128 = FullMath.mulDiv(sqrtRatio, sqrtRatio, 2 ** 64);

            // make sure the final result does not overflow
            unchecked {
                uint256 mm = mulmod(priceX128, amount, type(uint256).max);
                uint256 prod0 = priceX128 * amount;
                vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < 2 ** 128);
            }
        }

        uint256 res = harness.convert0to1(amount, uint160(sqrtRatio));

        // make sure result fits in uint128 and is nonzero
        vm.assume(res <= type(uint128).max && res > 0);

        assertEq(harness._convertNotional(amount, int24(tickLower), int24(tickUpper), 0), res);
    }

    function test_Success_convertNotional_asset0_InvalidNotionalValue(
        int256 tickLower,
        int256 tickUpper,
        uint128 amount
    ) public {
        tickLower = bound(tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK);
        tickUpper = bound(tickUpper, TickMath.MIN_TICK, TickMath.MAX_TICK);

        uint256 sqrtRatio = uint256(
            TickMath.getSqrtRatioAtTick(int24((tickLower + tickUpper) / 2))
        );

        // make sure nothing overflows
        if (sqrtRatio < type(uint128).max) {
            uint256 priceX192 = uint256(sqrtRatio) ** 2;

            unchecked {
                uint256 mm = mulmod(priceX192, amount, type(uint256).max);
                uint256 prod0 = priceX192 * amount;
                vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < 2 ** 192);
            }
        } else {
            uint256 priceX128 = FullMath.mulDiv(sqrtRatio, sqrtRatio, 2 ** 64);

            // make sure the final result does not overflow
            unchecked {
                uint256 mm = mulmod(priceX128, amount, type(uint256).max);
                uint256 prod0 = priceX128 * amount;
                vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < 2 ** 128);
            }
        }

        uint256 res = harness.convert0to1(amount, uint160(sqrtRatio));

        // make sure result does not fit in uint128 or is zero
        vm.assume(res > type(uint128).max || res == 0);

        vm.expectRevert(Errors.InvalidNotionalValue.selector);
        harness._convertNotional(amount, int24(tickLower), int24(tickUpper), 0);
    }

    function test_Success_convertNotional_asset1(
        int256 tickLower,
        int256 tickUpper,
        uint128 amount
    ) public {
        tickLower = bound(tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK);
        tickUpper = bound(tickUpper, TickMath.MIN_TICK, TickMath.MAX_TICK);

        uint256 sqrtRatio = uint256(
            TickMath.getSqrtRatioAtTick(int24((tickLower + tickUpper) / 2))
        );

        // make sure nothing overflows
        if (sqrtRatio < type(uint128).max) {
            uint256 priceX192 = uint256(sqrtRatio) ** 2;

            unchecked {
                uint256 mm = mulmod(2 ** 192, amount, type(uint256).max);
                uint256 prod0 = 2 ** 192 * amount;
                vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < priceX192);
            }
        } else {
            uint256 priceX128 = FullMath.mulDiv(sqrtRatio, sqrtRatio, 2 ** 64);

            // make sure the final result does not overflow
            unchecked {
                uint256 mm = mulmod(2 * 128, amount, type(uint256).max);
                uint256 prod0 = 2 ** 128 * amount;
                vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < priceX128);
            }
        }

        uint256 res = harness.convert1to0(amount, uint160(sqrtRatio));

        // make sure result fits in uint128 and is nonzero
        vm.assume(res <= type(uint128).max && res > 0);

        assertEq(harness._convertNotional(amount, int24(tickLower), int24(tickUpper), 1), res);
    }

    function test_Success_convertNotional_asset1_InvalidNotionalValue(
        int256 tickLower,
        int256 tickUpper,
        uint128 amount
    ) public {
        tickLower = bound(tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK);
        tickUpper = bound(tickUpper, TickMath.MIN_TICK, TickMath.MAX_TICK);

        uint256 sqrtRatio = uint256(
            TickMath.getSqrtRatioAtTick(int24((tickLower + tickUpper) / 2))
        );

        // make sure nothing overflows
        if (sqrtRatio < type(uint128).max) {
            uint256 priceX192 = uint256(sqrtRatio) ** 2;

            unchecked {
                uint256 mm = mulmod(2 ** 192, amount, type(uint256).max);
                uint256 prod0 = 2 ** 192 * amount;
                vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < priceX192);
            }
        } else {
            uint256 priceX128 = FullMath.mulDiv(sqrtRatio, sqrtRatio, 2 ** 64);

            // make sure the final result does not overflow
            unchecked {
                uint256 mm = mulmod(2 * 128, amount, type(uint256).max);
                uint256 prod0 = 2 ** 128 * amount;
                vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < priceX128);
            }
        }

        uint256 res = harness.convert1to0(amount, uint160(sqrtRatio));

        // make sure result does not fit in uint128 or is zero
        vm.assume(res > type(uint128).max || res == 0);

        vm.expectRevert(Errors.InvalidNotionalValue.selector);
        harness._convertNotional(amount, int24(tickLower), int24(tickUpper), 1);
    }

    function test_Success_convert0to1_PriceX192_Uint(uint256 amount, uint256 sqrtPriceSeed) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, TickMath.MIN_SQRT_RATIO, type(uint128).max - 1)
        );

        uint256 priceX192 = uint256(sqrtPrice) ** 2;

        // make sure the final result does not overflow
        unchecked {
            uint256 mm = mulmod(priceX192, amount, type(uint256).max);
            uint256 prod0 = priceX192 * amount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < 2 ** 192);
        }

        assertEq(
            harness.convert0to1(amount, sqrtPrice),
            FullMath.mulDiv(amount, priceX192, 2 ** 192)
        );
    }

    function test_Fail_convert0to1_PriceX192_Uint_overflow(
        uint256 amount,
        uint256 sqrtPriceSeed
    ) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, TickMath.MIN_SQRT_RATIO, type(uint128).max - 1)
        );

        uint256 priceX192 = uint256(sqrtPrice) ** 2;

        // make sure the final result does overflow
        unchecked {
            uint256 mm = mulmod(priceX192, amount, type(uint256).max);
            uint256 prod0 = priceX192 * amount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) >= 2 ** 192);
        }

        vm.expectRevert();
        harness.convert0to1(amount, sqrtPrice);
    }

    function test_Success_convert0to1_PriceX192_Int(int256 amount, uint256 sqrtPriceSeed) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, TickMath.MIN_SQRT_RATIO, type(uint128).max - 1)
        );

        uint256 priceX192 = uint256(sqrtPrice) ** 2;

        uint256 absAmount = Math.absUint(amount);

        // make sure the final result does not overflow
        unchecked {
            uint256 mm = mulmod(priceX192, absAmount, type(uint256).max);
            uint256 prod0 = priceX192 * absAmount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < 2 ** 192);
        }
        vm.assume(FullMath.mulDiv(absAmount, priceX192, 2 ** 192) <= uint256(type(int256).max));
        assertEq(
            harness.convert0to1(amount, sqrtPrice),
            (amount < 0 ? -1 : int(1)) * int(FullMath.mulDiv(absAmount, priceX192, 2 ** 192))
        );
    }

    function test_Fail_convert0to1_PriceX192_Int_overflow(
        int256 amount,
        uint256 sqrtPriceSeed
    ) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, TickMath.MIN_SQRT_RATIO, type(uint128).max - 1)
        );

        uint256 priceX192 = uint256(sqrtPrice) ** 2;

        uint256 absAmount = Math.absUint(amount);

        // make sure the final result does overflow
        unchecked {
            uint256 mm = mulmod(priceX192, absAmount, type(uint256).max);
            uint256 prod0 = priceX192 * absAmount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) >= 2 ** 192);
        }

        vm.expectRevert();
        harness.convert0to1(amount, sqrtPrice);
    }

    function test_Fail_convert0to1_PriceX192_Int_CastingError(
        int256 amount,
        uint256 sqrtPriceSeed
    ) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, TickMath.MIN_SQRT_RATIO, type(uint128).max - 1)
        );

        uint256 priceX192 = uint256(sqrtPrice) ** 2;

        uint256 absAmount = Math.absUint(amount);

        // make sure the final result does overflow
        unchecked {
            uint256 mm = mulmod(priceX192, absAmount, type(uint256).max);
            uint256 prod0 = priceX192 * absAmount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < 2 ** 192);
        }

        vm.assume(FullMath.mulDiv(absAmount, priceX192, 2 ** 192) > uint256(type(int256).max));
        vm.expectRevert(Errors.CastingError.selector);
        harness.convert0to1(amount, sqrtPrice);
    }

    function test_Success_convert1to0_PriceX192_Uint(uint256 amount, uint256 sqrtPriceSeed) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, TickMath.MIN_SQRT_RATIO, type(uint128).max - 1)
        );

        uint256 priceX192 = uint256(sqrtPrice) ** 2;

        // make sure the final result does not overflow
        unchecked {
            uint256 mm = mulmod(amount, 2 ** 192, type(uint256).max);
            uint256 prod0 = 2 ** 192 * amount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < priceX192);
        }

        assertEq(
            harness.convert1to0(amount, sqrtPrice),
            FullMath.mulDiv(amount, 2 ** 192, priceX192)
        );
    }

    function test_Fail_convert1to0_PriceX192_Uint_overflow(
        uint256 amount,
        uint256 sqrtPriceSeed
    ) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, TickMath.MIN_SQRT_RATIO, type(uint128).max - 1)
        );

        uint256 priceX192 = uint256(sqrtPrice) ** 2;

        // make sure the final result does overflow
        unchecked {
            uint256 mm = mulmod(amount, 2 ** 192, type(uint256).max);
            uint256 prod0 = 2 ** 192 * amount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) >= priceX192);
        }

        vm.expectRevert();
        harness.convert1to0(amount, sqrtPrice);
    }

    function test_Success_convert1to0_PriceX192_Int(int256 amount, uint256 sqrtPriceSeed) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, TickMath.MIN_SQRT_RATIO, type(uint128).max - 1)
        );

        uint256 priceX192 = uint256(sqrtPrice) ** 2;

        uint256 absAmount = Math.absUint(amount);

        // make sure the final result does not overflow
        unchecked {
            uint256 mm = mulmod(absAmount, 2 ** 192, type(uint256).max);
            uint256 prod0 = 2 ** 192 * absAmount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < priceX192);
        }

        vm.assume(FullMath.mulDiv(absAmount, 2 ** 192, priceX192) <= uint256(type(int256).max));
        assertEq(
            harness.convert1to0(amount, sqrtPrice),
            (amount < 0 ? -1 : int(1)) * int(FullMath.mulDiv(absAmount, 2 ** 192, priceX192))
        );
    }

    function test_Fail_convert1to0_PriceX192_Int_overflow(
        int256 amount,
        uint256 sqrtPriceSeed
    ) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, TickMath.MIN_SQRT_RATIO, type(uint128).max - 1)
        );

        uint256 priceX192 = uint256(sqrtPrice) ** 2;

        uint256 absAmount = Math.absUint(amount);

        // make sure the final result does not overflow
        unchecked {
            uint256 mm = mulmod(2 ** 192, absAmount, type(uint256).max);
            uint256 prod0 = 2 ** 192 * absAmount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) >= priceX192);
        }

        vm.expectRevert();
        harness.convert1to0(amount, sqrtPrice);
    }

    function test_Fail_convert1to0_PriceX192_Int_CastingError(
        int256 amount,
        uint256 sqrtPriceSeed
    ) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, TickMath.MIN_SQRT_RATIO, type(uint128).max - 1)
        );

        uint256 priceX192 = uint256(sqrtPrice) ** 2;

        uint256 absAmount = Math.absUint(amount);

        // make sure the final result does not overflow
        unchecked {
            uint256 mm = mulmod(2 ** 192, absAmount, type(uint256).max);
            uint256 prod0 = 2 ** 192 * absAmount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < priceX192);
        }

        vm.assume(FullMath.mulDiv(absAmount, 2 ** 192, priceX192) > uint256(type(int256).max));
        vm.expectRevert(Errors.CastingError.selector);
        harness.convert1to0(amount, sqrtPrice);
    }

    function test_Success_convert0to1_PriceX128_Uint(uint256 amount, uint256 sqrtPriceSeed) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, type(uint128).max, TickMath.MAX_SQRT_RATIO)
        );

        uint256 priceX128 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 2 ** 64);

        // make sure the final result does not overflow
        unchecked {
            uint256 mm = mulmod(priceX128, amount, type(uint256).max);
            uint256 prod0 = priceX128 * amount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < 2 ** 128);
        }

        assertEq(
            harness.convert0to1(amount, sqrtPrice),
            FullMath.mulDiv(amount, priceX128, 2 ** 128)
        );
    }

    function test_Fail_convert0to1_PriceX128_Uint_overflow(
        uint256 amount,
        uint256 sqrtPriceSeed
    ) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, type(uint128).max, TickMath.MAX_SQRT_RATIO)
        );

        uint256 priceX128 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 2 ** 64);

        // make sure the final result does overflow
        unchecked {
            uint256 mm = mulmod(priceX128, amount, type(uint256).max);
            uint256 prod0 = priceX128 * amount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) >= 2 ** 128);
        }

        vm.expectRevert();
        harness.convert0to1(amount, sqrtPrice);
    }

    function test_Success_convert0to1_PriceX128_Int(int256 amount, uint256 sqrtPriceSeed) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, type(uint128).max, TickMath.MAX_SQRT_RATIO)
        );

        uint256 priceX128 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 2 ** 64);

        uint256 absAmount = Math.absUint(amount);

        // make sure the final result does not overflow
        unchecked {
            uint256 mm = mulmod(priceX128, absAmount, type(uint256).max);
            uint256 prod0 = priceX128 * absAmount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < 2 ** 128);
        }

        vm.assume(FullMath.mulDiv(absAmount, priceX128, 2 ** 128) <= uint256(type(int256).max));
        assertEq(
            harness.convert0to1(amount, sqrtPrice),
            (amount < 0 ? -1 : int(1)) * int(FullMath.mulDiv(absAmount, priceX128, 2 ** 128))
        );
    }

    function test_Fail_convert0to1_PriceX128_Int_overflow(
        int256 amount,
        uint256 sqrtPriceSeed
    ) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, type(uint128).max, TickMath.MAX_SQRT_RATIO)
        );

        uint256 priceX128 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 2 ** 64);

        uint256 absAmount = Math.absUint(amount);

        // make sure the final result does overflow
        unchecked {
            uint256 mm = mulmod(priceX128, absAmount, type(uint256).max);
            uint256 prod0 = priceX128 * absAmount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) >= 2 ** 128);
        }

        vm.expectRevert();
        harness.convert0to1(amount, sqrtPrice);
    }

    function test_Fail_convert0to1_PriceX128_Int_CastingError(
        int256 amount,
        uint256 sqrtPriceSeed
    ) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, type(uint128).max, TickMath.MAX_SQRT_RATIO)
        );

        uint256 priceX128 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 2 ** 64);

        uint256 absAmount = Math.absUint(amount);

        // make sure the final result does overflow
        unchecked {
            uint256 mm = mulmod(priceX128, absAmount, type(uint256).max);
            uint256 prod0 = priceX128 * absAmount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < 2 ** 128);
        }

        vm.assume(FullMath.mulDiv(absAmount, priceX128, 2 ** 128) > uint256(type(int256).max));
        vm.expectRevert(Errors.CastingError.selector);
        harness.convert0to1(amount, sqrtPrice);
    }

    function test_Success_convert1to0_PriceX128_Uint(uint256 amount, uint256 sqrtPriceSeed) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, type(uint128).max, TickMath.MAX_SQRT_RATIO)
        );

        uint256 priceX128 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 2 ** 64);

        // make sure the final result does not overflow
        unchecked {
            uint256 mm = mulmod(2 ** 128, amount, type(uint256).max);
            uint256 prod0 = 2 ** 128 * amount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < priceX128);
        }

        assertEq(
            harness.convert1to0(amount, sqrtPrice),
            FullMath.mulDiv(amount, 2 ** 128, priceX128)
        );
    }

    function test_Success_convert1to0_PriceX128_Int(int256 amount, uint256 sqrtPriceSeed) public {
        // above this tick we use 128-bit precision because of overflow issues
        uint160 sqrtPrice = uint160(
            bound(sqrtPriceSeed, type(uint128).max, TickMath.MAX_SQRT_RATIO)
        );

        uint256 priceX128 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 2 ** 64);

        uint256 absAmount = Math.absUint(amount);

        // make sure the final result does not overflow
        unchecked {
            uint256 mm = mulmod(2 ** 128, absAmount, type(uint256).max);
            uint256 prod0 = 2 ** 128 * absAmount;
            vm.assume((mm - prod0) - (mm < prod0 ? 1 : 0) < priceX128);
        }

        vm.assume(FullMath.mulDiv(absAmount, 2 ** 128, priceX128) <= uint256(type(int256).max));
        assertEq(
            harness.convert1to0(amount, sqrtPrice),
            (amount < 0 ? -1 : int(1)) * int(FullMath.mulDiv(absAmount, 2 ** 128, priceX128))
        );
    }

    function test_Success_getAmountsMoved_asset0(
        uint256 optionRatioSeed,
        uint16 isLong,
        uint16 tokenType,
        int24 strike,
        int24 width,
        uint64 positionSize
    ) public {
        vm.assume(positionSize != 0);
        TokenId tokenId;

        // contruct a tokenId
        {
            uint256 optionRatio = bound(optionRatioSeed, 1, 1);

            // the following are all 1 bit so mask them:
            uint8 MASK = 0x1; // takes first 1 bit of the uint16
            isLong = isLong & MASK;
            tokenType = tokenType & MASK;

            // bound fuzzed tick
            selectedPool = pools[bound(optionRatio, 0, 2)]; // reuse optionRatio as seed
            tickSpacing = selectedPool.tickSpacing();

            width = int24(bound(width, 1, 2048));

            int24 rangeDown;
            int24 rangeUp;
            (rangeDown, rangeUp) = PanopticMath.getRangesFromStrike(width, int24(tickSpacing));

            (, currentTick, , , , , ) = selectedPool.slot0();
            (strikeOffset, minTick, maxTick) = PositionUtils.getContextFull(
                uint256(uint24(tickSpacing)),
                currentTick,
                width
            );

            lowerBound = int24(minTick + rangeDown - strikeOffset);
            upperBound = int24(maxTick - rangeUp - strikeOffset);

            // bound strike
            strike = int24(bound(strike, lowerBound / tickSpacing, upperBound / tickSpacing));
            strike = int24(strike * tickSpacing + strikeOffset);

            tokenId = TokenId.wrap(uint256(uint24(tickSpacing)) << 48);
            tokenId = tokenId.addLeg(0, optionRatio, 0, isLong, tokenType, 0, strike, width);
        }

        // get the tick range for this leg in order to get the strike price (the underlying price)
        (int24 tickLower, int24 tickUpper) = tokenId.asTicks(0);

        // set amount 0
        uint128 amount0 = positionSize * uint128(tokenId.optionRatio(0));

        // get amount 1
        // construct liq object
        LiquidityChunk liquidityAmounts = Math.getLiquidityForAmount0(
            tickLower,
            tickUpper,
            amount0
        );
        // set amount 1
        uint256 intermediateAmount1 = Math.getAmount1ForLiquidity(liquidityAmounts);
        vm.assume(intermediateAmount1 < type(uint128).max); // as sizes above 128 bits are not allowed (reverts in sc)
        uint128 amount1 = intermediateAmount1.toUint128();

        LeftRightUnsigned expectedContractsNotional = LeftRightUnsigned
            .wrap(0)
            .toRightSlot(amount0)
            .toLeftSlot(amount1);

        LeftRightUnsigned returnedContractsNotional = harness.getAmountsMoved(
            tokenId,
            positionSize,
            0
        );
        assertEq(
            LeftRightUnsigned.unwrap(expectedContractsNotional),
            LeftRightUnsigned.unwrap(returnedContractsNotional)
        );
    }

    function test_Success_getAmountsMoved_asset1(
        uint256 optionRatio,
        uint16 isLong,
        uint16 tokenType,
        int24 strike,
        int24 width,
        uint64 positionSize
    ) public {
        vm.assume(positionSize != 0);
        TokenId tokenId;

        // contruct a tokenId
        {
            selectedPool = pools[bound(optionRatio, 0, 2)]; // reuse optionRatio as seed

            optionRatio = bound(optionRatio, 1, 127);

            // the following are all 1 bit so mask them:
            uint8 MASK = 0x1; // takes first 1 bit of the uint16
            isLong = isLong & MASK;
            tokenType = tokenType & MASK;

            // bound fuzzed tick
            tickSpacing = selectedPool.tickSpacing();

            width = int24(bound(width, 1, 2048));

            int24 rangeDown;
            int24 rangeUp;
            (rangeDown, rangeUp) = PanopticMath.getRangesFromStrike(width, int24(tickSpacing));

            (, currentTick, , , , , ) = selectedPool.slot0();
            (strikeOffset, minTick, maxTick) = PositionUtils.getContextFull(
                uint256(uint24(tickSpacing)),
                currentTick,
                width
            );

            lowerBound = int24(minTick + rangeDown - strikeOffset);
            upperBound = int24(maxTick - rangeUp - strikeOffset);

            // Set current tick and pool price
            currentTick = int24(bound(currentTick, minTick, maxTick));

            // bound strike
            strike = int24(bound(strike, lowerBound / tickSpacing, upperBound / tickSpacing));
            strike = int24(strike * tickSpacing + strikeOffset);

            tokenId = TokenId.wrap(uint256(uint24(tickSpacing)) << 48);
            tokenId = tokenId.addLeg(0, optionRatio, 1, isLong, tokenType, 0, strike, width);
        }

        // get the tick range for this leg in order to get the strike price (the underlying price)
        (int24 tickLower, int24 tickUpper) = tokenId.asTicks(0);

        // set amount 1
        uint128 amount1 = positionSize * uint128(tokenId.optionRatio(0));

        // get amount 0
        // construct liq object
        LiquidityChunk liquidityAmounts = Math.getLiquidityForAmount1(
            tickLower,
            tickUpper,
            amount1
        );
        // set amount 1
        uint256 intermediateAmount0 = Math.getAmount0ForLiquidity(liquidityAmounts);
        vm.assume(intermediateAmount0 < type(uint128).max); // as sizes above 128 bits are not allowed (reverts in sc)
        uint128 amount0 = intermediateAmount0.toUint128();

        LeftRightUnsigned expectedContractsNotional = LeftRightUnsigned
            .wrap(0)
            .toRightSlot(amount0)
            .toLeftSlot(amount1);

        LeftRightUnsigned returnedContractsNotional = harness.getAmountsMoved(
            tokenId,
            positionSize,
            0
        );
        assertEq(
            LeftRightUnsigned.unwrap(expectedContractsNotional),
            LeftRightUnsigned.unwrap(returnedContractsNotional)
        );
    }

    // // _calculateIOAmounts
    function test_Success_calculateIOAmounts_shortTokenType0(
        uint256 optionRatioSeed,
        uint16 asset,
        int24 strike,
        int24 width,
        uint64 positionSize
    ) public {
        vm.assume(positionSize != 0);
        TokenId tokenId;

        // contruct a tokenId
        {
            uint256 optionRatio = bound(optionRatioSeed, 1, 1);

            // the following are all 1 bit so mask them:
            uint8 MASK = 0x1; // takes first 1 bit of the uint16
            asset = asset & MASK;

            // bound fuzzed tick
            selectedPool = pools[bound(optionRatio, 0, 2)]; // reuse optionRatio as seed
            tickSpacing = selectedPool.tickSpacing();

            width = int24(bound(width, 1, 2048));
            int24 oneSidedRange = (width * tickSpacing) / 2;

            (, currentTick, , , , , ) = selectedPool.slot0();
            (strikeOffset, minTick, maxTick) = PositionUtils.getContextFull(
                uint256(uint24(tickSpacing)),
                currentTick,
                width
            );

            lowerBound = int24(minTick + oneSidedRange - strikeOffset);
            upperBound = int24(maxTick - oneSidedRange - strikeOffset);

            // Set current tick and pool price
            currentTick = int24(bound(currentTick, minTick, maxTick));

            // bound strike
            strike = int24(bound(strike, lowerBound / tickSpacing, upperBound / tickSpacing));
            strike = int24(strike * tickSpacing + strikeOffset);

            tokenId = TokenId.wrap(uint256(uint24(tickSpacing)) << 48);
            tokenId = tokenId.addLeg(0, optionRatio, asset, 0, 0, 0, strike, width);
        }

        LeftRightUnsigned contractsNotional = harness.getAmountsMoved(tokenId, positionSize, 0);
        vm.assume(int256(uint256(contractsNotional.rightSlot())) < type(int128).max);

        LeftRightSigned expectedShorts = LeftRightSigned.wrap(0).toRightSlot(
            Math.toInt128(contractsNotional.rightSlot())
        );
        (LeftRightSigned returnedLongs, LeftRightSigned returnedShorts) = harness
            .calculateIOAmounts(tokenId, positionSize, 0);

        assertEq(LeftRightSigned.unwrap(expectedShorts), LeftRightSigned.unwrap(returnedShorts));
        assertEq(0, LeftRightSigned.unwrap(returnedLongs));
    }

    function test_Success_calculateIOAmounts_longTokenType0(
        uint16 asset,
        int24 strike,
        int24 width,
        uint64 positionSize
    ) public {
        vm.assume(positionSize != 0);
        TokenId tokenId;

        // contruct a tokenId
        {
            uint256 optionRatio = 1;

            // the following are all 1 bit so mask them:
            uint8 MASK = 0x1; // takes first 1 bit of the uint16
            asset = asset & MASK;

            // bound fuzzed tick
            selectedPool = pools[bound(optionRatio, 0, 2)]; // reuse optionRatio as seed
            tickSpacing = selectedPool.tickSpacing();

            width = int24(bound(width, 1, 2048));
            int24 oneSidedRange = (width * tickSpacing) / 2;

            (, currentTick, , , , , ) = selectedPool.slot0();
            (strikeOffset, minTick, maxTick) = PositionUtils.getContextFull(
                uint256(uint24(tickSpacing)),
                currentTick,
                width
            );

            lowerBound = int24(minTick + oneSidedRange - strikeOffset);
            upperBound = int24(maxTick - oneSidedRange - strikeOffset);

            // Set current tick and pool price
            currentTick = int24(bound(currentTick, minTick, maxTick));

            // bound strike
            strike = int24(bound(strike, lowerBound / tickSpacing, upperBound / tickSpacing));
            strike = int24(strike * tickSpacing + strikeOffset);

            tokenId = TokenId.wrap(uint256(uint24(tickSpacing)) << 48);
            tokenId = tokenId.addLeg(0, optionRatio, asset, 1, 0, 0, strike, width);
        }

        // contractSize = positionSize * uint128(tokenId.optionRatio(legIndex));
        (int24 legLowerTick, int24 legUpperTick) = tokenId.asTicks(0);

        positionSize = uint64(
            PositionUtils.getContractsForAmountAtTick(
                currentTick,
                legLowerTick,
                legUpperTick,
                1,
                uint128(positionSize)
            )
        );

        LeftRightUnsigned contractsNotional = harness.getAmountsMoved(tokenId, positionSize, 0);
        vm.assume(int256(uint256(contractsNotional.rightSlot())) < type(int128).max);

        LeftRightSigned expectedLongs = LeftRightSigned.wrap(0).toRightSlot(
            Math.toInt128(contractsNotional.rightSlot())
        );
        (LeftRightSigned returnedLongs, LeftRightSigned returnedShorts) = harness
            .calculateIOAmounts(tokenId, positionSize, 0);

        assertEq(LeftRightSigned.unwrap(expectedLongs), LeftRightSigned.unwrap(returnedLongs));
        assertEq(0, LeftRightSigned.unwrap(returnedShorts));
    }

    function test_Success_calculateIOAmounts_shortTokenType1(
        uint256 optionRatioSeed,
        uint16 asset,
        int24 strike,
        int24 width,
        uint64 positionSize
    ) public {
        positionSize = uint64(bound(positionSize, 1, type(uint64).max));
        TokenId tokenId;

        // contruct a tokenId
        {
            uint256 optionRatio = bound(optionRatioSeed, 1, 127);

            // the following are all 1 bit so mask them:
            uint8 MASK = 0x1; // takes first 1 bit of the uint16
            asset = asset & MASK;

            // bound fuzzed tick
            selectedPool = pools[bound(optionRatio, 0, 2)]; // reuse optionRatio as seed
            tickSpacing = selectedPool.tickSpacing();

            width = int24(bound(width, 1, 2048));
            int24 oneSidedRange = (width * tickSpacing) / 2;

            (, currentTick, , , , , ) = selectedPool.slot0();
            (strikeOffset, minTick, maxTick) = PositionUtils.getContextFull(
                uint256(uint24(tickSpacing)),
                currentTick,
                width
            );

            lowerBound = int24(minTick + oneSidedRange - strikeOffset);
            upperBound = int24(maxTick - oneSidedRange - strikeOffset);

            // bound strike
            strike = int24(bound(strike, lowerBound / tickSpacing, upperBound / tickSpacing));
            strike = int24(strike * tickSpacing + strikeOffset);

            tokenId = TokenId.wrap(uint256(uint24(tickSpacing)) << 48);
            tokenId = tokenId.addLeg(0, optionRatio, asset, 0, 1, 0, strike, width);
        }

        LeftRightUnsigned contractsNotional = harness.getAmountsMoved(tokenId, positionSize, 0);
        vm.assume(int256(uint256(contractsNotional.leftSlot())) < type(int128).max);

        LeftRightSigned expectedShorts = LeftRightSigned.wrap(0).toLeftSlot(
            Math.toInt128(contractsNotional.leftSlot())
        );
        (LeftRightSigned returnedLongs, LeftRightSigned returnedShorts) = harness
            .calculateIOAmounts(tokenId, positionSize, 0);

        assertEq(LeftRightSigned.unwrap(expectedShorts), LeftRightSigned.unwrap(returnedShorts));
        assertEq(0, LeftRightSigned.unwrap(returnedLongs));
    }

    function test_Success_calculateIOAmounts_longTokenType1(
        uint256 optionRatioSeed,
        uint16 asset,
        int24 strike,
        int24 width,
        uint64 positionSize
    ) public {
        vm.assume(positionSize != 0);
        TokenId tokenId;

        // contruct a tokenId
        {
            uint256 optionRatio = bound(optionRatioSeed, 1, 127);

            // max bound position size * optionRatio can be to avoid overflows
            vm.assume(positionSize * uint128(optionRatio) < type(uint56).max);

            // the following are all 1 bit so mask them:
            uint8 MASK = 0x1; // takes first 1 bit of the uint16
            asset = asset & MASK;

            // bound fuzzed tick
            selectedPool = pools[bound(optionRatio, 0, 2)]; // reuse optionRatio as seed
            tickSpacing = selectedPool.tickSpacing();

            width = int24(bound(width, 1, 2048));
            int24 oneSidedRange = (width * tickSpacing) / 2;

            (, currentTick, , , , , ) = selectedPool.slot0();
            (strikeOffset, minTick, maxTick) = PositionUtils.getContextFull(
                uint256(uint24(tickSpacing)),
                currentTick,
                width
            );

            lowerBound = int24(minTick + oneSidedRange - strikeOffset);
            upperBound = int24(maxTick - oneSidedRange - strikeOffset);

            // bound strike
            strike = int24(bound(strike, lowerBound / tickSpacing, upperBound / tickSpacing));
            strike = int24(strike * tickSpacing + strikeOffset);

            tokenId = TokenId.wrap(uint256(uint24(tickSpacing)) << 48);
            tokenId = tokenId.addLeg(0, optionRatio, asset, 1, 1, 0, strike, width);
        }

        LeftRightUnsigned contractsNotional = harness.getAmountsMoved(tokenId, positionSize, 0);

        vm.assume(int256(uint256(contractsNotional.leftSlot())) < type(int128).max);
        LeftRightSigned expectedLongs = LeftRightSigned.wrap(0).toLeftSlot(
            Math.toInt128(contractsNotional.leftSlot())
        );

        (LeftRightSigned returnedLongs, LeftRightSigned returnedShorts) = harness
            .calculateIOAmounts(tokenId, positionSize, 0);

        assertEq(LeftRightSigned.unwrap(expectedLongs), LeftRightSigned.unwrap(returnedLongs));
        assertEq(0, LeftRightSigned.unwrap(returnedShorts));
    }

    // mul div as ticks
    function test_Success_getRangesFromStrike_1bps_1TickWide() public {
        int24 width = 1;
        tickSpacing = 1;

        (int24 rangeDown, int24 rangeUp) = harness.getRangesFromStrike(width, tickSpacing);

        assertEq(rangeDown, 0, "rangeDown");
        assertEq(rangeUp, 1, "rangeUp");
    }

    function test_Success_getRangesFromStrike_allCombos(
        uint256 widthSeed,
        uint256 tickSpacingSeed,
        int24 strike
    ) public {
        // bound the width (1 -> 4094)
        uint24 widthBounded = uint24(bound(widthSeed, 1, 4094));

        // bound the tickSpacing
        uint24 tickSpacingBounded = uint24(bound(tickSpacingSeed, 1, 1000));

        // get a valid strike
        strike = int24((strike / int24(tickSpacingBounded)) * int24(tickSpacingBounded));

        // validate bounds
        vm.assume(strike > TickMath.MIN_TICK && strike < TickMath.MAX_TICK);

        // invoke
        (int24 rangeDown, int24 rangeUp) = harness.getRangesFromStrike(
            int24(widthBounded),
            int24(tickSpacingBounded)
        );

        // if width is odd and tickSpacing is odd
        // then actual range will not be a whole number
        if (widthBounded % 2 == 1 && tickSpacingBounded % 2 == 1) {
            uint256 mulDivRangeDown = Math.mulDiv(widthBounded, tickSpacingBounded, 2);

            uint256 mulDivRangeUp = Math.mulDivRoundingUp(widthBounded, tickSpacingBounded, 2);

            // ensure range is rounded down if width * tickSpacing is odd
            assertEq(uint24(rangeDown), mulDivRangeDown);

            // ensure range is rounded up if width * tickSpacing is odd
            assertEq(uint24(rangeUp), mulDivRangeUp);
        } else {
            // else even -> rangeDown and rangeUp are both just (width * ts) / 2
            int24 range = int24((widthBounded * tickSpacingBounded) / 2);

            assertEq(strike - rangeDown, strike - range);
            assertEq(strike + rangeUp, strike + range);
        }
    }
}
