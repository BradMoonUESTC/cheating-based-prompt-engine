// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../interfaces/IPMsgReceiverApp.sol";
import "../../core/libraries/BoringOwnableUpgradeable.sol";
import "../../core/libraries/Errors.sol";

// solhint-disable no-empty-blocks

abstract contract PendleMsgReceiverAppUpg is IPMsgReceiverApp {
    address public immutable pendleMsgReceiveEndpoint;

    uint256[100] private __gap;

    modifier onlyFromPendleMsgReceiveEndpoint() {
        if (msg.sender != pendleMsgReceiveEndpoint) revert Errors.MsgNotFromReceiveEndpoint(msg.sender);
        _;
    }

    constructor(address _pendleMsgReceiveEndpoint) {
        pendleMsgReceiveEndpoint = _pendleMsgReceiveEndpoint;
    }

    function executeMessage(bytes calldata message) external virtual onlyFromPendleMsgReceiveEndpoint {
        _executeMessage(message);
    }

    function _executeMessage(bytes memory message) internal virtual;
}
