// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {DoubleEndedQueueUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/DoubleEndedQueueUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IArbitrator} from "./interfaces/IArbitrator.sol";
import {IL1Gateway} from "./interfaces/IL1Gateway.sol";
import {IAdmin} from "./zksync/l1-contracts/zksync/interfaces/IAdmin.sol";
import {IZkSync} from "./zksync/l1-contracts/zksync/interfaces/IZkSync.sol";
import {FeeParams} from "./zksync/l1-contracts/zksync/Storage.sol";

/// @title Arbitrator contract
/// @author zk.link
contract Arbitrator is IArbitrator, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using DoubleEndedQueueUpgradeable for DoubleEndedQueueUpgradeable.Bytes32Deque;

    /// @dev The gateway for sending message from ethereum to primary chain
    IL1Gateway public primaryChainGateway;
    /// @dev The gateway for sending message from ethereum to secondary chain
    mapping(IL1Gateway => bool) public secondaryChainGateways;
    /// @dev A message hash queue waiting to forward to all secondary chains
    DoubleEndedQueueUpgradeable.Bytes32Deque public primaryChainMessageHashQueue;
    /// @dev A message hash queue waiting to forward to primary chain
    mapping(IL1Gateway => DoubleEndedQueueUpgradeable.Bytes32Deque) public secondaryChainMessageHashQueues;
    /// @notice List of permitted relayers
    mapping(address relayerAddress => bool isRelayer) public relayers;
    /// @dev A transient storage value for forwarding message from source chain to target chains
    bytes32 private finalizeMessageHash;
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;

    /// @notice Primary chain gateway init
    event InitPrimaryChain(IL1Gateway indexed gateway);
    /// @notice SecondaryChain's status changed
    event SecondaryChainStatusUpdate(IL1Gateway indexed gateway, bool isActive);
    /// @notice Relayer's status changed
    event RelayerStatusUpdate(address indexed relayer, bool isActive);
    /// @notice Validator's status changed
    event ValidatorStatusUpdate(IL1Gateway indexed gateway, address validatorAddress, bool isActive);
    /// @notice Fee params for L1->L2 transactions changed
    event NewFeeParams(IL1Gateway indexed gateway, FeeParams newFeeParams);
    /// @notice Emit when receive message from l1 gateway
    event MessageReceived(uint256 value, bytes callData);
    /// @notice Emit when forward message to l1 gateway
    event MessageForwarded(IL1Gateway indexed gateway, uint256 value, bytes callData);

    /// @notice Checks if relayer is active
    modifier onlyRelayer() {
        require(relayers[msg.sender], "Not relayer"); // relayer is not active
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // can only call by owner
    }

    /// @notice Return the message hash at a position stored in queue
    function getMessageHash(IL1Gateway _gateway, uint256 _index) external view returns (bytes32 messageHash) {
        if (_gateway == primaryChainGateway) {
            messageHash = primaryChainMessageHashQueue.at(_index);
        } else {
            messageHash = secondaryChainMessageHashQueues[_gateway].at(_index);
        }
    }

    /// @dev Set primary chain
    function setPrimaryChainGateway(IL1Gateway _gateway) external onlyOwner {
        require(address(primaryChainGateway) == address(0), "Duplicate init gateway");
        require(address(_gateway) != address(0), "Invalid gateway");
        primaryChainGateway = _gateway;
        emit InitPrimaryChain(_gateway);
    }

    /// @dev Set secondary chain
    function setSecondaryChainGateway(
        IL1Gateway _gateway,
        bool _active,
        bytes calldata _adapterParams
    ) external payable onlyOwner {
        require(_gateway != primaryChainGateway, "Invalid gateway");
        if (_active != secondaryChainGateways[_gateway]) {
            secondaryChainGateways[_gateway] = _active;
            bytes memory callData = abi.encodeCall(IZkSync.setSecondaryChainGateway, (address(_gateway), _active));
            // Forward fee to send message
            primaryChainGateway.sendMessage{value: msg.value}(0, callData, _adapterParams);
            emit SecondaryChainStatusUpdate(_gateway, _active);
        }
    }

    /// @dev Set relayer
    function setRelayer(address _relayer, bool _active) external onlyOwner {
        if (relayers[_relayer] != _active) {
            relayers[_relayer] = _active;
            emit RelayerStatusUpdate(_relayer, _active);
        }
    }

    /// @dev Set validator for a chain
    function setValidator(
        IL1Gateway _gateway,
        address _validator,
        bool _active,
        bytes calldata _adapterParams
    ) external payable onlyOwner {
        require(_gateway == primaryChainGateway || secondaryChainGateways[_gateway], "Invalid gateway");
        bytes memory callData = abi.encodeCall(IAdmin.setValidator, (_validator, _active));
        // Forward fee to send message
        _gateway.sendMessage{value: msg.value}(0, callData, _adapterParams);
        emit ValidatorStatusUpdate(_gateway, _validator, _active);
    }

    /// @dev Change fee params for a chain
    function changeFeeParams(
        IL1Gateway _gateway,
        FeeParams calldata _newFeeParams,
        bytes calldata _adapterParams
    ) external payable onlyOwner {
        require(_gateway == primaryChainGateway || secondaryChainGateways[_gateway], "Invalid gateway");
        bytes memory callData = abi.encodeCall(IAdmin.changeFeeParams, (_newFeeParams));
        // Forward fee to send message
        _gateway.sendMessage{value: msg.value}(0, callData, _adapterParams);
        emit NewFeeParams(_gateway, _newFeeParams);
    }

    function enqueueMessage(uint256 _value, bytes calldata _callData) external payable {
        require(msg.value == _value, "Invalid msg value");
        // store message hash for forwarding
        bytes32 _finalizeMessageHash = keccak256(abi.encode(_value, _callData));
        IL1Gateway gateway = IL1Gateway(msg.sender);
        if (gateway == primaryChainGateway) {
            primaryChainMessageHashQueue.pushBack(_finalizeMessageHash);
        } else {
            require(secondaryChainGateways[gateway], "Not secondary chain gateway");
            secondaryChainMessageHashQueues[gateway].pushBack(_finalizeMessageHash);
        }
        emit MessageReceived(_value, _callData);
    }

    /// @dev This function is called within the `claimMessageCallback` of L1 gateway
    function receiveMessage(uint256 _value, bytes calldata _callData) external payable {
        require(msg.value == _value, "Invalid msg value");
        // temporary store message hash for forwarding
        IL1Gateway gateway = IL1Gateway(msg.sender);
        require(gateway == primaryChainGateway || secondaryChainGateways[gateway], "Invalid gateway");
        bytes32 _finalizeMessageHash = keccak256(abi.encode(msg.sender, _value, _callData));
        assembly {
            tstore(finalizeMessageHash.slot, _finalizeMessageHash)
        }
    }

    function forwardMessage(
        IL1Gateway _gateway,
        uint256 _value,
        bytes calldata _callData,
        bytes calldata _adapterParams
    ) external payable nonReentrant onlyRelayer {
        bytes32 _finalizeMessageHash = keccak256(abi.encode(_value, _callData));
        if (_gateway == primaryChainGateway) {
            require(_finalizeMessageHash == primaryChainMessageHashQueue.popFront(), "Invalid finalize message hash");
            // Unpack destination chain and final callData
            (IL1Gateway secondaryChainGateway, bytes memory finalCallData) = abi.decode(_callData, (IL1Gateway, bytes));
            require(secondaryChainGateways[secondaryChainGateway], "Invalid secondary chain gateway");
            // Forward fee to send message
            secondaryChainGateway.sendMessage{value: msg.value + _value}(_value, finalCallData, _adapterParams);
        } else {
            require(secondaryChainGateways[_gateway], "Not secondary chain gateway");
            require(
                _finalizeMessageHash == secondaryChainMessageHashQueues[_gateway].popFront(),
                "Invalid finalize message hash"
            );
            // Forward fee to send message
            primaryChainGateway.sendMessage{value: msg.value + _value}(_value, _callData, _adapterParams);
        }
        emit MessageForwarded(_gateway, _value, _callData);
    }

    function claimMessage(
        address _sourceChainCanonicalMessageService,
        bytes calldata _sourceChainClaimCallData,
        IL1Gateway _sourceChainL1Gateway,
        uint256 _receiveValue,
        bytes calldata _receiveCallData,
        bytes calldata _forwardParams
    ) external payable nonReentrant onlyRelayer {
        // Call the claim interface of source chain message service
        // And it will inner call the `claimMessageCallback` interface of source chain L1Gateway
        // In the `claimMessageCallback` of L1Gateway, it will inner call `receiveMessage` of Arbitrator
        // No use of return value
        Address.functionCall(_sourceChainCanonicalMessageService, _sourceChainClaimCallData);

        // Load the transient `finalizeMessageHash`
        bytes32 _finalizeMessageHash;
        assembly {
            _finalizeMessageHash := tload(finalizeMessageHash.slot)
        }
        require(
            _finalizeMessageHash == keccak256(abi.encode(_sourceChainL1Gateway, _receiveValue, _receiveCallData)),
            "Incorrect finalize data"
        );

        // The msg value should be equal to the combined cost of all messages delivered from l1 to l2
        // The excess fees will be refunded to the relayer by rollup canonical message service
        if (_sourceChainL1Gateway == primaryChainGateway) {
            // Unpack destination chain and final callData
            bytes[] memory gatewayDataList = abi.decode(_receiveCallData, (bytes[]));
            bytes[] memory gatewayForwardParamsList = abi.decode(_forwardParams, (bytes[]));
            uint256 gatewayLength = gatewayDataList.length;
            require(gatewayLength == gatewayForwardParamsList.length, "Invalid forward params length");
            uint256 totalCallValue;
            uint256 totalSendMsgFee;
            unchecked {
                for (uint256 i = 0; i < gatewayLength; ++i) {
                    bytes memory gatewayData = gatewayDataList[i];
                    bytes memory gatewayForwardParams = gatewayForwardParamsList[i];
                    (IL1Gateway targetGateway, uint256 targetCallValue, bytes memory targetCallData) = abi.decode(
                        gatewayData,
                        (IL1Gateway, uint256, bytes)
                    );
                    require(secondaryChainGateways[targetGateway], "Invalid secondary chain gateway");
                    totalCallValue += targetCallValue;
                    (uint256 sendMsgFee, bytes memory adapterParams) = abi.decode(
                        gatewayForwardParams,
                        (uint256, bytes)
                    );
                    totalSendMsgFee += sendMsgFee;
                    // Forward fee to send message
                    targetGateway.sendMessage{value: sendMsgFee + targetCallValue}(
                        targetCallValue,
                        targetCallData,
                        adapterParams
                    );
                    emit MessageForwarded(targetGateway, targetCallValue, targetCallData);
                }
            }
            require(totalCallValue == _receiveValue, "Invalid call value");
            require(totalSendMsgFee == msg.value, "Invalid send msg fee");
        } else {
            IL1Gateway targetGateway = primaryChainGateway;
            // Forward fee to send message
            targetGateway.sendMessage{value: msg.value + _receiveValue}(
                _receiveValue,
                _receiveCallData,
                _forwardParams
            );
            emit MessageForwarded(targetGateway, _receiveValue, _receiveCallData);
        }
    }
}
