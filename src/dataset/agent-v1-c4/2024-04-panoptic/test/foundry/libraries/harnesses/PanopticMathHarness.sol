// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal
import {PanopticMath} from "@libraries/PanopticMath.sol";
// Uniswap
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
// Types
import {LiquidityChunk} from "@types/LiquidityChunk.sol";
import {TokenId} from "@types/TokenId.sol";
import {LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";

import "forge-std/Test.sol";

/// @title PanopticMathHarness: A harness to expose the PanopticMath library for code coverage analysis.
/// @notice Replicates the interface of the PanopticMath library, passing through any function calls
/// @author Axicon Labs Limited
contract PanopticMathHarness is Test {
    function getLiquidityChunk(
        TokenId tokenId,
        uint256 legIndex,
        uint128 positionSize
    ) public pure returns (LiquidityChunk) {
        LiquidityChunk liquidityChunk = PanopticMath.getLiquidityChunk(
            tokenId,
            legIndex,
            positionSize
        );
        return liquidityChunk;
    }

    /// @notice Extract the tick range specified by `strike` and `width` for the given `tickSpacing`, if valid.
    /// @param strike the strike price of the option
    /// @param width the width of the option
    /// @param tickSpacing the tick spacing of the underlying Uniswap v3 pool
    /// @return tickLower the lower tick of the liquidity chunk.
    /// @return tickUpper the upper tick of the liquidity chunk.
    function getTicks(
        int24 strike,
        int24 width,
        int24 tickSpacing
    ) public pure returns (int24, int24) {
        (int24 tickLower, int24 tickUpper) = PanopticMath.getTicks(strike, width, tickSpacing);
        return (tickLower, tickUpper);
    }

    function getPoolId(address univ3pool) public view returns (uint64) {
        uint64 poolId = PanopticMath.getPoolId(univ3pool);
        return poolId;
    }

    function incrementPoolPattern(uint64 poolId) public pure returns (uint64) {
        uint64 _poolId = PanopticMath.incrementPoolPattern(poolId);
        return _poolId;
    }

    function computeExercisedAmounts(
        TokenId tokenId,
        uint128 positionSize
    ) public pure returns (LeftRightSigned, LeftRightSigned) {
        (LeftRightSigned longAmounts, LeftRightSigned shortAmounts) = PanopticMath
            .computeExercisedAmounts(tokenId, positionSize);
        return (longAmounts, shortAmounts);
    }

    function numberOfLeadingHexZeros(address addr) public pure returns (uint256) {
        uint256 leadingZeroes = PanopticMath.numberOfLeadingHexZeros(addr);
        return leadingZeroes;
    }

    function updatePositionsHash(
        uint256 existingHash,
        TokenId tokenId,
        bool addFlag
    ) public pure returns (uint256) {
        uint256 newHash = PanopticMath.updatePositionsHash(existingHash, tokenId, addFlag);
        return newHash;
    }

    function twapFilter(IUniswapV3Pool univ3pool, uint32 twapWindow) public view returns (int24) {
        int24 twapTick = PanopticMath.twapFilter(univ3pool, twapWindow);
        return twapTick;
    }

    function computeMedianObservedPrice(
        IUniswapV3Pool univ3pool,
        uint256 observationIndex,
        uint256 observationCardinality,
        uint256 cardinality,
        uint256 period
    ) public view returns (int24) {
        int24 lastMedianObservation = PanopticMath.computeMedianObservedPrice(
            univ3pool,
            observationIndex,
            observationCardinality,
            cardinality,
            period
        );
        return lastMedianObservation;
    }

    function convertCollateralData(
        LeftRightUnsigned tokenData0,
        LeftRightUnsigned tokenData1,
        uint256 tokenType,
        int24 tick
    ) public pure returns (uint256, uint256) {
        (uint256 collateralBalance, uint256 requiredCollateral) = PanopticMath
            .convertCollateralData(tokenData0, tokenData1, tokenType, tick);
        return (collateralBalance, requiredCollateral);
    }

    function convertCollateralData(
        LeftRightUnsigned tokenData0,
        LeftRightUnsigned tokenData1,
        uint256 tokenType,
        uint160 sqrtPriceX96
    ) public pure returns (uint256, uint256) {
        (uint256 collateralBalance, uint256 requiredCollateral) = PanopticMath
            .convertCollateralData(tokenData0, tokenData1, tokenType, sqrtPriceX96);
        return (collateralBalance, requiredCollateral);
    }

    function _convertNotional(
        uint128 contractSize,
        int24 tickLower,
        int24 tickUpper,
        uint256 asset
    ) public pure returns (uint128) {
        uint128 notional = PanopticMath.convertNotional(contractSize, tickLower, tickUpper, asset);
        return notional;
    }

    function convertNotional(
        uint128 contractSize,
        int24 tickLower,
        int24 tickUpper,
        uint256 asset
    ) public view returns (uint128) {
        try this._convertNotional(contractSize, tickLower, tickUpper, asset) returns (
            uint128 notional
        ) {
            return notional;
        } catch {
            vm.assume(2 + 2 == 5);
            return 0;
        }
    }

    function _getAmountsMoved(
        TokenId tokenId,
        uint128 positionSize,
        uint256 legIndex
    ) public pure returns (LeftRightUnsigned) {
        LeftRightUnsigned amountsMoved = PanopticMath.getAmountsMoved(
            tokenId,
            positionSize,
            legIndex
        );
        return amountsMoved;
    }

    // skip if notional value is invalid (tested elsewhere)
    function getAmountsMoved(
        TokenId tokenId,
        uint128 positionSize,
        uint256 legIndex
    ) public view returns (LeftRightUnsigned) {
        try this._getAmountsMoved(tokenId, positionSize, legIndex) returns (
            LeftRightUnsigned contractsNotional
        ) {
            return contractsNotional;
        } catch {
            vm.assume(2 + 2 == 5);
            return LeftRightUnsigned.wrap(0);
        }
    }

    function _calculateIOAmounts(
        TokenId tokenId,
        uint128 positionSize,
        uint256 legIndex
    ) public pure returns (LeftRightSigned, LeftRightSigned) {
        (LeftRightSigned longs, LeftRightSigned shorts) = PanopticMath._calculateIOAmounts(
            tokenId,
            positionSize,
            legIndex
        );
        return (longs, shorts);
    }

    function calculateIOAmounts(
        TokenId tokenId,
        uint128 positionSize,
        uint256 legIndex
    ) public view returns (LeftRightSigned, LeftRightSigned) {
        try this._calculateIOAmounts(tokenId, positionSize, legIndex) returns (
            LeftRightSigned longs,
            LeftRightSigned shorts
        ) {
            return (longs, shorts);
        } catch {
            vm.assume(2 + 2 == 5);
            return (LeftRightSigned.wrap(0), LeftRightSigned.wrap(0));
        }
    }

    function convert0to1(uint256 amount, uint160 sqrtPriceX96) public pure returns (uint256) {
        uint256 result = PanopticMath.convert0to1(amount, sqrtPriceX96);
        return result;
    }

    function convert0to1(int256 amount, uint160 sqrtPriceX96) public pure returns (int256) {
        int256 result = PanopticMath.convert0to1(amount, sqrtPriceX96);
        return result;
    }

    function convert1to0(uint256 amount, uint160 sqrtPriceX96) public pure returns (uint256) {
        uint256 result = PanopticMath.convert1to0(amount, sqrtPriceX96);
        return result;
    }

    function convert1to0(int256 amount, uint160 sqrtPriceX96) public pure returns (int256) {
        int256 result = PanopticMath.convert1to0(amount, sqrtPriceX96);
        return result;
    }

    function getRangesFromStrike(
        int24 width,
        int24 tickSpacing
    ) public pure returns (int24 rangeDown, int24 rangeUp) {
        (int24 result0, int24 result1) = PanopticMath.getRangesFromStrike(width, tickSpacing);
        return (result0, result1);
    }
}
