// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.17;

import "./CamelotV1VolatileCommon.sol";

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../../../libraries/BoringOwnableUpgradeable.sol";

contract CamelotV1VolatilePreview is CamelotV1VolatileCommon, BoringOwnableUpgradeable, UUPSUpgradeable {
    address internal immutable factory;

    constructor(address _factory) initializer {
        factory = _factory;
    }

    function initialize() external initializer {
        __BoringOwnable_init();
    }

    // solhint-disable-next-line
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice The Camelot.swap() function takes reserve() as the previously recorded at the start
     * and take into account ALL floating balances after.
     */
    function previewZapIn(
        CamelotPairData memory data,
        address tokenIn,
        uint256 amountTokenIn
    ) external view returns (uint256 amountLpOut) {
        bool isToken0 = tokenIn == data.token0;

        uint256 amountToSwap = isToken0
            ? _getZapInSwapAmount(amountTokenIn, data.reserve0, data.fee0)
            : _getZapInSwapAmount(amountTokenIn, data.reserve1, data.fee1);

        uint256 amountSwapOut = _getSwapAmountOut(
            data,
            amountToSwap,
            tokenIn,
            tokenIn == data.token0 ? data.fee0 : data.fee1
        );

        uint256 amount0ToAddLiq;
        uint256 amount1ToAddLiq;

        if (isToken0) {
            data.reserve0 = _getPairBalance0(data) + amountToSwap;
            data.reserve1 = _getPairBalance1(data) - amountSwapOut;

            amount0ToAddLiq = amountTokenIn - amountToSwap;
            amount1ToAddLiq = amountSwapOut;
        } else {
            data.reserve0 = _getPairBalance0(data) - amountSwapOut;
            data.reserve1 = _getPairBalance1(data) + amountToSwap;

            amount0ToAddLiq = amountSwapOut;
            amount1ToAddLiq = amountTokenIn - amountToSwap;
        }

        return _calcAmountLpOut(data, amount0ToAddLiq, amount1ToAddLiq);
    }

    function previewZapOut(
        CamelotPairData memory data,
        address tokenOut,
        uint256 amountLpIn
    ) external view returns (uint256) {
        uint256 totalSupply = _getTotalSupplyAfterMintFee(data);

        data.reserve0 = _getPairBalance0(data);
        data.reserve1 = _getPairBalance1(data);

        uint256 amount0Removed = (data.reserve0 * amountLpIn) / totalSupply;
        uint256 amount1Removed = (data.reserve1 * amountLpIn) / totalSupply;

        data.reserve0 -= amount0Removed;
        data.reserve1 -= amount1Removed;

        if (tokenOut == data.token0) {
            return amount0Removed + _getSwapAmountOut(data, amount1Removed, data.token1, data.fee1);
        } else {
            return amount1Removed + _getSwapAmountOut(data, amount0Removed, data.token0, data.fee0);
        }
    }

    function _getPairBalance0(CamelotPairData memory data) private view returns (uint256) {
        return IERC20(data.token0).balanceOf(data.pair);
    }

    function _getPairBalance1(CamelotPairData memory data) private view returns (uint256) {
        return IERC20(data.token1).balanceOf(data.pair);
    }

    // @reference: Camelot
    function _getSwapAmountOut(
        CamelotPairData memory data,
        uint256 amountIn,
        address tokenIn,
        uint256 feePercent
    ) internal pure returns (uint256) {
        (uint256 reserve0, uint256 reserve1) = tokenIn == data.token0
            ? (data.reserve0, data.reserve1)
            : (data.reserve1, data.reserve0);
        amountIn = amountIn * (FEE_DENOMINATOR - feePercent);
        return (amountIn * reserve1) / (reserve0 * FEE_DENOMINATOR + amountIn);
    }

    /**
     * @notice This function simulates Camelot router so any precision issues from their calculation
     * is preserved in preview functions...
     */
    function _calcAmountLpOut(
        CamelotPairData memory data,
        uint256 amount0ToAddLiq,
        uint256 amount1ToAddLiq
    ) private view returns (uint256 amountLpOut) {
        uint256 amount1Optimal = _quote(amount0ToAddLiq, data.reserve0, data.reserve1);
        if (amount1Optimal <= amount1ToAddLiq) {
            amount1ToAddLiq = amount1Optimal;
        } else {
            amount0ToAddLiq = _quote(amount1ToAddLiq, data.reserve1, data.reserve0);
        }

        uint256 supply = _getTotalSupplyAfterMintFee(data);
        return PMath.min((amount0ToAddLiq * supply) / data.reserve0, (amount1ToAddLiq * supply) / data.reserve1);
    }

    function _quote(uint256 amountA, uint256 reserveA, uint256 reserveB) private pure returns (uint256 amountB) {
        amountB = (amountA * reserveB) / reserveA;
    }

    function _getTotalSupplyAfterMintFee(CamelotPairData memory data) private view returns (uint256) {
        (uint256 ownerFeeShare, address feeTo) = ICamelotFactory(factory).feeInfo();
        bool feeOn = feeTo != address(0);
        uint256 _kLast = ICamelotPair(data.pair).kLast();

        uint256 totalSupply = ICamelotPair(data.pair).totalSupply();
        // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = PMath.sqrt(data.reserve0 * data.reserve1);
                uint256 rootKLast = PMath.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 d = (FEE_DENOMINATOR * 100) / ownerFeeShare - 100;
                    uint256 numerator = totalSupply * (rootK - rootKLast) * 100;
                    uint256 denominator = rootK * d + rootKLast * 100;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) {
                        totalSupply += liquidity;
                    }
                }
            }
        }
        return totalSupply;
    }
}
