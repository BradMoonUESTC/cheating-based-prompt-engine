// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../../libraries/Errors.sol";
import "../../../../LiquidityMining/CrossChainMsg/libraries/LayerZeroHelper.sol";
import "../../../../interfaces/IPOracleForSy.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract PendleChainlinkReceiver is Initializable {
    address public immutable lzEndpoint;
    address public trustedRemoteAddr;
    uint64 public trustedRemoteChainId;
    int256 public latestAnswer;

    modifier onlyLzEndpoint() {
        if (msg.sender != address(lzEndpoint)) revert Errors.OnlyLayerZeroEndpoint();
        _;
    }

    modifier mustOriginateFromTrustedRemote(uint16 srcChainId, bytes memory path) {
        if (
            trustedRemoteAddr != LayerZeroHelper._getFirstAddressFromPath(path) ||
            trustedRemoteChainId != LayerZeroHelper._getOriginalChainIds(srcChainId)
        ) revert Errors.NotFromTrustedRemote(srcChainId, path);
        _;
    }

    constructor(address _lzEndpoint) {
        lzEndpoint = _lzEndpoint;
    }

    function initialize(address _trustedRemoteAddr, uint64 _trustedRemoteChainId) external initializer {
        trustedRemoteAddr = _trustedRemoteAddr;
        trustedRemoteChainId = _trustedRemoteChainId;
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _path,
        uint64 /*_nonce*/,
        bytes calldata _payload
    ) external onlyLzEndpoint mustOriginateFromTrustedRemote(_srcChainId, _path) {
        int256 rate = abi.decode(_payload, (int256));
        latestAnswer = rate;
    }
}
