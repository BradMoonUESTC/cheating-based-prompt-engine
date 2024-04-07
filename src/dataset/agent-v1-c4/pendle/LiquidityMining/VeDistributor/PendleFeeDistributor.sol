// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../../core/libraries/BoringOwnableUpgradeable.sol";
import "../../core/libraries/Errors.sol";
import "../../interfaces/IPFeeDistributor.sol";
import "../../interfaces/IPVotingEscrowMainchain.sol";
import "../../interfaces/IPVotingController.sol";
import "../libraries/WeekMath.sol";
import "../libraries/VeHistoryLib.sol";
import "../../core/libraries/ArrayLib.sol";

contract PendleFeeDistributor is UUPSUpgradeable, BoringOwnableUpgradeable, IPFeeDistributor {
    using SafeERC20 for IERC20;
    using VeBalanceLib for VeBalance;
    using ArrayLib for uint256[];

    address public immutable votingController;
    address public immutable vePendle;
    address public immutable token;

    address[] public allPools;

    // [pool] => lastFundedWeek
    mapping(address => uint256) public lastFundedWeek;

    // [pool, user] => UserInfo
    mapping(address => mapping(address => UserInfo)) public userInfo;

    // [pool, epoch] => [fee]
    mapping(address => mapping(uint256 => uint256)) public fees;

    modifier ensureValidPool(address pool) {
        if (lastFundedWeek[pool] == 0) revert Errors.FDInvalidPool(pool);
        _;
    }

    constructor(address _votingController, address _vePendle, address _rewardToken) initializer {
        votingController = _votingController;
        vePendle = _vePendle;
        token = _rewardToken;
    }

    function addPool(address pool, uint256 _startWeek) external onlyOwner {
        if (!WeekMath.isValidWTime(_startWeek) || _startWeek == 0) revert Errors.FDInvalidStartEpoch(_startWeek);

        if (lastFundedWeek[pool] != 0) revert Errors.FDPoolAlreadyExists(pool);

        lastFundedWeek[pool] = _startWeek - WeekMath.WEEK;
        allPools.push(pool);

        emit PoolAdded(pool, _startWeek);
    }

    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    function fund(
        address[] calldata pools,
        uint256[][] calldata wTimes,
        uint256[][] calldata amounts,
        uint256 totalAmountToFund
    ) external onlyOwner {
        uint256 length = pools.length;
        if (wTimes.length != length || amounts.length != length) revert Errors.ArrayLengthMismatch();

        uint256 totalFunded = 0;
        for (uint256 i = 0; i < length; ++i) {
            _fund(pools[i], wTimes[i], amounts[i]);
            totalFunded += amounts[i].sum();
        }

        if (totalFunded != totalAmountToFund) revert Errors.FDTotalAmountFundedNotMatch(totalFunded, totalAmountToFund);

        IERC20(token).transferFrom(msg.sender, address(this), totalFunded);
    }

    function _fund(address pool, uint256[] calldata wTimes, uint256[] calldata amounts) internal ensureValidPool(pool) {
        if (wTimes.length != amounts.length) revert Errors.FDEpochLengthMismatch();

        uint256 lastFunded = lastFundedWeek[pool];

        uint256 curWeek = WeekMath.getCurrentWeekStart();

        for (uint256 i = 0; i < amounts.length; ++i) {
            uint256 wTime = wTimes[i];
            uint256 amount = amounts[i];

            if (wTime != lastFunded + WeekMath.WEEK) revert Errors.FDInvalidWTimeFund(lastFunded, wTime);

            fees[pool][wTime] += amount;
            lastFunded += WeekMath.WEEK;

            emit UpdateFee(pool, wTime, amount);
        }

        if (lastFunded >= curWeek) revert Errors.FDInvalidWTimeFund(lastFunded, curWeek);

        lastFundedWeek[pool] = lastFunded;
    }

    function claimReward(address user, address[] calldata pools) external returns (uint256[] memory amountRewardOut) {
        amountRewardOut = new uint256[](pools.length);
        for (uint256 i = 0; i < pools.length; ) {
            amountRewardOut[i] = _accumulateUserReward(pools[i], user);
            unchecked {
                i++;
            }
        }
        IERC20(token).safeTransfer(user, amountRewardOut.sum());
    }

    function getAllActivePools() external view returns (address[] memory) {
        return allPools;
    }

    function _accumulateUserReward(
        address pool,
        address user
    ) internal ensureValidPool(pool) returns (uint256 totalReward) {
        uint256 length = _getUserCheckpointLength(pool, user);
        if (length == 0) return 0;

        uint256 lastWeek = lastFundedWeek[pool];
        uint256 curWeek = userInfo[pool][user].firstUnclaimedWeek;
        uint256 iter = userInfo[pool][user].iter;

        if (curWeek > lastWeek) return 0; // nothing to account

        Checkpoint memory checkpoint = _getUserCheckpointAt(pool, user, iter);
        Checkpoint memory nextCheckpoint = checkpoint;

        if (curWeek == 0) curWeek = checkpoint.timestamp + WeekMath.WEEK;

        while (curWeek <= lastWeek) {
            // we have at most one checkpoint per week
            if (iter + 1 < length) {
                if (nextCheckpoint.timestamp == checkpoint.timestamp) {
                    // next have been assigned to current checkpoint, so we need to get the next one
                    nextCheckpoint = _getUserCheckpointAt(pool, user, iter + 1);
                }

                if (nextCheckpoint.timestamp < curWeek) {
                    iter++;
                    checkpoint = nextCheckpoint;
                }
                // Important invariant: checkpoint[iter] < curWeek <= checkpoint[iter+1]
            }

            // assert(checkpoint.timestamp < curWeek); should always hold

            uint256 userShare = checkpoint.value.getValueAt(uint128(curWeek));
            if (userShare != 0) {
                uint256 totalShare = _getPoolTotalSharesAt(pool, uint128(curWeek));
                // userShare != 0 => totalShare != 0
                uint256 amountRewardOut = (userShare * fees[pool][curWeek]) / totalShare;
                totalReward += amountRewardOut;
                emit ClaimReward(pool, user, curWeek, amountRewardOut);
            }

            curWeek += WeekMath.WEEK;
        }

        userInfo[pool][user] = UserInfo({firstUnclaimedWeek: uint128(curWeek), iter: uint128(iter)});
    }

    function _getPoolTotalSharesAt(address pool, uint128 wTime) internal view returns (uint256) {
        if (pool == vePendle) {
            return IPVotingEscrowMainchain(vePendle).totalSupplyAt(wTime);
        } else {
            return IPVotingController(votingController).getPoolTotalVoteAt(pool, wTime);
        }
    }

    function _getUserCheckpointAt(address pool, address user, uint256 index) internal view returns (Checkpoint memory) {
        if (pool == vePendle) {
            return IPVotingEscrowMainchain(vePendle).getUserHistoryAt(user, index);
        } else {
            return IPVotingController(votingController).getUserPoolHistoryAt(user, pool, index);
        }
    }

    function _getUserCheckpointLength(address pool, address user) internal view returns (uint256) {
        if (pool == vePendle) {
            return IPVotingEscrowMainchain(vePendle).getUserHistoryLength(user);
        } else {
            return IPVotingController(votingController).getUserPoolHistoryLength(user, pool);
        }
    }

    function initialize() external initializer {
        __BoringOwnable_init();
    }

    // ----------------- upgrade-related -----------------

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
