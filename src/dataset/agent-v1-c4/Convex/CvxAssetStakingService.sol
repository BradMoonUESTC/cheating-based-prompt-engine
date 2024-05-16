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

/// @title Cvg-Finance - CvxAssetStakingService
/// @notice Specific deposits & withdraw functions designed for Convex liquid wrapper staking.
/// @dev Inherits from StakingServiceBase
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../StakingServiceBase.sol";

import "../../../interfaces/ICvgControlTowerV2.sol";
import "../../../interfaces/ICrvPoolPlain.sol";
import "../../../interfaces/ICommonStruct.sol";
import "../../../interfaces/Convex/ICvxStakingPositionManager.sol";
import "../../../interfaces/Convex/ICvxAssetStakerBuffer.sol";
import "../../../interfaces/Convex/ICvxAssetWrapper.sol";
import "../../../interfaces/Convex/IAssetDepositor.sol";

contract CvxAssetStakingService is StakingServiceBase {
    /// @dev Convex liquid locker of the base asset. i.e. cvxCRV
    IERC20 public cvxAsset;

    /// @dev Staker & Wrapper of the associated cvxAsset. i.e. stkCvxCrv
    ICvxAssetWrapper public cvxAssetWrapper;

    /// @dev Curve Stable Pool address of cvxAsset/Asset
    ICrvPoolPlain public curvePool;

    /// @dev Contract in charge to lock asset in cvxAsset.
    IAssetDepositor public assetDepositor;

    enum INPUT_TOKEN_TYPE {
        asset,
        cvxAsset,
        stkCvxAsset
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                      CONSTRUCTOR & INIT
  =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize function of the staking contract, can only be called once
     * @param _symbol Symbol to display on the NFT
     */
    function initialize(
        IERC20 _asset,
        IERC20 _cvxAsset,
        ICvxAssetWrapper _cvxAssetWrapper,
        ICrvPoolPlain _curvePool,
        IAssetDepositor _assetDepositor,
        string memory _symbol
    ) external initializer {
        asset = _asset;

        cvxAsset = _cvxAsset;

        curvePool = _curvePool;

        cvxAssetWrapper = _cvxAssetWrapper;

        assetDepositor = _assetDepositor;

        symbol = _symbol;

        /// @dev Initialize internal cycle with the cycle from the control tower
        stakingCycle = cvgControlTower.cvgCycle();

        /// @dev To prevent the claim of CVX on the first Cycle of deployment.
        ///      Staked asset must be staked during a FULL cycle to be eligible to rewards
        _cycleInfo[stakingCycle].isCvxProcessed = true;

        ICvxStakingPositionManager _cvxStakingPositionManager = cvgControlTower.cvxStakingPositionManager();
        require(address(_cvxStakingPositionManager) != address(0), "CVX_STAKING_MANAGER_ZERO");
        stakingPositionManager = _cvxStakingPositionManager;

        ICvxRewardDistributor _cvxRewardDistributor = cvgControlTower.cvxRewardDistributor();
        require(address(_cvxRewardDistributor) != address(0), "CVX_REWARD_DISTRIBUTOR");
        cvxRewardDistributor = _cvxRewardDistributor;

        address _treasuryDao = cvgControlTower.treasuryDao();
        require(_treasuryDao != address(0), "TREASURY_DAO_ZERO");
        _transferOwnership(_treasuryDao);

        /// @dev Allows to stake cvxAsset from this contract on the stkCvxAsset of Convex
        cvxAsset.approve(address(cvxAssetWrapper), type(uint256).max);

        /// @dev Allows to swap some Asset to cvxAsset on the stable pool
        asset.approve(address(_curvePool), type(uint256).max);

        /// @dev Allows to swap some Asset to cvxAsset on the asset depositor of Convex
        asset.approve(address(assetDepositor), type(uint256).max);
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                        USER EXTERNAL
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */
    /**
     * @notice Pay an amount of ETH to obtain cvxAsset to deposit in the staking contract.
     * @dev Staking at cycle N implies that first rewards will be claimable at the beginning of cycle N+2, then every cycle.
     * @param tokenId Id of the position, If 0, creates a new position
     * @param minAmountOutAsset Minimum amount of Asset to receive through the swap
     * @param minAmountOutCvxAsset Minimum amount of cvxAsset to receive through the swap
     * @param isLock If true, cvxAsset will be automatically locked
     * @param isStake If true, stakes all cvxAssets of the contract in stkCvxAsset.
     */
    function depositEth(
        uint256 tokenId,
        uint256 minAmountOutAsset,
        uint256 minAmountOutCvxAsset,
        bool isLock,
        bool isStake
    ) external payable lockReentrancy {
        uint256 amountAsset = _depositEth(msg.value, minAmountOutAsset);
        _deposit(tokenId, amountAsset, INPUT_TOKEN_TYPE.asset, minAmountOutCvxAsset, isLock, isStake, true);
    }

    /**
     * @notice Deposit an amount of cvxAsset or stkCvAsset in the staking contract.
     *         Accepts staking with :
     *          - Asset       :  Call Convex Depositor or swap in the stable LP (regarding the peg) to convert asset into cvxAsset & Send it to the StakerBuffer.
     *          - cvxAsset    :  Send the cvxAsset directly to the StakerBuffer.
     *          - stkCvxAsset :  Send already stakedAsset to the StakerBuffer.
     * @dev Staking at cycle N implies that first rewards will be claimable at the beginning of cycle N+2, then every cycle.
     * @param tokenId Id of the position, If 0, creates a new position
     * @param amount Amount of cvxAsset to deposit
     * @param inputTokenType Of one of the assets to stake
     * @param minAmountOut Of one of the assets to stake
     * @param isLock If true, cvxAsset will be automatically locked
     * @param isStake If true, stakes all cvxAssets of the contract in stkCvxAsset.
     */
    function deposit(
        uint256 tokenId,
        uint256 amount,
        INPUT_TOKEN_TYPE inputTokenType,
        uint256 minAmountOut,
        bool isLock,
        bool isStake
    ) external {
        _deposit(tokenId, amount, inputTokenType, minAmountOut, isLock, isStake, false);
    }

    /**
     * @notice Withdraw stakingAsset (stkCvxAsset or cvxAsset) from the contract.
     *         Removing rewards before the end of a cycle leads to the loss of all accumulated rewards during this cycle.
     * @dev Withdrawing always removes first from the staked amount not yet eligible to rewards.
     * @param tokenId Staking Position to withdraw token from
     * @param amount Amount of stakingAsset to withdraw
     * @param isStakedAsset Determines if the withdrawn asset is a staked asset (stkCvxAsset)
     */
    function withdraw(uint256 tokenId, uint256 amount, bool isStakedAsset) external checkCompliance(tokenId) {
        require(amount != 0, "WITHDRAW_LTE_0");

        uint256 _cvgStakingCycle = stakingCycle;

        /// @dev Update the CycleInfo & the TokenInfo for the current & next cycle
        _updateAmountStakedWithdraw(tokenId, amount, _cvgStakingCycle);

        ICvxAssetStakerBuffer(address(buffer)).withdraw(msg.sender, amount, isStakedAsset);

        emit Withdraw(tokenId, msg.sender, _cvgStakingCycle, amount);
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                        INTERNALS/PRIVATES
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    function _deposit(
        uint256 tokenId,
        uint256 amount,
        INPUT_TOKEN_TYPE inputTokenType,
        uint256 minAmountOut,
        bool isLock,
        bool isStake,
        bool isEthDeposit
    ) internal {
        /// @dev Verify if deposits are paused
        require(!depositPaused, "DEPOSIT_PAUSED");
        /// @dev Verify if the staked amount is > 0
        require(amount != 0, "DEPOSIT_LTE_0");

        /// @dev Memorize storage data
        ICvxAssetStakerBuffer _stakerBuffer = ICvxAssetStakerBuffer(address(buffer));
        uint256 _cvgStakingCycle = stakingCycle;
        uint256 _tokenId;

        /// @dev If tokenId != 0, user deposits for an already existing position, we have so to check ownership
        if (tokenId != 0) {
            /// @dev Fetches, for the tokenId, the owner, the StakingPositionService linked to and the timestamp of unlocking
            stakingPositionManager.checkIncreaseDepositCompliance(tokenId, msg.sender);
            _tokenId = tokenId;
        }
        /// @dev Else, we increment the nextId to get the new tokenId & mint the NFT
        else {
            _tokenId = stakingPositionManager.mint(msg.sender);
        }

        /// @dev Staking with asset => We need to convert it to cvxAsset
        if (inputTokenType == INPUT_TOKEN_TYPE.asset) {
            amount = _mintOrSwapToCvxAsset(amount, minAmountOut, address(_stakerBuffer), isLock, isEthDeposit);
        }
        /// @dev Staking with cvxAsset
        else if (inputTokenType == INPUT_TOKEN_TYPE.cvxAsset) {
            cvxAsset.transferFrom(msg.sender, address(_stakerBuffer), amount);
        }
        /// @dev Staking with stkCvxCrv
        else {
            cvxAssetWrapper.transferFrom(msg.sender, address(_stakerBuffer), amount);
        }

        /// @dev Update the CycleInfo & the TokenInfo for the next cycle
        _updateAmountStakedDeposit(_tokenId, amount, _cvgStakingCycle + 1);

        if (isStake) {
            _stakerBuffer.stakeAllCvxAsset();
        }

        emit Deposit(_tokenId, msg.sender, _cvgStakingCycle, amount);
    }

    function _mintOrSwapToCvxAsset(
        uint256 amount,
        uint256 minAmountOut,
        address _stakerBuffer,
        bool isLock,
        bool isEthDeposit
    ) internal returns (uint256) {
        if (!isEthDeposit) {
            asset.transferFrom(msg.sender, address(this), amount);
        }

        /// @dev Swaps asset to cvxAsset in the Curve LP
        if (minAmountOut != 0) {
            uint256 deltaBalance = cvxAsset.balanceOf(_stakerBuffer);

            curvePool.exchange(0, 1, amount, minAmountOut, _stakerBuffer);

            deltaBalance = cvxAsset.balanceOf(_stakerBuffer) - deltaBalance;
            return deltaBalance;
        }
        /// @dev Deposit through asset depositor, is not 1:1
        else {
            uint256 deltaBalance = cvxAsset.balanceOf(address(this));
            assetDepositor.deposit(amount, isLock);
            deltaBalance = cvxAsset.balanceOf(address(this)) - deltaBalance;
            cvxAsset.transfer(_stakerBuffer, deltaBalance);
            return deltaBalance;
        }
    }
}
