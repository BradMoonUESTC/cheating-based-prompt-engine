// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

enum Operation {
    Nop, // starts from 1.
    Mint,
    Burn,
    CrosschainRequest,
    CrosschainConfirm
}

enum Status {
    Unused,
    Pending,
    Confirmed,
    Rejected
}

struct Request {
    Operation op;
    Status status;
    uint128 nonce; // Those can be packed into one slot in evm storage.
    bytes32 srcChain;
    bytes srcAddress;
    bytes32 dstChain;
    bytes dstAddress;
    uint256 amount; // Transfer value without fee.
    uint256 fee;
    bytes extra;
}

struct UserInfo {
    bool locked;
    string depositAddress;
    string withdrawalAddress;
}

library ChainCode {
    // For EVM chains, the chain code is chain id in bytes32 format.
    bytes32 constant ETH =
        0x0000000000000000000000000000000000000000000000000000000000000001;

    bytes32 constant MANTLE =
        0x0000000000000000000000000000000000000000000000000000000000001388;

    // Other chains.
    bytes32 constant BTC =
        0x0100000000000000000000000000000000000000000000000000000000000000;

    bytes32 constant SOLANA =
        0x0200000000000000000000000000000000000000000000000000000000000000;

    // For test.
    bytes32 constant XTN =
        0x0110000000000000000000000000000000000000000000000000000000000000;

    function getSelfChainCode() internal view returns (bytes32) {
        return bytes32(block.chainid);
    }
}

library RequestLib {
    /// @dev This request hash should be unique across all chains.
    ///                       op  nonce  srcChain  dstChain
    ///   (1) Mint:           1   nonce  BTC       chainid  ...
    ///   (2) Burn:           2   nonce  chainid   BTC      ...
    ///   (3) Cross:          3   nonce  chainid   dst      ...
    ///   (4) Cross confirm:  4   nonce  src       chainid  ...
    ///   On the same chain:
    ///       The `nonce` differs
    ///   On different chains:
    ///       The `chain.id` differs or the `op` differs
    function getRequestHash(
        Request memory r
    ) internal pure returns (bytes32 _hash) {
        _hash = keccak256(
            abi.encode(
                r.op,
                r.nonce,
                r.srcChain,
                r.srcAddress,
                r.dstChain,
                r.dstAddress,
                r.amount,
                r.fee,
                r.extra // For Burn, this should be none.
            )
        );
    }

    function getCrossSourceRequestHash(
        Request memory src
    ) internal pure returns (bytes32 _hash) {
        // Save.
        bytes memory extra = src.extra;
        // Set temperary data to calculate hash.
        src.op = Operation.CrosschainRequest;
        src.extra = ""; // clear
        _hash = getRequestHash(src);
        // Restore.
        src.op = Operation.CrosschainConfirm;
        src.extra = extra;
    }
}
