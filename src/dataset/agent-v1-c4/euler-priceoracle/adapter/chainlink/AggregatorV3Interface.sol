// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title AggregatorV3Interface
/// @author smartcontractkit (https://github.com/smartcontractkit/chainlink/blob/e87b83cd78595c09061c199916c4bb9145e719b7/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol)
/// @notice Partial interface for Chainlink Data Feeds.
interface AggregatorV3Interface {
    /// @notice Returns the feed's decimals.
    /// @return The decimals of the feed.
    function decimals() external view returns (uint8);

    /// @notice Get data about the latest round.
    /// @return roundId The round ID from the aggregator for which the data was retrieved.
    /// @return answer The answer for the given round.
    /// @return startedAt The timestamp when the round was started.
    /// (Only some AggregatorV3Interface implementations return meaningful values)
    /// @return updatedAt The timestamp when the round last was updated (i.e. answer was last computed).
    /// @return answeredInRound is the round ID of the round in which the answer was computed.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
