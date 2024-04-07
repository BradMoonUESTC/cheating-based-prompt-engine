// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./RewardManagerAbstract.sol";

/// NOTE: This RewardManager is used with SY & YTv2 & PendleMarket. For YTv1, it will use RewardManagerAbstract
/// NOTE: RewardManager must not have duplicated rewardTokens
abstract contract RewardManager is RewardManagerAbstract {
    using PMath for uint256;
    using ArrayLib for uint256[];

    uint256 public lastRewardBlock;

    mapping(address => RewardState) public rewardState;

    function _updateRewardIndex()
        internal
        virtual
        override
        returns (address[] memory tokens, uint256[] memory indexes)
    {
        tokens = _getRewardTokens();
        indexes = new uint256[](tokens.length);

        if (tokens.length == 0) return (tokens, indexes);

        if (lastRewardBlock != block.number) {
            // if we have not yet update the index for this block
            lastRewardBlock = block.number;

            uint256 totalShares = _rewardSharesTotal();

            _redeemExternalReward();

            for (uint256 i = 0; i < tokens.length; ++i) {
                address token = tokens[i];

                // the entire token balance of the contract must be the rewards of the contract

                RewardState memory _state = rewardState[token];
                (uint256 lastBalance, uint256 index) = (_state.lastBalance, _state.index);

                uint256 accrued = _selfBalance(tokens[i]) - lastBalance;

                if (index == 0) index = INITIAL_REWARD_INDEX;
                if (totalShares != 0) index += accrued.divDown(totalShares);

                rewardState[token] = RewardState({
                    index: index.Uint128(),
                    lastBalance: (lastBalance + accrued).Uint128()
                });
                indexes[i] = index;
            }
        } else {
            for (uint256 i = 0; i < tokens.length; i++) {
                indexes[i] = rewardState[tokens[i]].index;
            }
        }
    }

    /// @dev this function doesn't need redeemExternal since redeemExternal is bundled in updateRewardIndex
    /// @dev this function also has to update rewardState.lastBalance
    function _doTransferOutRewards(
        address user,
        address receiver
    ) internal virtual override returns (uint256[] memory rewardAmounts) {
        address[] memory tokens = _getRewardTokens();
        rewardAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            rewardAmounts[i] = userReward[tokens[i]][user].accrued;
            if (rewardAmounts[i] != 0) {
                userReward[tokens[i]][user].accrued = 0;
                rewardState[tokens[i]].lastBalance -= rewardAmounts[i].Uint128();
                _transferOut(tokens[i], receiver, rewardAmounts[i]);
            }
        }
    }

    function _getRewardTokens() internal view virtual returns (address[] memory);

    function _rewardSharesTotal() internal view virtual returns (uint256);
}
