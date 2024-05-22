// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ISequenceRegistry} from "../interfaces/ISequenceRegistry.sol";

/// @title SequenceRegistry
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This contract maintains sequence counters associated with opaque designator strings.
/// Each counter starts at 1.
/// @dev Anybody can reserve a sequence ID. The only guarantee provided is that no two reservations for the same
/// designator will get the same ID.
contract SequenceRegistry is ISequenceRegistry {
    /// @dev Each designator maps to the previous sequence ID issued, or 0 if none were ever issued.
    mapping(string designator => uint256 lastSeqId) public counters;

    /// @notice A sequence ID has been reserved
    /// @param designator The opaque designator string
    /// @param id The reserved ID, which is unique per designator
    /// @param caller The msg.sender who reserved the ID
    event SequenceIdReserved(string indexed designator, uint256 indexed id, address indexed caller);

    /// @inheritdoc ISequenceRegistry
    function reserveSeqId(string calldata designator) external returns (uint256) {
        uint256 seqId = ++counters[designator];

        emit SequenceIdReserved(designator, seqId, msg.sender);

        return seqId;
    }
}
