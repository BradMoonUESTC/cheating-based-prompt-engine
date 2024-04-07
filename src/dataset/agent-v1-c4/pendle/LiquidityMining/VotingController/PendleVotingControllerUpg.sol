// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./VotingControllerStorageUpg.sol";
import "../CrossChainMsg/PendleMsgSenderAppUpg.sol";
import "../libraries/VeBalanceLib.sol";
import "../../core/libraries/math/PMath.sol";
import "../../interfaces/IPGaugeControllerMainchain.sol";
import "../../interfaces/IPVotingController.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/*
Voting accounting:
    - For gauge controller, it will consider each message from voting controller
    as a pack of money to incentivize it during the very next WEEK (block.timestamp -> block.timestamp + WEEK)
    - If the reward duration for the last pack of money has not ended, it will combine
    the leftover reward with the current reward to distribute.

    - In the very extreme case where no one broadcast the result of week x, and at week x+1,
    the results for both are now broadcasted, then the WEEK of (block.timestamp -> WEEK)
    will receive both of the reward pack
    - Each pack of money will has it own id as timestamp, a gauge controller does not
    receive a pack of money with the same id twice, this allow governance to rebroadcast
    in case the last message was corrupted by LayerZero

Pros:
    - If governance does not forget broadcasting the reward on the early of the week,
    the mechanism works just the same as the epoch-based one
    - If governance forget to broadcast the reward, the whole system still works normally,
    the reward is still incentivized, but only approximately fair
Cons:
    - Does not guarantee the reward will be distributed on epoch start and end
*/

contract PendleVotingControllerUpg is PendleMsgSenderAppUpg, VotingControllerStorageUpg, UUPSUpgradeable {
    using VeBalanceLib for VeBalance;
    using PMath for uint256;
    using PMath for int256;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(
        address _vePendle,
        address _pendleMsgSendEndpoint,
        uint256 initialApproxDestinationGas
    )
        VotingControllerStorageUpg(_vePendle)
        PendleMsgSenderAppUpg(_pendleMsgSendEndpoint, initialApproxDestinationGas) // constructor only set immutable variables
        initializer
    //solhint-disable-next-line
    {

    }

    function initialize() external initializer {
        __BoringOwnable_init();
        deployedWTime = WeekMath.getCurrentWeekStart();
    }

    /*///////////////////////////////////////////////////////////////
                FUNCTIONS CAN BE CALLED BY ANYONE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice updates a user's vote weights, also allowing user to divide their voting power
     * across different pools
     * @param pools pools to change vote weights, if not listed then existing weight won't change
     * @param weights voting weight on each pool in `pools`, must be same length as `pools`
     * @dev A user's max voting weights is equal to `USER_VOTE_MAX_WEIGHT` (1e18). If their total
     * voted weights is less than such, then the excess weight is not counted. For such reason, a
     * user's voting power will only be fully utilized if their total voted weight is exactly 1e18.
     * @dev Reverts if, after all vote changes, the total voted weight is more than 1e18.
     * @dev A removed pool can be included, but the new weight must be 0, otherwise will revert.
     * @dev See {`VotingControllerStorageUpg - getUserData()`} for current user data.
     */
    function vote(address[] calldata pools, uint64[] calldata weights) external {
        address user = msg.sender;

        if (pools.length != weights.length) revert Errors.ArrayLengthMismatch();
        if (user != owner && vePendle.balanceOf(user) == 0) revert Errors.VCZeroVePendle(user);

        LockedPosition memory userPosition = _getUserVePendlePosition(user);

        for (uint256 i = 0; i < pools.length; ++i) {
            if (_isPoolActive(pools[i])) applyPoolSlopeChanges(pools[i]);
            VeBalance memory newVote = _modifyVoteWeight(user, pools[i], userPosition, weights[i]);
            emit Vote(user, pools[i], weights[i], newVote);
        }

        uint256 totalVotedWeight = userData[user].totalVotedWeight;
        if (totalVotedWeight > VeBalanceLib.USER_VOTE_MAX_WEIGHT)
            revert Errors.VCExceededMaxWeight(totalVotedWeight, VeBalanceLib.USER_VOTE_MAX_WEIGHT);
    }

    /**
     * @notice Process all the slopeChanges that haven't been processed & update these data into
     * poolData
     * @dev reverts if pool is not active
     * @dev if pool is already up-to-date, the function will succeed without any state updates
     */
    function applyPoolSlopeChanges(address pool) public {
        if (!_isPoolActive(pool)) revert Errors.VCInactivePool(pool);

        uint128 wTime = poolData[pool].lastSlopeChangeAppliedAt;
        uint128 currentWeekStart = WeekMath.getCurrentWeekStart();

        // no state changes are expected
        if (wTime >= currentWeekStart) return;

        VeBalance memory currentVote = poolData[pool].totalVote;
        while (wTime < currentWeekStart) {
            wTime += WEEK;
            currentVote = currentVote.sub(poolData[pool].slopeChanges[wTime], wTime);
            _setFinalPoolVoteForWeek(pool, wTime, currentVote.getValueAt(wTime));
        }

        _setNewVotePoolData(pool, currentVote, wTime);
    }

    /**
     * @notice finalize the voting results of all pools, up to the current epoch
     * @dev See `applyPoolSlopeChanges()` for more details
     * @dev This function might be gas-costly if there are a lot of active pools, but this can be
     * mitigated by calling `applyPoolSlopeChanges()` for each pool separately, spreading the gas
     * cost across multiple txs (although the total gas cost will be higher).
     * This is because `applyPoolSlopeChanges()` will not update anything if already up-to-date.
     */
    function finalizeEpoch() public {
        uint256 length = allActivePools.length();
        for (uint256 i = 0; i < length; ++i) {
            applyPoolSlopeChanges(allActivePools.at(i));
        }
        _setAllPastEpochsAsFinalized();
    }

    /**
     * @notice broadcast the voting results of the current week to the chain with chainId. Can be
     * called by anyone.
     * @dev It's intentional to allow the same results to be broadcasted multiple
     * times. The receiver should be able to filter these duplicated messages
     * @dev The epoch must have already been finalized by `finalizeEpoch()`, otherwise will revert.
     */
    function broadcastResults(uint64 chainId) external payable refundUnusedEth {
        uint128 wTime = WeekMath.getCurrentWeekStart();
        if (!weekData[wTime].isEpochFinalized) revert Errors.VCEpochNotFinalized(wTime);
        _broadcastResults(chainId, wTime, pendlePerSec);
    }

    /*///////////////////////////////////////////////////////////////
                    GOVERNANCE-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice add a pool to allow users to vote. Can only be done by governance
     * @custom:gov NOTE TO GOV:
     * - Previous week's results should have been broadcasted prior to calling this function.
     * - `pool` must not have been added before (even if has been removed).
     * - `chainId` must be valid.
     */
    function addPool(uint64 chainId, address pool) external onlyOwner {
        if (_isPoolActive(pool)) revert Errors.VCPoolAlreadyActive(pool);
        if (allRemovedPools.contains(pool)) revert Errors.VCPoolAlreadyAddAndRemoved(pool);

        _addPool(chainId, pool);
        emit AddPool(chainId, pool);
    }

    /**
     * @notice remove a pool from voting. Can only be done by governance
     * @custom:gov NOTE TO GOV:
     * - Previous week's results should have been broadcasted prior to calling this function.
     * - `pool` must be currently active.
     */
    function removePool(address pool) external onlyOwner {
        if (!_isPoolActive(pool)) revert Errors.VCInactivePool(pool);

        uint64 chainId = poolData[pool].chainId;

        applyPoolSlopeChanges(pool);
        _removePool(pool);

        emit RemovePool(chainId, pool);
    }

    /**
     * @notice use the gov-privilege to force broadcast a message in case there are issues with LayerZero
     * @custom:gov NOTE TO GOV: gov should always call finalizeEpoch beforehand
     */
    function forceBroadcastResults(
        uint64 chainId,
        uint128 wTime,
        uint128 forcedPendlePerSec
    ) external payable onlyOwner refundUnusedEth {
        _broadcastResults(chainId, wTime, forcedPendlePerSec);
    }

    /**
     * @notice sets new pendlePerSec
     * @dev no zero checks because gov may want to stop liquidity mining
     * @custom:gov NOTE TO GOV: Should be done mid-week, well before the next broadcast to avoid
     * race condition
     */
    function setPendlePerSec(uint128 newPendlePerSec) external onlyOwner {
        pendlePerSec = newPendlePerSec;
        emit SetPendlePerSec(newPendlePerSec);
    }

    function getBroadcastResultFee(uint64 chainId) external view returns (uint256) {
        if (chainId == block.chainid) return 0; // Mainchain broadcast

        uint256 length = activeChainPools[chainId].length();
        if (length == 0) return 0;

        address[] memory pools = new address[](length);
        uint256[] memory totalPendleAmounts = new uint256[](length);

        return _getSendMessageFee(chainId, abi.encode(uint128(0), pools, totalPendleAmounts));
    }

    /*///////////////////////////////////////////////////////////////
                    INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice broadcast voting results of the timestamp to chainId
    function _broadcastResults(uint64 chainId, uint128 wTime, uint128 totalPendlePerSec) internal {
        uint256 totalVotes = weekData[wTime].totalVotes;
        if (totalVotes == 0) return;

        uint256 length = activeChainPools[chainId].length();
        if (length == 0) return;

        address[] memory pools = activeChainPools[chainId].values();
        uint256[] memory totalPendleAmounts = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            uint256 poolVotes = weekData[wTime].poolVotes[pools[i]];
            totalPendleAmounts[i] = (totalPendlePerSec * poolVotes * WEEK) / totalVotes;
        }

        if (chainId == block.chainid) {
            address gaugeController = destinationContracts.get(chainId);
            IPGaugeControllerMainchain(gaugeController).updateVotingResults(wTime, pools, totalPendleAmounts);
        } else {
            _sendMessage(chainId, abi.encode(wTime, pools, totalPendleAmounts));
        }

        emit BroadcastResults(chainId, wTime, totalPendlePerSec);
    }

    function _getUserVePendlePosition(address user) internal view returns (LockedPosition memory userPosition) {
        if (user == owner) {
            (userPosition.amount, userPosition.expiry) = (
                GOVERNANCE_PENDLE_VOTE,
                WeekMath.getWeekStartTimestamp(uint128(block.timestamp) + MAX_LOCK_TIME)
            );
        } else {
            (userPosition.amount, userPosition.expiry) = vePendle.positionData(user);
        }
    }

    //solhint-disable-next-line
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
