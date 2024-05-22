// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/Set.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";

contract IsVaultStatusCheckDeferredTest is Test {
    EthereumVaultConnectorHarness internal evc;

    function setUp() public {
        evc = new EthereumVaultConnectorHarness();
    }

    function test_IsVaultStatusCheckDeferred(uint8 numberOfVaults) external {
        vm.assume(numberOfVaults <= SET_MAX_ELEMENTS);

        for (uint256 i = 0; i < numberOfVaults; ++i) {
            evc.setChecksDeferred(false);

            address vault = address(new Vault(evc));
            assertFalse(evc.isVaultStatusCheckDeferred(vault));

            vm.prank(vault);
            evc.requireVaultStatusCheck();
            assertFalse(evc.isVaultStatusCheckDeferred(vault));

            evc.setChecksDeferred(true);

            vm.prank(vault);
            evc.requireVaultStatusCheck();
            assertTrue(evc.isVaultStatusCheckDeferred(vault));

            evc.reset();
        }
    }

    function test_RevertIfChecksInProgress_IsVaultStatusCheckDeferred(address vault) external {
        evc.setChecksInProgress(false);
        assertFalse(evc.isVaultStatusCheckDeferred(vault));

        evc.setChecksInProgress(true);
        vm.expectRevert(Errors.EVC_ChecksReentrancy.selector);
        evc.isVaultStatusCheckDeferred(vault);
    }
}
