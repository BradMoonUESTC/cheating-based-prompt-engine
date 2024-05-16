// SPDX-License-Identifier: MIT
/**
 _____
/  __ \
| /  \/ ___  _ ____   _____ _ __ __ _  ___ _ __   ___ ___
| |    / _ \| '_ \ \ / / _ \ '__/ _` |/ _ \ '_ \ / __/ _ \
| \__/\ (_) | | | \ V /  __/ | | (_| |  __/ | | | (_|  __/
 \____/\___/|_| |_|\_/ \___|_|  \__, |\___|_| |_|\___\___|
                                 __/ |
                                |___/
 */

/// @title Cvg-Finance - CvxRewardDistributor
/// @notice Receives all Convex rewards from CvxConvergenceLocker.
/// @dev Optimize gas cost on claim on several contract by limiting ERC20 transfers.
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/Convex/ICvxStakingPositionService.sol";
import "../../interfaces/Convex/ICvxStakingPositionManager.sol";
import "../../interfaces/ICvgControlTowerV2.sol";
import "../../interfaces/ICvg.sol";
import "../../interfaces/ICrvPoolPlain.sol";
import "../../interfaces/Convex/ICvxLocker.sol";
import "../../interfaces/Convex/ICvxConvergenceLocker.sol";

interface ICvx1 is IERC20 {
    function mint(address receiver, uint256 amount) external;
}

contract CvxRewardDistributor is Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev Convergence control tower
    ICvgControlTowerV2 public constant cvgControlTower = ICvgControlTowerV2(0xB0Afc8363b8F36E0ccE5D54251e20720FfaeaeE7);

    /// @dev Convex token
    IERC20 public constant CVX = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    /// @dev Convergence token
    ICvg public constant CVG = ICvg(0x97efFB790f2fbB701D88f89DB4521348A2B77be8);

    /// @notice Cvx Convergence Locker contract
    ICvxConvergenceLocker public cvxConvergenceLocker;

    /// @notice cvgCVX/CVX1 stable pool contract on Curve
    ICrvPoolPlain public poolCvgCvxCvx1;

    /// @notice Convex staking position manager contract
    ICvxStakingPositionManager public cvxStakingPositionManager;

    /// @dev CVX1 contract
    ICvx1 public cvx1;

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                        INITIALIZE
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(ICvx1 _cvx1) external initializer {
        address treasuryDao = cvgControlTower.treasuryDao();
        ICvxConvergenceLocker _cvxConvergenceLocker = cvgControlTower.cvxConvergenceLocker();
        ICvxStakingPositionManager _cvxStakingPositionManager = cvgControlTower.cvxStakingPositionManager();

        require(address(_cvxConvergenceLocker) != address(0), "CVX_LOCKER_ZERO");
        cvxConvergenceLocker = _cvxConvergenceLocker;

        require(address(_cvxStakingPositionManager) != address(0), "CVX_POSITION_MANAGER_ZERO");
        cvxStakingPositionManager = _cvxStakingPositionManager;

        cvx1 = _cvx1;
        CVX.approve(address(_cvx1), type(uint256).max);

        require(treasuryDao != address(0), "TREASURY_DAO_ZERO");
        _transferOwnership(treasuryDao);
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                        EXTERNALS
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    /**
     * @notice Mint CVG & distribute Convex rewards for a receiver, owner of a Staking Position
     * @dev    Function used when only one Staking Position is involved for a claiming.
     * @param receiver List of contracts having a list of tokenID with a list of cycleID to claim rewards on.
     * @param totalCvgClaimable List of contracts having a list of tokenID with a list of cycleID to claim rewards on.
     * @param totalCvxRewardsClaimable List of contracts having a list of tokenID with a list of cycleID to claim rewards on.
     * @param minCvgCvxAmountOut If greater than 0, converts all CVX into cvgCVX. Minimum amount to receive.
     * @param isConvert If true, converts all CVX into cvgCVX.
     */
    function claimCvgCvxSimple(
        address receiver,
        uint256 totalCvgClaimable,
        ICommonStruct.TokenAmount[] memory totalCvxRewardsClaimable,
        uint256 minCvgCvxAmountOut,
        bool isConvert
    ) external {
        require(cvgControlTower.isStakingContract(msg.sender), "NOT_STAKING");
        _withdrawRewards(receiver, totalCvgClaimable, totalCvxRewardsClaimable, minCvgCvxAmountOut, isConvert);
    }

    /**
     * @notice Claims rewards from Convex integration on several cycles for several tokenID on different CvxStakingPositionService.
     *         Allows the users to claim all the rewards from the Convex integration in 1 Tx.
     *         All CVG to mint are accumulated in one value.
     *         All Convex rewards are merged in one array.
     * @param claimContracts  List of contracts having a list of tokenID with a list of cycleID to claim rewards on.
     * @param minCvgCvxAmountOut If greater than 0, converts all CVX into cvgCVX through the pool. If equals to 0 mint through the cvgCVX contract. Minimum amount to receive.
     * @param isConvert          If true, converts all CVX into cvgCVX.
     * @param cvxRewardCount This parameter must be configured through the front-end.
     */
    function claimMultipleStaking(
        ICvxStakingPositionManager.ClaimCvxStakingContract[] calldata claimContracts,
        uint256 minCvgCvxAmountOut,
        bool isConvert,
        uint256 cvxRewardCount
    ) external {
        require(claimContracts.length != 0, "NO_STAKING_SELECTED");

        /// @dev Checks for all positions input in data : Token ownership & verify positions are linked to the right staking service & verify timelocking
        cvxStakingPositionManager.checkMultipleClaimCompliance(claimContracts, msg.sender);

        /// @dev Accumulates amounts of CVG coming from all claims.
        uint256 _totalCvgClaimable;

        /// @dev Array merging & accumulating rewards coming from different claims.
        ICommonStruct.TokenAmount[] memory _totalCvxClaimable = new ICommonStruct.TokenAmount[](cvxRewardCount);

        /// @dev Iterate over all staking service
        for (uint256 stakingIndex; stakingIndex < claimContracts.length; ) {
            ICvxStakingPositionService cvxStaking = claimContracts[stakingIndex].stakingContract;
            uint256 tokensLength = claimContracts[stakingIndex].tokenIds.length;
            require(tokensLength != 0, "NO_STAKING_POSITIONS_SELECTED");

            /// @dev Iterate over all tokens linked to the iterated cycle.
            for (uint256 tokenIdIndex; tokenIdIndex < tokensLength; ) {
                /** @dev Claims Cvg & Cvx
                 *       Returns the amount of CVG claimed on the position.
                 *       Returns the array of all CVX rewards claimed on the position.
                 */
                (uint256 cvgClaimable, ICommonStruct.TokenAmount[] memory _cvxRewards) = cvxStaking.claimCvgCvxMultiple(
                    claimContracts[stakingIndex].tokenIds[tokenIdIndex],
                    msg.sender
                );
                /// @dev increments the amount to mint at the end of function
                _totalCvgClaimable += cvgClaimable;

                uint256 cvxRewardsLength = _cvxRewards.length;
                /// @dev Iterate over all CVX rewards claimed on the iterated position
                for (uint256 positionRewardIndex; positionRewardIndex < cvxRewardsLength; ) {
                    /// @dev Is the claimable amount is 0 on this token
                    ///      We bypass the process to save gas
                    if (_cvxRewards[positionRewardIndex].amount != 0) {
                        /// @dev Iterate over the final array to merge the iterated CvxRewards in the totalSdtClaimable
                        for (uint256 totalRewardIndex; totalRewardIndex < cvxRewardCount; ) {
                            address iteratedTotalClaimableToken = address(_totalCvxClaimable[totalRewardIndex].token);
                            /// @dev If the token is not already in the totalCvxClaimable.
                            if (iteratedTotalClaimableToken == address(0)) {
                                /// @dev Set token data in the totalClaimable array.
                                _totalCvxClaimable[totalRewardIndex] = ICommonStruct.TokenAmount({
                                    token: _cvxRewards[positionRewardIndex].token,
                                    amount: _cvxRewards[positionRewardIndex].amount
                                });

                                /// @dev Pass to the next token
                                break;
                            }

                            /// @dev If the token is already in the totalSdtClaimable.
                            if (iteratedTotalClaimableToken == address(_cvxRewards[positionRewardIndex].token)) {
                                /// @dev Increments the claimable amount.
                                _totalCvxClaimable[totalRewardIndex].amount += _cvxRewards[positionRewardIndex].amount;
                                /// @dev Pass to the next token
                                break;
                            }

                            /// @dev If the token is not found in the totalRewards and we are at the end of the array.
                            ///      it means the cvxRewardCount is not properly configured.
                            require(totalRewardIndex != cvxRewardCount - 1, "REWARD_COUNT_TOO_SMALL");

                            unchecked {
                                ++totalRewardIndex;
                            }
                        }
                    }

                    unchecked {
                        ++positionRewardIndex;
                    }
                }

                unchecked {
                    ++tokenIdIndex;
                }
            }
            unchecked {
                ++stakingIndex;
            }
        }

        _withdrawRewards(msg.sender, _totalCvgClaimable, _totalCvxClaimable, minCvgCvxAmountOut, isConvert);
    }

    /** @dev Mint accumulated CVG & Transfers Cvonex rewards to the claimer of Stakings
     *  @param receiver                 Receiver of the claim
     *  @param totalCvgClaimable        Amount of CVG to mint to the receiver
     *  @param totalCvxRewardsClaimable Array of all Convex rewards to send to the receiver
     *  @param minCvgCvxAmountOut       Minimum amount of cvgCVX to receive in case of a pool exchange
     *  @param isConvert                If true, converts all CVX into cvgCVX.
     *
     */
    function _withdrawRewards(
        address receiver,
        uint256 totalCvgClaimable,
        ICommonStruct.TokenAmount[] memory totalCvxRewardsClaimable,
        uint256 minCvgCvxAmountOut,
        bool isConvert
    ) internal {
        /// @dev Mints accumulated CVG and claim Convex rewards
        if (totalCvgClaimable > 0) {
            CVG.mintStaking(receiver, totalCvgClaimable);
        }

        for (uint256 i; i < totalCvxRewardsClaimable.length; ) {
            uint256 rewardAmount = totalCvxRewardsClaimable[i].amount;

            if (rewardAmount > 0) {
                /// @dev If the token is CVX & we want to convert it in cvgCVX
                if (isConvert && totalCvxRewardsClaimable[i].token == CVX) {
                    if (minCvgCvxAmountOut == 0) {
                        /// @dev Mint cvgCVX 1:1 via cvxConvergenceLocker contract
                        cvxConvergenceLocker.mint(receiver, rewardAmount, false);
                    }
                    /// @dev Else it's a swap
                    else {
                        cvx1.mint(address(this), rewardAmount);
                        poolCvgCvxCvx1.exchange(0, 1, rewardAmount, minCvgCvxAmountOut, receiver);
                    }
                }
                /// @dev Else transfer the ERC20 to the receiver
                else {
                    totalCvxRewardsClaimable[i].token.safeTransfer(receiver, rewardAmount);
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     *  @notice Set the cvgCVX/CVX1 stable pool. Approve CVX1 tokens to be transferred from the cvgCVX LP.
     *  @dev    The approval has to be done to perform swaps from CVX1 to cvgCVX during claims.
     *  @param _poolCvgCvxCvx1 Address of the cvgCVX/CVX1 stable pool to set
     *  @param amount      Amount of CVX1 to approve on the Stable pool
     */
    function setPoolCvgCvxCvx1AndApprove(ICrvPoolPlain _poolCvgCvxCvx1, uint256 amount) external onlyOwner {
        /// @dev Remove approval from previous pool
        if (address(poolCvgCvxCvx1) != address(0)) cvx1.approve(address(poolCvgCvxCvx1), 0);

        poolCvgCvxCvx1 = _poolCvgCvxCvx1;
        cvx1.approve(address(_poolCvgCvxCvx1), amount);
        CVX.approve(address(cvxConvergenceLocker), amount);
    }
}
