// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PermitHash} from "permit2/src/libraries/PermitHash.sol";
import {IEIP712} from "permit2/src/interfaces/IEIP712.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

contract Permit2ECDSASigner is Test {
    address private immutable permit2;

    constructor(address _permit2) {
        permit2 = _permit2;
    }

    function signPermitSingle(uint256 privateKey, IAllowanceTransfer.PermitSingle memory permitSingle)
        external
        view
        returns (bytes memory signature)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                PermitHash._PERMIT_SINGLE_TYPEHASH,
                keccak256(abi.encode(PermitHash._PERMIT_DETAILS_TYPEHASH, permitSingle.details)),
                permitSingle.spender,
                permitSingle.sigDeadline
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey, keccak256(abi.encodePacked("\x19\x01", IEIP712(permit2).DOMAIN_SEPARATOR(), structHash))
        );
        signature = abi.encodePacked(r, s, v);
    }
}
