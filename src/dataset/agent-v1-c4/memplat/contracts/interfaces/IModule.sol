// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IModule {

    function initialize() external;

    function beforeBuy(
        address _trader,
        uint256 _amountIn
    ) external;

    function afterBuy(
        address _trader,
        uint256 _amountIn,
        uint256 _mountOut
    ) external returns (uint256);

    function beforeSell(
        address _trader,
        uint256 _amountIn
    ) external;

    function afterSell(
        address _trader,
        uint256 _amountIn,
        uint256 _amountOut
    ) external returns (uint256);

    function afterAdd(
        address _user,
        uint256 _tokenIn,
        uint256 _nativeIn
    ) external;

    function afterRemove(
        address _user,
        uint256 _tokenOut,
        uint256 _nativeOut
    ) external;

    function quoteBuy(
        address _trader,
        uint256 _amountIn,
        uint256 _amountOut
    ) external view returns (uint256 amountOut);

    function quoteSell(
        address _trader,
        uint256 _amountIn,
        uint256 _amountOut
    ) external view returns (uint256 amountOut);

    function getFlag() external view returns (bool, bool, bool, bool, bool, bool, bool);

}
