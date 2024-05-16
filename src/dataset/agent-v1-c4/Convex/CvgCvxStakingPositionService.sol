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

/// @title Cvg-Finance - CvgCvxStakingPositionService
/// @notice Staking contract of Convex integration.
///         Allow to Stake, Unstake and Claim rewards.
///         Cvg Rewards are distributed by CvgCycle, each week.
///         After each Cvg cycle, rewards from CVX can be claimed and distributed to Stakers.
/// @dev    Tracks staking shares per CvgCycle even for a cycle in the past.
pragma solidity ^0.8.0;

import "../StakingServiceBase.sol";
import "../../../interfaces/ICrvPoolPlain.sol";
import "../../../interfaces/Convex/ICvxStakingPositionManager.sol";
import "../../../interfaces/Convex/ICvxRewardDistributor.sol";

interface ICvx1 is IERC20 {
    function mint(address receiver, uint256 amount) external;
    function withdraw(uint256 _amount, address receiver) external;
}

contract CvgCvxStakingPositionService is StakingServiceBase {
    /// @dev Convex token
    IERC20 public constant CVX = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    /// @dev internal constant used for divisions
    uint256 internal constant HUNDRED = 1_000;

    /// @notice Address of Convergence locker
    ICvxConvergenceLocker public cvxConvergenceLocker;

    /// @notice cvgCVX/CVX1 curve pool
    ICrvPoolPlain public curvePool;

    /// @dev Corresponds to the % of depeg from which we need to start swapping the CVX.
    uint256 public depegPercentage;

    /// @dev CVX1 contract
    ICvx1 public cvx1;

    struct DepositCvxData {
        uint256 amount;
        uint256 minAmountOut;
    }

    enum TOKEN_TYPE {
        cvgCVX,
        CVX1,
        CVX
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
     * @param _cvxConvergenceLocker Convergence Locker
     * @param _curvePool cvgCVX/CVX1 Curve pool
     * @param _cvx1 CVX1 token contract
     * @param _symbol Symbol of the NFT
     */
    function initialize(
        address _cvxConvergenceLocker,
        ICrvPoolPlain _curvePool,
        ICvx1 _cvx1,
        string memory _symbol
    ) external initializer {
        require(_cvxConvergenceLocker != address(0), "CVG_LOCKER_ZERO");

        asset = CVX;
        symbol = _symbol;
        cvxConvergenceLocker = ICvxConvergenceLocker(_cvxConvergenceLocker);
        buffer = IUnderlayingBuffer(_cvxConvergenceLocker);
        curvePool = _curvePool;
        depegPercentage = 1_025; // 2.5%
        cvx1 = _cvx1;

        /// @dev Initialize internal cycle with the cycle from the control tower
        stakingCycle = cvgControlTower.cvgCycle();

        /// @dev To prevent the claim of CVX on the first Cycle of deployment.
        ///      Staked asset must be staked during a FULL cycle to be eligible to rewards
        _cycleInfo[stakingCycle].isCvxProcessed = true;

        ICvxRewardDistributor _cvxRewardDistributor = cvgControlTower.cvxRewardDistributor();
        require(address(_cvxRewardDistributor) != address(0), "CVX_REWARD_RECEIVER_ZERO");
        cvxRewardDistributor = _cvxRewardDistributor;

        ICvxStakingPositionManager _cvxStakingPositionManager = cvgControlTower.cvxStakingPositionManager();
        require(address(_cvxStakingPositionManager) != address(0), "CVX_STAKING_MANAGER_ZERO");
        stakingPositionManager = _cvxStakingPositionManager;

        /// @dev Allows Convergence Locker to transfer CVX from this contract. Is used for the Converting CVX => cvgCVX
        CVX.approve(address(_cvxConvergenceLocker), type(uint256).max);
        /// @dev Allows CVX1 to transfer CVX from this contract. Is used for the Converting CVX => CVX1
        CVX.approve(address(_cvx1), type(uint256).max);
        /// @dev Allows the Curve stable pool to transfer CVX1 from this contract. Is used for the Converting CVX1 => cvgCVX
        _cvx1.approve(address(_curvePool), type(uint256).max);
        /// @dev Allows CVX1 to transfer CVX1 from this contract. Is used for the Converting CVX1 => CVX
        _cvx1.approve(address(_cvx1), type(uint256).max);
        /// @dev Allows the Curve stable pool to transfer cvgCVX from this contract. Is used for the Converting cvgCVX => CVX1
        cvxConvergenceLocker.approve(address(_curvePool), type(uint256).max);

        address _treasuryDao = cvgControlTower.treasuryDao();
        require(_treasuryDao != address(0), "TREASURY_DAO_ZERO");
        _transferOwnership(_treasuryDao);
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                        USER EXTERNAL
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    /**
     * @notice Pay an amount of ETH to obtain cvgCVX to deposit in the staking contract.
     *         Mints a Staking position (tokenId == 0) or increase one owned.
     *         Staking rewards are claimable after being staked for one full cycle.
     * @dev Staking at cycle N implies that first rewards will be claimable at the beginning of cycle N+2, then every cycle.
     * @param tokenId of the staking position
     * @param minAmountOutCvx for the swap ETH => CVX
     * @param minCvgCvxAmountOut for the swap CVX => cvgCVX
     */
    function depositEth(
        uint256 tokenId,
        uint256 minAmountOutCvx,
        uint256 minCvgCvxAmountOut
    ) external payable lockReentrancy {
        uint256 amountCvx = _depositEth(msg.value, minAmountOutCvx);
        _deposit(tokenId, 0, DepositCvxData({amount: amountCvx, minAmountOut: minCvgCvxAmountOut}), true);
    }

    /**
     * @notice Deposit an amount of cvgCVX into this staking contract.
     *         Mints a Staking position (tokenId == 0) or increase one owned.
     *         Staking rewards are claimable after being staked for one full cycle.
     * @dev Staking at cycle N implies that first rewards will be claimable at the beginning of cycle N+2, then every cycle.
     * @param tokenId of the staking position
     * @param cvgCvxAmount Amount of cvgCVX to deposit
     * @param cvxData Convex data to mint or swap CVX into cvgCVX to stake them.
     */
    function deposit(uint256 tokenId, uint256 cvgCvxAmount, DepositCvxData calldata cvxData) external {
        _deposit(tokenId, cvgCvxAmount, cvxData, false);
    }

    /**
     * @notice Withdraw cvgCVX from the vault to the Staking Position owner.
     *         Removing rewards before the end of a cycle leads to the loss of all accumulated rewards during this cycle.
     * @dev Withdrawing always removes first from the staked amount not yet eligible to rewards.
     * @param tokenId Staking Position to withdraw token from
     * @param amount Amount to withdraw
     * @param tokenType Token to withdraw (between CVX, CVX1 and cvgCVX)
     * @param minCvx1AmountOut Minimum amount of CVX1 to receive in case of a swap
     */
    function withdraw(
        uint256 tokenId,
        uint256 amount,
        TOKEN_TYPE tokenType,
        uint256 minCvx1AmountOut
    ) external checkCompliance(tokenId) {
        require(amount != 0, "WITHDRAW_LTE_0");

        uint256 _cvgStakingCycle = stakingCycle;

        /// @dev Update the CycleInfo & the TokenInfo for the current & next cycle
        _updateAmountStakedWithdraw(tokenId, amount, _cvgStakingCycle);

        /// @dev transfer tokens back to user depending on the selected option
        if (tokenType == TOKEN_TYPE.CVX) {
            ICvx1 _cvx1 = cvx1;

            /// @dev swap cvgCVX to CVX1 through the Curve pool
            uint256 exchangedAmount = curvePool.exchange(1, 0, amount, minCvx1AmountOut, address(this));

            /// @dev withdraw CVX from CVX1 contract
            _cvx1.withdraw(exchangedAmount, msg.sender);
        } else if (tokenType == TOKEN_TYPE.CVX1) {
            /// @dev swap cvgCVX to CVX1 through the Curve pool and directly send tokens to user
            curvePool.exchange(1, 0, amount, minCvx1AmountOut, msg.sender);
        } else {
            /// @dev Transfers cvgCVX back to user
            cvxConvergenceLocker.transfer(msg.sender, amount);
        }

        emit Withdraw(tokenId, msg.sender, _cvgStakingCycle, amount);
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                        INTERNALS/PRIVATES
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */
    function _deposit(
        uint256 tokenId,
        uint256 cvgCvxAmount,
        DepositCvxData memory cvxData,
        bool isEthDeposit
    ) internal {
        /// @dev Verify if deposits are paused
        require(!depositPaused, "DEPOSIT_PAUSED");

        uint256 totalAmount = cvgCvxAmount;

        /// @dev Memorize storage data
        ICvxStakingPositionManager _cvxStakingPositionManager = stakingPositionManager;
        uint256 _cvgStakingCycle = stakingCycle;

        uint256 _tokenId;
        /// @dev If tokenId != 0, user deposits for an already existing position, we have so to check ownership
        if (tokenId != 0) {
            /// @dev Fetches, for the tokenId, the owner, the StakingPositionService linked to and the timestamp of unlocking
            _cvxStakingPositionManager.checkIncreaseDepositCompliance(tokenId, msg.sender);
            _tokenId = tokenId;
        }
        /// @dev Else, we increment the nextId to get the new tokenId
        else {
            _tokenId = _cvxStakingPositionManager.mint(msg.sender);
        }

        /// @dev transfers cvgCVX tokens from caller to this contract
        if (cvgCvxAmount != 0) cvxConvergenceLocker.transferFrom(msg.sender, address(this), cvgCvxAmount);

        /// @dev convert CVX to cvgCVX if amount is specified
        if (cvxData.amount != 0) {
            totalAmount += _convertCvxToCvgCvx(cvxData.amount, cvxData.minAmountOut, isEthDeposit);
        }

        /// @dev Verify if the staked amount is > 0
        require(totalAmount != 0, "DEPOSIT_LTE_0");

        /// @dev Update the CycleInfo & the TokenInfo for the next cycle
        _updateAmountStakedDeposit(_tokenId, totalAmount, _cvgStakingCycle + 1);

        emit Deposit(_tokenId, msg.sender, _cvgStakingCycle, totalAmount);
    }

    /**
     * @notice Convert CVX to cvgCVX depending on the depeg percentage allowed.
     * @dev Force the swap if the cvgCVX/CVX1 stable pool is depegged from CVX, acts as a peg keeper.
     * @param cvxAmount amount of CVX to use to get cvgCVX
     * @param minCvgCvxAmountOut Minimum amount of cvgCVX to receive when swapping through the Curve pool
     */
    function _convertCvxToCvgCvx(
        uint256 cvxAmount,
        uint256 minCvgCvxAmountOut,
        bool isEthDeposit
    ) internal returns (uint256) {
        uint256 balance = cvxConvergenceLocker.balanceOf(address(this));
        if (!isEthDeposit) {
            /// @dev transfer CVX from user to this contract
            CVX.transferFrom(msg.sender, address(this), cvxAmount);
        }

        /// @dev Acts as a peg keeper and will prefers swap in the liquid pool in case of a depeg
        uint256 feesAmount = (cvxAmount * cvxConvergenceLocker.mintFees()) / 10_000;
        ICrvPoolPlain _curvePool = curvePool;
        if (_curvePool.get_dy(0, 1, cvxAmount) > ((cvxAmount - feesAmount) * depegPercentage) / HUNDRED) {
            require(minCvgCvxAmountOut >= cvxAmount, "INVALID_SLIPPAGE");

            /// @dev peg is too low, we swap in the LP with the CVX sent
            cvx1.mint(address(this), cvxAmount);
            _curvePool.exchange(0, 1, cvxAmount, minCvgCvxAmountOut, address(this));
        } else {
            /// @dev peg OK, we pass through the mint process 1:1
            cvxConvergenceLocker.mint(address(this), cvxAmount, false);
        }

        return cvxConvergenceLocker.balanceOf(address(this)) - balance;
    }

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                            SETTERS
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */

    /**
     * @notice Method allowing the owner to update the depeg percentage from which CVX will be swapped to cvgCVX during mint
     * @param _depegPercentage Depeg percentage
     */
    function setDepegPercentage(uint256 _depegPercentage) external onlyOwner {
        require(_depegPercentage >= 1000, "PERCENTAGE_TOO_LOW");
        depegPercentage = _depegPercentage;
    }
}
