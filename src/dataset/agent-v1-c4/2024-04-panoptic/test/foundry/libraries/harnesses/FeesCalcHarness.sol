// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "univ3-core/interfaces/IUniswapV3Pool.sol";
import {FeesCalc} from "@libraries/FeesCalc.sol";

import {LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";
import {TokenId} from "@types/TokenId.sol";

/// @title FeesCalcHarness: A harness to expose the Feescalc library for code coverage analysis.
/// @notice Replicates the interface of the Feescalc library, passing through any function calls
/// @author Axicon Labs Limited
contract FeesCalcHarness {
    // used to pass into libraries
    mapping(TokenId tokenId => LeftRightUnsigned balance) public userBalance;

    function getPortfolioValue(
        int24 atTick,
        TokenId[] calldata positionIdList
    ) public view returns (int256, int256) {
        (int256 value0, int256 value1) = FeesCalc.getPortfolioValue(
            atTick,
            userBalance,
            positionIdList
        );
        return (value0, value1);
    }

    function calculateAMMSwapFees(
        IUniswapV3Pool univ3pool,
        int24 currentTick,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public view returns (LeftRightSigned) {
        LeftRightSigned feesEachToken = FeesCalc.calculateAMMSwapFees(
            univ3pool,
            currentTick,
            tickLower,
            tickUpper,
            liquidity
        );
        return (feesEachToken);
    }

    function getAMMSwapFeesPerLiquidityCollected(
        IUniswapV3Pool univ3pool,
        int24 currentTick,
        int24 tickLower,
        int24 tickUpper
    ) public view returns (uint256, uint256) {
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = FeesCalc
            ._getAMMSwapFeesPerLiquidityCollected(univ3pool, currentTick, tickLower, tickUpper);

        return (feeGrowthInside0X128, feeGrowthInside1X128);
    }

    function addBalance(TokenId tokenId, uint128 balance) public {
        userBalance[tokenId] = LeftRightUnsigned.wrap(0).toRightSlot(balance);
    }
}
