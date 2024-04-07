// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.9;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/token/ERC721/IERC721.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

contract EggFarm is ERC20, Ownable {
    event DifficultyAdjusted(uint256 oldDifficulty, uint256 newDifficulty);
    event MiningRewardAdjusted(uint256 oldReward, uint256 newReward, uint256 halvingCount, uint256 nextHalvingAt);
    event RewardFound(address indexed miner, uint256 reward);

    uint256 public constant MAX_HALVINGS = 12;
    uint256 public constant TARGET_MINT_RATE = 1 minutes;
    uint256 public constant BASE_DIFFICULTY_TARGET = 0x10c6f7a0b5ed8d36b4c7f34938583621fafc8b0079a2834d26fa3fcc9ea9; // bottom 1/1,000,000 of the 256-bit hash space
    uint256 public constant DAMPENING_FACTOR = 9;

    uint256 public difficulty = 1;
    uint256 public lastMintTime;

    uint256 public miningReward = 12e18; // Initial reward of 12 tokens
    uint256 public halvingInterval = 328752; // Approx. halving interval, 1 week at 2s block time
    uint256 public halvingCount = 0;
    uint256 public nextHalvingAt = block.number + halvingInterval;

    mapping(address => bool) public usedNonces;

    constructor(uint256 initialSupply) ERC20("EggFarm", "EGG") {
        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    function mine(bytes memory signature, address nonce, address recipient) external {
        // Verify PoW
        require(verifyPoW(nonce), "Invalid PoW");

        // Recover the signer from the signature
        address signer = recoverSigner(signature, nonce);
        require(signer == nonce, "Signature verification failed");

        // Mark the nonce as used
        usedNonces[nonce] = true;

        uint256 mintedReward = getCurrentReward();

        _adjustDifficulty();
        _adjustMiningReward();

        _mint(recipient, mintedReward);
        emit RewardFound(recipient, mintedReward);
    }

    function verifyPoW(address nonce) public view returns (bool) {
        require(!usedNonces[nonce], "Nonce already used");

        bytes32 hash = keccak256(abi.encodePacked(nonce));
        uint256 target = calculateTarget();

        bool isValid = uint256(hash) < target;

        return isValid;
    }

    function calculateTarget() public view returns (uint256) {
        // Here we use a base value and adjust the target based on the difficulty level
        return BASE_DIFFICULTY_TARGET / difficulty;
    }

    function recoverSigner(bytes memory signature, address nonce) public pure returns (address) {
        // Prepare the message hash that was signed
        bytes32 messageHash = keccak256(abi.encodePacked(nonce));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        // Recover the signer's address
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        return ecrecover(ethSignedMessageHash, v, r, s);
    }

    function _splitSignature(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        // Adjust for Ethereum's signature format
        if (v < 27) v += 27;

        return (r, s, v);
    }

    function _adjustDifficulty() internal {
        uint256 oldDifficulty = difficulty;
        uint256 timeSinceLastMint = block.timestamp - lastMintTime;

        int256 deviation = (int256(timeSinceLastMint) - int256(TARGET_MINT_RATE)) / int256(DAMPENING_FACTOR);

        if (deviation > 0 && difficulty > 1) {
            difficulty -= 1;
        } else if (deviation < 0) {
            difficulty += 1;
        }

        lastMintTime = block.timestamp;

        // Emit the event if the difficulty has changed
        if (oldDifficulty != difficulty) {
            emit DifficultyAdjusted(oldDifficulty, difficulty);
        }
    }

    function _adjustMiningReward() internal {
        if (block.number >= nextHalvingAt) {
            if (halvingCount < MAX_HALVINGS) {
                uint256 oldReward = miningReward;
                miningReward /= 2; // Halve the mining reward
                halvingCount++;
                nextHalvingAt += halvingInterval;
                emit MiningRewardAdjusted(oldReward, miningReward, halvingCount, nextHalvingAt);
            }
        }
    }

    function getCurrentReward() public view returns (uint256) {
        return miningReward;
    }

    function withdrawETH(address payable _to) external onlyOwner {
        (bool success,) = payable(_to).call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function withdrawERC20(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20 tokenContract = IERC20(tokenAddress);
        require(tokenContract.transfer(msg.sender, amount), "Withdrawal failed");
    }

    function withdrawERC721(address tokenAddress, uint256 tokenId) external onlyOwner {
        IERC721 tokenContract = IERC721(tokenAddress);
        tokenContract.safeTransferFrom(address(this), msg.sender, tokenId);
    }
}