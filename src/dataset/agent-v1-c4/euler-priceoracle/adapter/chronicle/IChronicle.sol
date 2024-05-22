// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

/// @title IChronicle
/// @author chronicleprotocol (https://github.com/chronicleprotocol/chronicle-std/blob/ea9afe78a1d33245afcdbcc3f530ee9cbd7cde28/src/IChronicle.sol)
/// @notice Partial interface for Chronicle Protocol's oracle products.
interface IChronicle {
    /// @notice Returns the oracle's current value and its age.
    /// @dev Reverts if no value set.
    /// @return value The oracle's current value.
    /// @return age The value's age.
    function readWithAge() external view returns (uint256 value, uint256 age);
    /// @notice Returns the oracle's decimals.
    /// @return The decimals of the oracle.
    function decimals() external view returns (uint8);
}
