// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

/// @title IHookTarget
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @custom:security-contact security@euler.xyz
/// @notice Provides an interface for the hook target contract
interface IHookTarget {
    /// @notice If given contract is a hook target, it is expected to return the bytes4 magic value that is the selector
    /// of this function
    /// @return The bytes4 magic value (0x87439e04) that is the selector of this function
    function isHookTarget() external returns (bytes4);
}
