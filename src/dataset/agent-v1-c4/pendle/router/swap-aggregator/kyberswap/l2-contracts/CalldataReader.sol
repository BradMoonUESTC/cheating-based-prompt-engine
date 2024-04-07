// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library CalldataReader {
    /// @notice read the bytes value of data from a starting position and length
    /// @param data bytes array of data
    /// @param startByte starting position to read
    /// @param length length from starting position
    /// @return retVal value of the bytes
    /// @return (the next position to read from)
    function _calldataVal(
        bytes memory data,
        uint256 startByte,
        uint256 length
    ) internal pure returns (bytes memory retVal, uint256) {
        require(length + startByte <= data.length, "calldataVal trying to read beyond data size");
        uint256 loops = (length + 31) / 32;
        assembly {
            let m := mload(0x40)
            mstore(m, length)
            for {
                let i := 0
            } lt(i, loops) {
                i := add(1, i)
            } {
                mstore(add(m, mul(32, add(1, i))), mload(add(data, add(mul(32, add(1, i)), startByte))))
            }
            mstore(0x40, add(m, add(32, length)))
            retVal := m
        }
        return (retVal, length + startByte);
    }

    function _readBool(bytes memory data, uint256 startByte) internal pure returns (bool, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 1);
        return (bytes1(ret) > 0, startByte);
    }

    function _readUint8(bytes memory data, uint256 startByte) internal pure returns (uint8, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 1);
        return (uint8(bytes1(ret)), startByte);
    }

    function _readUint24(bytes memory data, uint256 startByte) internal pure returns (uint24, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 3);
        return (uint24(bytes3(ret)), startByte);
    }

    function _readUint32(bytes memory data, uint256 startByte) internal pure returns (uint32, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 4);
        return (uint32(bytes4(ret)), startByte);
    }

    function _readUint128(bytes memory data, uint256 startByte) internal pure returns (uint128, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 16);
        return (uint128(bytes16(ret)), startByte);
    }

    function _readUint160(bytes memory data, uint256 startByte) internal pure returns (uint160, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 20);
        return (uint160(bytes20(ret)), startByte);
    }

    /// @dev only when sure that the value of uint256 never exceed uint128
    function _readUint128AsUint256(bytes memory data, uint256 startByte) internal pure returns (uint256, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 16);
        return (uint256(uint128(bytes16(ret))), startByte);
    }

    function _readAddress(bytes memory data, uint256 startByte) internal pure returns (address, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 20);
        return (address(bytes20(ret)), startByte);
    }

    function _readBytes1(bytes memory data, uint256 startByte) internal pure returns (bytes1, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 1);
        return (bytes1(ret), startByte);
    }

    function _readBytes4(bytes memory data, uint256 startByte) internal pure returns (bytes4, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 4);
        return (bytes4(ret), startByte);
    }

    function _readBytes32(bytes memory data, uint256 startByte) internal pure returns (bytes32, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 32);
        return (bytes32(ret), startByte);
    }

    /// @dev length of bytes is currently limited to uint32
    function _readBytes(bytes memory data, uint256 startByte) internal pure returns (bytes memory b, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 4);
        uint256 length = uint256(uint32(bytes4(ret)));
        (b, startByte) = _calldataVal(data, startByte, length);
        return (b, startByte);
    }

    /// @dev length of bytes array is currently limited to uint8
    function _readBytesArray(
        bytes memory data,
        uint256 startByte
    ) internal pure returns (bytes[] memory bytesArray, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 1);
        uint256 length = uint256(uint8(bytes1(ret)));
        bytesArray = new bytes[](length);
        for (uint8 i = 0; i < length; ++i) {
            (bytesArray[i], startByte) = _readBytes(data, startByte);
        }
        return (bytesArray, startByte);
    }

    /// @dev length of address array is currently limited to uint8 to save bytes
    function _readAddressArray(
        bytes memory data,
        uint256 startByte
    ) internal pure returns (address[] memory addrs, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 1);
        uint256 length = uint256(uint8(bytes1(ret)));
        addrs = new address[](length);
        for (uint8 i = 0; i < length; ++i) {
            (addrs[i], startByte) = _readAddress(data, startByte);
        }
        return (addrs, startByte);
    }

    /// @dev length of uint array is currently limited to uint8 to save bytes
    /// @dev same as _readUint128AsUint256, only use when sure that value never exceed uint128
    function _readUint128ArrayAsUint256Array(
        bytes memory data,
        uint256 startByte
    ) internal pure returns (uint256[] memory, uint256) {
        bytes memory ret;
        (ret, startByte) = _calldataVal(data, startByte, 1);
        uint256 length = uint256(uint8(bytes1(ret)));
        uint256[] memory us = new uint256[](length);
        for (uint8 i = 0; i < length; ++i) {
            (us[i], startByte) = _readUint128AsUint256(data, startByte);
        }
        return (us, startByte);
    }
}
