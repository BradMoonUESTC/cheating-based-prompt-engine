// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// prettier-ignore
import {
    AccessDenied,
    DeadlineExpired,
    Signature,
    InvalidEAS,
    InvalidLength,
    InvalidSignature,
    NotFound,
    NO_EXPIRATION_TIME,
    uncheckedInc
} from "../../Common.sol";

// prettier-ignore
import {
    AttestationRequest,
    AttestationRequestData,
    DelegatedAttestationRequest,
    DelegatedRevocationRequest,
    IEAS,
    MultiAttestationRequest,
    MultiDelegatedAttestationRequest,
    MultiDelegatedRevocationRequest,
    MultiRevocationRequest,
    RevocationRequest,
    RevocationRequestData
} from "../../IEAS.sol";

import { Semver } from "../../Semver.sol";

/// @notice A struct representing the full arguments of the full delegated attestation request.
struct DelegatedProxyAttestationRequest {
    bytes32 schema; // The unique identifier of the schema.
    AttestationRequestData data; // The arguments of the attestation request.
    Signature signature; // The EIP712 signature data.
    address attester; // The attesting account.
    uint64 deadline; // The deadline of the signature/request.
}

/// @notice A struct representing the full arguments of the delegated multi attestation request.
struct MultiDelegatedProxyAttestationRequest {
    bytes32 schema; // The unique identifier of the schema.
    AttestationRequestData[] data; // The arguments of the attestation requests.
    Signature[] signatures; // The EIP712 signatures data. Please note that the signatures are assumed to be signed with increasing nonces.
    address attester; // The attesting account.
    uint64 deadline; // The deadline of the signature/request.
}

/// @notice A struct representing the arguments of the full delegated revocation request.
struct DelegatedProxyRevocationRequest {
    bytes32 schema; // The unique identifier of the schema.
    RevocationRequestData data; // The arguments of the revocation request.
    Signature signature; // The EIP712 signature data.
    address revoker; // The revoking account.
    uint64 deadline; // The deadline of the signature/request.
}

/// @notice A struct representing the full arguments of the delegated multi revocation request.
struct MultiDelegatedProxyRevocationRequest {
    bytes32 schema; // The unique identifier of the schema.
    RevocationRequestData[] data; // The arguments of the revocation requests.
    Signature[] signatures; // The EIP712 signatures data. Please note that the signatures are assumed to be signed with increasing nonces.
    address revoker; // The revoking account.
    uint64 deadline; // The deadline of the signature/request.
}

/// @title EIP712Proxy
/// @notice This utility contract an be used to aggregate delegated attestations without requiring a specific order via
///     nonces. The contract doesn't request nonces and implements replay protection by storing ***immalleable***
///     signatures.
contract EIP712Proxy is Semver, EIP712 {
    error UsedSignature();

    // The hash of the data type used to relay calls to the attest function. It's the value of
    // keccak256("Attest(address attester,bytes32 schema,address recipient,uint64 expirationTime,bool revocable,bytes32 refUID,bytes data,uint256 value,uint64 deadline)").
    bytes32 private constant ATTEST_PROXY_TYPEHASH = 0xea02ffba7dcb45f6fc649714d23f315eef12e3b27f9a7735d8d8bf41eb2b1af1;

    // The hash of the data type used to relay calls to the revoke function. It's the value of
    // keccak256("Revoke(address revoker,bytes32 schema,bytes32 uid,uint256 value,uint64 deadline)").
    bytes32 private constant REVOKE_PROXY_TYPEHASH = 0x78a69a78c1a55cdff5cbf949580b410778cd9e4d1ecbe6f06a7fa8dc2441b57d;

    // The global EAS contract.
    IEAS private immutable _eas;

    // The user readable name of the signing domain.
    string private _name;

    // The global mapping between proxy attestations and their attesters, so that we can verify that only the original
    // attester is able to revert attestations by proxy.
    mapping(bytes32 uid => address attester) private _attesters;

    // Replay protection signatures.
    mapping(bytes signature => bool used) private _signatures;

    /// @dev Creates a new EIP1271Verifier instance.
    /// @param eas The address of the global EAS contract.
    /// @param name The user readable name of the signing domain.
    constructor(IEAS eas, string memory name) Semver(1, 3, 0) EIP712(name, "1.3.0") {
        if (address(eas) == address(0)) {
            revert InvalidEAS();
        }

        _eas = eas;
        _name = name;
    }

    /// @notice Returns the EAS.
    function getEAS() external view returns (IEAS) {
        return _eas;
    }

    /// @notice Returns the domain separator used in the encoding of the signatures for attest, and revoke.
    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// Returns the EIP712 type hash for the attest function.
    function getAttestTypeHash() external pure returns (bytes32) {
        return ATTEST_PROXY_TYPEHASH;
    }

    /// Returns the EIP712 type hash for the revoke function.
    function getRevokeTypeHash() external pure returns (bytes32) {
        return REVOKE_PROXY_TYPEHASH;
    }

    /// Returns the EIP712 name.
    function getName() external view returns (string memory) {
        return _name;
    }

    /// Returns the attester for a given uid.
    function getAttester(bytes32 uid) external view returns (address) {
        return _attesters[uid];
    }

    /// @notice Attests to a specific schema via the provided EIP712 signature.
    /// @param delegatedRequest The arguments of the delegated attestation request.
    /// @return The UID of the new attestation.
    ///
    /// Example:
    ///     attestByDelegation({
    ///         schema: '0x8e72f5bc0a8d4be6aa98360baa889040c50a0e51f32dbf0baa5199bd93472ebc',
    ///         data: {
    ///             recipient: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    ///             expirationTime: 1673891048,
    ///             revocable: true,
    ///             refUID: '0x0000000000000000000000000000000000000000000000000000000000000000',
    ///             data: '0x1234',
    ///             value: 0
    ///         },
    ///         signature: {
    ///             v: 28,
    ///             r: '0x148c...b25b',
    ///             s: '0x5a72...be22'
    ///         },
    ///         attester: '0xc5E8740aD971409492b1A63Db8d83025e0Fc427e',
    ///         deadline: 1673891048
    ///     })
    function attestByDelegation(
        DelegatedProxyAttestationRequest calldata delegatedRequest
    ) public payable virtual returns (bytes32) {
        _verifyAttest(delegatedRequest);

        bytes32 uid = _eas.attest{ value: msg.value }(
            AttestationRequest({ schema: delegatedRequest.schema, data: delegatedRequest.data })
        );

        _attesters[uid] = delegatedRequest.attester;

        return uid;
    }

    /// @notice Attests to multiple schemas using via provided EIP712 signatures.
    /// @param multiDelegatedRequests The arguments of the delegated multi attestation requests. The requests should be
    ///     grouped by distinct schema ids to benefit from the best batching optimization.
    /// @return The UIDs of the new attestations.
    ///
    /// Example:
    ///     multiAttestByDelegation([{
    ///         schema: '0x8e72f5bc0a8d4be6aa98360baa889040c50a0e51f32dbf0baa5199bd93472ebc',
    ///         data: [{
    ///             recipient: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    ///             expirationTime: 1673891048,
    ///             revocable: true,
    ///             refUID: '0x0000000000000000000000000000000000000000000000000000000000000000',
    ///             data: '0x1234',
    ///             value: 0
    ///         },
    ///         {
    ///             recipient: '0xdEADBeAFdeAdbEafdeadbeafDeAdbEAFdeadbeaf',
    ///             expirationTime: 0,
    ///             revocable: false,
    ///             refUID: '0x0000000000000000000000000000000000000000000000000000000000000000',
    ///             data: '0x00',
    ///             value: 0
    ///         }],
    ///         signatures: [{
    ///             v: 28,
    ///             r: '0x148c...b25b',
    ///             s: '0x5a72...be22'
    ///         },
    ///         {
    ///             v: 28,
    ///             r: '0x487s...67bb',
    ///             s: '0x12ad...2366'
    ///         }],
    ///         attester: '0x1D86495b2A7B524D747d2839b3C645Bed32e8CF4',
    ///         deadline: 1673891048
    ///     }])
    function multiAttestByDelegation(
        MultiDelegatedProxyAttestationRequest[] calldata multiDelegatedRequests
    ) public payable virtual returns (bytes32[] memory) {
        uint256 length = multiDelegatedRequests.length;
        MultiAttestationRequest[] memory multiRequests = new MultiAttestationRequest[](length);

        for (uint256 i = 0; i < length; i = uncheckedInc(i)) {
            MultiDelegatedProxyAttestationRequest calldata multiDelegatedRequest = multiDelegatedRequests[i];
            AttestationRequestData[] calldata data = multiDelegatedRequest.data;

            // Ensure that no inputs are missing.
            uint256 dataLength = data.length;
            if (dataLength == 0 || dataLength != multiDelegatedRequest.signatures.length) {
                revert InvalidLength();
            }

            // Verify EIP712 signatures. Please note that the signatures are assumed to be signed with increasing nonces.
            for (uint256 j = 0; j < dataLength; j = uncheckedInc(j)) {
                _verifyAttest(
                    DelegatedProxyAttestationRequest({
                        schema: multiDelegatedRequest.schema,
                        data: data[j],
                        signature: multiDelegatedRequest.signatures[j],
                        attester: multiDelegatedRequest.attester,
                        deadline: multiDelegatedRequest.deadline
                    })
                );
            }

            multiRequests[i] = MultiAttestationRequest({ schema: multiDelegatedRequest.schema, data: data });
        }

        bytes32[] memory uids = _eas.multiAttest{ value: msg.value }(multiRequests);

        // Store all attesters, according to the order of the attestation requests.
        uint256 uidCounter = 0;

        for (uint256 i = 0; i < length; i = uncheckedInc(i)) {
            MultiDelegatedProxyAttestationRequest calldata multiDelegatedRequest = multiDelegatedRequests[i];
            AttestationRequestData[] calldata data = multiDelegatedRequest.data;

            uint256 dataLength = data.length;
            for (uint256 j = 0; j < dataLength; j = uncheckedInc(j)) {
                _attesters[uids[uidCounter]] = multiDelegatedRequest.attester;

                unchecked {
                    ++uidCounter;
                }
            }
        }

        return uids;
    }

    /// @notice Revokes an existing attestation to a specific schema via the provided EIP712 signature.
    /// @param delegatedRequest The arguments of the delegated revocation request.
    ///
    /// Example:
    ///     revokeByDelegation({
    ///         schema: '0x8e72f5bc0a8d4be6aa98360baa889040c50a0e51f32dbf0baa5199bd93472ebc',
    ///         data: {
    ///             uid: '0xcbbc12102578c642a0f7b34fe7111e41afa25683b6cd7b5a14caf90fa14d24ba',
    ///             value: 0
    ///         },
    ///         signature: {
    ///             v: 27,
    ///             r: '0xb593...7142',
    ///             s: '0x0f5b...2cce'
    ///         },
    ///         revoker: '0x244934dd3e31bE2c81f84ECf0b3E6329F5381992',
    ///         deadline: 1673891048
    ///     })
    function revokeByDelegation(DelegatedProxyRevocationRequest calldata delegatedRequest) public payable virtual {
        _verifyRevoke(delegatedRequest);

        return
            _eas.revoke{ value: msg.value }(
                RevocationRequest({ schema: delegatedRequest.schema, data: delegatedRequest.data })
            );
    }

    /// @notice Revokes existing attestations to multiple schemas via provided EIP712 signatures.
    /// @param multiDelegatedRequests The arguments of the delegated multi revocation attestation requests. The requests
    ///     should be grouped by distinct schema ids to benefit from the best batching optimization.
    ///
    /// Example:
    ///     multiRevokeByDelegation([{
    ///         schema: '0x8e72f5bc0a8d4be6aa98360baa889040c50a0e51f32dbf0baa5199bd93472ebc',
    ///         data: [{
    ///             uid: '0x211296a1ca0d7f9f2cfebf0daaa575bea9b20e968d81aef4e743d699c6ac4b25',
    ///             value: 1000
    ///         },
    ///         {
    ///             uid: '0xe160ac1bd3606a287b4d53d5d1d6da5895f65b4b4bab6d93aaf5046e48167ade',
    ///             value: 0
    ///         }],
    ///         signatures: [{
    ///             v: 28,
    ///             r: '0x148c...b25b',
    ///             s: '0x5a72...be22'
    ///         },
    ///         {
    ///             v: 28,
    ///             r: '0x487s...67bb',
    ///             s: '0x12ad...2366'
    ///         }],
    ///         revoker: '0x244934dd3e31bE2c81f84ECf0b3E6329F5381992',
    ///         deadline: 1673891048
    ///     }])
    function multiRevokeByDelegation(
        MultiDelegatedProxyRevocationRequest[] calldata multiDelegatedRequests
    ) public payable virtual {
        uint256 length = multiDelegatedRequests.length;
        MultiRevocationRequest[] memory multiRequests = new MultiRevocationRequest[](length);

        for (uint256 i = 0; i < length; i = uncheckedInc(i)) {
            MultiDelegatedProxyRevocationRequest memory multiDelegatedRequest = multiDelegatedRequests[i];
            RevocationRequestData[] memory data = multiDelegatedRequest.data;

            // Ensure that no inputs are missing.
            uint256 dataLength = data.length;
            if (dataLength == 0 || dataLength != multiDelegatedRequest.signatures.length) {
                revert InvalidLength();
            }

            // Verify EIP712 signatures. Please note that the signatures are assumed to be signed with increasing nonces.
            for (uint256 j = 0; j < dataLength; j = uncheckedInc(j)) {
                RevocationRequestData memory requestData = data[j];

                _verifyRevoke(
                    DelegatedProxyRevocationRequest({
                        schema: multiDelegatedRequest.schema,
                        data: requestData,
                        signature: multiDelegatedRequest.signatures[j],
                        revoker: multiDelegatedRequest.revoker,
                        deadline: multiDelegatedRequest.deadline
                    })
                );
            }

            multiRequests[i] = MultiRevocationRequest({ schema: multiDelegatedRequest.schema, data: data });
        }

        _eas.multiRevoke{ value: msg.value }(multiRequests);
    }

    /// @dev Verifies delegated attestation request.
    /// @param request The arguments of the delegated attestation request.
    function _verifyAttest(DelegatedProxyAttestationRequest memory request) internal {
        if (request.deadline != NO_EXPIRATION_TIME && request.deadline < _time()) {
            revert DeadlineExpired();
        }

        AttestationRequestData memory data = request.data;
        Signature memory signature = request.signature;

        _verifyUnusedSignature(signature);

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ATTEST_PROXY_TYPEHASH,
                    request.attester,
                    request.schema,
                    data.recipient,
                    data.expirationTime,
                    data.revocable,
                    data.refUID,
                    keccak256(data.data),
                    data.value,
                    request.deadline
                )
            )
        );

        if (ECDSA.recover(digest, signature.v, signature.r, signature.s) != request.attester) {
            revert InvalidSignature();
        }
    }

    /// @dev Verifies delegated revocation request.
    /// @param request The arguments of the delegated revocation request.
    function _verifyRevoke(DelegatedProxyRevocationRequest memory request) internal {
        if (request.deadline != NO_EXPIRATION_TIME && request.deadline < _time()) {
            revert DeadlineExpired();
        }

        RevocationRequestData memory data = request.data;

        // Allow only original attesters to revoke their attestations.
        address attester = _attesters[data.uid];
        if (attester == address(0)) {
            revert NotFound();
        }

        if (attester != msg.sender) {
            revert AccessDenied();
        }

        Signature memory signature = request.signature;

        _verifyUnusedSignature(signature);

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    REVOKE_PROXY_TYPEHASH,
                    request.revoker,
                    request.schema,
                    data.uid,
                    data.value,
                    request.deadline
                )
            )
        );

        if (ECDSA.recover(digest, signature.v, signature.r, signature.s) != request.revoker) {
            revert InvalidSignature();
        }
    }

    /// @dev Ensures that the provided EIP712 signature wasn't already used.
    /// @param signature The EIP712 signature data.
    function _verifyUnusedSignature(Signature memory signature) internal {
        bytes memory packedSignature = abi.encodePacked(signature.v, signature.r, signature.s);

        if (_signatures[packedSignature]) {
            revert UsedSignature();
        }

        _signatures[packedSignature] = true;
    }

    /// @dev Returns the current's block timestamp. This method is overridden during tests and used to simulate the
    ///     current block time.
    function _time() internal view virtual returns (uint64) {
        return uint64(block.timestamp);
    }
}
