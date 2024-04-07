// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.17;

import "./ThenaMath.sol";

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../libraries/BoringOwnableUpgradeable.sol";
import "../../../../interfaces/IPPreviewHelper.sol";
import "../../../../interfaces/Thena/IThenaFactory.sol";

interface IThenaSY {
    function pair() external view returns (address);
}

contract ThenaPreview is IPPreviewHelper, ThenaMath, BoringOwnableUpgradeable, UUPSUpgradeable {
    using PMath for uint256;

    address internal immutable factory;

    constructor(address _factory) initializer {
        factory = _factory;
    }

    function initialize() external initializer {
        __BoringOwnable_init();
    }

    // solhint-disable-next-line
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function previewDeposit(address tokenIn, uint256 amountTokenIn) external view returns (uint256 amountLpOut) {
        address pair = IThenaSY(msg.sender).pair();

        ThenaData memory data = _getNormalizedPairData(pair, tokenIn);

        uint256 amountToSwap = _getZapInSwapAmount(data, tokenIn, amountTokenIn);
        uint256 amountSwapOut = _getSwapAmountOut(data, amountToSwap);

        uint256 amount0ToAddLiq;
        uint256 amount1ToAddLiq;

        data.reserve0 = _getReserveAfterSwap(amountToSwap, data.reserve0, data.fee); // no need getBalance here since we dont need 100% accuracy
        data.reserve1 -= amountSwapOut;

        amount0ToAddLiq = amountTokenIn - amountToSwap;
        amount1ToAddLiq = amountSwapOut;

        return _calcAmountLpOut(data, amount0ToAddLiq, amount1ToAddLiq);
    }

    function previewRedeem(address tokenOut, uint256 amountLpIn) external view returns (uint256) {
        address pair = IThenaSY(msg.sender).pair();

        // Token1 = tokenOut
        address token0 = IThenaPair(pair).token0();
        address token1 = IThenaPair(pair).token1();

        ThenaData memory data = _getNormalizedPairData(pair, tokenOut == token0 ? token1 : token0);

        uint256 totalSupply = IThenaPair(data.pair).totalSupply();

        uint256 amount0Removed = (data.reserve0 * amountLpIn) / totalSupply;
        uint256 amount1Removed = (data.reserve1 * amountLpIn) / totalSupply;

        data.reserve0 -= amount0Removed;
        data.reserve1 -= amount1Removed;

        return amount1Removed + _getSwapAmountOut(data, amount0Removed);
    }

    // @reference: Camelot
    function _getSwapAmountOut(ThenaData memory data, uint256 amountIn) internal pure returns (uint256) {
        if (!data.isStable) {
            amountIn = amountIn * (FEE_DENOMINATOR - data.fee);
            return (amountIn * data.reserve1) / (data.reserve0 * FEE_DENOMINATOR + amountIn);
        } else {
            amountIn = (amountIn - (amountIn * data.fee) / FEE_DENOMINATOR).divDown(data.decimals0);
            uint256 reserveA = data.reserve0.divDown(data.decimals0);
            uint256 reserveB = data.reserve1.divDown(data.decimals1);
            uint256 xy = reserveA.mulDown(reserveB).mulDown(reserveA.squareDown() + reserveB.squareDown());
            uint256 y = reserveB - _get_y(amountIn + reserveA, xy, reserveB);
            return y.mulDown(data.decimals1);
        }
    }

    /**
     * @notice This function simulates Camelot router so any precision issues from their calculation
     * is preserved in preview functions...
     */
    function _calcAmountLpOut(
        ThenaData memory data,
        uint256 amount0ToAddLiq,
        uint256 amount1ToAddLiq
    ) private view returns (uint256 amountLpOut) {
        uint256 amount1Optimal = _quote(amount0ToAddLiq, data.reserve0, data.reserve1);
        if (amount1Optimal <= amount1ToAddLiq) {
            amount1ToAddLiq = amount1Optimal;
        } else {
            amount0ToAddLiq = _quote(amount1ToAddLiq, data.reserve1, data.reserve0);
        }

        uint256 supply = IThenaPair(data.pair).totalSupply();
        return PMath.min((amount0ToAddLiq * supply) / data.reserve0, (amount1ToAddLiq * supply) / data.reserve1);
    }

    function _quote(uint256 amountA, uint256 reserveA, uint256 reserveB) private pure returns (uint256 amountB) {
        amountB = (amountA * reserveB) / reserveA;
    }

    function _getNormalizedPairData(address pair, address pivotToken) internal view returns (ThenaData memory data) {
        data.pair = pair;
        data.isStable = IThenaPair(pair).isStable();
        data.fee = IThenaFactory(factory).getFee(data.isStable);
        (data.reserve0, data.reserve1, ) = IThenaPair(pair).getReserves();

        if (data.isStable) {
            // if not stable, skip readding these datas
            data.decimals0 = 10 ** IERC20Metadata(IThenaPair(pair).token0()).decimals();
            data.decimals1 = 10 ** IERC20Metadata(IThenaPair(pair).token1()).decimals();
        }

        // Normalize token order
        if (pivotToken == IThenaPair(pair).token1()) {
            (data.reserve0, data.reserve1) = (data.reserve1, data.reserve0);
            (data.decimals0, data.decimals1) = (data.decimals1, data.decimals0);
        }
    }

    // Camelot copied math functions
    function _get_y(uint256 x0, uint256 xy, uint256 y) internal pure returns (uint256) {
        for (uint256 i = 0; i < 255; i++) {
            uint256 y_prev = y;
            uint256 k = _f(x0, y);
            if (k < xy) {
                uint256 dy = ((xy - k) * 1e18) / _d(x0, y);
                y = y + dy;
            } else {
                uint256 dy = ((k - xy) * 1e18) / _d(x0, y);
                y = y - dy;
            }
            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    return y;
                }
            } else {
                if (y_prev - y <= 1) {
                    return y;
                }
            }
        }
        return y;
    }

    function _f(uint256 x0, uint256 y) internal pure returns (uint256) {
        return (x0 * ((((y * y) / 1e18) * y) / 1e18)) / 1e18 + (((((x0 * x0) / 1e18) * x0) / 1e18) * y) / 1e18;
    }

    function _d(uint256 x0, uint256 y) internal pure returns (uint256) {
        return (3 * x0 * ((y * y) / 1e18)) / 1e18 + ((((x0 * x0) / 1e18) * x0) / 1e18);
    }
}
