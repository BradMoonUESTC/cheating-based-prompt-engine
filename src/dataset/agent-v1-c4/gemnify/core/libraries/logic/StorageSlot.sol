// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DataTypes} from "../types/DataTypes.sol";

library StorageSlot {
    bytes32 constant STORAGE_VAULT_ADDRESS =
        bytes32(uint256(keccak256("gemnify.vault.adress.storage")) - 1);
    bytes32 constant STORAGE_VAULT_TOKEN_CONFIG =
        bytes32(uint256(keccak256("gemnify.vault.token.config.storage")) - 1);
    bytes32 constant STORAGE_VAULT_FEE =
        bytes32(uint256(keccak256("gemnify.vault.fee.storage")) - 1);
    bytes32 constant STORAGE_VAULT_PERMISSION =
        bytes32(uint256(keccak256("gemnify.vault.permission.storage")) - 1);
    bytes32 constant STORAGE_VAULT_NFT =
        bytes32(uint256(keccak256("gemnify.vault.nft.storage")) - 1);
    bytes32 constant STORAGE_VAULT_POSITION =
        bytes32(uint256(keccak256("gemnify.vault.position.storage")) - 1);

    function getVaultAddressStorage()
        internal
        pure
        returns (DataTypes.AddressStorage storage rs)
    {
        bytes32 position = STORAGE_VAULT_ADDRESS;
        assembly {
            rs.slot := position
        }
    }

    function getVaultTokenConfigStorage()
        internal
        pure
        returns (DataTypes.TokenConfigSotrage storage rs)
    {
        bytes32 position = STORAGE_VAULT_TOKEN_CONFIG;
        assembly {
            rs.slot := position
        }
    }

    function getVaultFeeStorage()
        internal
        pure
        returns (DataTypes.FeeStorage storage rs)
    {
        bytes32 position = STORAGE_VAULT_FEE;
        assembly {
            rs.slot := position
        }
    }

    function getVaultPermissionStorage()
        internal
        pure
        returns (DataTypes.PermissionStorage storage rs)
    {
        bytes32 position = STORAGE_VAULT_PERMISSION;
        assembly {
            rs.slot := position
        }
    }

    function getVaultNftStorage()
        internal
        pure
        returns (DataTypes.NftStorage storage rs)
    {
        bytes32 position = STORAGE_VAULT_NFT;
        assembly {
            rs.slot := position
        }
    }

    function getVaultPositionStorage()
        internal
        pure
        returns (DataTypes.PositionStorage storage rs)
    {
        bytes32 position = STORAGE_VAULT_POSITION;
        assembly {
            rs.slot := position
        }
    }
}
