// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IEAS, AttestationRequest, AttestationRequestData, Attestation } from "./IEAS.sol";
import { EMPTY_UID, uncheckedInc } from "./Common.sol";
import { Semver } from "./Semver.sol";

/// @title Indexer
/// @notice Indexing Service for the Ethereum Attestation Service
contract Indexer is Semver {
    error InvalidEAS();
    error InvalidAttestation();
    error InvalidOffset();

    /// @notice Emitted when an attestation has been indexed.
    /// @param uid The UID the attestation.
    event Indexed(bytes32 indexed uid);

    /// A mapping between an account and its received attestations.
    mapping(address account => mapping(bytes32 => bytes32[] uids) receivedAttestations) private _receivedAttestations;

    // A mapping between an account and its sent attestations.
    mapping(address account => mapping(bytes32 => bytes32[] uids) sentAttestations) private _sentAttestations;

    // A mapping between a schema, attester, and recipient.
    mapping(bytes32 schemaUID => mapping(address attester => mapping(address recipient => bytes32[] uids)))
        private _schemaAttesterRecipientAttestations;

    // A mapping between a schema and its attestations.
    mapping(bytes32 schemaUID => bytes32[] uids) private _schemaAttestations;

    // The global mapping of attestation indexing status.
    mapping(bytes32 attestationUID => bool status) private _indexedAttestations;

    // The address of the global EAS contract.
    IEAS private immutable _eas;

    /// @dev Creates a new Indexer instance.
    /// @param eas The address of the global EAS contract.
    constructor(IEAS eas) Semver(1, 3, 0) {
        if (address(eas) == address(0)) {
            revert InvalidEAS();
        }

        _eas = eas;
    }

    /// @notice Returns the EAS.
    function getEAS() external view returns (IEAS) {
        return _eas;
    }

    /// @notice Indexes an existing attestation.
    /// @param attestationUID The UID of the attestation to index.
    function indexAttestation(bytes32 attestationUID) external {
        _indexAttestation(attestationUID);
    }

    /// @notice Indexes multiple existing attestations.
    /// @param attestationUIDs The UIDs of the attestations to index.
    function indexAttestations(bytes32[] calldata attestationUIDs) external {
        uint256 length = attestationUIDs.length;
        for (uint256 i = 0; i < length; i = uncheckedInc(i)) {
            _indexAttestation(attestationUIDs[i]);
        }
    }

    /// @notice Returns whether an existing attestation has been already indexed.
    /// @param attestationUID The UID of the attestation to check.
    /// @return Whether an attestation has been already indexed.
    function isAttestationIndexed(bytes32 attestationUID) external view returns (bool) {
        return _indexedAttestations[attestationUID];
    }

    /// @notice Returns the UIDs of attestations to a specific schema which were attested to/received by a specific
    ///     recipient.
    /// @param recipient The recipient of the attestation.
    /// @param schema The UID of the schema.
    /// @param start The offset to start from.
    /// @param length The number of total members to retrieve.
    /// @param reverseOrder Whether the offset starts from the end and the data is returned in reverse.
    /// @return An array of attestation UIDs.
    function getReceivedAttestationUIDs(
        address recipient,
        bytes32 schema,
        uint256 start,
        uint256 length,
        bool reverseOrder
    ) external view returns (bytes32[] memory) {
        return _sliceUIDs(_receivedAttestations[recipient][schema], start, length, reverseOrder);
    }

    /// @notice Returns the total number of attestations to a specific schema which were attested to/received by a
    ///     specific recipient.
    /// @param recipient The recipient of the attestation.
    /// @param schema The UID of the schema.
    /// @return The total number of attestations.
    function getReceivedAttestationUIDCount(address recipient, bytes32 schema) external view returns (uint256) {
        return _receivedAttestations[recipient][schema].length;
    }

    /// @notice Returns the UIDs of attestations to a specific schema which were attested by a specific attester.
    /// @param attester The attester of the attestation.
    /// @param schema The UID of the schema.
    /// @param start The offset to start from.
    /// @param length The number of total members to retrieve.
    /// @param reverseOrder Whether the offset starts from the end and the data is returned in reverse.
    /// @return An array of attestation UIDs.
    function getSentAttestationUIDs(
        address attester,
        bytes32 schema,
        uint256 start,
        uint256 length,
        bool reverseOrder
    ) external view returns (bytes32[] memory) {
        return _sliceUIDs(_sentAttestations[attester][schema], start, length, reverseOrder);
    }

    /// @notice Returns the total number of attestations to a specific schema which were attested by a specific
    /// attester.
    /// @param attester The attester of the attestation.
    /// @param schema The UID of the schema.
    /// @return The total number of attestations.
    function getSentAttestationUIDCount(address attester, bytes32 schema) external view returns (uint256) {
        return _sentAttestations[attester][schema].length;
    }

    /// @notice Returns the UIDs of attestations to a specific schema which were attested by a specific attester to a
    ///     specific recipient.
    /// @param schema The UID of the schema.
    /// @param attester The attester of the attestation.
    /// @param recipient The recipient of the attestation.
    /// @param start The offset to start from.
    /// @param length The number of total members to retrieve.
    /// @param reverseOrder Whether the offset starts from the end and the data is returned in reverse.
    /// @return An array of attestation UIDs.
    function getSchemaAttesterRecipientAttestationUIDs(
        bytes32 schema,
        address attester,
        address recipient,
        uint256 start,
        uint256 length,
        bool reverseOrder
    ) external view returns (bytes32[] memory) {
        return
            _sliceUIDs(_schemaAttesterRecipientAttestations[schema][attester][recipient], start, length, reverseOrder);
    }

    /// @notice Returns the total number of UIDs of attestations to a specific schema which were attested by a specific
    ///     attester to a specific recipient.
    /// @param schema The UID of the schema.
    /// @param attester The attester of the attestation.
    /// @param recipient The recipient of the attestation.
    /// @return An array of attestation UIDs.
    function getSchemaAttesterRecipientAttestationUIDCount(
        bytes32 schema,
        address attester,
        address recipient
    ) external view returns (uint256) {
        return _schemaAttesterRecipientAttestations[schema][attester][recipient].length;
    }

    /// @notice Returns the UIDs of attestations to a specific schema.
    /// @param schema The UID of the schema.
    /// @param start The offset to start from.
    /// @param length The number of total members to retrieve.
    /// @param reverseOrder Whether the offset starts from the end and the data is returned in reverse.
    /// @return An array of attestation UIDs.
    function getSchemaAttestationUIDs(
        bytes32 schema,
        uint256 start,
        uint256 length,
        bool reverseOrder
    ) external view returns (bytes32[] memory) {
        return _sliceUIDs(_schemaAttestations[schema], start, length, reverseOrder);
    }

    /// @notice Returns the total number of attestations to a specific schema.
    /// @param schema The UID of the schema.
    /// @return An array of attestation UIDs.
    function getSchemaAttestationUIDCount(bytes32 schema) external view returns (uint256) {
        return _schemaAttestations[schema].length;
    }

    /// @dev Indexes an existing attestation.
    /// @param attestationUID The UID of the attestation to index.
    function _indexAttestation(bytes32 attestationUID) private {
        // Skip already indexed attestations.
        if (_indexedAttestations[attestationUID]) {
            return;
        }

        // Check if the attestation exists.
        Attestation memory attestation = _eas.getAttestation(attestationUID);

        bytes32 uid = attestation.uid;
        if (uid == EMPTY_UID) {
            revert InvalidAttestation();
        }

        // Index the attestation.
        address attester = attestation.attester;
        address recipient = attestation.recipient;
        bytes32 schema = attestation.schema;

        _indexedAttestations[attestationUID] = true;
        _schemaAttestations[schema].push(attestationUID);
        _receivedAttestations[recipient][schema].push(attestationUID);
        _sentAttestations[attester][schema].push(attestationUID);
        _schemaAttesterRecipientAttestations[schema][attester][recipient].push(attestationUID);

        emit Indexed({ uid: uid });
    }

    /// @dev Returns a slice in an array of attestation UIDs.
    /// @param uids The array of attestation UIDs.
    /// @param start The offset to start from.
    /// @param length The number of total members to retrieve.
    /// @param reverseOrder Whether the offset starts from the end and the data is returned in reverse.
    /// @return An array of attestation UIDs.
    function _sliceUIDs(
        bytes32[] memory uids,
        uint256 start,
        uint256 length,
        bool reverseOrder
    ) private pure returns (bytes32[] memory) {
        uint256 attestationsLength = uids.length;
        if (attestationsLength == 0) {
            return new bytes32[](0);
        }

        if (start >= attestationsLength) {
            revert InvalidOffset();
        }

        unchecked {
            uint256 len = length;
            if (attestationsLength < start + length) {
                len = attestationsLength - start;
            }

            bytes32[] memory res = new bytes32[](len);

            for (uint256 i = 0; i < len; ++i) {
                res[i] = uids[reverseOrder ? attestationsLength - (start + i + 1) : start + i];
            }

            return res;
        }
    }
}
