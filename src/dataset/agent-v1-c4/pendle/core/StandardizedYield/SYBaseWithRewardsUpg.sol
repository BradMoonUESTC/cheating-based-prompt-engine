// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../RewardManager/RewardManager.sol";
import "./SYBaseUpg.sol";

/// NOTE: yieldToken MUST NEVER BE a rewardToken, else the rewardManager will behave erroneously
abstract contract SYBaseWithRewardsUpg is SYBaseUpg, RewardManager {
    using PMath for uint256;
    using ArrayLib for address[];

    uint256[100] private __gap;

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-claimRewards}
     */
    function claimRewards(
        address user
    ) external virtual override nonReentrant whenNotPaused returns (uint256[] memory rewardAmounts) {
        _updateAndDistributeRewards(user);
        rewardAmounts = _doTransferOutRewards(user, user);

        emit ClaimRewards(user, _getRewardTokens(), rewardAmounts);
    }

    /**
     * @dev See {IStandardizedYield-getRewardTokens}
     */
    function getRewardTokens() external view virtual override returns (address[] memory rewardTokens) {
        rewardTokens = _getRewardTokens();
    }

    /**
     * @dev See {IStandardizedYield-accruedRewards}
     */
    function accruedRewards(address user) external view virtual override returns (uint256[] memory rewardAmounts) {
        address[] memory rewardTokens = _getRewardTokens();
        rewardAmounts = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; ) {
            rewardAmounts[i] = userReward[rewardTokens[i]][user].accrued;
            unchecked {
                i++;
            }
        }
    }

    function rewardIndexesCurrent() external override nonReentrant whenNotPaused returns (uint256[] memory indexes) {
        (, indexes) = _updateRewardIndex();
    }

    function rewardIndexesStored() public view virtual override returns (uint256[] memory indexes) {
        address[] memory rewardTokens = _getRewardTokens();
        indexes = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; ) {
            indexes[i] = rewardState[rewardTokens[i]].index;
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice returns the total number of reward shares
     * @dev this is simply the total supply of shares, as rewards shares are equivalent to SY shares
     */
    function _rewardSharesTotal() internal view virtual override returns (uint256) {
        return totalSupply();
    }

    /**
     * @notice returns the reward shares of (`user`)
     * @dev this is simply the SY balance of (`user`), as rewards shares are equivalent to SY shares
     */
    function _rewardSharesUser(address user) internal view virtual override returns (uint256) {
        return balanceOf(user);
    }

    /*///////////////////////////////////////////////////////////////
                            TRANSFER HOOKS
    //////////////////////////////////////////////////////////////*/
    function _beforeTokenTransfer(address from, address to, uint256) internal virtual override whenNotPaused {
        _updateAndDistributeRewardsForTwo(from, to);
    }
}
