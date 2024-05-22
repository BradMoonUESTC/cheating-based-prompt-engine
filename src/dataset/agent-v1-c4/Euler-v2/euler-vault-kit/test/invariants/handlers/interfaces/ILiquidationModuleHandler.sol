// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ILiquidationModuleHandler {
    function liquidate(uint256 repayAssets, uint256 minYielBalance, uint256 i) external;
}
