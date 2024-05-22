// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/Set.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";

contract VaultStatusTest is Test {
    EthereumVaultConnectorHarness internal evc;

    event VaultStatusCheck(address indexed vault);

    function setUp() public {
        evc = new EthereumVaultConnectorHarness();
    }

    function test_RequireVaultStatusCheck(uint8 vaultsNumber, bool allStatusesValid) external {
        vm.assume(vaultsNumber > 0 && vaultsNumber <= SET_MAX_ELEMENTS);

        for (uint256 i = 0; i < vaultsNumber; i++) {
            address vault = address(new Vault(evc));

            // check all the options: vault state is ok, vault state is violated with
            // vault returning false and reverting
            Vault(vault).setVaultStatusState(
                allStatusesValid ? 0 : uint160(vault) % 3 == 0 ? 0 : uint160(vault) % 3 == 1 ? 1 : 2
            );

            vm.prank(vault);
            if (allStatusesValid || uint160(vault) % 3 == 0) {
                vm.expectEmit(true, false, false, false, address(evc));
                emit VaultStatusCheck(vault);
            } else {
                vm.expectRevert(
                    uint160(vault) % 3 == 1 ? bytes("vault status violation") : abi.encode(bytes4(uint32(1)))
                );
            }

            evc.requireVaultStatusCheck();
            evc.verifyVaultStatusChecks();
            evc.clearExpectedChecks();
        }
    }

    function test_WhenDeferred_RequireVaultStatusCheck(uint8 vaultsNumber, bool allStatusesValid) external {
        vm.assume(vaultsNumber > 0 && vaultsNumber <= SET_MAX_ELEMENTS);

        for (uint256 i = 0; i < vaultsNumber; i++) {
            address vault = address(new Vault(evc));

            // check all the options: vault state is ok, vault state is violated with
            // vault returning false and reverting
            Vault(vault).setVaultStatusState(
                allStatusesValid ? 0 : uint160(vault) % 3 == 0 ? 0 : uint160(vault) % 3 == 1 ? 1 : 2
            );

            Vault(vault).setVaultStatusState(1);
            evc.setChecksDeferred(true);

            vm.prank(vault);

            // even though the vault status state was set to 1 which should revert,
            // it doesn't because in checks deferral we only add the vaults to the set
            // so that the checks can be performed later
            evc.requireVaultStatusCheck();

            if (!(allStatusesValid || uint160(vault) % 3 == 0)) {
                // checks no longer deferred
                evc.setChecksDeferred(false);

                vm.prank(vault);
                vm.expectRevert(bytes("vault status violation"));
                evc.requireVaultStatusCheck();
            }
        }
    }

    function test_RevertIfChecksReentrancy_RequireVaultStatusCheck(uint8 index, uint8 vaultsNumber) external {
        vm.assume(index < vaultsNumber);
        vm.assume(vaultsNumber > 0 && vaultsNumber <= SET_MAX_ELEMENTS);

        address[] memory vaults = new address[](vaultsNumber);
        for (uint256 i = 0; i < vaultsNumber; i++) {
            vaults[i] = address(new Vault(evc));
        }

        evc.setChecksInProgress(true);

        vm.prank(vaults[index]);
        vm.expectRevert(abi.encodeWithSelector(Errors.EVC_ChecksReentrancy.selector));
        evc.requireVaultStatusCheck();

        evc.setChecksInProgress(false);
        vm.prank(vaults[index]);
        evc.requireVaultStatusCheck();
    }

    function test_AcquireChecksLock_RequireVaultStatusChecks(uint8 numberOfVaults) external {
        vm.assume(numberOfVaults > 0 && numberOfVaults <= SET_MAX_ELEMENTS);

        address[] memory vaults = new address[](numberOfVaults);
        for (uint256 i = 0; i < numberOfVaults; i++) {
            vaults[i] = address(new VaultMalicious(evc));

            VaultMalicious(vaults[i]).setExpectedErrorSelector(Errors.EVC_ChecksReentrancy.selector);

            vm.prank(vaults[i]);
            // function will revert with EVC_VaultStatusViolation according to VaultMalicious implementation
            vm.expectRevert(bytes("malicious vault"));
            evc.requireVaultStatusCheck();
        }
    }

    function test_ForgiveVaultStatusCheck(uint8 vaultsNumber) external {
        vm.assume(vaultsNumber > 0 && vaultsNumber <= SET_MAX_ELEMENTS);

        for (uint256 i = 0; i < vaultsNumber; i++) {
            address vault = address(new Vault(evc));

            // vault status check will be scheduled for later due to deferred state
            evc.setChecksDeferred(true);

            vm.prank(vault);
            evc.requireVaultStatusCheck();

            assertTrue(evc.isVaultStatusCheckDeferred(vault));
            vm.prank(vault);
            evc.forgiveVaultStatusCheck();
            assertFalse(evc.isVaultStatusCheckDeferred(vault));
        }
    }

    function test_RevertIfChecksReentrancy_ForgiveVaultStatusCheck(bool locked) external {
        evc.setChecksInProgress(locked);

        if (locked) {
            vm.expectRevert(abi.encodeWithSelector(Errors.EVC_ChecksReentrancy.selector));
        }
        evc.forgiveVaultStatusCheck();
    }
}
