// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.19;

interface IStargateRouterETH {

    function swapETH(
        uint16 _dstChainId,
        address payable _refundAddress,
        bytes calldata _toAddress,
        uint256 _amountLD,
        uint256 _minAmountLD
    ) external payable;
}
