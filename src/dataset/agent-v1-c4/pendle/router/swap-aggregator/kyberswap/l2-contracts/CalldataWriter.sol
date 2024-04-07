// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMetaAggregationRouterV2} from "../interfaces/IMetaAggregationRouterV2.sol";
import {IAggregationExecutorOptimistic as IExecutorHelperL2} from "../interfaces/IAggregationExecutorOptimistic.sol";
import {IExecutorHelper as IExecutorHelperL1} from "../interfaces/IExecutorHelper.sol";

library CalldataWriter {
    function writeSimpleSwapData(
        IMetaAggregationRouterV2.SimpleSwapData memory simpleSwapData
    ) internal pure returns (bytes memory shortData) {
        shortData = bytes.concat(shortData, _writeAddressArray(simpleSwapData.firstPools));
        shortData = bytes.concat(shortData, _writeUint256ArrayAsUint128Array(simpleSwapData.firstSwapAmounts));
        shortData = bytes.concat(shortData, _writeBytesArray(simpleSwapData.swapDatas));
        shortData = bytes.concat(shortData, bytes16(uint128(simpleSwapData.deadline)));
        shortData = bytes.concat(shortData, _writeBytes(simpleSwapData.positiveSlippageData));
    }

    /*
     ************************ AggregationExecutor ************************
     */
    function writeSwapExecutorDescription(
        IExecutorHelperL2.SwapExecutorDescription memory desc
    ) internal pure returns (bytes memory shortData) {
        // write Swap array
        uint8 lX = uint8(desc.swapSequences.length);
        shortData = bytes.concat(shortData, bytes1(lX));
        for (uint8 i = 0; i < lX; ++i) {
            uint8 lY = uint8(desc.swapSequences[i].length);
            shortData = bytes.concat(shortData, bytes1(lY));
            for (uint8 j = 0; j < lY; ++j) {
                shortData = bytes.concat(shortData, _writeSwap(desc.swapSequences[i][j]));
            }
        }

        // basic members
        shortData = bytes.concat(shortData, bytes20(desc.tokenIn));
        shortData = bytes.concat(shortData, bytes20(desc.tokenOut));
        shortData = bytes.concat(shortData, bytes20(desc.to));
        shortData = bytes.concat(shortData, bytes16(uint128(desc.deadline)));
        shortData = bytes.concat(shortData, _writeBytes(desc.positiveSlippageData));
    }

    function writeSimpleModeSwapDatas(
        bytes[] memory swapDatas,
        address tokenIn
    ) internal pure returns (bytes[] memory shortData) {
        uint8 len = uint8(swapDatas.length);
        for (uint8 i = 0; i < len; ++i) {
            swapDatas[i] = _writeSwapSingleSequence(swapDatas[i], tokenIn);
        }
        return (swapDatas);
    }

    function _writeSwapSingleSequence(
        bytes memory data,
        address tokenIn
    ) internal pure returns (bytes memory shortData) {
        IExecutorHelperL2.Swap[] memory swaps = abi.decode(data, (IExecutorHelperL2.Swap[]));

        uint8 len = uint8(swaps.length);
        shortData = bytes.concat(shortData, bytes1(len));
        for (uint8 i = 0; i < len; ++i) {
            shortData = bytes.concat(shortData, _writeSwap(swaps[i]));
        }
        shortData = bytes.concat(shortData, bytes20(tokenIn));
    }

    function _writeAddressArray(address[] memory addrs) internal pure returns (bytes memory data) {
        uint8 length = uint8(addrs.length);
        data = bytes.concat(data, bytes1(length));
        for (uint8 i = 0; i < length; ++i) {
            data = bytes.concat(data, bytes20(addrs[i]));
        }
        return data;
    }

    function _writeUint256ArrayAsUint128Array(uint256[] memory us) internal pure returns (bytes memory data) {
        uint8 length = uint8(us.length);
        data = bytes.concat(data, bytes1(length));
        for (uint8 i = 0; i < length; ++i) {
            data = bytes.concat(data, bytes16(uint128(us[i])));
        }
        return data;
    }

    function _writeBytes(bytes memory b) internal pure returns (bytes memory data) {
        uint32 length = uint32(b.length);
        data = bytes.concat(data, bytes4(length));
        data = bytes.concat(data, b);
        return data;
    }

    function _writeBytesArray(bytes[] memory bytesArray) internal pure returns (bytes memory data) {
        uint8 x = uint8(bytesArray.length);
        data = bytes.concat(data, bytes1(x));
        for (uint8 i; i < x; ++i) {
            uint32 length = uint32(bytesArray[i].length);
            data = bytes.concat(data, bytes4(length));
            data = bytes.concat(data, bytesArray[i]);
        }
        return data;
    }

    function _writeBytes32Array(bytes32[] memory bytesArray) internal pure returns (bytes memory data) {
        uint8 x = uint8(bytesArray.length);
        data = bytes.concat(data, bytes1(x));
        for (uint8 i; i < x; ++i) {
            data = bytes.concat(data, bytesArray[i]);
        }
        return data;
    }

    function _writeSwap(IExecutorHelperL2.Swap memory swap) internal pure returns (bytes memory shortData) {
        shortData = bytes.concat(shortData, _writeBytes(swap.data));
        shortData = bytes.concat(shortData, bytes1(uint8(uint32(swap.functionSelector))));
    }
}
