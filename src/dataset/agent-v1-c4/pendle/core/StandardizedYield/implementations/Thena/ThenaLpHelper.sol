// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../../../../interfaces/Thena/IThenaPair.sol";
import "../../../../interfaces/Thena/IThenaRouter.sol";
import "../../../../interfaces/Thena/IThenaFactory.sol";
import "../../../libraries/TokenHelper.sol";
import "../../../libraries/math/PMath.sol";
import "./ThenaMath.sol";

abstract contract ThenaLpHelper is TokenHelper, ThenaMath {
    address public immutable factory;
    address public immutable pair;

    bool public immutable isStable;
    address public immutable token0;
    address public immutable token1;
    uint256 public immutable decimals0;
    uint256 public immutable decimals1;
    address public immutable router;

    constructor(address _pair, address _factory, address _router) {
        factory = _factory;
        pair = _pair;
        router = _router;

        isStable = IThenaPair(pair).isStable();
        token0 = IThenaPair(pair).token0();
        token1 = IThenaPair(pair).token1();
        decimals0 = 10 ** IERC20Metadata(token0).decimals();
        decimals1 = 10 ** IERC20Metadata(token1).decimals();

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
        ThenaData memory data = _getNormalizedThenaData(tokenIn);
        if (tokenIn == token0) {
            uint256 amount0ToSwap = _getZapInSwapAmount(data, tokenIn, amountIn);
            amount0ToAddLiq = amountIn - amount0ToSwap;
            amount1ToAddLiq = _swap(token0, amount0ToSwap);
        } else {
            uint256 amount1ToSwap = _getZapInSwapAmount(data, tokenIn, amountIn);
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
        (, , amountLpOut) = IThenaRouter(router).addLiquidity(
            token0,
            token1,
            isStable,
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
            IThenaRouter(router).removeLiquidity(
                token0,
                token1,
                isStable,
                amountLpToRemove,
                0,
                0,
                address(this),
                block.timestamp
            );
    }

    function _swap(address tokenIn, uint256 amountTokenIn) private returns (uint256) {
        address tokenOut = tokenIn == token0 ? token1 : token0;
        uint256 preBalance = _selfBalance(tokenOut);

        IThenaRouter(router).swapExactTokensForTokensSimple(
            amountTokenIn,
            0,
            tokenIn,
            tokenOut,
            isStable,
            address(this),
            block.timestamp
        );

        return _selfBalance(tokenOut) - preBalance;
    }

    /**
     * ==================================================================
     *                      CAMELOT PAIR DATA READ
     * ==================================================================
     */

    function _getNormalizedThenaData(address tokenIn) internal view returns (ThenaData memory data) {
        data.pair = pair;
        data.isStable = isStable;
        data.fee = IThenaFactory(factory).getFee(data.isStable);
        (data.reserve0, data.reserve1, ) = IThenaPair(pair).getReserves();

        if (data.isStable) {
            // if not stable, skip reading these data
            data.decimals0 = decimals0;
            data.decimals1 = decimals1;
        }

        // Normalize token order
        if (tokenIn == token1) {
            (data.reserve0, data.reserve1) = (data.reserve1, data.reserve0);
            (data.decimals0, data.decimals1) = (data.decimals1, data.decimals0);
        }
    }
}
