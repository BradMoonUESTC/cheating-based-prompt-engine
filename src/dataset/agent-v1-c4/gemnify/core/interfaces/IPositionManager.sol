// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IPositionManager {
    function executeIncreaseOrder(
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external;

    function executeDecreaseOrder(
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external;
}
