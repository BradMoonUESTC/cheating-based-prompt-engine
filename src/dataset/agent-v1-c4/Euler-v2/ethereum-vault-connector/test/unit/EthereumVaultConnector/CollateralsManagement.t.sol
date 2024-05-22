// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/Set.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";

contract EthereumVaultConnectorHandler is EthereumVaultConnectorHarness {
    using ExecutionContext for EC;
    using Set for SetStorage;

    function handlerEnableCollateral(address account, address vault) external {
        clearExpectedChecks();

        super.enableCollateral(account, vault);

        if (executionContext.areChecksDeferred()) return;

        expectedAccountsChecked.push(account);

        verifyAccountStatusChecks();
    }

    function handlerReorderCollaterals(address account, uint8 index1, uint8 index2) external {
        clearExpectedChecks();

        super.reorderCollaterals(account, index1, index2);

        if (executionContext.areChecksDeferred()) return;

        expectedAccountsChecked.push(account);

        verifyAccountStatusChecks();
    }

    function handlerDisableCollateral(address account, address vault) external {
        clearExpectedChecks();

        super.disableCollateral(account, vault);

        if (executionContext.areChecksDeferred()) return;

        expectedAccountsChecked.push(account);

        verifyAccountStatusChecks();
    }
}

contract CollateralsManagementTest is Test {
    EthereumVaultConnectorHandler internal evc;

    event CollateralStatus(address indexed account, address indexed collateral, bool enabled);

    function setUp() public {
        evc = new EthereumVaultConnectorHandler();
    }

    function test_CollateralsManagement(address alice, uint8 subAccountId, uint8 numberOfVaults, uint256 seed) public {
        // call setUp() explicitly for Diligence Fuzzing tool to pass
        setUp();

        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(numberOfVaults > 0 && numberOfVaults <= SET_MAX_ELEMENTS);
        vm.assume(seed > 1000);

        address account = address(uint160(uint160(alice) ^ subAccountId));

        assertEq(evc.getAccountOwner(account), address(0));

        // test collaterals management with use of an operator
        address msgSender = alice;
        if (seed % 2 == 0 && !evc.haveCommonOwner(account, address(uint160(seed)))) {
            msgSender = address(uint160(uint256(keccak256(abi.encodePacked(seed)))));
            vm.prank(alice);
            evc.setAccountOperator(account, msgSender, true);
            assertEq(evc.getAccountOwner(account), alice);
        }

        // enable a controller to check if account status check works properly
        address controller = address(new Vault(evc));
        if (seed % 3 == 0) {
            vm.prank(alice);
            evc.enableController(account, controller);
            assertEq(evc.getAccountOwner(account), alice);
        }

        // enabling collaterals
        for (uint256 i = 1; i <= numberOfVaults; ++i) {
            Vault(controller).clearChecks();
            address[] memory collateralsPre = evc.getCollaterals(account);

            address vault = i % 5 == 0 ? collateralsPre[seed % collateralsPre.length] : address(new Vault(evc));

            bool alreadyEnabled = evc.isCollateralEnabled(account, vault);

            assert((alreadyEnabled && i % 5 == 0) || (!alreadyEnabled && i % 5 != 0));

            if (!alreadyEnabled) {
                vm.expectEmit(true, true, false, true, address(evc));
                emit CollateralStatus(account, vault, true);
            }
            vm.prank(msgSender);
            evc.handlerEnableCollateral(account, vault);

            address[] memory collateralsPost = evc.getCollaterals(account);

            if (alreadyEnabled) {
                assertEq(collateralsPost.length, collateralsPre.length);
            } else {
                assertEq(collateralsPost.length, collateralsPre.length + 1);
                assertEq(collateralsPost[collateralsPost.length - 1], vault);
            }

            for (uint256 j = 0; j < collateralsPre.length; ++j) {
                assertEq(collateralsPre[j], collateralsPost[j]);
            }

            // try to reorder the collaterals if there's enough of them
            if (collateralsPost.length > 1) {
                collateralsPre = evc.getCollaterals(account);

                uint8 index1 = uint8(seed % collateralsPre.length);
                uint8 index2 = uint8((seed / 2) % collateralsPre.length);

                if (index1 == index2) {
                    index2 = uint8((index2 + 1) % collateralsPre.length);
                }

                if (index1 > index2) {
                    (index1, index2) = (index2, index1);
                }

                Vault(controller).clearChecks();

                vm.prank(msgSender);
                evc.handlerReorderCollaterals(account, index1, index2);

                collateralsPost = evc.getCollaterals(account);

                assertEq(collateralsPost.length, collateralsPre.length);
                assertEq(collateralsPost[index1], collateralsPre[index2]);
                assertEq(collateralsPost[index2], collateralsPre[index1]);

                (collateralsPost[index1], collateralsPost[index2]) = (collateralsPost[index2], collateralsPost[index1]);

                for (uint256 j = 0; j < collateralsPre.length; ++j) {
                    assertEq(collateralsPre[j], collateralsPost[j]);
                }
            }
        }

        // disabling collaterals
        while (evc.getCollaterals(account).length > 0) {
            Vault(controller).clearChecks();
            address[] memory collateralsPre = evc.getCollaterals(account);
            address vault = collateralsPre[seed % collateralsPre.length];

            vm.expectEmit(true, true, false, true, address(evc));
            emit CollateralStatus(account, vault, false);
            vm.prank(msgSender);
            evc.handlerDisableCollateral(account, vault);

            address[] memory collateralsPost = evc.getCollaterals(account);

            assertEq(collateralsPost.length, collateralsPre.length - 1);

            for (uint256 j = 0; j < collateralsPost.length; ++j) {
                assertNotEq(collateralsPost[j], vault);
            }
        }
    }

    function test_RevertIfNotOwnerOrNotOperator_CollateralsManagement(address alice, address bob) public {
        vm.assume(alice != address(0) && alice != address(evc) && bob != address(0) && bob != address(evc));
        vm.assume(!evc.haveCommonOwner(alice, bob));

        address vault1 = address(new Vault(evc));
        address vault2 = address(new Vault(evc));

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.enableCollateral(bob, vault1);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.reorderCollaterals(bob, 0, 1);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.disableCollateral(bob, vault1);

        vm.prank(bob);
        evc.setAccountOperator(bob, alice, true);

        vm.prank(bob);
        evc.enableCollateral(bob, vault2);

        vm.prank(alice);
        evc.enableCollateral(bob, vault1);

        vm.prank(alice);
        evc.reorderCollaterals(bob, 0, 1);

        vm.prank(alice);
        evc.disableCollateral(bob, vault1);
    }

    function test_RevertIfChecksReentrancy_CollateralsManagement(address alice) public {
        vm.assume(alice != address(evc));
        address vault1 = address(new Vault(evc));
        address vault2 = address(new Vault(evc));

        evc.setChecksInProgress(true);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_ChecksReentrancy.selector);
        evc.enableCollateral(alice, vault1);

        evc.setChecksInProgress(false);

        vm.prank(alice);
        evc.enableCollateral(alice, vault1);

        vm.prank(alice);
        evc.enableCollateral(alice, vault2);

        evc.setChecksInProgress(true);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_ChecksReentrancy.selector);
        evc.reorderCollaterals(alice, 0, 1);

        evc.setChecksInProgress(false);

        vm.prank(alice);
        evc.reorderCollaterals(alice, 0, 1);

        evc.setChecksInProgress(true);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_ChecksReentrancy.selector);
        evc.disableCollateral(alice, vault1);

        evc.setChecksInProgress(false);

        vm.prank(alice);
        evc.disableCollateral(alice, vault1);
    }

    function test_RevertIfControlCollateralReentrancy_CollateralsManagement(address alice) public {
        vm.assume(alice != address(evc));
        address vault1 = address(new Vault(evc));
        address vault2 = address(new Vault(evc));

        evc.setControlCollateralInProgress(true);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_ControlCollateralReentrancy.selector);
        evc.enableCollateral(alice, vault1);

        evc.setControlCollateralInProgress(false);

        vm.prank(alice);
        evc.enableCollateral(alice, vault1);

        vm.prank(alice);
        evc.enableCollateral(alice, vault2);

        evc.setControlCollateralInProgress(true);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_ControlCollateralReentrancy.selector);
        evc.reorderCollaterals(alice, 0, 1);

        evc.setControlCollateralInProgress(false);

        vm.prank(alice);
        evc.reorderCollaterals(alice, 0, 1);

        evc.setControlCollateralInProgress(true);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_ControlCollateralReentrancy.selector);
        evc.disableCollateral(alice, vault1);

        evc.setControlCollateralInProgress(false);

        vm.prank(alice);
        evc.disableCollateral(alice, vault1);
    }

    function test_RevertIfInvalidVault_CollateralsManagement(address alice) public {
        vm.assume(alice != address(evc));
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_InvalidAddress.selector);
        evc.enableCollateral(alice, address(evc));
    }

    function test_RevertIfAccountStatusViolated_CollateralsManagement(address alice) public {
        vm.assume(alice != address(evc));

        address vault = address(new Vault(evc));
        address controller = address(new Vault(evc));

        vm.prank(alice);
        evc.enableController(alice, controller);

        Vault(controller).setAccountStatusState(1); // account status is violated

        vm.prank(alice);
        vm.expectRevert(bytes("account status violation"));
        evc.enableCollateral(alice, vault);

        vm.prank(alice);
        vm.expectRevert(bytes("account status violation"));
        evc.disableCollateral(alice, vault);

        Vault(controller).setAccountStatusState(0); // account status is NOT violated

        Vault(controller).clearChecks();
        vm.prank(alice);
        evc.enableCollateral(alice, vault);

        Vault(controller).clearChecks();
        vm.prank(alice);
        evc.disableCollateral(alice, vault);
    }
}
