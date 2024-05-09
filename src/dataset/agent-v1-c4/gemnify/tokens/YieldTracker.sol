//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IDistributor} from "./interfaces/IDistributor.sol";
import {IYieldTracker} from "./interfaces/IYieldTracker.sol";
import {IYieldToken} from "./interfaces/IYieldToken.sol";

// code adapated from https://github.com/trusttoken/smart-contracts/blob/master/contracts/truefi/TrueFarm.sol
contract YieldTracker is
    IYieldTracker,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant PRECISION = 1e30;

    address public yieldToken;
    address public distributor;

    uint256 public cumulativeRewardPerToken;
    mapping(address => uint256) public claimableReward;
    mapping(address => uint256) public previousCumulatedRewardPerToken;

    event Claim(address receiver, uint256 amount);

    function initialize(address _yieldToken) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        yieldToken = _yieldToken;
    }

    function setDistributor(address _distributor) external onlyOwner {
        distributor = _distributor;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyOwner {
        IERC20Upgradeable(_token).safeTransfer(_account, _amount);
    }

    function claim(
        address _account,
        address _receiver
    ) external override returns (uint256) {
        require(msg.sender == yieldToken, "YieldTracker: forbidden");
        updateRewards(_account);

        uint256 tokenAmount = claimableReward[_account];
        claimableReward[_account] = 0;

        address rewardToken = IDistributor(distributor).getRewardToken(
            address(this)
        );
        IERC20Upgradeable(rewardToken).safeTransfer(_receiver, tokenAmount);
        emit Claim(_account, tokenAmount);

        return tokenAmount;
    }

    function getTokensPerInterval() external view override returns (uint256) {
        return IDistributor(distributor).tokensPerInterval(address(this));
    }

    function claimable(
        address _account
    ) external view override returns (uint256) {
        uint256 stakedBalance = IYieldToken(yieldToken).stakedBalance(_account);
        if (stakedBalance == 0) {
            return claimableReward[_account];
        }
        uint256 pendingRewards = IDistributor(distributor)
            .getDistributionAmount(address(this)) * PRECISION;
        uint256 totalStaked = IYieldToken(yieldToken).totalStaked();
        uint256 nextCumulativeRewardPerToken = cumulativeRewardPerToken +
            (pendingRewards / totalStaked);
        return
            claimableReward[_account] +
            ((stakedBalance *
                (nextCumulativeRewardPerToken -
                    previousCumulatedRewardPerToken[_account])) / PRECISION);
    }

    function updateRewards(address _account) public override nonReentrant {
        uint256 blockReward;

        if (distributor != address(0)) {
            blockReward = IDistributor(distributor).distribute();
        }

        uint256 _cumulativeRewardPerToken = cumulativeRewardPerToken;
        uint256 totalStaked = IYieldToken(yieldToken).totalStaked();
        // only update cumulativeRewardPerToken when there are stakers, i.e. when totalStaked > 0
        // if blockReward == 0, then there will be no change to cumulativeRewardPerToken
        if (totalStaked > 0 && blockReward > 0) {
            _cumulativeRewardPerToken =
                _cumulativeRewardPerToken +
                ((blockReward * PRECISION) / totalStaked);
            cumulativeRewardPerToken = _cumulativeRewardPerToken;
        }

        // cumulativeRewardPerToken can only increase
        // so if cumulativeRewardPerToken is zero, it means there are no rewards yet
        if (_cumulativeRewardPerToken == 0) {
            return;
        }

        if (_account != address(0)) {
            uint256 stakedBalance = IYieldToken(yieldToken).stakedBalance(
                _account
            );
            uint256 _previousCumulatedReward = previousCumulatedRewardPerToken[
                _account
            ];
            uint256 _claimableReward = claimableReward[_account] +
                ((stakedBalance *
                    (_cumulativeRewardPerToken - _previousCumulatedReward)) /
                    PRECISION);

            claimableReward[_account] = _claimableReward;
            previousCumulatedRewardPerToken[
                _account
            ] = _cumulativeRewardPerToken;
        }
    }
}
