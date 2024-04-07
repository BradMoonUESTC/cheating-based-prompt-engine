// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../interfaces/IPVeToken.sol";
import "../../interfaces/IPVotingController.sol";

import "../libraries/VeBalanceLib.sol";
import "../libraries/WeekMath.sol";
import "../libraries/VeHistoryLib.sol";

import "../../core/libraries/MiniHelpers.sol";
import "../../core/libraries/Errors.sol";

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract VotingControllerStorageUpg is IPVotingController {
    using VeBalanceLib for VeBalance;
    using VeBalanceLib for LockedPosition;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Checkpoints for Checkpoints.History;
    using WeekMath for uint128;

    struct PoolData {
        uint64 chainId;
        uint128 lastSlopeChangeAppliedAt;
        VeBalance totalVote;
        // wTime => slopeChange value
        mapping(uint128 => uint128) slopeChanges;
    }

    struct UserPoolData {
        uint64 weight;
        VeBalance vote;
    }

    struct UserData {
        uint64 totalVotedWeight;
        mapping(address => UserPoolData) voteForPools;
    }

    struct WeekData {
        bool isEpochFinalized;
        uint128 totalVotes;
        mapping(address => uint128) poolVotes;
    }

    uint128 public constant MAX_LOCK_TIME = 104 weeks;
    uint128 public constant WEEK = 1 weeks;
    uint128 public constant GOVERNANCE_PENDLE_VOTE = 10 * (10 ** 6) * (10 ** 18); // 10 mils of PENDLE

    IPVeToken public immutable vePendle;

    uint128 public deployedWTime;

    uint128 public pendlePerSec;

    EnumerableSet.AddressSet internal allActivePools;

    EnumerableSet.AddressSet internal allRemovedPools;

    // [chainId] => [pool]
    mapping(uint64 => EnumerableSet.AddressSet) internal activeChainPools;

    // [poolAddress] -> PoolData
    mapping(address => PoolData) internal poolData;

    // [wTime] => WeekData
    mapping(uint128 => WeekData) internal weekData;

    // user voting data
    mapping(address => UserData) internal userData;

    // [user][pool] => checkpoint
    mapping(address => mapping(address => Checkpoints.History)) internal __dep_userPoolHistory;

    uint256[100] private __gap;

    constructor(address _vePendle) {
        vePendle = IPVeToken(_vePendle);
    }

    /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getPoolTotalVoteAt(address pool, uint128 wTime) public view returns (uint128) {
        return weekData[wTime].poolVotes[pool];
    }

    /// @notice deprecated, only kept for compatibility reasons
    function getUserPoolHistoryLength(address user, address pool) external view returns (uint256) {
        return __dep_userPoolHistory[user][pool].length();
    }

    /// @notice deprecated, only kept for compatibility reasons
    function getUserPoolHistoryAt(address user, address pool, uint256 index) external view returns (Checkpoint memory) {
        return __dep_userPoolHistory[user][pool].get(index);
    }

    function getPoolData(
        address pool,
        uint128[] calldata wTimes
    )
        public
        view
        returns (
            uint64 chainId,
            uint128 lastSlopeChangeAppliedAt,
            VeBalance memory totalVote,
            uint128[] memory slopeChanges
        )
    {
        PoolData storage data = poolData[pool];
        (chainId, lastSlopeChangeAppliedAt, totalVote) = (data.chainId, data.lastSlopeChangeAppliedAt, data.totalVote);

        slopeChanges = new uint128[](wTimes.length);
        for (uint256 i = 0; i < wTimes.length; ++i) {
            if (!wTimes[i].isValidWTime()) revert Errors.InvalidWTime(wTimes[i]);
            slopeChanges[i] = data.slopeChanges[wTimes[i]];
        }
    }

    function getUserData(
        address user,
        address[] calldata pools
    ) public view returns (uint64 totalVotedWeight, UserPoolData[] memory voteForPools) {
        UserData storage data = userData[user];

        totalVotedWeight = data.totalVotedWeight;

        voteForPools = new UserPoolData[](pools.length);
        for (uint256 i = 0; i < pools.length; ++i) voteForPools[i] = data.voteForPools[pools[i]];
    }

    function getWeekData(
        uint128 wTime,
        address[] calldata pools
    ) public view returns (bool isEpochFinalized, uint128 totalVotes, uint128[] memory poolVotes) {
        if (!wTime.isValidWTime()) revert Errors.InvalidWTime(wTime);

        WeekData storage data = weekData[wTime];

        (isEpochFinalized, totalVotes) = (data.isEpochFinalized, data.totalVotes);

        poolVotes = new uint128[](pools.length);
        for (uint256 i = 0; i < pools.length; ++i) poolVotes[i] = data.poolVotes[pools[i]];
    }

    function getAllActivePools() external view returns (address[] memory) {
        return allActivePools.values();
    }

    function getAllRemovedPools(
        uint256 start,
        uint256 end
    ) external view returns (uint256 lengthOfRemovedPools, address[] memory arr) {
        lengthOfRemovedPools = allRemovedPools.length();

        if (end >= lengthOfRemovedPools) revert Errors.ArrayOutOfBounds();

        arr = new address[](end - start + 1);
        for (uint256 i = start; i <= end; ++i) arr[i - start] = allRemovedPools.at(i);
    }

    function getActiveChainPools(uint64 chainId) external view returns (address[] memory) {
        return activeChainPools[chainId].values();
    }

    function getUserPoolVote(address user, address pool) external view returns (UserPoolData memory) {
        return userData[user].voteForPools[pool];
    }

    /*///////////////////////////////////////////////////////////////
                INTERNAL DATA MANIPULATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _addPool(uint64 chainId, address pool) internal {
        if (!activeChainPools[chainId].add(pool)) assert(false);
        if (!allActivePools.add(pool)) assert(false);

        poolData[pool].chainId = chainId;
        poolData[pool].lastSlopeChangeAppliedAt = WeekMath.getCurrentWeekStart();
    }

    function _removePool(address pool) internal {
        uint64 chainId = poolData[pool].chainId;
        if (!activeChainPools[chainId].remove(pool)) assert(false);
        if (!allActivePools.remove(pool)) assert(false);
        if (!allRemovedPools.add(pool)) assert(false);

        delete poolData[pool];
    }

    function _setFinalPoolVoteForWeek(address pool, uint128 wTime, uint128 vote) internal {
        weekData[wTime].totalVotes += vote;
        weekData[wTime].poolVotes[pool] = vote;
    }

    function _setNewVotePoolData(address pool, VeBalance memory vote, uint128 wTime) internal {
        poolData[pool].totalVote = vote;
        poolData[pool].lastSlopeChangeAppliedAt = wTime;
        emit PoolVoteChange(pool, vote);
    }

    /**
     * @notice modifies `user`'s vote weight on `pool`
     * @dev works by simply removing the old vote position, then adds in a fresh vote
     */
    function _modifyVoteWeight(
        address user,
        address pool,
        LockedPosition memory userPosition,
        uint64 weight
    ) internal returns (VeBalance memory newVote) {
        UserData storage uData = userData[user];
        PoolData storage pData = poolData[pool];

        VeBalance memory oldVote = uData.voteForPools[pool].vote;

        // REMOVE OLD VOTE
        if (oldVote.bias != 0) {
            if (_isPoolActive(pool) && _isVoteActive(oldVote)) {
                pData.totalVote = pData.totalVote.sub(oldVote);
                pData.slopeChanges[oldVote.getExpiry()] -= oldVote.slope;
            }
            uData.totalVotedWeight -= uData.voteForPools[pool].weight;
            delete uData.voteForPools[pool];
        }

        // ADD NEW VOTE
        if (weight != 0) {
            if (!_isPoolActive(pool)) revert Errors.VCInactivePool(pool);

            newVote = userPosition.convertToVeBalance(weight);

            pData.totalVote = pData.totalVote.add(newVote);
            pData.slopeChanges[newVote.getExpiry()] += newVote.slope;

            uData.voteForPools[pool] = UserPoolData(weight, newVote);
            uData.totalVotedWeight += weight;
        }

        emit PoolVoteChange(pool, pData.totalVote);
    }

    function _setAllPastEpochsAsFinalized() internal {
        uint128 wTime = WeekMath.getCurrentWeekStart();
        while (wTime > deployedWTime && weekData[wTime].isEpochFinalized == false) {
            weekData[wTime].isEpochFinalized = true;
            wTime -= WEEK;
        }
    }

    function _isPoolActive(address pool) internal view returns (bool) {
        return allActivePools.contains(pool);
    }

    /// @notice check if a vote still counts by checking if the vote is not (x,0) (in case the
    /// weight of the vote is too small) & the expiry is after the current time
    function _isVoteActive(VeBalance memory vote) internal view returns (bool) {
        return vote.slope != 0 && !MiniHelpers.isCurrentlyExpired(vote.getExpiry());
    }
}
