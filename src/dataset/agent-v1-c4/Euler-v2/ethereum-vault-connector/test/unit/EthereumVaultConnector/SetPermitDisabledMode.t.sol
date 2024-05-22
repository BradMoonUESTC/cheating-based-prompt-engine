// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";

contract SetPermitDisabledModeTest is Test {
    EthereumVaultConnectorHarness internal evc;

    event PermitDisabledModeStatus(bytes19 indexed addressPrefix, bool status);

    function setUp() public {
        evc = new EthereumVaultConnectorHarness();
    }

    function test_SetPermitDisabledMode(address alice) public {
        vm.assume(alice != address(0) && alice != address(evc));

        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        assertEq(evc.isPermitDisabledMode(addressPrefix), false);

        // no-op when setting permit disabled mode to the same value
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, false);
        assertEq(evc.isPermitDisabledMode(addressPrefix), false);

        vm.expectEmit(true, true, false, false, address(evc));
        emit PermitDisabledModeStatus(addressPrefix, true);

        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, true);
        assertEq(evc.isPermitDisabledMode(addressPrefix), true);

        // no-op when setting permit disabled mode to the same value
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, true);
        assertEq(evc.isPermitDisabledMode(addressPrefix), true);

        vm.expectEmit(true, true, false, false, address(evc));
        emit PermitDisabledModeStatus(addressPrefix, false);

        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, false);
        assertEq(evc.isPermitDisabledMode(addressPrefix), false);

        vm.expectEmit(true, true, false, false, address(evc));
        emit PermitDisabledModeStatus(addressPrefix, true);

        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, true);
        assertEq(evc.isPermitDisabledMode(addressPrefix), true);
    }

    function test_RevertIfChecksDeferred_SetPermitDisabledMode(address alice) public {
        vm.assume(alice != address(0) && alice != address(evc));

        bytes19 addressPrefix = evc.getAddressPrefix(alice);

        // set checks deferred
        evc.setChecksDeferred(true);

        // succeeds with checks deferred when enabling
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, true);
        assertEq(evc.isPermitDisabledMode(addressPrefix), true);

        // fails with checks deferred when disabling
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setPermitDisabledMode(addressPrefix, false);
    }

    function test_Integration_SetPermitDisabledMode(address alice, address vault, address operator) public {
        vm.assume(alice != address(0) && !evc.haveCommonOwner(alice, operator) && alice.code.length == 0);
        vm.assume(
            vault != address(0) && vault != alice && vault != operator && vault.code.length == 0
                && vault != 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a
        );
        vm.assume(operator != address(0) && operator.code.length == 0);

        bytes19 addressPrefix = evc.getAddressPrefix(alice);

        // setting nonce works when not in permit disabled mode
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, false);

        vm.prank(alice);
        evc.setNonce(addressPrefix, 0, 1);

        // setting nonce also works when in permit disabled mode
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, true);

        vm.prank(alice);
        evc.setNonce(addressPrefix, 1, 1);

        // setting operator works when not in permit disabled mode
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, false);

        vm.prank(alice);
        evc.setOperator(addressPrefix, operator, 1);

        // setting operator also works when in permit disabled mode
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, true);

        vm.prank(alice);
        evc.setOperator(addressPrefix, operator, 2);

        // enabling collateral works when not in permit disabled mode
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, false);

        vm.prank(alice);
        evc.enableCollateral(alice, vault);

        // enabling collateral still works when in permit disabled mode
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, true);

        vm.prank(alice);
        evc.enableCollateral(alice, vault);

        // external contract call works when not in permit disabled mode
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, false);

        address targetContract = address(new Target());
        bytes memory data = abi.encodeWithSelector(
            Target(targetContract).callTest.selector, address(evc), address(evc), 0, alice, false
        );

        vm.prank(alice);
        evc.call(targetContract, alice, 0, data);

        // external contract call still works when in permit disabled mode
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, true);

        vm.prank(alice);
        evc.call(targetContract, alice, 0, data);

        // control collateral works when not in permit disabled mode
        address controller = address(new Vault(evc));

        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, false);

        vm.prank(alice);
        evc.enableController(alice, controller);

        vm.prank(controller);
        evc.controlCollateral(vault, alice, 0, "");

        // control collateral still works when in permit disabled mode
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, true);

        vm.prank(controller);
        evc.controlCollateral(vault, alice, 0, "");
    }
}
