// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Set, SetStorage} from "evc/Set.sol";
import {BaseRewardStreams} from "./BaseRewardStreams.sol";
import {IStakingRewardStreams} from "./interfaces/IRewardStreams.sol";

/// @title StakingRewardStreams
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This contract inherits from `BaseRewardStreams` and implements `IStakingRewardStreams`.
/// It allows for the rewards to be distributed to the rewarded token holders who have staked it.
contract StakingRewardStreams is BaseRewardStreams, IStakingRewardStreams {
    using SafeERC20 for IERC20;
    using Set for SetStorage;

    /// @notice Constructor for the StakingRewardStreams contract.
    /// @param evc The Ethereum Vault Connector contract.
    /// @param periodDuration The duration of a period.
    constructor(address evc, uint48 periodDuration) BaseRewardStreams(evc, periodDuration) {}

    /// @notice Allows a user to stake rewarded tokens.
    /// @dev If the amount is max, the entire balance of the user is staked.
    /// @param rewarded The address of the rewarded token.
    /// @param amount The amount of tokens to stake.
    function stake(address rewarded, uint256 amount) external virtual override nonReentrant {
        address msgSender = _msgSender();

        if (amount == type(uint256).max) {
            amount = IERC20(rewarded).balanceOf(msgSender);
        }

        if (amount == 0) {
            revert InvalidAmount();
        }

        AccountStorage storage accountStorage = accounts[msgSender][rewarded];
        uint256 currentAccountBalance = accountStorage.balance;
        address[] memory rewards = accountStorage.enabledRewards.get();

        for (uint256 i = 0; i < rewards.length; ++i) {
            address reward = rewards[i];
            DistributionStorage storage distributionStorage = distributions[rewarded][reward];

            // We always allocate rewards before updating any balances.
            updateRewardInternal(
                distributionStorage, accountStorage.earned[reward], rewarded, reward, currentAccountBalance, false
            );

            distributionStorage.totalEligible += amount;
        }

        uint256 newAccountBalance = currentAccountBalance + amount;
        accountStorage.balance = newAccountBalance;

        emit BalanceUpdated(msgSender, rewarded, currentAccountBalance, newAccountBalance);

        pullToken(IERC20(rewarded), msgSender, amount);
    }

    /// @notice Allows a user to unstake rewarded tokens.
    /// @dev This function reverts if the recipient is zero address or is a known non-owner EVC account.
    /// @dev If the amount is max, the entire balance of the user is unstaked.
    /// @param rewarded The address of the rewarded token.
    /// @param recipient The address to receive the unstaked tokens.
    /// @param amount The amount of tokens to unstake.
    /// @param forfeitRecentReward Whether to forfeit the recent reward and not update the accumulator.
    function unstake(
        address rewarded,
        uint256 amount,
        address recipient,
        bool forfeitRecentReward
    ) external virtual override nonReentrant {
        address msgSender = _msgSender();
        AccountStorage storage accountStorage = accounts[msgSender][rewarded];
        uint256 currentAccountBalance = accountStorage.balance;

        if (amount == type(uint256).max) {
            amount = currentAccountBalance;
        }

        if (amount == 0 || amount > currentAccountBalance) {
            revert InvalidAmount();
        }

        address[] memory rewards = accountStorage.enabledRewards.get();

        for (uint256 i = 0; i < rewards.length; ++i) {
            address reward = rewards[i];
            DistributionStorage storage distributionStorage = distributions[rewarded][reward];

            // We always allocate rewards before updating any balances.
            updateRewardInternal(
                distributionStorage,
                accountStorage.earned[reward],
                rewarded,
                reward,
                currentAccountBalance,
                forfeitRecentReward
            );

            distributionStorage.totalEligible -= amount;
        }

        uint256 newAccountBalance = currentAccountBalance - amount;
        accountStorage.balance = newAccountBalance;

        emit BalanceUpdated(msgSender, rewarded, currentAccountBalance, newAccountBalance);

        pushToken(IERC20(rewarded), recipient, amount);
    }
}
