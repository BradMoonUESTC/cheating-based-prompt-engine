// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../../../libraries/math/PMath.sol";
import "../../../../interfaces/Thena/IThenaPair.sol";

abstract contract ThenaMath {
    using PMath for uint256;

    struct ThenaData {
        address pair;
        bool isStable;
        uint256 reserve0;
        uint256 reserve1;
        uint256 fee;
        uint256 decimals0;
        uint256 decimals1;
    }

    struct StableBinarySearchParams {
        uint256 guessMin;
        uint256 guessMax;
        uint256 amountSwapIn;
        uint256 newReserve0;
        uint256 newReserve1;
        uint256 amount0ToAddLiq;
        uint256 amount1ToAddLiq;
    }

    uint256 internal constant FEE_DENOMINATOR = 10000;
    uint256 internal constant ONE = 1 * FEE_DENOMINATOR;
    uint256 internal constant TWO = 2 * FEE_DENOMINATOR;
    uint256 internal constant FOUR = 4 * FEE_DENOMINATOR;
    uint256 internal constant DEFAULT_BINARY_SEARCH_EPS = 1e14; // 0.01% accuracy

    uint256 public binarySearchEps = DEFAULT_BINARY_SEARCH_EPS;

    function _getZapInSwapAmount(
        ThenaData memory data,
        address tokenIn,
        uint256 amountIn
    ) internal view returns (uint256) {
        return data.isStable ? _getStableZapAmount(data, tokenIn, amountIn) : _getVolatileZapAmount(data, amountIn);
    }

    function _getVolatileZapAmount(ThenaData memory data, uint256 amountIn) private pure returns (uint256) {
        uint256 numer0 = ((TWO - FEE_DENOMINATOR) * data.reserve0) / FEE_DENOMINATOR;
        uint256 numer1 = PMath.square(numer0);
        uint256 numer2 = 4 * PMath.square(ONE - data.fee) * amountIn * data.reserve0;

        uint256 numer = PMath.sqrt(numer1 + numer2) - numer0;
        uint256 denom = 2 * PMath.square(ONE - data.fee);

        return (numer * FEE_DENOMINATOR) / denom;
    }

    function _getStableZapAmount(
        ThenaData memory data,
        address tokenIn,
        uint256 amountIn
    ) private view returns (uint256) {
        StableBinarySearchParams memory params = _prepareStableBinarySearchParams(amountIn, data);

        while (!PMath.isAApproxB(params.guessMin, params.guessMax, binarySearchEps)) {
            params.amountSwapIn = (params.guessMax + params.guessMin) / 2;
            params.amount1ToAddLiq = IThenaPair(data.pair).getAmountOut(params.amountSwapIn, tokenIn);

            params.newReserve0 = _getReserveAfterSwap(params.amountSwapIn, data.reserve0, data.fee);
            params.newReserve1 = data.reserve1 - params.amount1ToAddLiq;
            params.amount0ToAddLiq = amountIn - params.amountSwapIn;

            if (params.amount0ToAddLiq * params.newReserve1 < params.amount1ToAddLiq * params.newReserve0) {
                params.guessMax = params.amountSwapIn - 1; // need swap less
            } else {
                params.guessMin = params.amountSwapIn + 1; // swap more
            }
        }
        return params.guessMin;
    }

    function _prepareStableBinarySearchParams(
        uint256 amountIn,
        ThenaData memory data
    ) private pure returns (StableBinarySearchParams memory params) {
        uint256 X = data.reserve0.divDown(data.decimals0);
        uint256 Y = data.reserve1.divDown(data.decimals1);
        amountIn = amountIn.divDown(data.decimals0);

        uint256 t = Y.divDown(X + amountIn);
        uint256 K = X.mulDown(Y).mulDown(X.mulDown(X) + Y.mulDown(Y));
        uint256 denom = t.mulDown(t).mulDown(t) + t;

        params.guessMin = (_fourthRoot(K.divDown(denom)) - X).mulDown(data.decimals0);
        params.guessMax = (params.guessMin * FEE_DENOMINATOR) / (FEE_DENOMINATOR - data.fee);
    }

    function _getReserveAfterSwap(uint256 amountIn, uint256 reserve, uint256 fee) internal pure returns (uint256) {
        return reserve + amountIn - (amountIn * fee) / FEE_DENOMINATOR;
    }

    // this returns the fourthRoot of y in base 18
    function _fourthRoot(uint256 y) private pure returns (uint256) {
        uint256 root = PMath.sqrt(y) * (10 ** 9);
        return PMath.sqrt(root) * (10 ** 9);
    }
}
