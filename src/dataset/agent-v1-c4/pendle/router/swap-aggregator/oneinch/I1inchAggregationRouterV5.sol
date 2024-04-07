// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface I1inchAggregationRouterV5 {
    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    function uniswapV3SwapTo(
        address payable recipient,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount);

    function swap(
        address executor,
        SwapDescription calldata desc,
        bytes calldata permit,
        bytes calldata data
    ) external payable returns (uint256 returnAmount, uint256 spentAmount);

    function unoswapTo(
        address payable recipient,
        address srcToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount);
}
