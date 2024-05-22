// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/EthereumVaultConnector.sol";

contract EVCHarness is EthereumVaultConnector {
    function permitHash(
        address signer,
        address sender,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256 value,
        bytes calldata data
    ) external view returns (bytes32) {
        return getPermitHash(signer, sender, nonceNamespace, nonce, deadline, value, data);
    }

    function getIsValidERC1271Signature(
        address signer,
        bytes32 hash,
        bytes memory signature
    ) external returns (bool isValid) {
        // for compatibility with scribble, do not make this view
        return isValidERC1271Signature(signer, hash, signature);
    }
}

contract EVCGas is Test {
    using Set for SetStorage;

    EVCHarness evc;

    function setUp() public {
        evc = new EVCHarness();
    }

    function testGas_getPermitHash(
        address signer,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256 value,
        bytes calldata data
    ) public view {
        evc.permitHash(signer, address(this), nonceNamespace, nonce, deadline, value, data);
    }

    function testGas_haveCommonOwner(address a, address b) public view {
        evc.haveCommonOwner(a, b);
    }

    function testGas_isValidSignature_eoa(address signer, bytes32 hash, bytes memory signature) public {
        vm.assume(!evc.haveCommonOwner(signer, address(0)));
        vm.assume(signature.length < 100);
        evc.getIsValidERC1271Signature(signer, hash, signature);
    }

    function testGas_isValidSignature_contract(address signer, bytes32 hash, bytes memory signature) public {
        vm.assume(signer != address(evc) && uint160(signer) > 1000);
        vm.assume(signature.length < 100);
        vm.etch(signer, "ff");
        evc.getIsValidERC1271Signature(signer, hash, signature);
    }
}
