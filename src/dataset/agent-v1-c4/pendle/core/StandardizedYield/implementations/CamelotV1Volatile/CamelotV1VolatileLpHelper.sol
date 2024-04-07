// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../../../../interfaces/Camelot/ICamelotPair.sol";
import "../../../../interfaces/Camelot/ICamelotRouter.sol";
import "../../../../interfaces/Camelot/ICamelotFactory.sol";
import "../../../libraries/TokenHelper.sol";
import "../../../libraries/math/PMath.sol";
import "./CamelotV1VolatileCommon.sol";

/**
 * @notice This contract is intended to be launched on Arbitrum
 *         Thus, some obvious gas optimization might be ignored
 *
 * @notice Since Camelot LP may offer the pool token as a reward token (for example PENDLE/ETH
 * has PENDLE rewards),
 * this contract should not take into account any floating balance
 * for swap/add liquidity
 */
abstract contract CamelotV1VolatileLpHelper is TokenHelper, CamelotV1VolatileCommon {
    address public immutable token0;
    address public immutable token1;
    address public immutable pair;
    address public immutable router;

    constructor(address _pair, address _router) {
        assert(ICamelotPair(_pair).stableSwap() == false);
        pair = _pair;
        router = _router;
        token0 = ICamelotPair(pair).token0();
        token1 = ICamelotPair(pair).token1();
        _safeApproveInf(token0, router);
        _safeApproveInf(token1, router);
        _safeApproveInf(pair, router);
    }

    /**
     * ==================================================================
     *                      ZAP ACTION RELATED
     * ==================================================================
     */
    function _zapIn(address tokenIn, uint256 amountIn) internal returns (uint256) {
        (uint256 amount0ToAddLiq, uint256 amount1ToAddLiq) = _swapZapIn(tokenIn, amountIn);
        return _addLiquidity(amount0ToAddLiq, amount1ToAddLiq);
    }

    function _zapOut(address tokenOut, uint256 amountLpIn) internal returns (uint256) {
        (uint256 amount0, uint256 amount1) = _removeLiquidity(amountLpIn);
        if (tokenOut == token0) {
            return amount0 + _swap(token1, amount1);
        } else {
            return amount1 + _swap(token0, amount0);
        }
    }

    function _swapZapIn(
        address tokenIn,
        uint256 amountIn
    ) private returns (uint256 amount0ToAddLiq, uint256 amount1ToAddLiq) {
        (uint256 reserve0, uint256 reserve1, uint256 fee0, uint256 fee1) = ICamelotPair(pair).getReserves();

        if (tokenIn == token0) {
            uint256 amount0ToSwap = _getZapInSwapAmount(amountIn, reserve0, fee0);
            amount0ToAddLiq = amountIn - amount0ToSwap;
            amount1ToAddLiq = _swap(token0, amount0ToSwap);
        } else {
            uint256 amount1ToSwap = _getZapInSwapAmount(amountIn, reserve1, fee1);
            amount0ToAddLiq = _swap(token1, amount1ToSwap);
            amount1ToAddLiq = amountIn - amount1ToSwap;
        }
    }

    /**
     * ==================================================================
     *                      CAMELOT ROUTER RELATED
     * ==================================================================
     */

    function _addLiquidity(uint256 amount0ToAddLiq, uint256 amount1ToAddLiq) private returns (uint256 amountLpOut) {
        (, , amountLpOut) = ICamelotRouter(router).addLiquidity(
            token0,
            token1,
            amount0ToAddLiq,
            amount1ToAddLiq,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function _removeLiquidity(uint256 amountLpToRemove) private returns (uint256 amountTokenA, uint256 amountTokenB) {
        return
            ICamelotRouter(router).removeLiquidity(
                token0,
                token1,
                amountLpToRemove,
                0,
                0,
                address(this),
                block.timestamp
            );
    }

    function _swap(address tokenIn, uint256 amountTokenIn) private returns (uint256) {
        address[] memory path = new address[](2);

        address tokenOut = tokenIn == token0 ? token1 : token0;

        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256 preBalance = _selfBalance(tokenOut);

        ICamelotRouter(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountTokenIn,
            0,
            path,
            address(this),
            address(0),
            block.timestamp
        );

        return _selfBalance(tokenOut) - preBalance;
    }
}
