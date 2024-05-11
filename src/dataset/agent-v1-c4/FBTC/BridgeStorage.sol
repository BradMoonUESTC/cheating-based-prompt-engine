// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Request, UserInfo} from "./Common.sol";

contract BridgeStorage {
    address public minter;
    address public fbtc;

    EnumerableSet.AddressSet internal qualifiedUsers;

    mapping(address qualifiedUser => UserInfo info) public userInfo;
    mapping(string depositAddress => address qualifiedUser)
        public depositAddressToUser; // For uniqueness check

    bytes32[] public requestHashes;
    mapping(bytes32 _hash => Request r) public requests;

    mapping(bytes32 bytesHash => bytes32 requestHash) public usedDepositTxs;
    mapping(bytes32 bytesHash => bytes32 requestHash) public usedWithdrawalTxs;

    mapping(bytes32 srcHash => bytes32 dstHash)
        public crosschainRequestConfirmation;

    address public feeModel;
    address public feeRecipient;

    uint256[50] private __gap;
}
