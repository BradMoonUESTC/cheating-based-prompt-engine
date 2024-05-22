// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

/// @title ISequenceRegistry
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Provides an interface for reserving sequence IDs.
interface ISequenceRegistry {
    /// @notice Reserve an ID for a given designator
    /// @param designator An opaque string that corresponds to the sequence counter to be used
    /// @return Sequence ID
    function reserveSeqId(string calldata designator) external returns (uint256);
}
