// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "./IBalanceTracker.sol";

/// @title IRewardStreams
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Interface for Reward Streams distributor contract.
interface IRewardStreams {
    function EPOCH_DURATION() external view returns (uint256);
    function MAX_EPOCHS_AHEAD() external view returns (uint256);
    function MAX_DISTRIBUTION_LENGTH() external view returns (uint256);
    function MAX_REWARDS_ENABLED() external view returns (uint256);
    function registerReward(address rewarded, address reward, uint48 startEpoch, uint128[] calldata rewardAmounts) external;
    function updateReward(address rewarded, address reward, address recipient) external;
    function claimReward(address rewarded, address reward, address recipient, bool forfeitRecentReward) external;
    function enableReward(address rewarded, address reward) external;
    function disableReward(address rewarded, address reward, bool forfeitRecentReward) external;
    function earnedReward(address account, address rewarded, address reward, bool forfeitRecentReward) external view returns (uint256);
    function enabledRewards(address account, address rewarded) external view returns (address[] memory);
    function balanceOf(address account, address rewarded) external view returns (uint256);
    function rewardAmount(address rewarded, address reward) external view returns (uint256);
    function totalRewardedEligible(address rewarded, address reward) external view returns (uint256);
    function totalRewardRegistered(address rewarded, address reward) external view returns (uint256);
    function totalRewardClaimed(address rewarded, address reward) external view returns (uint256);
    function rewardAmount(address rewarded, address reward, uint48 epoch) external view returns (uint256);
    function currentEpoch() external view returns (uint48);
    function getEpoch(uint48 timestamp) external view returns (uint48);
    function getEpochStartTimestamp(uint48 epoch) external view returns (uint48);
    function getEpochEndTimestamp(uint48 epoch) external view returns (uint48);
}

/// @title ITrackingRewardStreams
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Interface for Tracking Reward Streams. Extends `IRewardStreams` and `IBalanceTracker`.
interface ITrackingRewardStreams is IRewardStreams, IBalanceTracker {}

/// @title IStakingRewardStreams
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Interface for Staking Reward Streams. Extends `IRewardStreams` with staking functionality.
interface IStakingRewardStreams is IRewardStreams {
    function stake(address rewarded, uint256 amount) external;
    function unstake(address rewarded, uint256 amount, address recipient, bool forfeitRecentReward) external;
}
