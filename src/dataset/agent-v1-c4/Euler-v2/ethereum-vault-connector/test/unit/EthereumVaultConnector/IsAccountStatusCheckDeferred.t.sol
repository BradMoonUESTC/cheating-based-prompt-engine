// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/Set.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";

contract IsAccountStatusCheckDeferredTest is Test {
    EthereumVaultConnectorHarness internal evc;

    function setUp() public {
        evc = new EthereumVaultConnectorHarness();
    }

    function test_IsAccountStatusCheckDeferred(uint8 numberOfAccounts, bytes memory seed) external {
        vm.assume(numberOfAccounts <= SET_MAX_ELEMENTS);

        for (uint256 i = 0; i < numberOfAccounts; ++i) {
            evc.setChecksDeferred(false);

            address account = address(uint160(uint256(keccak256(abi.encode(i, seed)))));
            assertFalse(evc.isAccountStatusCheckDeferred(account));

            evc.requireAccountStatusCheck(account);
            assertFalse(evc.isAccountStatusCheckDeferred(account));

            evc.setChecksDeferred(true);

            evc.requireAccountStatusCheck(account);
            assertTrue(evc.isAccountStatusCheckDeferred(account));

            evc.reset();
        }
    }

    function test_RevertIfChecksInProgress_IsAccountStatusCheckDeferred(address account) external {
        evc.setChecksInProgress(false);
        assertFalse(evc.isAccountStatusCheckDeferred(account));

        evc.setChecksInProgress(true);
        vm.expectRevert(Errors.EVC_ChecksReentrancy.selector);
        evc.isAccountStatusCheckDeferred(account);
    }
}
