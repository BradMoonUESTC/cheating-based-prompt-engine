// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";

contract SetOperatorTest is Test {
    EthereumVaultConnectorHarness internal evc;

    event OperatorStatus(bytes19 indexed addressPrefix, address indexed operator, uint256 operatorBitField);
    event OwnerRegistered(bytes19 indexed addressPrefix, address indexed owner);

    function setUp() public {
        evc = new EthereumVaultConnectorHarness();
    }

    function test_WhenOwnerCalling_SetOperator(address alice, address operator, uint256 operatorBitField) public {
        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(operator != address(evc));
        vm.assume(!evc.haveCommonOwner(alice, operator));
        vm.assume(operatorBitField > 0);

        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        assertEq(evc.getAccountOwner(alice), address(0));
        assertEq(evc.getOperator(addressPrefix, operator), 0);

        vm.expectEmit(true, true, false, false, address(evc));
        emit OwnerRegistered(addressPrefix, alice);
        vm.expectEmit(true, true, false, true, address(evc));
        emit OperatorStatus(addressPrefix, operator, operatorBitField);
        vm.prank(alice);
        evc.setOperator(addressPrefix, operator, operatorBitField);

        assertEq(evc.getOperator(addressPrefix, operator), operatorBitField);

        for (uint256 i = 0; i < 256; ++i) {
            address account = address(uint160(uint160(alice) ^ i));
            bool isAlreadyAuthorized = operatorBitField & (1 << i) != 0;
            assertEq(evc.isAccountOperatorAuthorized(account, operator), isAlreadyAuthorized);

            // authorize the operator
            if (!isAlreadyAuthorized) {
                vm.expectEmit(true, true, false, true, address(evc));
                emit OperatorStatus(addressPrefix, operator, operatorBitField | (1 << i));
                vm.prank(alice);
                evc.setAccountOperator(account, operator, true);
            }
            assertEq(evc.isAccountOperatorAuthorized(account, operator), true);

            // deauthorize the operator
            vm.expectEmit(true, true, false, true, address(evc));
            emit OperatorStatus(addressPrefix, operator, operatorBitField & ~(1 << i));
            vm.prank(alice);
            evc.setAccountOperator(account, operator, false);
            assertEq(evc.isAccountOperatorAuthorized(account, operator), false);

            // restore to the original state if needed
            if (evc.getOperator(addressPrefix, operator) != operatorBitField) {
                vm.prank(alice);
                evc.setOperator(addressPrefix, operator, operatorBitField);
            }
        }

        // reset the operator status
        vm.expectEmit(true, true, false, true, address(evc));
        emit OperatorStatus(addressPrefix, operator, 0);
        vm.prank(alice);
        evc.setOperator(addressPrefix, operator, 0);

        assertEq(evc.getOperator(addressPrefix, operator), 0);
    }

    function test_WhenOperatorCalling_SetOperator(address alice, address operator, uint256 seed) public {
        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(operator != address(evc));
        vm.assume(!evc.haveCommonOwner(alice, operator));

        for (uint256 i = 0; i < 256; ++i) {
            address account = address(uint160(uint160(alice) ^ i));
            bytes19 addressPrefix = evc.getAddressPrefix(account);
            assertEq(evc.isAccountOperatorAuthorized(account, operator), false);

            if (i == 0) {
                assertEq(evc.getAccountOwner(account), address(0));
            } else {
                assertEq(evc.getAccountOwner(account), alice);
            }

            // authorize the operator
            if (i == 0) {
                vm.expectEmit(true, true, false, false, address(evc));
                emit OwnerRegistered(evc.getAddressPrefix(alice), alice);
            }
            vm.expectEmit(true, true, false, true, address(evc));
            emit OperatorStatus(addressPrefix, operator, 1 << i);
            vm.recordLogs();
            vm.prank(alice);
            evc.setAccountOperator(account, operator, true);
            Vm.Log[] memory logs = vm.getRecordedLogs();

            assertTrue(i == 0 ? logs.length == 2 : logs.length == 1); // OwnerRegistered event is emitted only once
            assertEq(evc.isAccountOperatorAuthorized(account, operator), true);
            assertEq(evc.getAccountOwner(account), alice);

            // the operator cannot call setOperator()
            vm.prank(operator);
            vm.expectRevert(Errors.EVC_NotAuthorized.selector);
            evc.setOperator(addressPrefix, operator, seed);

            // but the operator can deauthorize itself calling setAccountOperator()
            vm.expectEmit(true, true, false, true, address(evc));
            emit OperatorStatus(addressPrefix, operator, 0);
            vm.prank(operator);
            evc.setAccountOperator(account, operator, false);

            assertEq(evc.isAccountOperatorAuthorized(account, operator), false);
            assertEq(evc.getAccountOwner(account), alice);
        }
    }

    function test_RevertIfInvalidOperatorStatus_SetOperator(
        address alice,
        address operator,
        uint256 operatorBitField
    ) public {
        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(operator != address(evc));
        vm.assume(!evc.haveCommonOwner(alice, operator));

        bytes19 addressPrefix = evc.getAddressPrefix(alice);

        if (operatorBitField > 0) {
            vm.prank(alice);
            evc.setOperator(addressPrefix, operator, operatorBitField);
        }

        // revert when trying to set the same operator status
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_InvalidOperatorStatus.selector);
        evc.setOperator(addressPrefix, operator, operatorBitField);

        for (uint256 i = 0; i < 256; ++i) {
            address account = address(uint160(uint160(alice) ^ i));
            bool isAlreadyAuthorized = operatorBitField & (1 << i) != 0;

            // revert when trying to set the same operator status
            vm.prank(alice);
            vm.expectRevert(Errors.EVC_InvalidOperatorStatus.selector);
            evc.setAccountOperator(account, operator, isAlreadyAuthorized);
        }
    }

    function test_RevertIfSenderNotOwner_SetOperator(
        address alice,
        address operator,
        uint256 operatorBitField
    ) public {
        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(operator != address(evc));
        vm.assume(!evc.haveCommonOwner(alice, operator));
        vm.assume(addressPrefix != bytes19(type(uint152).max));
        vm.assume(operatorBitField > 0);

        // fails if address prefix does not belong to an owner
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setOperator(bytes19(uint152(addressPrefix) + 1), operator, operatorBitField);

        // succeeds if address prefix belongs to an owner
        vm.prank(alice);
        evc.setOperator(addressPrefix, operator, operatorBitField);

        // fails if owner not consistent
        vm.prank(address(uint160(uint160(alice) ^ 1)));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setOperator(addressPrefix, operator, operatorBitField);

        // reverts if sender is an operator
        vm.prank(operator);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setOperator(addressPrefix, operator, operatorBitField);
    }

    function test_RevertIfSenderNotOwnerAndNotOperator_SetAccountOperator(address alice, address operator) public {
        vm.assume(alice != address(0) && alice != address(0xfe) && alice != address(evc));
        vm.assume(operator != address(evc));
        vm.assume(!evc.haveCommonOwner(alice, operator));

        address account = address(uint160(uint160(alice) ^ 256));

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setAccountOperator(account, operator, true);

        // succeeds if sender is authorized
        account = address(uint160(uint160(alice) ^ 255));
        vm.prank(address(uint160(uint160(alice) ^ 254)));
        evc.setAccountOperator(account, operator, true);

        // reverts if sender is not a registered owner nor operator
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setAccountOperator(account, operator, true);

        // reverts if sender is not a registered owner nor operator
        vm.prank(address(uint160(uint160(operator) ^ 1)));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setAccountOperator(account, operator, true);
    }

    function test_RevertWhenOperatorNotAuthorizedToPerformTheOperation_SetAccountOperator(
        address alice,
        address operator
    ) public {
        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(!evc.haveCommonOwner(address(evc), operator));
        vm.assume(!evc.haveCommonOwner(alice, operator));

        assertEq(evc.isAccountOperatorAuthorized(alice, operator), false);

        vm.prank(alice);
        evc.setAccountOperator(alice, operator, true);
        assertEq(evc.isAccountOperatorAuthorized(alice, operator), true);

        // operator cannot change authorization status for any other operator nor account
        vm.prank(operator);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setAccountOperator(address(uint160(alice) ^ 1), operator, true);

        vm.prank(operator);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setAccountOperator(alice, address(uint160(operator) ^ 1), true);

        vm.prank(alice);
        evc.setAccountOperator(alice, address(uint160(operator) ^ 1), true);

        vm.prank(operator);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setAccountOperator(alice, address(uint160(operator) ^ 1), false);

        // operator can deauthorize itself
        vm.prank(operator);
        evc.setAccountOperator(alice, operator, false);

        assertEq(evc.isAccountOperatorAuthorized(alice, operator), false);
    }

    function test_RevertIfOperatorIsInvalidAddress_SetOperator(address alice, uint8 subAccountId) public {
        vm.assume(alice != address(evc));
        bytes19 addressPrefix = evc.getAddressPrefix(alice);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_InvalidAddress.selector);
        evc.setOperator(addressPrefix, address(evc), 0);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_InvalidAddress.selector);
        evc.setAccountOperator(alice, address(evc), true);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_InvalidAddress.selector);
        evc.setOperator(addressPrefix, address(uint160(alice) ^ subAccountId), 0);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_InvalidAddress.selector);
        evc.setAccountOperator(alice, address(uint160(alice) ^ subAccountId), true);
    }
}
