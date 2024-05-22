// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";

contract EthereumVaultConnectorHandler is EthereumVaultConnectorHarness {
    using ExecutionContext for EC;
    using Set for SetStorage;

    function handlerEnableController(address account, address vault) external {
        clearExpectedChecks();
        Vault(vault).clearChecks();

        super.enableController(account, vault);

        if (executionContext.areChecksDeferred()) return;

        expectedAccountsChecked.push(account);

        verifyAccountStatusChecks();
    }

    function handlerDisableController(address account) external {
        clearExpectedChecks();
        Vault(msg.sender).clearChecks();

        super.disableController(account);

        if (executionContext.areChecksDeferred()) return;

        expectedAccountsChecked.push(account);

        verifyAccountStatusChecks();
    }
}

contract ControllersManagementTest is Test {
    EthereumVaultConnectorHandler internal evc;

    event ControllerStatus(address indexed account, address indexed controller, bool enabled);

    function setUp() public {
        evc = new EthereumVaultConnectorHandler();
    }

    function test_ControllersManagement(address alice, uint8 subAccountId, uint256 seed) public {
        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(seed > 1000);

        address account = address(uint160(uint160(alice) ^ subAccountId));

        // test controllers management with use of an operator
        address msgSender = alice;
        if (seed % 2 == 0 && !evc.haveCommonOwner(account, address(uint160(seed)))) {
            msgSender = address(uint160(uint256(keccak256(abi.encode(seed)))));
            vm.prank(alice);
            evc.setAccountOperator(account, msgSender, true);
        }

        // enabling controller
        address vault = address(new Vault(evc));

        assertFalse(evc.isControllerEnabled(account, vault));
        address[] memory controllersPre = evc.getControllers(account);

        vm.expectEmit(true, true, false, true, address(evc));
        emit ControllerStatus(account, vault, true);
        vm.prank(msgSender);
        evc.handlerEnableController(account, vault);

        address[] memory controllersPost = evc.getControllers(account);
        assertEq(controllersPost.length, controllersPre.length + 1);
        assertEq(controllersPost[controllersPost.length - 1], vault);
        assertTrue(evc.isControllerEnabled(account, vault));

        // enabling the same controller again should succeed (duplicate will not be added and the event won't be
        // emitted)
        assertTrue(evc.isControllerEnabled(account, vault));
        controllersPre = evc.getControllers(account);

        vm.prank(msgSender);
        evc.handlerEnableController(account, vault);

        controllersPost = evc.getControllers(account);

        assertEq(controllersPost.length, controllersPre.length);
        assertEq(controllersPost[0], controllersPre[0]);
        assertTrue(evc.isControllerEnabled(account, vault));

        // trying to enable second controller will throw on the account status check
        address otherVault = address(new Vault(evc));

        vm.prank(msgSender);
        vm.expectRevert(Errors.EVC_ControllerViolation.selector);
        evc.handlerEnableController(account, otherVault);

        // only the controller vault can disable itself
        assertTrue(evc.isControllerEnabled(account, vault));
        controllersPre = evc.getControllers(account);

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(evc));
        emit ControllerStatus(account, vault, false);
        Vault(vault).call(address(evc), abi.encodeWithSelector(evc.handlerDisableController.selector, account));

        controllersPost = evc.getControllers(account);

        assertEq(controllersPost.length, controllersPre.length - 1);
        assertEq(controllersPost.length, 0);
        assertFalse(evc.isControllerEnabled(account, vault));
    }

    function test_RevertIfNotOwnerOrNotOperator_EnableController(address alice, address bob) public {
        vm.assume(alice != address(0) && alice != address(evc) && bob != address(0) && bob != address(evc));
        vm.assume(!evc.haveCommonOwner(alice, bob));

        address vault = address(new Vault(evc));

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.handlerEnableController(bob, vault);

        vm.prank(bob);
        evc.setAccountOperator(bob, alice, true);

        vm.prank(alice);
        evc.handlerEnableController(bob, vault);
    }

    function test_RevertIfProgressReentrancy_ControllersManagement(address alice) public {
        vm.assume(alice != address(evc));

        address vault = address(new Vault(evc));

        evc.setChecksInProgress(true);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_ChecksReentrancy.selector);
        evc.enableController(alice, vault);

        evc.setChecksInProgress(false);

        vm.prank(alice);
        evc.enableController(alice, vault);

        evc.setChecksInProgress(true);

        vm.prank(vault);
        vm.expectRevert(Errors.EVC_ChecksReentrancy.selector);
        evc.disableController(alice);

        evc.setChecksInProgress(false);

        vm.prank(vault);
        evc.disableController(alice);
    }

    function test_RevertIfControlCollateralReentrancy_ControllersManagement(address alice) public {
        vm.assume(alice != address(evc));

        address vault = address(new Vault(evc));

        evc.setControlCollateralInProgress(true);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_ControlCollateralReentrancy.selector);
        evc.enableController(alice, vault);

        evc.setControlCollateralInProgress(false);

        vm.prank(alice);
        evc.enableController(alice, vault);

        evc.setControlCollateralInProgress(true);

        vm.prank(vault);
        vm.expectRevert(Errors.EVC_ControlCollateralReentrancy.selector);
        evc.disableController(alice);

        evc.setControlCollateralInProgress(false);

        vm.prank(vault);
        evc.disableController(alice);
    }

    function test_RevertIfInvalidVault_ControllersManagement(address alice) public {
        vm.assume(alice != address(evc));
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_InvalidAddress.selector);
        evc.enableController(alice, address(evc));
    }

    function test_RevertIfAccountStatusViolated_ControllersManagement(address alice) public {
        vm.assume(alice != address(evc));

        address vault = address(new Vault(evc));

        Vault(vault).setAccountStatusState(1); // account status is violated

        vm.prank(alice);
        vm.expectRevert("account status violation");
        evc.handlerEnableController(alice, vault);

        vm.prank(alice);
        // succeeds as there's no controller to perform the account status check
        Vault(vault).call(address(evc), abi.encodeWithSelector(evc.handlerDisableController.selector, alice));

        Vault(vault).setAccountStatusState(1); // account status is still violated

        vm.prank(alice);
        // succeeds as there's no controller to perform the account status check
        evc.enableCollateral(alice, vault);

        Vault(vault).setAccountStatusState(0); // account status is no longer violated in order to enable controller

        vm.prank(alice);
        evc.handlerEnableController(alice, vault);

        Vault(vault).setAccountStatusState(1); // account status is violated again

        vm.prank(alice);
        // it won't succeed as this time we have a controller so the account status check is performed
        vm.expectRevert("account status violation");
        evc.enableCollateral(alice, vault);
    }
}
