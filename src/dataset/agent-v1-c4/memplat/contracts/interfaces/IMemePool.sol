// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMemePool is IERC20 {

    function initialize() payable external returns (uint256 lockAmount);

    function addLiquidity(uint256 minReturn) external payable;

    function removeLiquidity(uint256 liquidity, uint256 minNative, uint256 minToken) external;

    function buy(uint256 minReturn) external payable;

    function sell(uint256 tokenIn, uint256 minReturn) external;

    function getAmountOut(
        address trader,
        uint256 amount,
        bool _buy
    ) external view returns(uint256);

    function getReserves() external view returns (uint256, uint256);

}
