// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// OpenZeppelin libraries
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/// @title Minimalist ERC1155 implementation without metadata.
/// @author Axicon Labs Limited
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/v7/src/tokens/ERC1155.sol)
/// @dev Not compliant to the letter, does not include any metadata functionality.
abstract contract ERC1155 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when only a single token is transferred.
    /// @param operator The user who initiated the transfer
    /// @param from The user who sent the tokens
    /// @param to The user who received the tokens
    /// @param id The ERC1155 token id
    /// @param amount The amount of tokens transferred
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount
    );

    /// @notice Emitted when multiple tokens are transferred from one user to another.
    /// @param operator The user who initiated the transfer
    /// @param from The user who sent the tokens
    /// @param to The user who received the tokens
    /// @param ids The ERC1155 token ids
    /// @param amounts The amounts of tokens transferred
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] amounts
    );

    /// @notice Emitted when the approval status of an operator to transfer all tokens on behalf of a user is modified.
    /// @param owner The user who approved or disapproved `operator` to transfer their tokens
    /// @param operator The user who was approved or disapproved to transfer all tokens on behalf of `owner`
    /// @param approved Whether `operator` is approved or disapproved to transfer all tokens on behalf of `owner`
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user attempts to transfer tokens they do not own nor are approved to transfer.
    error NotAuthorized();

    /// @notice Emitted when an attempt is made to initiate a transfer to a contract recipient that fails to signal support for ERC1155.
    error UnsafeRecipient();

    /*//////////////////////////////////////////////////////////////
                             ERC1155 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Token balances for each user.
    /// @dev Indexed by user, then by token id.
    mapping(address account => mapping(uint256 tokenId => uint256 balance)) public balanceOf;

    /// @notice Approved addresses for each user.
    /// @dev Indexed by user, then by operator.
    /// @dev Operator is approved to transfer all tokens on behalf of user.
    mapping(address owner => mapping(address operator => bool approvedForAll))
        public isApprovedForAll;

    /*//////////////////////////////////////////////////////////////
                              ERC1155 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Approve or revoke approval for `operator` to transfer all tokens on behalf of the caller.
    /// @param operator The address to approve or revoke approval for
    /// @param approved True to approve, false to revoke approval
    function setApprovalForAll(address operator, bool approved) public {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @notice Transfer a single token from one user to another.
    /// @dev Supports approved token transfers.
    /// @param from The user to transfer tokens from
    /// @param to The user to transfer tokens to
    /// @param id The ERC1155 token id to transfer
    /// @param amount The amount of tokens to transfer
    /// @param data Optional data to include in the `onERC1155Received` hook
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) public virtual {
        if (!(msg.sender == from || isApprovedForAll[from][msg.sender])) revert NotAuthorized();

        balanceOf[from][id] -= amount;

        // balance will never overflow
        unchecked {
            balanceOf[to][id] += amount;
        }

        emit TransferSingle(msg.sender, from, to, id, amount);

        if (to.code.length != 0) {
            if (
                ERC1155Holder(to).onERC1155Received(msg.sender, from, id, amount, data) !=
                ERC1155Holder.onERC1155Received.selector
            ) {
                revert UnsafeRecipient();
            }
        }
    }

    /// @notice Transfer multiple tokens from one user to another.
    /// @dev Supports approved token transfers.
    /// @dev `ids` and `amounts` must be of equal length.
    /// @param from The user to transfer tokens from
    /// @param to The user to transfer tokens to
    /// @param ids The ERC1155 token ids to transfer
    /// @param amounts The amounts of tokens to transfer
    /// @param data Optional data to include in the `onERC1155Received` hook
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) public virtual {
        if (!(msg.sender == from || isApprovedForAll[from][msg.sender])) revert NotAuthorized();

        // Storing these outside the loop saves ~15 gas per iteration.
        uint256 id;
        uint256 amount;

        for (uint256 i = 0; i < ids.length; ) {
            id = ids[i];
            amount = amounts[i];

            balanceOf[from][id] -= amount;

            // balance will never overflow
            unchecked {
                balanceOf[to][id] += amount;
            }

            // An array can't have a total length
            // larger than the max uint256 value.
            unchecked {
                ++i;
            }
        }

        emit TransferBatch(msg.sender, from, to, ids, amounts);

        if (to.code.length != 0) {
            if (
                ERC1155Holder(to).onERC1155BatchReceived(msg.sender, from, ids, amounts, data) !=
                ERC1155Holder.onERC1155BatchReceived.selector
            ) {
                revert UnsafeRecipient();
            }
        }
    }

    /// @notice Query balances for multiple users and tokens at once.
    /// @dev `owners` and `ids` should be of equal length
    /// @param owners The list of users to query balances for
    /// @param ids The list of ERC1155 token ids to query
    /// @return balances The balances for each owner-id pair in the same order as the input arrays
    function balanceOfBatch(
        address[] calldata owners,
        uint256[] calldata ids
    ) public view returns (uint256[] memory balances) {
        balances = new uint256[](owners.length);

        // Unchecked because the only math done is incrementing
        // the array index counter which cannot possibly overflow.
        unchecked {
            for (uint256 i = 0; i < owners.length; ++i) {
                balances[i] = balanceOf[owners[i]][ids[i]];
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Signal support for ERC165 and ERC1155.
    /// @param interfaceId The interface to check for support
    /// @return Whether the interface is supported
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0xd9b67a26; // ERC165 Interface ID for ERC1155
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal utility to mint tokens to a user's account.
    /// @param to The user to mint tokens to
    /// @param id The ERC1155 token id to mint
    /// @param amount The amount of tokens to mint
    function _mint(address to, uint256 id, uint256 amount) internal {
        // balance will never overflow
        unchecked {
            balanceOf[to][id] += amount;
        }

        emit TransferSingle(msg.sender, address(0), to, id, amount);

        if (to.code.length != 0) {
            if (
                ERC1155Holder(to).onERC1155Received(msg.sender, address(0), id, amount, "") !=
                ERC1155Holder.onERC1155Received.selector
            ) {
                revert UnsafeRecipient();
            }
        }
    }

    /// @notice Internal utility to burn tokens from a user's account.
    /// @param from The user to burn tokens from
    /// @param id The ERC1155 token id to mint
    /// @param amount The amount of tokens to burn
    function _burn(address from, uint256 id, uint256 amount) internal {
        balanceOf[from][id] -= amount;

        emit TransferSingle(msg.sender, from, address(0), id, amount);
    }
}
