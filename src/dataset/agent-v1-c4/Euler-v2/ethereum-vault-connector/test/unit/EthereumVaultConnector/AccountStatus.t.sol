// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/Set.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";

contract AccountStatusTest is Test {
    EthereumVaultConnectorHarness internal evc;

    event AccountStatusCheck(address indexed account, address indexed controller);

    function setUp() public {
        evc = new EthereumVaultConnectorHarness();
    }

    function test_RequireAccountStatusCheck(
        uint8 numberOfAccounts,
        bytes memory seed,
        uint40 timestamp,
        bool allStatusesValid
    ) external {
        vm.assume(numberOfAccounts > 0 && numberOfAccounts <= SET_MAX_ELEMENTS);
        vm.assume(timestamp > 0);

        for (uint256 i = 0; i < numberOfAccounts; i++) {
            address account = address(uint160(uint256(keccak256(abi.encode(i, seed)))));
            address controller = address(new Vault(evc));

            vm.warp(0);

            vm.prank(account);
            evc.enableController(account, controller);
            Vault(controller).clearChecks();
            evc.clearExpectedChecks();

            vm.warp(timestamp);

            // check all the options: account state is ok, account state is violated with
            // controller returning false and reverting
            Vault(controller).setAccountStatusState(
                allStatusesValid ? 0 : uint160(account) % 3 == 0 ? 0 : uint160(account) % 3 == 1 ? 1 : 2
            );

            if (allStatusesValid || uint160(account) % 3 == 0) {
                vm.expectEmit(true, true, false, false, address(evc));
                emit AccountStatusCheck(account, controller);
            } else {
                vm.expectRevert(
                    uint160(account) % 3 == 1 ? bytes("account status violation") : abi.encode(bytes4(uint32(2)))
                );
            }

            evc.requireAccountStatusCheck(account);
            evc.verifyAccountStatusChecks();

            if (allStatusesValid || uint160(account) % 3 == 0) {
                assertTrue(evc.getLastAccountStatusCheckTimestamp(account) == block.timestamp);
            } else {
                assertFalse(evc.getLastAccountStatusCheckTimestamp(account) == block.timestamp);
            }

            Vault(controller).clearChecks();
            evc.clearExpectedChecks();
        }
    }

    function test_WhenDeferred_RequireAccountStatusCheck(
        uint8 numberOfAccounts,
        bytes memory seed,
        uint40 timestamp
    ) external {
        vm.assume(numberOfAccounts > 0 && numberOfAccounts <= SET_MAX_ELEMENTS);
        vm.assume(timestamp > 0);

        for (uint256 i = 0; i < numberOfAccounts; i++) {
            evc.setChecksDeferred(false);

            address account = address(uint160(uint256(keccak256(abi.encode(i, seed)))));
            address controller = address(new Vault(evc));

            vm.warp(0);

            vm.prank(account);
            evc.enableController(account, controller);
            Vault(controller).setAccountStatusState(1);

            vm.warp(timestamp);

            // account status check will be scheduled for later due to deferred state
            evc.setChecksDeferred(true);

            // even though the account status state was set to 1 which should revert,
            // it doesn't because in checks deferral we only add the accounts to the set
            // so that the checks can be performed later
            assertFalse(evc.isAccountStatusCheckDeferred(account));
            evc.requireAccountStatusCheck(account);
            assertTrue(evc.isAccountStatusCheckDeferred(account));
            assertTrue(evc.getLastAccountStatusCheckTimestamp(account) == 0);
            evc.reset();
        }
    }

    function test_RevertIfChecksReentrancy_RequireAccountStatusCheck(address account) external {
        evc.setChecksInProgress(true);

        vm.expectRevert(abi.encodeWithSelector(Errors.EVC_ChecksReentrancy.selector));
        evc.requireAccountStatusCheck(account);

        vm.expectRevert(abi.encodeWithSelector(Errors.EVC_ChecksReentrancy.selector));
        evc.getLastAccountStatusCheckTimestamp(account);

        evc.setChecksInProgress(false);
        evc.requireAccountStatusCheck(account);
        evc.getLastAccountStatusCheckTimestamp(account);
    }

    function test_AcquireChecksLock_RequireAccountStatusChecks(uint8 numberOfAccounts, bytes memory seed) external {
        vm.assume(numberOfAccounts > 0 && numberOfAccounts <= SET_MAX_ELEMENTS);

        for (uint256 i = 0; i < numberOfAccounts; i++) {
            address account = address(uint160(uint256(keccak256(abi.encode(i, seed)))));
            address controller = address(new VaultMalicious(evc));

            vm.prank(account);
            evc.enableController(account, controller);

            VaultMalicious(controller).setExpectedErrorSelector(Errors.EVC_ChecksReentrancy.selector);

            // function will revert with EVC_AccountStatusViolation according to VaultMalicious implementation
            vm.expectRevert(bytes("malicious vault"));
            evc.requireAccountStatusCheck(account);
        }
    }

    function test_ForgiveAccountStatusCheck(uint8 numberOfAccounts, bytes memory seed) external {
        vm.assume(numberOfAccounts > 0 && numberOfAccounts <= SET_MAX_ELEMENTS);

        address[] memory accounts = new address[](numberOfAccounts);
        for (uint256 i = 0; i < numberOfAccounts; i++) {
            accounts[i] = address(uint160(uint256(keccak256(abi.encode(i, seed)))));
        }

        address controller = address(new Vault(evc));
        for (uint256 i = 0; i < numberOfAccounts; i++) {
            address account = accounts[i];

            // account status check will be scheduled for later due to deferred state
            evc.setChecksDeferred(true);

            vm.prank(account);
            evc.enableController(account, controller);

            assertTrue(evc.isAccountStatusCheckDeferred(account));
            vm.prank(controller);
            evc.forgiveAccountStatusCheck(account);
            assertFalse(evc.isAccountStatusCheckDeferred(account));

            evc.reset();
        }

        evc.setChecksDeferred(true);

        for (uint256 i = 0; i < accounts.length; ++i) {
            assertFalse(evc.isAccountStatusCheckDeferred(accounts[i]));
            evc.requireAccountStatusCheck(accounts[i]);
            assertTrue(evc.isAccountStatusCheckDeferred(accounts[i]));
        }

        for (uint256 i = 0; i < accounts.length; ++i) {
            vm.prank(controller);
            evc.forgiveAccountStatusCheck(accounts[i]);
            assertFalse(evc.isAccountStatusCheckDeferred(accounts[i]));
        }
    }

    function test_RevertIfChecksReentrancy_ForgiveAccountStatusCheckNow(address account) external {
        vm.assume(account != address(evc));

        address controller = address(new Vault(evc));

        vm.prank(account);
        evc.enableController(account, controller);

        evc.setChecksInProgress(true);

        vm.prank(controller);
        vm.expectRevert(abi.encodeWithSelector(Errors.EVC_ChecksReentrancy.selector));
        evc.forgiveAccountStatusCheck(account);

        evc.setChecksInProgress(false);
        vm.prank(controller);
        evc.forgiveAccountStatusCheck(account);
    }

    function test_RevertIfNoControllerEnabled_ForgiveAccountStatusCheck(
        uint8 numberOfAccounts,
        bytes memory seed
    ) external {
        vm.assume(numberOfAccounts > 0 && numberOfAccounts <= SET_MAX_ELEMENTS);

        for (uint256 i = 0; i < numberOfAccounts; i++) {
            address account = address(uint160(uint256(keccak256(abi.encode(i, seed)))));

            // account status check will be scheduled for later due to deferred state
            evc.setChecksDeferred(true);

            assertFalse(evc.isAccountStatusCheckDeferred(account));
            evc.requireAccountStatusCheck(account);
            assertTrue(evc.isAccountStatusCheckDeferred(account));

            // the check does not get forgiven
            vm.expectRevert(Errors.EVC_ControllerViolation.selector);
            evc.forgiveAccountStatusCheck(account);

            evc.reset();
        }
    }

    function test_RevertIfMultipleControllersEnabled_ForgiveAccountStatusCheck(
        uint8 numberOfAccounts,
        bytes memory seed
    ) external {
        vm.assume(numberOfAccounts > 0 && numberOfAccounts <= SET_MAX_ELEMENTS);
        address controller_1 = address(new Vault(evc));
        address controller_2 = address(new Vault(evc));

        for (uint256 i = 0; i < numberOfAccounts; i++) {
            address account = address(uint160(uint256(keccak256(abi.encode(i, seed)))));

            // account status check will be scheduled for later due to deferred state
            evc.setChecksDeferred(true);

            vm.prank(account);
            evc.enableController(account, controller_1);

            vm.prank(account);
            evc.enableController(account, controller_2);

            assertTrue(evc.isAccountStatusCheckDeferred(account));
            vm.prank(controller_1);
            vm.expectRevert(Errors.EVC_ControllerViolation.selector);
            evc.forgiveAccountStatusCheck(account);

            evc.reset();
        }
    }

    function test_RevertIfMsgSenderIsNotEnabledController_ForgiveAccountStatusCheck(
        uint8 numberOfAccounts,
        bytes memory seed
    ) external {
        vm.assume(numberOfAccounts > 0 && numberOfAccounts <= SET_MAX_ELEMENTS);

        address controller = address(new Vault(evc));
        for (uint256 i = 0; i < numberOfAccounts; i++) {
            address account = address(uint160(uint256(keccak256(abi.encode(i, seed)))));

            // account status check will be scheduled for later due to deferred state
            evc.setChecksDeferred(true);

            vm.prank(account);
            evc.enableController(account, controller);

            assertTrue(evc.isAccountStatusCheckDeferred(account));
            vm.prank(address(uint160(controller) + 1));
            vm.expectRevert(Errors.EVC_NotAuthorized.selector);
            evc.forgiveAccountStatusCheck(account);

            evc.reset();
        }
    }
}
