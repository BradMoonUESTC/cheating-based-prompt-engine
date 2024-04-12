// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IArbitrator} from "../../interfaces/IArbitrator.sol";
import {L2BaseGateway} from "../L2BaseGateway.sol";
import {L1BaseGateway} from "../L1BaseGateway.sol";

contract EthereumGateway is
    L1BaseGateway,
    L2BaseGateway,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    constructor(IArbitrator _arbitrator, address _zkLink) L1BaseGateway(_arbitrator) L2BaseGateway(_zkLink) {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getRemoteGateway() external view returns (address) {
        return address(this);
    }

    function sendMessage(uint256 _value, bytes calldata _callData, bytes calldata) external payable onlyArbitrator {
        require(msg.value == _value, "Invalid value");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = ZKLINK.call{value: _value}(_callData);
        require(success, "Call zkLink failed");
    }

    function sendMessage(uint256 _value, bytes calldata _callData) external payable override onlyZkLink {
        require(msg.value == _value, "Invalid value");
        // Forward message to arbitrator
        ARBITRATOR.enqueueMessage{value: _value}(_value, _callData);
        emit L2GatewayMessageSent(_value, _callData);
    }
}
