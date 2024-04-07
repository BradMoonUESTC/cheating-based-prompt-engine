// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CalldataReader.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IAggregationExecutorOptimistic.sol";

library ExecutorReader {
    function readSwapExecutorDescription(bytes memory data) internal pure returns (bytes memory) {
        uint256 startByte = 0;
        IAggregationExecutorOptimistic.SwapExecutorDescription memory desc;

        // Swap array
        bytes memory ret;
        (ret, startByte) = CalldataReader._calldataVal(data, startByte, 1);
        uint256 lX = uint256(uint8(bytes1(ret)));
        desc.swapSequences = new IAggregationExecutorOptimistic.Swap[][](lX);
        for (uint8 i = 0; i < lX; ++i) {
            (ret, startByte) = CalldataReader._calldataVal(data, startByte, 1);
            uint256 lY = uint256(uint8(bytes1(ret)));
            desc.swapSequences[i] = new IAggregationExecutorOptimistic.Swap[](lY);
            for (uint8 j = 0; j < lY; ++j) {
                (desc.swapSequences[i][j], startByte) = _readSwap(data, startByte);
            }
        }

        // basic members
        (desc.tokenIn, startByte) = CalldataReader._readAddress(data, startByte);
        (desc.tokenOut, startByte) = CalldataReader._readAddress(data, startByte);
        (desc.to, startByte) = CalldataReader._readAddress(data, startByte);
        (desc.deadline, startByte) = CalldataReader._readUint128AsUint256(data, startByte);
        (desc.positiveSlippageData, startByte) = CalldataReader._readBytes(data, startByte);

        return abi.encode(desc);
    }

    function readSwapSingleSequence(
        bytes memory data
    ) internal pure returns (IAggregationExecutorOptimistic.Swap[] memory swaps, address tokenIn) {
        uint256 startByte = 0;
        bytes memory ret;
        (ret, startByte) = CalldataReader._calldataVal(data, startByte, 1);
        uint256 len = uint256(uint8(bytes1(ret)));
        swaps = new IAggregationExecutorOptimistic.Swap[](len);
        for (uint8 i = 0; i < len; ++i) {
            (swaps[i], startByte) = _readSwap(data, startByte);
        }
        (tokenIn, startByte) = CalldataReader._readAddress(data, startByte);
    }

    function _readSwap(
        bytes memory data,
        uint256 startByte
    ) internal pure returns (IAggregationExecutorOptimistic.Swap memory swap, uint256) {
        (swap.data, startByte) = CalldataReader._readBytes(data, startByte);
        bytes1 t;
        (t, startByte) = CalldataReader._readBytes1(data, startByte);
        swap.functionSelector = bytes4(uint32(uint8(t)));
        return (swap, startByte);
    }
}
