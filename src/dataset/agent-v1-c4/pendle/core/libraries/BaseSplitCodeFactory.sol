// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Create2.sol";

library CodeDeployer {
    // During contract construction, the full code supplied exists as code, and can be accessed via `codesize` and
    // `codecopy`. This is not the contract's final code however: whatever the constructor returns is what will be
    // stored as its code.
    //
    // We use this mechanism to have a simple constructor that stores whatever is appended to it. The following opcode
    // sequence corresponds to the creation code of the following equivalent Solidity contract, plus padding to make the
    // full code 32 bytes long:
    //
    // contract CodeDeployer {
    //     constructor() payable {
    //         uint256 size;
    //         assembly {
    //             size := sub(codesize(), 32) // size of appended data, as constructor is 32 bytes long
    //             codecopy(0, 32, size) // copy all appended data to memory at position 0
    //             return(0, size) // return appended data for it to be stored as code
    //         }
    //     }
    // }
    //
    // More specifically, it is composed of the following opcodes (plus padding):
    //
    // [1] PUSH1 0x20
    // [2] CODESIZE
    // [3] SUB
    // [4] DUP1
    // [6] PUSH1 0x20
    // [8] PUSH1 0x00
    // [9] CODECOPY
    // [11] PUSH1 0x00
    // [12] RETURN
    //
    // The padding is just the 0xfe sequence (invalid opcode). It is important as it lets us work in-place, avoiding
    // memory allocation and copying.
    bytes32 private constant _DEPLOYER_CREATION_CODE =
        0x602038038060206000396000f3fefefefefefefefefefefefefefefefefefefe;

    /**
     * @dev Deploys a contract with `code` as its code, returning the destination address.
     *
     * Reverts if deployment fails.
     */
    function deploy(bytes memory code) internal returns (address destination) {
        bytes32 deployerCreationCode = _DEPLOYER_CREATION_CODE;

        // We need to concatenate the deployer creation code and `code` in memory, but want to avoid copying all of
        // `code` (which could be quite long) into a new memory location. Therefore, we operate in-place using
        // assembly.

        // solhint-disable-next-line no-inline-assembly
        assembly {
            let codeLength := mload(code)

            // `code` is composed of length and data. We've already stored its length in `codeLength`, so we simply
            // replace it with the deployer creation code (which is exactly 32 bytes long).
            mstore(code, deployerCreationCode)

            // At this point, `code` now points to the deployer creation code immediately followed by `code`'s data
            // contents. This is exactly what the deployer expects to receive when created.
            destination := create(0, code, add(codeLength, 32))

            // Finally, we restore the original length in order to not mutate `code`.
            mstore(code, codeLength)
        }

        // The create opcode returns the zero address when contract creation fails, so we revert if this happens.
        require(destination != address(0), "DEPLOYMENT_FAILED_BALANCER");
    }
}

library BaseSplitCodeFactory {
    function setCreationCode(
        bytes memory creationCode
    )
        internal
        returns (
            address creationCodeContractA,
            uint256 creationCodeSizeA,
            address creationCodeContractB,
            uint256 creationCodeSizeB
        )
    {
        unchecked {
            require(creationCode.length > 0, "zero length");
            uint256 creationCodeSize = creationCode.length;

            // We are going to deploy two contracts: one with approximately the first half of `creationCode`'s contents
            // (A), and another with the remaining half (B).
            // We store the lengths in both immutable and stack variables, since immutable variables cannot be read during
            // construction.
            creationCodeSizeA = creationCodeSize / 2;

            creationCodeSizeB = creationCodeSize - creationCodeSizeA;

            // To deploy the contracts, we're going to use `CodeDeployer.deploy()`, which expects a memory array with
            // the code to deploy. Note that we cannot simply create arrays for A and B's code by copying or moving
            // `creationCode`'s contents as they are expected to be very large (> 24kB), so we must operate in-place.

            // Memory: [ code length ] [ A.data ] [ B.data ]

            // Creating A's array is simple: we simply replace `creationCode`'s length with A's length. We'll later restore
            // the original length.

            bytes memory creationCodeA;
            assembly {
                creationCodeA := creationCode
                mstore(creationCodeA, creationCodeSizeA)
            }

            // Memory: [ A.length ] [ A.data ] [ B.data ]
            //         ^ creationCodeA

            creationCodeContractA = CodeDeployer.deploy(creationCodeA);

            // Creating B's array is a bit more involved: since we cannot move B's contents, we are going to create a 'new'
            // memory array starting at A's last 32 bytes, which will be replaced with B's length. We'll back-up this last
            // byte to later restore it.

            bytes memory creationCodeB;
            bytes32 lastByteA;

            assembly {
                // `creationCode` points to the array's length, not data, so by adding A's length to it we arrive at A's
                // last 32 bytes.
                creationCodeB := add(creationCode, creationCodeSizeA)
                lastByteA := mload(creationCodeB)
                mstore(creationCodeB, creationCodeSizeB)
            }

            // Memory: [ A.length ] [ A.data[ : -1] ] [ B.length ][ B.data ]
            //         ^ creationCodeA                ^ creationCodeB

            creationCodeContractB = CodeDeployer.deploy(creationCodeB);

            // We now restore the original contents of `creationCode` by writing back the original length and A's last byte.
            assembly {
                mstore(creationCodeA, creationCodeSize)
                mstore(creationCodeB, lastByteA)
            }
        }
    }

    /**
     * @dev Returns the creation code of the contract this factory creates.
     */
    function getCreationCode(
        address creationCodeContractA,
        uint256 creationCodeSizeA,
        address creationCodeContractB,
        uint256 creationCodeSizeB
    ) internal view returns (bytes memory) {
        return
            _getCreationCodeWithArgs(
                "",
                creationCodeContractA,
                creationCodeSizeA,
                creationCodeContractB,
                creationCodeSizeB
            );
    }

    /**
     * @dev Returns the creation code that will result in a contract being deployed with `constructorArgs`.
     */
    function _getCreationCodeWithArgs(
        bytes memory constructorArgs,
        address creationCodeContractA,
        uint256 creationCodeSizeA,
        address creationCodeContractB,
        uint256 creationCodeSizeB
    ) private view returns (bytes memory code) {
        unchecked {
            // This function exists because `abi.encode()` cannot be instructed to place its result at a specific address.
            // We need for the ABI-encoded constructor arguments to be located immediately after the creation code, but
            // cannot rely on `abi.encodePacked()` to perform concatenation as that would involve copying the creation code,
            // which would be prohibitively expensive.
            // Instead, we compute the creation code in a pre-allocated array that is large enough to hold *both* the
            // creation code and the constructor arguments, and then copy the ABI-encoded arguments (which should not be
            // overly long) right after the end of the creation code.

            // Immutable variables cannot be used in assembly, so we store them in the stack first.

            uint256 creationCodeSize = creationCodeSizeA + creationCodeSizeB;
            uint256 constructorArgsSize = constructorArgs.length;

            uint256 codeSize = creationCodeSize + constructorArgsSize;

            assembly {
                // First, we allocate memory for `code` by retrieving the free memory pointer and then moving it ahead of
                // `code` by the size of the creation code plus constructor arguments, and 32 bytes for the array length.
                code := mload(0x40)
                mstore(0x40, add(code, add(codeSize, 32)))

                // We now store the length of the code plus constructor arguments.
                mstore(code, codeSize)

                // Next, we concatenate the creation code stored in A and B.
                let dataStart := add(code, 32)
                extcodecopy(creationCodeContractA, dataStart, 0, creationCodeSizeA)
                extcodecopy(creationCodeContractB, add(dataStart, creationCodeSizeA), 0, creationCodeSizeB)
            }

            // Finally, we copy the constructorArgs to the end of the array. Unfortunately there is no way to avoid this
            // copy, as it is not possible to tell Solidity where to store the result of `abi.encode()`.
            uint256 constructorArgsDataPtr;
            uint256 constructorArgsCodeDataPtr;
            assembly {
                constructorArgsDataPtr := add(constructorArgs, 32)
                constructorArgsCodeDataPtr := add(add(code, 32), creationCodeSize)
            }

            _memcpy(constructorArgsCodeDataPtr, constructorArgsDataPtr, constructorArgsSize);
        }
    }

    /**
     * @dev Deploys a contract with constructor arguments. To create `constructorArgs`, call `abi.encode()` with the
     * contract's constructor arguments, in order.
     */
    function _create2(
        uint256 amount,
        bytes32 salt,
        bytes memory constructorArgs,
        address creationCodeContractA,
        uint256 creationCodeSizeA,
        address creationCodeContractB,
        uint256 creationCodeSizeB
    ) internal returns (address) {
        unchecked {
            bytes memory creationCode = _getCreationCodeWithArgs(
                constructorArgs,
                creationCodeContractA,
                creationCodeSizeA,
                creationCodeContractB,
                creationCodeSizeB
            );
            return Create2.deploy(amount, salt, creationCode);
        }
    }

    // From
    // https://github.com/Arachnid/solidity-stringutils/blob/b9a6f6615cf18a87a823cbc461ce9e140a61c305/src/strings.sol
    function _memcpy(uint256 dest, uint256 src, uint256 len) private pure {
        unchecked {
            // Copy word-length chunks while possible
            for (; len >= 32; len -= 32) {
                assembly {
                    mstore(dest, mload(src))
                }
                dest += 32;
                src += 32;
            }

            // Copy remaining bytes
            uint256 mask = 256 ** (32 - len) - 1;
            assembly {
                let srcpart := and(mload(src), not(mask))
                let destpart := and(mload(dest), mask)
                mstore(dest, or(destpart, srcpart))
            }
        }
    }
}
