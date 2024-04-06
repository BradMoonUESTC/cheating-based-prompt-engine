// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Foundry
import "forge-std/Test.sol";
// Internal
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {Math} from "@libraries/Math.sol";
import {PanopticMath} from "@libraries/PanopticMath.sol";
import {Errors} from "@libraries/Errors.sol";
import {FeesCalcHarness} from "./harnesses/FeesCalcHarness.sol";
import {TokenId} from "@types/TokenId.sol";
import {LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {LiquidityChunk} from "@types/LiquidityChunk.sol";
// Uniswap
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {FixedPoint96} from "v3-core/libraries/FixedPoint96.sol";
import {FixedPoint128} from "v3-core/libraries/FixedPoint128.sol";
// Test util
import {PositionUtils} from "../testUtils/PositionUtils.sol";

/**
 * Test the FeesCalc functionality with Foundry and Fuzzing.
 *
 * @author Axicon Labs Limited
 */
contract FeesCalcTest is Test, PositionUtils {
    // harness
    FeesCalcHarness harness;

    // store a few different mainnet pairs - the pool used is part of the fuzz
    IUniswapV3Pool constant USDC_WETH_5 =
        IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    IUniswapV3Pool constant WBTC_ETH_30 =
        IUniswapV3Pool(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD);
    IUniswapV3Pool constant USDC_WETH_30 =
        IUniswapV3Pool(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8);
    IUniswapV3Pool[3] public pools = [USDC_WETH_5, WBTC_ETH_30, USDC_WETH_30];

    // cache tick data
    uint160 sqrtPriceAt;
    int24 tickSpacing;
    int24 currentTick;

    // current run selected pool
    IUniswapV3Pool selectedPool;

    function setUp() public {
        harness = new FeesCalcHarness();
    }

    function test_Success_getPortfolioValue(
        uint256 poolIdSeed,
        uint256 optionRatioSeed,
        uint256 assetSeed,
        uint256 isLongSeed,
        uint256 tokenTypeSeed,
        int256 strikeSeed,
        int256 widthSeed,
        uint64 positionSize
    ) public {
        vm.assume(positionSize != 0);
        TokenId tokenId;
        selectedPool = pools[bound(poolIdSeed, 0, 2)];

        {
            // construct one leg token
            tokenId = fuzzedPosition(
                1, // total amount of legs
                poolIdSeed,
                optionRatioSeed,
                assetSeed,
                isLongSeed,
                tokenTypeSeed,
                strikeSeed,
                widthSeed
            );
        }

        // position size
        addBalance(tokenId, positionSize);

        // liquidity chunk
        LiquidityChunk liquidityChunk = PanopticMath.getLiquidityChunk(
            tokenId,
            0,
            harness.userBalance(tokenId).rightSlot()
        );

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceAt,
            TickMath.getSqrtRatioAtTick(liquidityChunk.tickLower()),
            TickMath.getSqrtRatioAtTick(liquidityChunk.tickUpper()),
            liquidityChunk.liquidity()
        );

        LeftRightSigned positionAmounts = LeftRightSigned
            .wrap(0)
            .toRightSlot(int128(int256(amount0)))
            .toLeftSlot(int128(int256(amount1)));
        LeftRightSigned portfolioAmounts;
        {
            // portfolio amounts
            unchecked {
                portfolioAmounts = tokenId.isLong(0) == 0
                    ? portfolioAmounts = portfolioAmounts.add(positionAmounts)
                    : portfolioAmounts = portfolioAmounts.sub(positionAmounts);
            }

            /// expected values
            int256 expectedValue0;
            int256 expectedValue1;
            unchecked {
                {
                    expectedValue0 = portfolioAmounts.rightSlot();
                }
                {
                    expectedValue1 = portfolioAmounts.leftSlot();
                }
            }

            /// actual values
            TokenId[] memory posIdList = new TokenId[](1);
            posIdList[0] = tokenId;
            (int256 returnedValue0, int256 returnedValue1) = harness.getPortfolioValue(
                currentTick,
                posIdList
            );

            assertEq(expectedValue0, returnedValue0, "value0");
            assertEq(expectedValue1, returnedValue1, "value1");
        }
    }

    // above/below/in-range branches
    function test_Success_calculateAMMSwapFeesLiquidityChunk(
        uint256 poolIdSeed,
        uint256 optionRatioSeed,
        uint256 assetSeed,
        uint256 isLongSeed,
        uint256 tokenTypeSeed,
        int256 strikeSeed,
        int256 widthSeed,
        uint64 positionSize,
        uint64 startingLiquidity
    ) public {
        vm.assume(positionSize != 0);
        TokenId tokenId;
        selectedPool = pools[bound(poolIdSeed, 0, 2)];

        {
            // construct one leg token
            tokenId = fuzzedPosition(
                1, // total amount of legs
                poolIdSeed,
                optionRatioSeed,
                assetSeed,
                isLongSeed,
                tokenTypeSeed,
                strikeSeed,
                widthSeed
            );
        }

        LiquidityChunk liquidityChunk = PanopticMath.getLiquidityChunk(tokenId, 0, positionSize);

        (uint256 ammFeesPerLiqToken0X128, uint256 ammFeesPerLiqToken1X128) = harness
            .getAMMSwapFeesPerLiquidityCollected(
                selectedPool,
                currentTick,
                liquidityChunk.tickLower(),
                liquidityChunk.tickUpper()
            );

        LeftRightSigned expectedFeesEachToken;
        expectedFeesEachToken = expectedFeesEachToken
            .toRightSlot(int128(int256(Math.mulDiv128(ammFeesPerLiqToken0X128, startingLiquidity))))
            .toLeftSlot(int128(int256(Math.mulDiv128(ammFeesPerLiqToken1X128, startingLiquidity))));

        LeftRightSigned returnedFeesEachToken = harness.calculateAMMSwapFees(
            selectedPool,
            currentTick,
            liquidityChunk.tickLower(),
            liquidityChunk.tickUpper(),
            startingLiquidity
        );

        assertEq(
            LeftRightSigned.unwrap(expectedFeesEachToken),
            LeftRightSigned.unwrap(returnedFeesEachToken)
        );
    }

    // returns token containing 'totalLegs' amount of legs
    // i.e totalLegs of 1 has a tokenId with 1 legs
    // uses a seed to fuzz data so that there is different data for each leg
    function fuzzedPosition(
        uint256 totalLegs,
        uint256 poolIdSeed,
        uint256 optionRatioSeed,
        uint256 assetSeed,
        uint256 isLongSeed,
        uint256 tokenTypeSeed,
        int256 strikeSeed,
        int256 widthSeed
    ) internal returns (TokenId) {
        tickSpacing = selectedPool.tickSpacing();
        // add univ3pool to token
        uint64 poolId = uint64(
            ((uint64(bound(poolIdSeed, 1, type(uint64).max)) >> 16)) +
                (uint64(uint24(tickSpacing)) << 48)
        );
        TokenId tokenId = TokenId.wrap(uint256(poolId));

        for (uint256 legIndex; legIndex < totalLegs; legIndex++) {
            // We don't want the same data for each leg
            // int divide each seed by the current legIndex
            // gives us a pseudorandom seed
            // forge bound does not randomize the output
            {
                uint256 randomizer = legIndex + 1;

                optionRatioSeed = optionRatioSeed / randomizer;
                assetSeed = assetSeed / randomizer;
                isLongSeed = isLongSeed / randomizer;
                tokenTypeSeed = tokenTypeSeed / randomizer;
                strikeSeed = strikeSeed / int24(int256(randomizer));
                widthSeed = widthSeed / int24(int256(randomizer));
            }

            {
                // the following are all 1 bit so mask them:
                uint16 MASK = 0x1; // takes first 1 bit of the uint16
                assetSeed = assetSeed & MASK;
                isLongSeed = isLongSeed & MASK;
                tokenTypeSeed = tokenTypeSeed & MASK;
            }

            /// bound inputs
            int24 strike;
            int24 width;
            {
                // the following must be at least 1
                optionRatioSeed = bound(optionRatioSeed, 1, 127);

                width = int24(bound(widthSeed, 1, 4094));
                int24 oneSidedRange = (width * tickSpacing) / 2;

                (int24 strikeOffset, int24 minTick, int24 maxTick) = PositionUtils.getContextFull(
                    uint256(uint24(tickSpacing)),
                    currentTick,
                    width
                );

                int24 lowerBound = int24(minTick + oneSidedRange - strikeOffset);
                int24 upperBound = int24(maxTick - oneSidedRange - strikeOffset);

                // Set current tick and pool price
                currentTick = int24(bound(currentTick, minTick, maxTick));
                sqrtPriceAt = TickMath.getSqrtRatioAtTick(currentTick);

                // bound strike
                strike = int24(
                    bound(strikeSeed, lowerBound / tickSpacing, upperBound / tickSpacing)
                );
                strike = int24(strike * tickSpacing + strikeOffset);
            }

            {
                // add a leg
                // no risk partner by default (will reference its own leg index)
                tokenId = tokenId.addLeg(
                    legIndex,
                    optionRatioSeed,
                    assetSeed,
                    isLongSeed,
                    tokenTypeSeed,
                    legIndex,
                    strike,
                    width
                );
            }
        }

        return tokenId;
    }

    function addBalance(TokenId tokenId, uint128 balance) public {
        harness.addBalance(tokenId, balance);
    }
}
