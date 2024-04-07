// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

struct SwapData {
    SwapType swapType;
    address extRouter;
    bytes extCalldata;
    bool needScale;
}

enum SwapType {
    NONE,
    KYBERSWAP,
    ONE_INCH,
    // ETH_WETH not used in Aggregator
    ETH_WETH
}

interface IPSwapAggregator {
    function swap(address tokenIn, uint256 amountIn, SwapData calldata swapData) external payable;
}
