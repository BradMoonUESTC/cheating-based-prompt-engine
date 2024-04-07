// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../core/libraries/TokenHelper.sol";
import "./IPSwapAggregator.sol";
import "./kyberswap/l1-contracts/InputScalingHelper.sol";
import "./kyberswap/l2-contracts/InputScalingHelperL2.sol";
import "./oneinch/OneInchAggregationRouterHelper.sol";

abstract contract PendleSwapBase is IPSwapAggregator, TokenHelper, OneInchAggregationRouterHelper {
    using Address for address;

    function swap(address tokenIn, uint256 amountIn, SwapData calldata data) external payable {
        _safeApproveInf(tokenIn, data.extRouter);
        data.extRouter.functionCallWithValue(
            data.needScale ? _getScaledInputData(data.swapType, data.extCalldata, amountIn) : data.extCalldata,
            tokenIn == NATIVE ? amountIn : 0
        );
    }

    function _getScaledInputData(
        SwapType swapType,
        bytes calldata rawCallData,
        uint256 amountIn
    ) internal pure returns (bytes memory scaledCallData) {
        if (swapType == SwapType.KYBERSWAP) {
            scaledCallData = _getKyberScaledInputData(rawCallData, amountIn);
        } else if (swapType == SwapType.ONE_INCH) {
            scaledCallData = _get1inchScaledInputData(rawCallData, amountIn);
        } else {
            assert(false);
        }
    }

    function _getKyberScaledInputData(
        bytes calldata rawCallData,
        uint256 amountIn
    ) internal pure virtual returns (bytes memory scaledCallData);

    receive() external payable {}
}

contract PendleSwapL1 is PendleSwapBase {
    function _getKyberScaledInputData(
        bytes calldata rawCallData,
        uint256 amountIn
    ) internal pure override returns (bytes memory) {
        return InputScalingHelper._getScaledInputData(rawCallData, amountIn);
    }
}

contract PendleSwapL2 is PendleSwapBase {
    function _getKyberScaledInputData(
        bytes calldata rawCallData,
        uint256 amountIn
    ) internal pure override returns (bytes memory) {
        return InputScalingHelperL2._getScaledInputData(rawCallData, amountIn);
    }
}
