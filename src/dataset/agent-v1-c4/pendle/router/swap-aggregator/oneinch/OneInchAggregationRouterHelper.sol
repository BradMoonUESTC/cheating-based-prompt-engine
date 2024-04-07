// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./I1inchAggregationRouterV5.sol";
import "../../../core/libraries/Errors.sol";

abstract contract OneInchAggregationRouterHelper {
    function _rescaleMinAmount(
        uint256 minAmount,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (uint256) {
        return (minAmount * newAmount) / oldAmount;
    }

    function _get1inchScaledInputData(
        bytes calldata rawCallData,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        bytes4 selector = bytes4(rawCallData[:4]);
        bytes memory args = rawCallData[4:];

        if (selector == I1inchAggregationRouterV5.uniswapV3SwapTo.selector) {
            (address payable recipient, uint256 amount, uint256 minReturn, uint256[] memory pools) = abi.decode(
                args,
                (address, uint256, uint256, uint256[])
            );

            amount = newAmount;
            return abi.encodeWithSelector(selector, recipient, amount, minReturn, pools);
        }

        if (selector == I1inchAggregationRouterV5.swap.selector) {
            (
                address executor,
                I1inchAggregationRouterV5.SwapDescription memory desc,
                bytes memory permit,
                bytes memory data
            ) = abi.decode(args, (address, I1inchAggregationRouterV5.SwapDescription, bytes, bytes));

            desc.amount = newAmount;
            return abi.encodeWithSelector(selector, executor, desc, permit, data);
        }

        if (selector == I1inchAggregationRouterV5.unoswapTo.selector) {
            (
                address payable recipient,
                address srcToken,
                uint256 amount,
                uint256 minReturn,
                uint256[] memory pools
            ) = abi.decode(args, (address, address, uint256, uint256, uint256[]));

            amount = newAmount;
            return abi.encodeWithSelector(selector, recipient, srcToken, amount, minReturn, pools);
        }

        revert Errors.UnsupportedSelector(2, selector);
    }
}
