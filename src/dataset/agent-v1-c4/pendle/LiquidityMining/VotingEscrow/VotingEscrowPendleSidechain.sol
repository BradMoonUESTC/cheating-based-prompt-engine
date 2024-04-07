// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.17;

import "../libraries/VeBalanceLib.sol";
import "../libraries/WeekMath.sol";

import "./VotingEscrowTokenBase.sol";
import "../CrossChainMsg/PendleMsgReceiverAppUpg.sol";

// solhint-disable no-empty-blocks
contract VotingEscrowPendleSidechain is VotingEscrowTokenBase, PendleMsgReceiverAppUpg, BoringOwnableUpgradeable {
    uint256 public lastTotalSupplyReceivedAt;

    mapping(address => address) internal delegatorOf;

    event SetNewDelegator(address delegator, address receiver);

    event SetNewTotalSupply(VeBalance totalSupply);

    event SetNewUserPosition(LockedPosition position);

    constructor(
        address _PendleMsgReceiveEndpointUpg
    ) initializer PendleMsgReceiverAppUpg(_PendleMsgReceiveEndpointUpg) {
        __BoringOwnable_init();
    }

    function totalSupplyCurrent() public view virtual override returns (uint128) {
        return totalSupplyStored();
    }

    /**
     * @dev The mechanism of delegating is for governance to support protocol to build on top
     * This way, it is more gas efficient and does not affect the crosschain messaging cost
     */
    function setDelegatorFor(address receiver, address delegator) external onlyOwner {
        delegatorOf[receiver] = delegator;
        emit SetNewDelegator(delegator, receiver);
    }

    /**
     * @dev Both two types of message will contain VeBalance supply & wTime
     * @dev If the message also contains some users' position, we should update it
     */
    function _executeMessage(bytes memory message) internal virtual override {
        (uint128 msgTime, VeBalance memory supply, bytes memory userData) = abi.decode(
            message,
            (uint128, VeBalance, bytes)
        );
        _setNewTotalSupply(msgTime, supply);
        if (userData.length > 0) {
            _setNewUserPosition(userData);
        }
    }

    function _setNewUserPosition(bytes memory userData) internal {
        (address userAddr, LockedPosition memory position) = abi.decode(userData, (address, LockedPosition));
        positionData[userAddr] = position;
        emit SetNewUserPosition(position);
    }

    function _setNewTotalSupply(uint128 msgTime, VeBalance memory supply) internal {
        // lastSlopeChangeAppliedAt = wTime;
        if (msgTime < lastTotalSupplyReceivedAt) {
            revert Errors.VEReceiveOldSupply(msgTime);
        }
        lastTotalSupplyReceivedAt = msgTime;
        _totalSupply = supply;
        emit SetNewTotalSupply(supply);
    }

    function balanceOf(address user) public view virtual override returns (uint128) {
        address delegator = delegatorOf[user];
        if (delegator == address(0)) return super.balanceOf(user);
        return super.balanceOf(delegator);
    }
}
