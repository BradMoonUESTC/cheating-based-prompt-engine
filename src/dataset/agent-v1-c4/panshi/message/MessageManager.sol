// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../../interfaces/IMessageManager.sol";

contract MessageManager is
    Initializable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    IMessageManager
{
    uint256 public nextMessageNumber;
    address public poolManagerAddress;
    mapping(bytes32 => bool) public sentMessageStatus;
    mapping(bytes32 => bool) public cliamMessageStatus;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _poolManagerAddress) public initializer {
        poolManagerAddress = _poolManagerAddress;
        nextMessageNumber = 1;
    }

    modifier onlyTokenBridge() {
        require(
            msg.sender == poolManagerAddress,
            "MessageManager: only token bridge can do this operate"
        );
        _;
    }

    function sendMessage(
        uint256 sourceChainId,
        uint256 destChainId,
        address _to,
        uint256 _value,
        uint256 _fee
    ) external onlyTokenBridge {
        if (_to == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        uint256 messageNumber = nextMessageNumber;
        bytes32 messageHash = keccak256(
            abi.encode(
                sourceChainId,
                destChainId,
                _to,
                _fee,
                _value,
                messageNumber
            )
        );
        nextMessageNumber++;
        sentMessageStatus[messageHash] = true;
        emit MessageSent(
            sourceChainId,
            destChainId,
            msg.sender,
            _to,
            _fee,
            _value,
            messageNumber,
            messageHash
        );
    }

    function claimMessage(
        uint256 sourceChainId,
        uint256 destChainId,
        address _to,
        uint256 _fee,
        uint256 _value,
        uint256 _nonce
    ) external onlyTokenBridge nonReentrant {
        bytes32 messageHash = keccak256(
            abi.encode(sourceChainId, destChainId, _to, _fee, _value, _nonce)
        );
        cliamMessageStatus[messageHash] = true;
        emit MessageClaimed(sourceChainId, destChainId, messageHash);
    }

    //    function setPerFee(address _poolManagerAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
    //        poolManagerAddress = _poolManagerAddress;
    //    }
}
