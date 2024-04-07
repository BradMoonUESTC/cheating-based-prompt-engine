// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "../core/libraries/BoringOwnableUpgradeable.sol";
import "../core/libraries/TokenHelper.sol";
import "../interfaces/IPMerkleDistributor.sol";

contract PendleMerkleDistributor is IPMerkleDistributor, UUPSUpgradeable, BoringOwnableUpgradeable, TokenHelper {
    address public immutable token;

    bytes32 public merkleRoot;

    mapping(address => uint256) public claimed;
    mapping(address => uint256) public verified;

    constructor(address _token) initializer {
        token = _token;
    }

    receive() external payable {}

    function initialize() external initializer {
        __BoringOwnable_init();
    }

    function claim(
        address receiver,
        uint256 totalAccrued,
        bytes32[] calldata proof
    ) external returns (uint256 amountOut) {
        address user = msg.sender;
        if (!_verifyMerkleData(user, totalAccrued, proof)) revert InvalidMerkleProof();

        amountOut = totalAccrued - claimed[user];
        claimed[user] = totalAccrued;

        _transferOut(token, receiver, amountOut);
        emit Claimed(user, receiver, amountOut);
    }

    function claimVerified(address receiver) external returns (uint256 amountOut) {
        address user = msg.sender;
        uint256 amountVerified = verified[user];
        uint256 amountClaimed = claimed[user];

        if (amountVerified <= amountClaimed) {
            return 0;
        }

        amountOut = amountVerified - amountClaimed;
        claimed[user] = amountVerified;

        _transferOut(token, receiver, amountOut);
        emit Claimed(user, receiver, amountOut);
    }

    function verify(
        address user,
        uint256 totalAccrued,
        bytes32[] calldata proof
    ) external returns (uint256 amountClaimable) {
        if (!_verifyMerkleData(user, totalAccrued, proof)) revert InvalidMerkleProof();
        amountClaimable = totalAccrued - claimed[user];
        verified[user] = totalAccrued;

        emit Verified(user, amountClaimable);
    }

    function _verifyMerkleData(address user, uint256 amount, bytes32[] calldata proof) internal view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(user, amount));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }

    // ----------------- owner logic -----------------
    function setMerkleRoot(bytes32 newMerkleRoot) external payable onlyOwner {
        merkleRoot = newMerkleRoot;
        emit SetMerkleRoot(merkleRoot);
    }

    // ----------------- upgrade-related -----------------

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
