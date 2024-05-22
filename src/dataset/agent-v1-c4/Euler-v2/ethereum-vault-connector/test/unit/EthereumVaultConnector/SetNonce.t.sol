// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";

contract SetNonceTest is Test {
    EthereumVaultConnectorHarness internal evc;

    event NonceStatus(
        bytes19 indexed addressPrefix, uint256 indexed nonceNamespace, uint256 oldNonce, uint256 newNonce
    );

    function setUp() public {
        evc = new EthereumVaultConnectorHarness();
    }

    function test_SetNonce(address alice, uint256 nonceNamespace, uint128 nonce) public {
        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(nonce > 0);

        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        assertEq(evc.getNonce(addressPrefix, nonceNamespace), 0);

        vm.expectEmit(true, true, false, true, address(evc));
        emit NonceStatus(addressPrefix, nonceNamespace, 0, nonce);
        vm.prank(alice);
        evc.setNonce(addressPrefix, nonceNamespace, nonce);
        assertEq(evc.getNonce(addressPrefix, nonceNamespace), nonce);

        vm.expectEmit(true, true, false, true, address(evc));
        emit NonceStatus(addressPrefix, nonceNamespace, nonce, 2 * uint256(nonce));
        vm.prank(alice);
        evc.setNonce(addressPrefix, nonceNamespace, 2 * uint256(nonce));
        assertEq(evc.getNonce(addressPrefix, nonceNamespace), 2 * uint256(nonce));
    }

    function test_RevertIfSenderNotOwner_SetNonce(
        address alice,
        address operator,
        uint256 nonceNamespace,
        uint256 nonce
    ) public {
        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(addressPrefix != bytes19(type(uint152).max));
        vm.assume(operator != address(0) && operator != address(evc));
        vm.assume(!evc.haveCommonOwner(alice, operator));
        vm.assume(nonce > 0);

        // fails if address prefix does not belong to an owner
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setNonce(bytes19(uint152(addressPrefix) + 1), nonceNamespace, nonce);

        // succeeds if address prefix belongs to an owner
        vm.prank(alice);
        evc.setNonce(addressPrefix, nonceNamespace, nonce);

        // fails if owner not consistent
        vm.prank(address(uint160(uint160(alice) ^ 1)));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setNonce(addressPrefix, nonceNamespace, nonce);

        // reverts if sender is an operator
        vm.prank(alice);
        evc.setAccountOperator(alice, operator, true);

        vm.prank(operator);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setNonce(addressPrefix, nonceNamespace, nonce);
    }

    function test_RevertIfInvalidNonce_SetNonce(address alice, uint256 nonceNamespace, uint256 nonce) public {
        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(nonce > 0);

        bytes19 addressPrefix = evc.getAddressPrefix(alice);

        // fails if invalid nonce
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_InvalidNonce.selector);
        evc.setNonce(addressPrefix, nonceNamespace, 0);

        // succeeds if valid nonce
        vm.prank(alice);
        evc.setNonce(addressPrefix, nonceNamespace, nonce);

        // fails again if invalid nonce
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_InvalidNonce.selector);
        evc.setNonce(addressPrefix, nonceNamespace, nonce);
    }
}
