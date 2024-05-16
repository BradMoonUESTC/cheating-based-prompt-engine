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
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import "../../../interfaces/ICvgControlTowerV2.sol";
import "../../../interfaces/Convex/ICvxLocker.sol";
import "../../../interfaces/Convex/ICvxAssetWrapper.sol";

import "../../../interfaces/Convex/ICvxAssetStakerBuffer.sol";

/// @title Cvg Finance - CvxAssetStakerBuffer
/// @notice Stakes all cvxAsset received through the associated CvxAssetStakingService.
///         Claims, accumulates and process the rewards for stakers until the weekly distribution.
contract CvxAssetStakerBuffer is Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev Convergence control tower
    ICvgControlTowerV2 public constant cvgControlTower = ICvgControlTowerV2(0xB0Afc8363b8F36E0ccE5D54251e20720FfaeaeE7);

    /// @dev Used to calculate the percentage of fees
    uint256 private constant DENOMINATOR = 100_000;

    /// @dev Convex liquid locker of the base asset. ex : cvxCRV
    IERC20 public cvxAsset;

    /// @dev Staker & Wrapper of the associated cvxAsset. ex : stkCvxCrv
    ICvxAssetWrapper public cvxAssetWrapper;

    /// @dev Staking service associated to the buffer
    address public cvxAssetStakingService;

    /// @notice Receiver of all Convex rewards.
    ICvxRewardDistributor public cvxRewardDistributor;

    /// @notice Allows to switch between 2 different types of signature during the call to stake on the wrapper.
    uint256 public stakingType;

    /// @notice Contains all rewarded ERC20 and associated fees taken
    ICvxAssetStakerBuffer.CvxRewardConfig[] public rewardTokensConfigs;

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                            INIT
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    /**
     * @notice Initialize function of the staking contract, can only be called once.
     * @param _cvxAsset                Convex liquid locker ERC20
     * @param _cvxAssetWrapper         Liquid locker wrapper
     * @param _cvxAssetStakingService  Staking contract linked to the StakerBuffer
     * @param _stakingType             Type of the signature on liquid locker staking
     * @param _rewardTokensConfigs     Rewarded ERC20 and associated fees taken
     */
    function initialize(
        IERC20 _cvxAsset,
        ICvxAssetWrapper _cvxAssetWrapper,
        address _cvxAssetStakingService,
        uint256 _stakingType,
        ICvxAssetStakerBuffer.CvxRewardConfig[] calldata _rewardTokensConfigs
    ) external initializer {
        require(address(_cvxAsset) != address(0), "CVX_ASSET");
        cvxAsset = _cvxAsset;

        require(address(_cvxAssetWrapper) != address(0), "CVX_ASSET_WRAPPER");
        cvxAssetWrapper = _cvxAssetWrapper;

        require(address(_cvxAssetStakingService) != address(0), "CVX_ASSET_STAKING");
        cvxAssetStakingService = _cvxAssetStakingService;

        ICvxRewardDistributor _cvxRewardDistributor = cvgControlTower.cvxRewardDistributor();
        require(address(_cvxRewardDistributor) != address(0), "CVX_REWARD_DISTRIBUTOR");
        cvxRewardDistributor = _cvxRewardDistributor;

        address treasuryDao = cvgControlTower.treasuryDao();
        require(treasuryDao != address(0), "TREASURY_DAO");
        _transferOwnership(treasuryDao);

        stakingType = _stakingType;

        for (uint256 i; i < _rewardTokensConfigs.length; ) {
            rewardTokensConfigs.push(_rewardTokensConfigs[i]);
            unchecked {
                i++;
            }
        }

        /// @dev Allows the liquid locker wrapper to transfer the liquid locker tokens that are on this contract
        _cvxAsset.approve(address(_cvxAssetWrapper), type(uint256).max);
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                    STAKING SERVICE FUNCTIONS
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    /**
     * @notice Withdraw an amount of stkCvxAsset or cvxAsset.
     * @dev Only callable by the withdraw function from the associated staking service.
     * @param withdrawer       Address that is withdrawing the asset.
     * @param amount           Amount of token to withdraw.
     * @param isStakedAsset    Set the type of the asset to be returned ( stkCvxAsset or cvxAsset )
     */
    function withdraw(address withdrawer, uint256 amount, bool isStakedAsset) external {
        require(cvxAssetStakingService == msg.sender, "NOT_CVX_ASSET_STAKING_SERVICE");

        /// @dev Send stkCvxAsset to the withdrawer
        if (isStakedAsset) {
            cvxAssetWrapper.transfer(withdrawer, amount);
        }
        /// @dev Convert back to cvxAsset
        else {
            IERC20 _cvxAsset = cvxAsset;
            uint256 actualBalance = _cvxAsset.balanceOf(address(this));

            /// @dev In case there is not enough cvxAsset pending on the contract, we need to withdraw from the staker
            if (actualBalance < amount) {
                cvxAssetWrapper.withdraw(amount - actualBalance);
            }

            _cvxAsset.transfer(withdrawer, amount);
        }
    }

    /**
     * @notice Processes rewards from Convex to stakers for the previous cycle.
     * @dev    Once a cycle, this function is callable from the Staking Service associated.
     *             It :
     *              - Stakes all cvxAsset owned by the contract in the associated wrapper
     *              - Claims all rewards
     *              - Computes and transfers the fees dedicated for the processor & the pod
     *              - Computes and transfers the rewards for stakers to the CvxRewardDistributor.
     *              - Writes the amount rewards distributed on this cycle in the associated Staking Service
     * @return An array of token amount to the Staking Service
     **/
    function pullRewards(address processor) external returns (ICommonStruct.TokenAmount[] memory) {
        require(cvxAssetStakingService == msg.sender, "NOT_CVX_ASSET_STAKING_SERVICE");

        address treasuryPod = cvgControlTower.treasuryPod();

        address rewardReceiver = address(cvxRewardDistributor);
        uint256 rewardLength = rewardTokensConfigs.length;

        /// @dev Stakes all cvxAsset pending on the contract
        stakeAllCvxAsset();
        /// @dev Claim all rewards
        cvxAssetWrapper.getReward(address(this));

        ICommonStruct.TokenAmount[] memory rewardAssets = new ICommonStruct.TokenAmount[](rewardLength);
        uint256 counterDelete;
        for (uint256 i; i < rewardLength; ) {
            ICvxAssetStakerBuffer.CvxRewardConfig memory rewardConfig = rewardTokensConfigs[i];
            IERC20 token = rewardConfig.token;
            uint256 balance = token.balanceOf(address(this));

            uint256 processorFees = (balance * rewardConfig.processorFees) / DENOMINATOR;
            uint256 podFees = (balance * rewardConfig.podFees) / DENOMINATOR;
            uint256 amountToStakers = balance - podFees - processorFees;

            if (amountToStakers != 0) {
                token.safeTransfer(rewardReceiver, amountToStakers);
                rewardAssets[i - counterDelete] = ICommonStruct.TokenAmount({token: token, amount: amountToStakers});
            }

            if (processorFees != 0) {
                token.safeTransfer(processor, processorFees);
            }

            if (podFees != 0) {
                token.safeTransfer(treasuryPod, podFees);
            }

            if (balance == 0) {
                unchecked {
                    ++counterDelete;
                }
            }
            unchecked {
                ++i;
            }
        }

        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(rewardAssets, sub(mload(rewardAssets), counterDelete))
        }
        return rewardAssets;
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                        OPEN FUNCTIONS
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    /**
     * @notice Stake all cvxAsset owned by the contract to stkCvxAsset.
     * @dev Regarding the type of the staking, use different signature. (cvxCRV is for now the only different from the others)
     */
    function stakeAllCvxAsset() public {
        uint256 balanceCvxAsset = cvxAsset.balanceOf(address(this));
        if (balanceCvxAsset != 0) {
            if (stakingType == 0) {
                cvxAssetWrapper.stake(balanceCvxAsset, address(this));
            } else {
                cvxAssetWrapper.stake(balanceCvxAsset);
            }
        }
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                        OWNER FUNCTIONS
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    /** @notice Setup the list of rewards and fees from Convex that the contract distributes as reward
     *  @dev    Callable only by the contract owner.
     */
    function setRewardTokensConfig(
        ICvxAssetStakerBuffer.CvxRewardConfig[] calldata _rewardTokensConfigs
    ) external onlyOwner {
        delete rewardTokensConfigs;
        for (uint256 i; i < _rewardTokensConfigs.length; ) {
            rewardTokensConfigs.push(_rewardTokensConfigs[i]);
            unchecked {
                i++;
            }
        }
    }

    /** @notice For cvxCRV only, allows to set the type of reward we are getting. ( Assets or Stable )
     *  @dev    Callable only by the contract owner.
     *  @param  weight of the reward in % (max 10_000)
     */
    function setRewardWeight(uint256 weight) external onlyOwner {
        cvxAssetWrapper.setRewardWeight(weight);
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                            VIEWS
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */
    function getRewardTokensConfig() external view returns (ICvxAssetStakerBuffer.CvxRewardConfig[] memory) {
        return rewardTokensConfigs;
    }
}
