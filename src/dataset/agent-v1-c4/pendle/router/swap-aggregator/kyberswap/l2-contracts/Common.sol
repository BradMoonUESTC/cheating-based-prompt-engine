// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CalldataReader.sol";

library Common {
    using CalldataReader for bytes;

    function _readPool(bytes memory data, uint256 startByte) internal pure returns (address, uint256) {
        uint24 poolId;
        address poolAddress;
        (poolId, startByte) = data._readUint24(startByte);
        if (poolId == 0) {
            (poolAddress, startByte) = data._readAddress(startByte);
        }
        return (poolAddress, startByte);
    }

    function _readRecipient(bytes memory data, uint256 startByte) internal pure returns (address, uint256) {
        uint8 recipientFlag;
        address recipient;
        (recipientFlag, startByte) = data._readUint8(startByte);
        if (recipientFlag != 2 && recipientFlag != 1) {
            (recipient, startByte) = data._readAddress(startByte);
        }
        return (recipient, startByte);
    }

    function _readBytes32Array(
        bytes memory data,
        uint256 startByte
    ) internal pure returns (bytes32[] memory bytesArray, uint256) {
        bytes memory ret;
        (ret, startByte) = data._calldataVal(startByte, 1);
        uint256 length = uint256(uint8(bytes1(ret)));
        bytesArray = new bytes32[](length);
        for (uint8 i = 0; i < length; ++i) {
            (bytesArray[i], startByte) = data._readBytes32(startByte);
        }
        return (bytesArray, startByte);
    }
}
