// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../interfaces/ILayerZeroEndpoint.sol";
import "../../interfaces/IPMsgReceiverApp.sol";
import "../../interfaces/ILayerZeroReceiver.sol";
import "../../core/libraries/BoringOwnableUpgradeable.sol";
import "../../core/libraries/Errors.sol";
import "./libraries/LayerZeroHelper.sol";
import "./libraries/ExcessivelySafeCall.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @dev Initially, currently we will use layer zero's default send and receive version (which is most updated)
 * So we can leave the configuration unset.
 */

contract PendleMsgReceiveEndpointUpg is ILayerZeroReceiver, Initializable, UUPSUpgradeable, BoringOwnableUpgradeable {
    using ExcessivelySafeCall for address;

    address public immutable lzEndpoint;
    address public immutable sendEndpointAddr;
    uint64 public immutable sendEndpointChainId;

    event MessageFailed(uint16 _srcChainId, bytes _path, uint64 _nonce, bytes _payload, bytes _reason);

    modifier onlyLzEndpoint() {
        if (msg.sender != address(lzEndpoint)) revert Errors.OnlyLayerZeroEndpoint();
        _;
    }

    /**
     * @dev Lz has a built-in feature for trusted receive and send endpoint
     * But in order to aim for flexibility in switching to other crosschain messaging protocol, there
     * is no harm to keep our current whitelisting mechanism.
     */
    modifier mustOriginateFromSendEndpoint(uint16 srcChainId, bytes memory path) {
        if (
            sendEndpointAddr != LayerZeroHelper._getFirstAddressFromPath(path) ||
            sendEndpointChainId != LayerZeroHelper._getOriginalChainIds(srcChainId)
        ) revert Errors.MsgNotFromSendEndpoint(srcChainId, path);
        _;
    }

    // by default we will use LZ's default version (most updated version). Hence, it's not necessary
    // to call setLzReceiveVersion
    constructor(address _lzEndpoint, address _sendEndpointAddr, uint64 _sendEndpointChainId) initializer {
        lzEndpoint = _lzEndpoint;
        sendEndpointAddr = _sendEndpointAddr;
        sendEndpointChainId = _sendEndpointChainId;
    }

    function initialize() external initializer {
        __BoringOwnable_init();
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _path,
        uint64 _nonce,
        bytes calldata _payload
    ) external onlyLzEndpoint mustOriginateFromSendEndpoint(_srcChainId, _path) {
        (address receiver, bytes memory message) = abi.decode(_payload, (address, bytes));

        (bool success, bytes memory reason) = address(receiver).excessivelySafeCall(
            gasleft(),
            150,
            abi.encodeWithSelector(IPMsgReceiverApp.executeMessage.selector, message)
        );

        if (!success) {
            emit MessageFailed(_srcChainId, _path, _nonce, _payload, reason);
        }
    }

    function govExecuteMessage(address receiver, bytes calldata message) external payable onlyOwner {
        IPMsgReceiverApp(receiver).executeMessage(message);
    }

    function setLzReceiveVersion(uint16 _newVersion) external onlyOwner {
        ILayerZeroEndpoint(lzEndpoint).setReceiveVersion(_newVersion);
    }

    //solhint-disable-next-line
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
