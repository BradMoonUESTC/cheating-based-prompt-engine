// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IBasePositionManager {
    function maxGlobalLongSizes(address _token) external view returns (uint256);

    function maxGlobalShortSizes(
        address _token
    ) external view returns (uint256);
}
