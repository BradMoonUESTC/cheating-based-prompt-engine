// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";

contract SetLockdownModeTest is Test {
    EthereumVaultConnectorHarness internal evc;

    event LockdownModeStatus(bytes19 indexed addressPrefix, bool status);

    function setUp() public {
        evc = new EthereumVaultConnectorHarness();
    }

    function test_SetLockdownMode(address alice) public {
        vm.assume(alice != address(0) && alice != address(evc));

        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        assertEq(evc.isLockdownMode(addressPrefix), false);

        // no-op when setting lockdown mode to the same value
        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, false);
        assertEq(evc.isLockdownMode(addressPrefix), false);

        vm.expectEmit(true, true, false, false, address(evc));
        emit LockdownModeStatus(addressPrefix, true);

        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, true);
        assertEq(evc.isLockdownMode(addressPrefix), true);

        // no-op when setting lockdown mode to the same value
        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, true);
        assertEq(evc.isLockdownMode(addressPrefix), true);

        vm.expectEmit(true, true, false, false, address(evc));
        emit LockdownModeStatus(addressPrefix, false);

        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, false);
        assertEq(evc.isLockdownMode(addressPrefix), false);

        vm.expectEmit(true, true, false, false, address(evc));
        emit LockdownModeStatus(addressPrefix, true);

        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, true);
        assertEq(evc.isLockdownMode(addressPrefix), true);
    }

    function test_RevertIfChecksDeferred_SetLockdownMode(address alice) public {
        vm.assume(alice != address(0) && alice != address(evc));

        bytes19 addressPrefix = evc.getAddressPrefix(alice);

        // set checks deferred
        evc.setChecksDeferred(true);

        // succeeds with checks deferred when enabling
        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, true);
        assertEq(evc.isLockdownMode(addressPrefix), true);

        // fails with checks deferred when disabling
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setLockdownMode(addressPrefix, false);
    }

    function test_Integration_SetLockdownMode(address alice, address vault, address operator) public {
        vm.assume(alice != address(0) && alice != address(evc) && !evc.haveCommonOwner(alice, operator));
        vm.assume(
            vault != address(0) && vault != address(evc) && vault != address(this) && vault != alice
                && vault != operator && !evc.haveCommonOwner(vault, address(0)) && vault.code.length == 0
        );
        vm.assume(operator != address(0) && operator != address(evc));

        bytes19 addressPrefix = evc.getAddressPrefix(alice);

        // setting nonce works when not in lockdown mode
        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, false);

        vm.prank(alice);
        evc.setNonce(addressPrefix, 0, 1);

        // setting nonce also works when in lockdown mode
        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, true);

        vm.prank(alice);
        evc.setNonce(addressPrefix, 1, 1);

        // setting operator works when not in lockdown mode
        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, false);

        vm.prank(alice);
        evc.setOperator(addressPrefix, operator, 1);

        // setting operator also works when in lockdown mode
        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, true);

        vm.prank(alice);
        evc.setOperator(addressPrefix, operator, 2);

        // enabling collateral works when not in lockdown mode
        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, false);

        vm.prank(alice);
        evc.enableCollateral(alice, vault);

        // enabling collateral doesn't work when in lockdown mode
        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, true);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_LockdownMode.selector);
        evc.enableCollateral(alice, vault);

        // external contract call works when not in lockdown mode
        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, false);

        address targetContract = address(new Target());
        bytes memory data = abi.encodeWithSelector(
            Target(targetContract).callTest.selector, address(evc), address(evc), 0, alice, false
        );

        vm.prank(alice);
        evc.call(targetContract, alice, 0, data);

        // external contract call doesn't work when in lockdown mode
        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, true);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_LockdownMode.selector);
        evc.call(targetContract, alice, 0, data);

        // control collateral works when not in lockdown mode
        address controller = address(new Vault(evc));

        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, false);

        vm.prank(alice);
        evc.enableController(alice, controller);

        vm.prank(controller);
        evc.controlCollateral(vault, alice, 0, "");

        // control collateral still works when in lockdown mode
        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, true);

        vm.prank(controller);
        evc.controlCollateral(vault, alice, 0, "");

        // setting permit disabled mode still works when in lockdown mode
        vm.prank(alice);
        evc.setLockdownMode(addressPrefix, true);

        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, true);

        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, false);
    }
}
