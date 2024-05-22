// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

/// @title IFlashLoan
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Definition of callback method that flashLoan will invoke on your contract
interface IFlashLoan {
    /// @notice Function that will be called on the caller of `flashloan`
    /// @param data Data that was passed to the `flashloan` call
    function onFlashLoan(bytes memory data) external;
}
