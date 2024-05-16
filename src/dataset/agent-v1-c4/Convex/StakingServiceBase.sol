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

/// @title Cvg-Finance - StakingServiceBase
/// @notice Base of the Staking contracts of Convex integration.
///         Contains all common logic to contracts
/// @dev    Tracks staking shares per CvgCycle even for a cycle in the past.
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/ICvgControlTowerV2.sol";
import "../../interfaces/ICommonStruct.sol";
import "../../interfaces/Convex/ICvxStakingPositionManager.sol";
import "../../interfaces/Convex/IUnderlayingBuffer.sol";
import "../../interfaces/IUniv2Router.sol";
import "../../interfaces/IUniv3Router.sol";
import "../../interfaces/ICrvPool.sol";

contract StakingServiceBase is Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;
    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                            STRUCTS
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */
    /// @dev defines the information about an NFT
    struct TokenInfo {
        uint256 amountStaked;
        uint256 pendingStaked;
    }

    struct NextClaimableCycles {
        uint128 nextClaimableCvg;
        uint128 nextClaimableCvx;
    }

    /// @dev defines the information about a CVG cycle
    struct CycleInfo {
        uint256 cvgRewardsAmount;
        uint256 totalStaked;
        bool isCvxProcessed;
    }

    struct ClaimableCyclesAndAmounts {
        uint256 cycleClaimable;
        uint256 cvgRewards;
        ICommonStruct.TokenAmount[] cvxRewards;
    }

    enum PoolType {
        DEACTIVATED,
        UNIV2,
        UNIV3,
        CURVE
    }
    struct PoolEthInfo {
        uint24 fee; //UNIV3
        uint256 indexEth; //Curve
        ICrvPool poolCurve; //Curve
        PoolType poolType;
        address token;
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                            EVENTS
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */
    event Deposit(uint256 indexed tokenId, address account, uint256 indexed cycleId, uint256 amount);
    event Withdraw(uint256 indexed tokenId, address account, uint256 indexed cycleId, uint256 amount);
    event CvgCycleProcess(uint256 indexed cycleId, uint256 rewardAmount);
    event ClaimCvgMultiple(uint256 indexed tokenId, address account);
    event ClaimCvgCvxMultiple(uint256 indexed tokenId, address account);
    event ProcessCvxRewards(uint256 indexed cycleId, address operator, ICommonStruct.TokenAmount[] tokenAmounts);

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IUniv3Router private constant UNISWAPV3_ROUTER = IUniv3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniv2Router private constant UNISWAPV2_ROUTER = IUniv2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    /// @dev Convergence control tower
    ICvgControlTowerV2 public constant cvgControlTower = ICvgControlTowerV2(0xB0Afc8363b8F36E0ccE5D54251e20720FfaeaeE7);

    /// @dev Convergence token
    ICvg public constant CVG = ICvg(0x97efFB790f2fbB701D88f89DB4521348A2B77be8);

    /// @dev ID created for the reentrancy lock
    bytes32 private constant LOCK = keccak256("LOCK");

    /// @notice Deposits are paused when true
    bool public depositPaused;

    /// @notice Receiver of all Convex rewards.
    ICvxRewardDistributor public cvxRewardDistributor;

    /// @notice Staking position manager.
    ICvxStakingPositionManager public stakingPositionManager;

    /// @notice Address of the paired buffer accumulating and sending rewards on procesCvxRewards call
    IUnderlayingBuffer public buffer;

    /// @dev Base underlying asset. ex : CRV
    IERC20 public asset;

    /// @notice Cvg staking cycle for this staking contract
    uint128 public stakingCycle;

    /// @notice Maximum amount of rewards claimable through CVX,
    ///         is incremented during the processCvxRewards each time a new reward ERC20 is distributed
    uint128 public numberOfUnderlyingRewards;

    /// @notice Token symbol
    string public symbol;

    /// @dev infos used to swap ETH into the staking asset
    PoolEthInfo public poolEthInfo;

    mapping(uint256 => CycleInfo) internal _cycleInfo; // cycleId => cycleInfos

    /**
     *  @notice Get the global information of a cycle.
     *  Contains the total staked and the distributed amount during the {cycleId}.
     *  Allows to know if rewards have been processed for a cycle or not.
     * @param cycleId Id of the cycle to get the information
     * @return Returns a struct containing the totalStaked on a cycle,
     */
    function cycleInfo(uint256 cycleId) external view returns (CycleInfo memory) {
        return _cycleInfo[cycleId];
    }

    mapping(uint256 => mapping(uint256 => TokenInfo)) internal _tokenInfoByCycle; // cycleId => tokenId => tokenInfos

    /**
     * @notice Returns the information of a Staking position at a specified cycle Id.
     * @param cycleId Information of the token will be at this cycle
     * @param tokenId Token Id of the Staking position
     * @return amountStaked : Amount used in the share computation.
     *         pendingStaked : Staked amount not yet eligible for rewards, is removed in priority during a withdraw.
     *         isCvgRewardsClaimed : Allows to know if the position has already claimed the Cvg rewards for this cycle.
     *         isCvxRewardsClaimed : Allows to know if the position has already claimed the StakeDao rewards for this cycle.
     */
    function tokenInfoByCycle(uint256 cycleId, uint256 tokenId) external view returns (TokenInfo memory) {
        return _tokenInfoByCycle[cycleId][tokenId];
    }

    mapping(uint256 => uint256[]) internal _stakingHistoryByToken; // tokenId => cycleIds

    /** @notice Array of cycleId where staking/withdraw actions occured in the past.
     * We need this array in order to be able to claim for an old cycle.
     * @param tokenId Reads the actions history of this Token ID
     * @param index   Index of the element to return from the history array
     * @return A Cycle ID
     */
    function stakingHistoryByToken(uint256 tokenId, uint256 index) external view returns (uint256) {
        return _stakingHistoryByToken[tokenId][index];
    }

    mapping(IERC20 => uint256) internal _tokenToId; // tokenAddress => cvxRewardId

    /** @notice Get the Id of the ERC20 distributed during the StakeDao distribution
     *  @param erc20Address erc20 address of the reward token from StakeDao
     *  @return Id of the StakeDao reward
     */
    function tokenToId(IERC20 erc20Address) external view returns (uint256) {
        return _tokenToId[erc20Address];
    }

    mapping(uint256 => mapping(uint256 => ICommonStruct.TokenAmount)) internal _cvxRewardsByCycle; // cycleId => cvxRewardId => TokenAmount

    /** @notice Pair of token/amount distributed for all stakers per cycleId per Id of ERC20 CVX rewards.
     *  @param cycleId         CycleId where the rewards distribution occurred
     *  @param cvxRewardsIndex Index of the token rewarded
     *  @return The reward token and its amount
     */
    function cvxRewardsByCycle(
        uint256 cycleId,
        uint256 cvxRewardsIndex
    ) external view returns (ICommonStruct.TokenAmount memory) {
        return _cvxRewardsByCycle[cycleId][cvxRewardsIndex];
    }

    mapping(uint256 => NextClaimableCycles) internal _nextClaims; // tokenId => lastCycleClaimed

    /** @notice Next cycle to be claimed on a position for Cvg & StakeDao process.
     *  @param tokenId Id of the position to get the next cycle claimable.
     *  @return The next claimable cycles where a claimed occured.
     */
    function nextClaims(uint256 tokenId) external view returns (NextClaimableCycles memory) {
        return _nextClaims[tokenId];
    }

    uint256[50] private __gap;

    modifier lockReentrancy() {
        /// @dev Reentrancy lock check
        require(_tload(LOCK) == 0, "NOT_LOCKED");

        /// @dev Reentrancy lock set
        _tstore(LOCK, 1);

        _;

        /// @dev Reentrancy lock clear
        _tstore(LOCK, 0);
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                      CONSTRUCTOR & INIT
  =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                    MODIFIERS & PRE CHECKS
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */
    modifier checkCompliance(uint256 tokenId) {
        stakingPositionManager.checkTokenFullCompliance(tokenId, msg.sender);
        _;
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                        USER EXTERNAL
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    /**
     * @notice Claim CVG rewards for a Staking Position on one OR several already passed AND not claimed cycles.
     * @dev    CVG are minted on the fly to the owner of the Staking Position
     * @param tokenId   Staking Position id to claim the rewards of.
     */
    function claimCvgRewards(uint256 tokenId) external checkCompliance(tokenId) {
        uint128 actualCycle = stakingCycle;

        uint128 nextClaimableCvg = _nextClaims[tokenId].nextClaimableCvg;

        uint256 lengthHistory = _stakingHistoryByToken[tokenId].length;

        /// @dev If never claimed on this token
        if (nextClaimableCvg == 0) {
            /// @dev Set the lastClaimed as the first action.
            nextClaimableCvg = uint128(_stakingHistoryByToken[tokenId][0]);
        }

        require(actualCycle > nextClaimableCvg, "ALL_CVG_CLAIMED_FOR_NOW");

        uint256 _totalAmount;
        for (; nextClaimableCvg < actualCycle; ) {
            /// @dev Retrieve the staked amount at the iterated cycle for this Staking position
            uint256 tokenStaked = _stakedAmountEligibleAtCycle(nextClaimableCvg, tokenId, lengthHistory);
            /// @dev If staked amount are eligible to rewards on the iterated cycle.
            if (tokenStaked != 0) {
                /// @dev Computes the staking share of the Staking Position compare to the total Staked.
                ///      By multiplying this share by the total CVG distributed for the cycle, we get the claimable amount.
                /// @dev increments the total amount in CVG to mint to the user
                _totalAmount +=
                    (tokenStaked * _cycleInfo[nextClaimableCvg].cvgRewardsAmount) /
                    _cycleInfo[nextClaimableCvg].totalStaked;
            }

            unchecked {
                ++nextClaimableCvg;
            }
        }
        require(_totalAmount > 0, "NO_CVG_TO_CLAIM");

        /// @dev set the cycle as claimed for the NFT
        _nextClaims[tokenId].nextClaimableCvg = actualCycle;

        /// @dev mint CVG to user
        CVG.mintStaking(msg.sender, _totalAmount);

        emit ClaimCvgMultiple(tokenId, msg.sender);
    }

    /**
     * @notice Claim CVG and CVX rewards for a Staking Position on one OR several already passed AND not claimed cycles.
     *         Also allows to claim CVX rewards only if CVG rewards
     * @dev    CVG are minted on the fly to the owner of the Staking Position
     * @param _tokenId    of the Position to claim the rewards on
     * @param _minCvgCvxAmountOut  Minimum amount of cvgCVX to receive in case of a pool exchange
     * @param _isConvert     If true, converts all CVX into CvgCVX.
     */
    function claimCvgCvxRewards(
        uint256 _tokenId,
        uint256 _minCvgCvxAmountOut,
        bool _isConvert
    ) external checkCompliance(_tokenId) {
        (uint256 cvgClaimable, ICommonStruct.TokenAmount[] memory tokenAmounts) = _claimCvgCvxRewards(_tokenId);

        cvxRewardDistributor.claimCvgCvxSimple(msg.sender, cvgClaimable, tokenAmounts, _minCvgCvxAmountOut, _isConvert);

        emit ClaimCvgCvxMultiple(_tokenId, msg.sender);
    }

    /**
     * @notice Claim CVG and CVX rewards for a Staking Position on one OR several already passed AND not claimed cycles.
     *         Also allows to claim CVX rewards only if CVG rewards haven't been already claimed.
     * @dev    CVG are minted on the fly to the owner of the Staking Position
     * @param tokenId    of the Position to claim the rewards on
     * @param operator   used if called by the Reward Distributor, allows to claim of several tokenId at the same time
     */
    function claimCvgCvxMultiple(
        uint256 tokenId,
        address operator
    ) external returns (uint256, ICommonStruct.TokenAmount[] memory) {
        /// @dev Only the CvxRewardDistributor can claim this function.
        require(msg.sender == address(cvxRewardDistributor), "NOT_CVX_REWARD_DISTRIBUTOR");

        (uint256 cvgClaimable, ICommonStruct.TokenAmount[] memory cvxRewards) = _claimCvgCvxRewards(tokenId);

        emit ClaimCvgCvxMultiple(tokenId, operator);
        return (cvgClaimable, cvxRewards);
    }

    /**
     * @notice Claim CVG and CVX rewards for a Staking Position on one OR several already passed AND not claimed cycles.
     *         Also allows to claim CVX rewards only if CVG rewards
     * @dev    CVG are minted on the fly to the owner of the Staking Position
     * @param tokenId    of the Position to claim the rewards on.
     */
    function _claimCvgCvxRewards(
        uint256 tokenId
    ) internal returns (uint256, ICommonStruct.TokenAmount[] memory tokenAmounts) {
        uint128 nextClaimableCvg = _nextClaims[tokenId].nextClaimableCvg;
        uint128 nextClaimableCvx = _nextClaims[tokenId].nextClaimableCvx;
        uint128 actualCycle = stakingCycle;
        uint256 lengthHistory = _stakingHistoryByToken[tokenId].length;

        /// @dev If never claimed on this token
        if (nextClaimableCvx == 0) {
            /// @dev Set the lastClaimed as the first action.
            nextClaimableCvx = uint128(_stakingHistoryByToken[tokenId][0]);
        }
        require(actualCycle > nextClaimableCvx, "ALL_CVX_CLAIMED_FOR_NOW");

        /// @dev Total amount of CVG, accumulated through all cycles and minted at the end of the function
        uint256 _cvgClaimable;

        uint256 maxLengthRewards = nextClaimableCvx;
        /// @dev Array of all rewards from StakeDao, all cycles are accumulated in this array and transfer at the end of the function
        ICommonStruct.TokenAmount[] memory _totalRewardsClaimable = new ICommonStruct.TokenAmount[](maxLengthRewards);

        uint256 newLastClaimCvx;
        bool isCvxRewards;
        for (; nextClaimableCvx < actualCycle; ) {
            /// @dev Retrieve the amount staked at the iterated cycle for this Staking position.
            uint256 tokenStaked = _stakedAmountEligibleAtCycle(nextClaimableCvx, tokenId, lengthHistory);
            /// @dev Retrieve the total amount staked on the iterated cycle.
            uint256 totalStaked = _cycleInfo[nextClaimableCvx].totalStaked;
            /// @dev If staked amount are eligible to rewards on the iterated cycle.
            if (tokenStaked != 0) {
                /// @dev CVG PART
                ///      If the CVG rewards haven't been claimed on the iterated cycle
                if (nextClaimableCvg <= nextClaimableCvx) {
                    /// @dev Computes the staking share of the Staking Position compared to the total Staked.
                    ///      By multiplying this share by the total CVG distributed for the cycle, we get the claimable amount.
                    /// @dev Increments the total amount in CVG to mint to the user
                    _cvgClaimable += ((tokenStaked * _cycleInfo[nextClaimableCvx].cvgRewardsAmount) / totalStaked);
                }

                /// @dev StakeDao PART
                /// @dev We only do the CVX computation when CVX has been processed for the iterated cycle.
                if (_cycleInfo[nextClaimableCvx].isCvxProcessed) {
                    for (uint256 erc20Id; erc20Id < maxLengthRewards; ) {
                        /// @dev Get the ERC20 and the amount distributed on the iterated cycle.
                        ICommonStruct.TokenAmount memory rewardAsset = _cvxRewardsByCycle[nextClaimableCvx][
                            erc20Id + 1
                        ];

                        /// @dev If there is an amount of this rewardAsset distributed on this cycle
                        if (rewardAsset.amount != 0) {
                            isCvxRewards = true;
                            /// @dev if the token is set for the first time
                            if (address(_totalRewardsClaimable[erc20Id].token) == address(0)) {
                                /// @dev Get the ERC20 and the amount distributed on the iterated cycle
                                _totalRewardsClaimable[erc20Id].token = rewardAsset.token;
                            }
                            /// @dev Computes the staking share of the Staking Position compared to the total Staked.
                            ///      By multiplying this share by the total of the StakeDao reward distributed for the cycle, we get the claimable amount.
                            /// @dev increment the total rewarded amount for the iterated ERC20
                            _totalRewardsClaimable[erc20Id].amount += ((tokenStaked * rewardAsset.amount) /
                                totalStaked);
                        }
                        unchecked {
                            ++erc20Id;
                        }
                    }
                    newLastClaimCvx = nextClaimableCvx;
                }
            }

            unchecked {
                ++nextClaimableCvx;
            }
        }
        require(_cvgClaimable != 0 || isCvxRewards, "NO_REWARDS_CLAIMABLE");

        /// @dev If last CVX cycle claimed is the last cycle, we can setup the next cycle to claim as the actual cycle
        if (newLastClaimCvx == actualCycle - 1) {
            _nextClaims[tokenId].nextClaimableCvx = actualCycle;
        }
        /// @dev Else, we don't know yet if the last cycle has been distributed, so we put the last cycle as the next CVX Cycle to claim.
        else {
            _nextClaims[tokenId].nextClaimableCvx = actualCycle - 1;
        }

        _nextClaims[tokenId].nextClaimableCvg = actualCycle;

        return (_cvgClaimable, _totalRewardsClaimable);
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                    CYCLE PROCESSING 
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    /**
     * @notice launches the CVG reward process.
     * @dev    Updates the internal stakingCycle, writes the amount of CVG distributed for the finished cycle and reports the totalStaked on the next cycle.
     * @param amount Amount of Cvg to distribute as rewards for the current cycle, computed by the CvgRewards
     */
    function processStakersRewards(uint256 amount) external {
        require(msg.sender == address(cvgControlTower.cvgRewards()), "NOT_CVG_REWARDS");

        /// @dev Increments the cvg cycle
        uint256 _cvgStakingCycle = stakingCycle++;

        /// @dev Sets the amount computed by the CvgRewards ( related to Gauge weights ) in the triggered cycle.
        _cycleInfo[_cvgStakingCycle].cvgRewardsAmount = amount;
        /// @dev Reports the old totalStaked on the new cycle
        _cycleInfo[_cvgStakingCycle + 2].totalStaked = _cycleInfo[_cvgStakingCycle + 1].totalStaked;

        emit CvgCycleProcess(_cvgStakingCycle, amount);
    }

    /**
     * @notice Pull Rewards from the paired buffer.
     *         Associate these rewards to the last cycle.
     *         Is callable only one time per cycle, after Cvg rewards have been processed.
     * @dev    We need to wait that processCvgRewards writes the final totalStaked amount on a cycle before processing CVX rewards.
     *         As we are merging all rewards in the claimCvgCvx & that rewards from buffer may differ, rewards from StakeDao must always be written at the same index.
     *         We are so incrementing the numberOfCvxRewards for each new token distributed in the StakeDao rewards.
     */
    function processCvxRewards() external {
        /// @dev Retrieve last staking cycle
        uint256 _cvgStakingCycle = stakingCycle - 1;
        /// @dev Allows to don't distribute rewards if no stakers was staked for this cycle.
        require(_cycleInfo[_cvgStakingCycle].totalStaked != 0, "NO_STAKERS");
        require(!_cycleInfo[_cvgStakingCycle].isCvxProcessed, "CVX_REWARDS_ALREADY_PROCESSED");

        /// @dev call and returns tokens and amounts returned in rewards by the gauge
        ICommonStruct.TokenAmount[] memory _rewardAssets = buffer.pullRewards(msg.sender);

        for (uint256 i; i < _rewardAssets.length; ) {
            IERC20 _token = _rewardAssets[i].token;
            uint256 erc20Id = _tokenToId[_token];
            if (erc20Id == 0) {
                uint256 _numberOfCvxRewards = ++numberOfUnderlyingRewards;
                _tokenToId[_token] = _numberOfCvxRewards;
                erc20Id = _numberOfCvxRewards;
            }

            _cvxRewardsByCycle[_cvgStakingCycle][erc20Id] = ICommonStruct.TokenAmount({
                token: _token,
                amount: _cvxRewardsByCycle[_cvgStakingCycle][erc20Id].amount + _rewardAssets[i].amount
            });

            unchecked {
                ++i;
            }
        }

        _cycleInfo[_cvgStakingCycle].isCvxProcessed = true;

        emit ProcessCvxRewards(_cvgStakingCycle, msg.sender, _rewardAssets);
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                            PUBLIC
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    /**
     *  @notice Finds NFT staked amount eligible for rewards for a specified _cycleId.
     *          Finds the latest deposit or withdraw (last action) before the given _cycleId to retrieve the staked amount of the NFT at this period
     *  @param _tokenId  ID of the token to find the staked amount eligible to rewards
     *  @param _cycleId  Cycle ID  where to find the staked amount eligible to rewards
     *  @return The staked amount eligible to rewards
     */
    function stakedAmountEligibleAtCycle(
        uint256 _cycleId,
        uint256 _tokenId,
        uint256 _actualCycle
    ) external view returns (uint256) {
        /// @dev _cycleId be greater or equal than the cycle of the contract
        if (_cycleId >= _actualCycle) return 0;

        /// @dev if no action has been performed on this position, it means it's not created so returns 0
        uint256 length = _stakingHistoryByToken[_tokenId].length;
        if (length == 0) return 0;

        /// @dev If the cycleId is smaller than the first time a staking action occured on
        if (_cycleId < _stakingHistoryByToken[_tokenId][0]) return 0;

        uint256 historyCycle;
        /// @dev Finds the cycle of the last first action performed before the {_cycleId}
        for (uint256 i = length - 1; ; ) {
            historyCycle = _stakingHistoryByToken[_tokenId][i];
            if (historyCycle > _cycleId) {
                unchecked {
                    --i;
                }
            } else {
                break;
            }
        }

        /// @dev Return the amount staked on this cycle
        return _tokenInfoByCycle[historyCycle][_tokenId].amountStaked;
    }

    /**
     *  @dev Finds NFT staked amount eligible for rewards for a specified _cycleId.
     *          Finds the latest deposit or withdraw (last action) before the given _cycleId to retrieve the staked amount of the NFT at this period
     *  @param cycleId  ID of the token to find the staked amount eligible to rewards
     *  @param tokenId  Cycle ID  where to find the staked amount eligible to rewards
     *  @param lengthHistory  Cycle ID  where to find the staked amount eligible to rewards
     *  @return The staked amount eligible to rewards
     */
    function _stakedAmountEligibleAtCycle(
        uint256 cycleId,
        uint256 tokenId,
        uint256 lengthHistory
    ) internal view returns (uint256) {
        uint256 i = lengthHistory - 1;
        uint256 historyCycle = _stakingHistoryByToken[tokenId][i];
        /// @dev Finds the cycle of the last first action performed before the {_cycleId}
        while (historyCycle > cycleId) {
            historyCycle = _stakingHistoryByToken[tokenId][i];
            unchecked {
                --i;
            }
        }

        return _tokenInfoByCycle[historyCycle][tokenId].amountStaked;
    }

    /**
     *  @notice Retrieves the total amount staked for a Staking Position.
     *  @dev    Uses the array of all Staking/Withdraw history to retrieve the last staking value updated in case a user doesn't stake/withdraw at each cycle.
     *  @param _tokenId  Id of the Staking position.
     *  @return The total amount staked on this position.
     */
    function tokenTotalStaked(uint256 _tokenId) public view returns (uint256) {
        /// @dev Retrieve the amount of cycle with action on it
        uint256 _cycleLength = _stakingHistoryByToken[_tokenId].length;
        /// @dev If 0, means that no action has ever been made on this tokenId
        if (_cycleLength == 0) return 0;

        /// @dev Retrieves the last cycle where an action occured
        /// @dev Fetches the amount staked on this cycle in tokenInfoByCycle
        return _tokenInfoByCycle[_stakingHistoryByToken[_tokenId][_cycleLength - 1]][_tokenId].amountStaked;
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                        INTERNALS/PRIVATES
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */
    /**
     *  @dev Updates NFT staking information on deposit.
     *       When a user stakes, it's always linking this staked amount for the next cycle.
     *       Increase also the total staked amount for the next cycle.
     *       Tracks also for cycle in the past the amount staked for each positions.
     *  @param tokenId    Id of the Staking position
     *  @param amount     Amount of staked asset to deposit
     *  @param nextCycle  Id of the next cvg cycle
     */
    function _updateAmountStakedDeposit(uint256 tokenId, uint256 amount, uint256 nextCycle) internal {
        /// @dev Get the amount already staked on this position and adds it the new deposited amount
        uint256 _newTokenStakedAmount = tokenTotalStaked(tokenId) + amount;

        /// @dev updates the amount staked for this tokenId for the next cvgCycle
        _tokenInfoByCycle[nextCycle][tokenId].amountStaked = _newTokenStakedAmount;

        /**
         * @dev Increments the pending amount with the deposited amount.
         *      The pending amount is the staked amount still in accumulation mode.
         *      Is always removed from the witdhraw before the amountStaked.
         */
        _tokenInfoByCycle[nextCycle][tokenId].pendingStaked += amount;

        /// @dev increments the total amount staked on the Staking Contract for the nextCycle
        _cycleInfo[nextCycle].totalStaked += amount;

        uint256 cycleLength = _stakingHistoryByToken[tokenId].length;

        /// @dev If it's the mint of the position
        if (cycleLength == 0) {
            _stakingHistoryByToken[tokenId].push(nextCycle);
        }
        /// @dev Else it's not the mint of the position
        else {
            /// @dev fetches the _lastActionCycle where an action has been performed
            uint256 _lastActionCycle = _stakingHistoryByToken[tokenId][cycleLength - 1];

            /// @dev if this _lastActionCycle is less than the next cycle => it's the first deposit done on this cycle
            if (_lastActionCycle < nextCycle) {
                uint256 currentCycle = nextCycle - 1;
                /// @dev if this _lastActionCycle is less than the current cycle =>
                ///      No deposits occurred on the last cycle & no withdraw on this cycle
                if (_lastActionCycle < currentCycle) {
                    /// @dev we have so to checkpoint the current cycle
                    _stakingHistoryByToken[tokenId].push(currentCycle);
                    /// @dev and to report the amountStaked of the lastActionCycle to the currentCycle
                    _tokenInfoByCycle[currentCycle][tokenId].amountStaked = _tokenInfoByCycle[_lastActionCycle][tokenId]
                        .amountStaked;
                }
                /// @dev checkpoint the next cycle
                _stakingHistoryByToken[tokenId].push(nextCycle);
            }
        }
    }

    /**
     *  @dev Updates NFT and total amount staked for a tokenId when a withdraw action occurs.
     *       It will first remove amount in pending on the next cycle to remove first the amount not eligible to rewards for the current cycle.
     *       If the withdrawn amount is greater than the pending, we start to withdraw staked token from the next cycle then the leftover from the staking eligible to rewards.
     *  @param tokenId      tokenId to withdraw on
     *  @param amount       of stakedAsset to withdraw
     *  @param currentCycle id of the Cvg cycle
     */
    function _updateAmountStakedWithdraw(uint256 tokenId, uint256 amount, uint256 currentCycle) internal {
        uint256 nextCycle = currentCycle + 1;
        /// @dev get pending staked amount not already eligible for rewards
        uint256 nextCyclePending = _tokenInfoByCycle[nextCycle][tokenId].pendingStaked;
        /// @dev Get amount already staked on the token when the last operation occurred
        uint256 _tokenTotalStaked = tokenTotalStaked(tokenId);

        /// @dev Verify that the withdrawn amount is lower than the total staked amount
        require(amount <= _tokenTotalStaked, "WITHDRAW_EXCEEDS_STAKED_AMOUNT");
        uint256 _newTokenStakedAmount = _tokenTotalStaked - amount;

        /// @dev update last amountStaked for current cycle
        uint256 _lastActionCycle = _stakingHistoryByToken[tokenId][_stakingHistoryByToken[tokenId].length - 1];
        uint256 _lastStakedAmount;

        /// @dev if this _lastActionCycle is less than the current cycle =>
        ///      No deposits occurred on the last cycle & no withdraw on this cycle
        if (_lastActionCycle < currentCycle) {
            /// @dev we have so to checkpoint the current cycle
            _stakingHistoryByToken[tokenId].push(currentCycle);
            /// @dev and to report the amountStaked of the lastActionCycle to the currentCycle
            _lastStakedAmount = _tokenInfoByCycle[_lastActionCycle][tokenId].amountStaked;
        } else {
            _lastStakedAmount = _tokenInfoByCycle[currentCycle][tokenId].amountStaked;
        }

        /// @dev updates the amount staked for this position for the next cycle
        _tokenInfoByCycle[nextCycle][tokenId].amountStaked = _newTokenStakedAmount;

        /// @dev Fully removes the amount from the totalStaked of next cycle.
        ///      This withdrawn amount is not anymore eligible to the distribution of the next cycle.
        _cycleInfo[nextCycle].totalStaked -= amount;

        /// @dev If there is some token deposited on this cycle ( pending token )
        ///      We first must to remove them before the tokens that are already accumulating rewards
        if (nextCyclePending != 0) {
            /// @dev If the amount to withdraw is lower or equal to the pending amount
            if (nextCyclePending >= amount) {
                /// @dev we decrement this pending amount
                _tokenInfoByCycle[nextCycle][tokenId].pendingStaked -= amount;
            }
            /// @dev Else, the amount to withdraw is greater than the pending
            else {
                /// @dev Computes the amount to remove from the staked amount eligible to rewards
                amount -= nextCyclePending;

                /// @dev Fully removes the pending amount for next cycle
                delete _tokenInfoByCycle[nextCycle][tokenId].pendingStaked;

                /// @dev Removes the adjusted amount to the staked total amount eligible to rewards
                _cycleInfo[currentCycle].totalStaked -= amount;

                /// @dev Removes the adjusted amount to the staked position amount eligible to rewards
                _tokenInfoByCycle[currentCycle][tokenId].amountStaked = _lastStakedAmount - amount;
            }
        }
        /// @dev If nothing has been desposited on this cycle
        else {
            /// @dev removes the withdrawn amount to the staked total amount eligible to rewards
            _cycleInfo[currentCycle].totalStaked -= amount;
            /// @dev removes the withdrawn amount to the staked token amount eligible to rewards
            _tokenInfoByCycle[currentCycle][tokenId].amountStaked = _lastStakedAmount - amount;
        }
    }

    function _depositEth(uint256 amountIn, uint256 amountOutMin) internal returns (uint256 amountOut) {
        PoolEthInfo memory _poolEthInfo = poolEthInfo;
        require(_poolEthInfo.poolType != PoolType.DEACTIVATED, "DEPOSIT_ETH_PAUSED");
        if (_poolEthInfo.poolType == PoolType.UNIV2) {
            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = _poolEthInfo.token;
            uint256[] memory amounts = UNISWAPV2_ROUTER.swapExactETHForTokens{value: amountIn}(
                amountOutMin,
                path,
                address(this),
                block.timestamp + 1000
            );
            amountOut = amounts[1];
        } else if (_poolEthInfo.poolType == PoolType.UNIV3) {
            amountOut = UNISWAPV3_ROUTER.exactInputSingle{value: amountIn}(
                IUniv3Router.ExactInputSingleParams({
                    tokenIn: WETH,
                    tokenOut: _poolEthInfo.token,
                    fee: _poolEthInfo.fee,
                    recipient: address(this),
                    deadline: block.timestamp + 1000,
                    amountIn: amountIn,
                    amountOutMinimum: amountOutMin,
                    sqrtPriceLimitX96: 0
                })
            );
        } else if (_poolEthInfo.poolType == PoolType.CURVE) {
            (uint256 tokenInIndex, uint256 tokenOutIndex) = _poolEthInfo.indexEth == 0 ? (0, 1) : (1, 0);
            amountOut = _poolEthInfo.poolCurve.exchange{value: amountIn}(
                tokenInIndex,
                tokenOutIndex,
                amountIn,
                amountOutMin,
                true
            );
        }
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                            INFO
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    /**
     *  @notice Fetches all data needed for the NFT logo being displayed
     *  @param tokenId of the position to get informations
     */
    function stakingInfo(uint256 tokenId) public view returns (ICvxStakingPositionService.StakingInfo memory) {
        uint256 pending = _tokenInfoByCycle[stakingCycle + 1][tokenId].pendingStaked;

        (uint256 _cvgClaimable, ICommonStruct.TokenAmount[] memory _cvxRewardsClaimable) = getAllClaimableAmounts(
            tokenId
        );

        return (
            ICvxStakingPositionService.StakingInfo({
                tokenId: tokenId,
                symbol: symbol,
                pending: pending,
                totalStaked: tokenTotalStaked(tokenId) - pending,
                cvgClaimable: _cvgClaimable,
                cvxClaimable: _cvxRewardsClaimable
            })
        );
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                            GETTERS
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    /**
     *  @notice Fetches and aggregates all claimable CVG, for a _tokenId.
     *  @param tokenId  Id of the token to fetch the amount of rewards from.
     *  @return The total value of claimable CVG on this staking position.
     */
    function getAllClaimableCvgAmount(uint256 tokenId) public view returns (uint256) {
        uint256 actualCycle = stakingCycle;
        uint128 nextClaimableCvg = _nextClaims[tokenId].nextClaimableCvg;
        /// @dev As claim claimCvgCvxRewards claims also Cvg, if the last claim is a cvx claim, we consider it as the lastClaimed cycle for Cvg.
        ///      Else we take the lastClaimed on Cvg.
        uint256 lengthHistory = _stakingHistoryByToken[tokenId].length;

        /// @dev If never claimed on this token
        if (nextClaimableCvg == 0) {
            /// @dev Get the length of the history
            nextClaimableCvg = uint128(_stakingHistoryByToken[tokenId][0]);
        }

        if (actualCycle <= nextClaimableCvg) {
            return 0;
        }

        uint256 _totalAmount;
        for (; nextClaimableCvg < actualCycle; ) {
            /// @dev Retrieve the staked amount at the iterated cycle for this Staking position
            uint256 tokenStaked = _stakedAmountEligibleAtCycle(nextClaimableCvg, tokenId, lengthHistory);
            uint256 claimableAmount;
            /// @dev If staked amount are eligible to rewards on the iterated cycle.
            if (tokenStaked != 0) {
                /// @dev Computes the staking share of the Staking Position compare to the total Staked.
                ///      By multiplying this share by the total CVG distributed for the cycle, we get the claimable amount.
                claimableAmount =
                    (tokenStaked * _cycleInfo[nextClaimableCvg].cvgRewardsAmount) /
                    _cycleInfo[nextClaimableCvg].totalStaked;
                /// @dev increments the total amount in CVG to mint to the user
                _totalAmount += claimableAmount;
            }

            unchecked {
                ++nextClaimableCvg;
            }
        }

        return _totalAmount;
    }

    /**
     *  @notice Computes, for a {_tokenId}, the total rewards claimable in CVG and from CVX for a range of cycle bewteen {fromCycle} and {toCycle}.
     *          For CVX rewards, it aggregates amounts of same token from different cycles in the returned array.
     *  @param tokenId  Staking position ID able ton claim the rewards
     *  @return total amount of Cvg claimable by the {_tokenId} in the cycle range
     *  @return array of total token / amount pair claimable by the {_tokenId} in the cycle range
     */
    function getAllClaimableAmounts(uint256 tokenId) public view returns (uint256, ICommonStruct.TokenAmount[] memory) {
        uint128 nextClaimableCvg = _nextClaims[tokenId].nextClaimableCvg;
        uint128 nextClaimableCvx = _nextClaims[tokenId].nextClaimableCvx;
        uint128 actualCycle = stakingCycle;
        uint256 lengthHistory = _stakingHistoryByToken[tokenId].length;

        /// @dev If never claimed on this token
        if (nextClaimableCvx == 0) {
            /// @dev Get the length of the history
            nextClaimableCvx = uint128(_stakingHistoryByToken[tokenId][0]);
        }

        uint256 maxLengthRewards = numberOfUnderlyingRewards;
        uint256 realLengthRewards;
        ICommonStruct.TokenAmount[] memory _totalCvxRewardsClaimable = new ICommonStruct.TokenAmount[](
            maxLengthRewards
        );

        uint256 _cvgClaimable;

        for (; nextClaimableCvx < actualCycle; ) {
            /// @dev Retrieve the amount staked at the iterated cycle for this Staking position.
            uint256 tokenStaked = _stakedAmountEligibleAtCycle(nextClaimableCvx, tokenId, lengthHistory);
            /// @dev Retrieve the total amount staked on the iterated cycle.
            uint256 totalStaked = _cycleInfo[nextClaimableCvx].totalStaked;
            /// @dev If staked amount are eligible to rewards on the iterated cycle.
            if (tokenStaked != 0) {
                /// @dev CVG PART
                ///      If the CVG rewards haven't been claimed on the iterated cycle
                if (nextClaimableCvg <= nextClaimableCvx) {
                    /// @dev Computes the staking share of the Staking Position compared to the total Staked.
                    ///      By multiplying this share by the total CVG distributed for the cycle, we get the claimable amount.
                    uint256 cvgClaimableAmount = (tokenStaked * _cycleInfo[nextClaimableCvx].cvgRewardsAmount) /
                        totalStaked;
                    /// @dev increments the total amount in CVG to mint to the user
                    _cvgClaimable += cvgClaimableAmount;
                }

                /// @dev StakeDao PART
                /// @dev We only do the CVX computation when CVX has been processed for the iterated cycle.
                if (_cycleInfo[nextClaimableCvx].isCvxProcessed) {
                    for (uint256 erc20Id; erc20Id < maxLengthRewards; ) {
                        /// @dev Get the ERC20 and the amount distributed during on the iterated cycle
                        ICommonStruct.TokenAmount memory rewardAsset = _cvxRewardsByCycle[nextClaimableCvx][
                            erc20Id + 1
                        ];

                        /// @dev If there is no amount of this rewardAsset distributed on this cycle
                        if (rewardAsset.amount != 0) {
                            /// @dev if the token is set for the first time
                            if (address(_totalCvxRewardsClaimable[erc20Id].token) == address(0)) {
                                _totalCvxRewardsClaimable[erc20Id].token = rewardAsset.token;
                                ++realLengthRewards;
                            }
                            /// @dev Computes the staking share of the Staking Position compare to the total Staked.
                            ///      By multiplying this share by the total of the StakeDao reward distributed for the cycle, we get the claimable amount.
                            uint256 rewardAmount = (tokenStaked * rewardAsset.amount) / totalStaked;

                            /// @dev increment the total rewarded amount for the iterated ERC20
                            _totalCvxRewardsClaimable[erc20Id].amount += rewardAmount;
                        }
                        unchecked {
                            ++erc20Id;
                        }
                    }
                }
            }

            unchecked {
                ++nextClaimableCvx;
            }
        }

        /// @dev this array should have the right length
        ICommonStruct.TokenAmount[] memory _cvxRewardsClaimable = new ICommonStruct.TokenAmount[](realLengthRewards);

        delete realLengthRewards;
        for (uint256 i; i < _totalCvxRewardsClaimable.length; ) {
            if (_totalCvxRewardsClaimable[i].amount != 0) {
                _cvxRewardsClaimable[realLengthRewards++] = ICommonStruct.TokenAmount({
                    token: _totalCvxRewardsClaimable[i].token,
                    amount: _totalCvxRewardsClaimable[i].amount
                });
            }
            unchecked {
                ++i;
            }
        }

        return (_cvgClaimable, _cvxRewardsClaimable);
    }

    /**
     * @notice Get an array of token and reward associated to the Staking position sorted by cycleId.
     * @param tokenId Staking position ID to get amount claimable on.
     * @return An array of token and reward associated to the Staking position sorted by cycleId.
     */
    function getClaimableCyclesAndAmounts(uint256 tokenId) external view returns (ClaimableCyclesAndAmounts[] memory) {
        uint128 actualCycle = stakingCycle;
        uint128 nextClaimableCvg = _nextClaims[tokenId].nextClaimableCvg;
        uint128 nextClaimableCvx = _nextClaims[tokenId].nextClaimableCvx;
        uint256 lengthHistory = _stakingHistoryByToken[tokenId].length;

        /// @dev If never claimed on this token
        if (nextClaimableCvx == 0) {
            /// @dev Get the length of the history
            nextClaimableCvx = uint128(_stakingHistoryByToken[tokenId][0]);
        }

        /// @dev potential max length
        ClaimableCyclesAndAmounts[] memory claimableCyclesAndAmounts = new ClaimableCyclesAndAmounts[](
            actualCycle - nextClaimableCvx
        );
        uint256 counter;
        uint256 maxLengthRewards = numberOfUnderlyingRewards;
        for (; nextClaimableCvx < actualCycle; ) {
            uint256 amountStaked = _stakedAmountEligibleAtCycle(nextClaimableCvx, tokenId, lengthHistory);
            uint256 totalStaked = _cycleInfo[nextClaimableCvx].totalStaked;
            /// @dev If the position is eligible to claim rewards for the iterated cycle.
            if (amountStaked != 0) {
                uint256 cvgAmount;

                /// @dev CVG PART
                ///      If the CVG rewards haven't been claimed on the iterated cycle
                if (nextClaimableCvg <= nextClaimableCvx) {
                    /// @dev Computes the staking share of the Staking Position compared to the total Staked.
                    ///      By multiplying this share by the total CVG distributed for the cycle, we get the claimable amount.
                    cvgAmount = (amountStaked * _cycleInfo[nextClaimableCvx].cvgRewardsAmount) / totalStaked;
                }

                /// @dev Convex part
                /// @dev We only do the CVX computation when CVX has been processed for the iterated cycle.
                ICommonStruct.TokenAmount[] memory _cvxRewardsClaimable;
                if (_cycleInfo[nextClaimableCvx].isCvxProcessed) {
                    _cvxRewardsClaimable = new ICommonStruct.TokenAmount[](maxLengthRewards);
                    for (uint256 x; x < maxLengthRewards; ) {
                        ICommonStruct.TokenAmount memory rewardAsset = _cvxRewardsByCycle[nextClaimableCvx][x + 1];
                        if (rewardAsset.amount != 0) {
                            _cvxRewardsClaimable[x] = ICommonStruct.TokenAmount({
                                token: rewardAsset.token,
                                amount: (amountStaked * rewardAsset.amount) / totalStaked
                            });
                        } else {
                            // solhint-disable-next-line no-inline-assembly
                            assembly {
                                /// @dev this reduce the length of the array to not return some useless 0 at the end
                                mstore(_cvxRewardsClaimable, sub(mload(_cvxRewardsClaimable), 1))
                            }
                        }
                        unchecked {
                            ++x;
                        }
                    }
                }
                claimableCyclesAndAmounts[counter++] = ClaimableCyclesAndAmounts({
                    cycleClaimable: nextClaimableCvx,
                    cvgRewards: cvgAmount,
                    cvxRewards: _cvxRewardsClaimable
                });
            } else {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    /// @dev this reduce the length of the array to not return some useless 0 at the end
                    mstore(claimableCyclesAndAmounts, sub(mload(claimableCyclesAndAmounts), 1))
                }
            }

            unchecked {
                ++nextClaimableCvx;
            }
        }

        return claimableCyclesAndAmounts;
    }

    /**
     *  @notice Get Convex rewards that have been processed for a cycleId.
     *  @param cycleId  Rewards have been processed for this cycleId
     *  @return An array of struct with the address of the ERC20 and the associated amount.
     */
    function getProcessedCvxRewards(uint256 cycleId) external view returns (ICommonStruct.TokenAmount[] memory) {
        uint256 maxLengthRewards = numberOfUnderlyingRewards;
        ICommonStruct.TokenAmount[] memory _rewards = new ICommonStruct.TokenAmount[](maxLengthRewards);
        uint256 index;
        for (uint256 x; x < maxLengthRewards; ) {
            if (_cvxRewardsByCycle[cycleId][x + 1].amount != 0) {
                _rewards[index] = _cvxRewardsByCycle[cycleId][x + 1];
                unchecked {
                    ++index;
                }
            } else {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    /// @dev this reduces the length of the _rewardsClaimable array not to return some useless 0 at the end
                    mstore(_rewards, sub(mload(_rewards), 1))
                }
            }
            unchecked {
                ++x;
            }
        }
        return _rewards;
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                            SETTERS
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */
    /// @notice method for the owner to update the deposit status of the contract
    function toggleDepositPaused() external onlyOwner {
        depositPaused = !depositPaused;
    }

    /**
     *  @notice Set the {_buffer} linked to the contract
     *  @param _buffer to pair with this contract
     */
    function setBuffer(IUnderlayingBuffer _buffer) external onlyOwner {
        buffer = _buffer;
    }

    function setPoolEthInfo(PoolEthInfo calldata _poolEthInfo) public onlyOwner {
        if (_poolEthInfo.poolType == PoolType.UNIV2 || _poolEthInfo.poolType == PoolType.DEACTIVATED) {
            require(_poolEthInfo.fee == 0, "FEE_FOR_UNIV3");
            require(_poolEthInfo.indexEth == 0, "INDEX_FOR_CURVE");
            require(address(_poolEthInfo.poolCurve) == address(0), "POOL_FOR_CURVE");
        } else if (_poolEthInfo.poolType == PoolType.UNIV3) {
            require(_poolEthInfo.indexEth == 0, "INDEX_FOR_CURVE");
            require(address(_poolEthInfo.poolCurve) == address(0), "POOL_FOR_CURVE");
        } else if (_poolEthInfo.poolType == PoolType.CURVE) {
            require(_poolEthInfo.fee == 0, "FEE_FOR_UNIV3");
            require(_poolEthInfo.poolCurve.coins(_poolEthInfo.indexEth) == WETH, "WRONG_INDEX_ETH");
        }
        if (_poolEthInfo.poolType == PoolType.DEACTIVATED) {
            delete poolEthInfo;
        } else {
            require(_poolEthInfo.token == address(asset), "WRONG TOKEN");
            poolEthInfo = _poolEthInfo;
        }
    }

    function _tstore(bytes32 location, uint256 value) private {
        assembly {
            tstore(location, value)
        }
    }

    function _tload(bytes32 location) private view returns (uint256 value) {
        assembly {
            value := tload(location)
        }
    }
}
