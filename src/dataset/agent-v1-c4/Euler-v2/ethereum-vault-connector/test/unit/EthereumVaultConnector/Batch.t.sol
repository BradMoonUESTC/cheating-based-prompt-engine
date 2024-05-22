// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";

contract EthereumVaultConnectorHandler is EthereumVaultConnectorHarness {
    using ExecutionContext for EC;
    using Set for SetStorage;

    function handlerBatch(BatchItem[] calldata items) public payable {
        super.batch(items);

        verifyVaultStatusChecks();
        verifyAccountStatusChecks();
    }
}

contract EthereumVaultConnectorNoRevert is EthereumVaultConnectorHarness {
    using Set for SetStorage;

    function batchRevert(BatchItem[] calldata) public payable override nonReentrantChecksAndControlCollateral {
        // doesn't revert as expected
        return;
    }
}

contract BatchTest is Test {
    EthereumVaultConnectorHandler internal evc;

    bytes32 internal expectedHash;

    fallback(bytes calldata data) external returns (bytes memory) {
        require(keccak256(data) == expectedHash, "fallback-error");
        return data;
    }

    event CallWithContext(
        address indexed caller,
        bytes19 indexed onBehalfOfAddressPrefix,
        address onBehalfOfAccount,
        address indexed targetContract,
        bytes4 selector
    );

    function setUp() public {
        evc = new EthereumVaultConnectorHandler();
    }

    function test_Batch(address alice, address bob, uint256 seed) external {
        vm.assume(alice != address(0) && alice != address(evc) && bob != address(evc));
        vm.assume(bob != address(0) && !evc.haveCommonOwner(alice, bob));
        vm.assume(seed >= 4);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](6);
        address controller = address(new Vault(evc));
        address otherVault = address(new Vault(evc));
        address alicesSubAccount = address(uint160(alice) ^ 0x10);

        vm.assume(alice != controller && alice != otherVault);
        vm.assume(bob != controller && bob != otherVault);

        // -------------- FIRST BATCH -------------------------
        items[0].onBehalfOfAccount = address(0);
        items[0].targetContract = address(evc);
        items[0].value = 0;
        items[0].data = abi.encodeWithSelector(evc.enableController.selector, alice, controller);

        items[1].onBehalfOfAccount = address(0);
        items[1].targetContract = address(evc);
        items[1].value = 0;
        items[1].data = abi.encodeWithSelector(evc.setAccountOperator.selector, alice, bob, true);

        items[2].onBehalfOfAccount = alicesSubAccount;
        items[2].targetContract = otherVault;
        items[2].value = 0;
        items[2].data = abi.encodeWithSelector(Vault.requireChecks.selector, alicesSubAccount);

        items[3].onBehalfOfAccount = alice;
        items[3].targetContract = controller;
        items[3].value = seed / 3;
        items[3].data = abi.encodeWithSelector(
            Vault.call.selector,
            otherVault,
            abi.encodeWithSelector(Target.callTest.selector, address(evc), controller, seed / 3, alice, false)
        );

        items[4].onBehalfOfAccount = alice;
        items[4].targetContract = otherVault;
        items[4].value = type(uint256).max;
        items[4].data =
            abi.encodeWithSelector(Target.callTest.selector, address(evc), address(evc), seed - seed / 3, alice, false);

        items[5].onBehalfOfAccount = address(0);
        items[5].targetContract = address(evc);
        items[5].value = 0;
        items[5].data = abi.encodeWithSelector(evc.enableController.selector, alicesSubAccount, controller);

        vm.deal(alice, seed);
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(
            alice, evc.getAddressPrefix(alicesSubAccount), alicesSubAccount, otherVault, Vault.requireChecks.selector
        );
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(alice, evc.getAddressPrefix(alice), alice, controller, Vault.call.selector);
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(alice, evc.getAddressPrefix(alice), alice, otherVault, Target.callTest.selector);
        vm.prank(alice);
        evc.handlerBatch{value: seed}(items);

        assertTrue(evc.isControllerEnabled(alice, controller));
        assertTrue(evc.isControllerEnabled(alicesSubAccount, controller));
        assertEq(evc.isAccountOperatorAuthorized(alice, bob), true);
        assertEq(address(otherVault).balance, seed);

        evc.reset();
        Vault(controller).reset();
        Vault(otherVault).reset();

        // -------------- SECOND BATCH -------------------------
        items = new IEVC.BatchItem[](1);

        items[0].onBehalfOfAccount = address(0);
        items[0].targetContract = address(evc);
        items[0].value = 0;
        items[0].data = abi.encodeWithSelector(evc.call.selector, address(evc), alice, 0, "");

        vm.prank(bob);
        vm.expectRevert(Errors.EVC_InvalidAddress.selector);
        evc.handlerBatch(items);

        // -------------- THIRD BATCH -------------------------
        items = new IEVC.BatchItem[](4);

        items[0].onBehalfOfAccount = alice;
        items[0].targetContract = controller;
        items[0].value = 0;
        items[0].data = abi.encodeWithSelector(Vault.disableController.selector);

        items[1].onBehalfOfAccount = bob;
        items[1].targetContract = controller;
        items[1].value = 0;
        items[1].data = abi.encodeWithSelector(Vault.requireChecks.selector, bob);

        items[2].onBehalfOfAccount = bob;
        items[2].targetContract = otherVault;
        items[2].value = 0;
        items[2].data = abi.encodeWithSelector(Vault.requireChecks.selector, alicesSubAccount);

        items[3].onBehalfOfAccount = alice;
        items[3].targetContract = otherVault;
        items[3].value = 0;
        items[3].data = abi.encodeWithSelector(Target.callTest.selector, address(evc), address(evc), 0, alice, true);

        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(bob, evc.getAddressPrefix(alice), alice, controller, Vault.disableController.selector);
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(bob, evc.getAddressPrefix(bob), bob, controller, Vault.requireChecks.selector);
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(bob, evc.getAddressPrefix(bob), bob, otherVault, Vault.requireChecks.selector);
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(bob, evc.getAddressPrefix(alice), alice, otherVault, Target.callTest.selector);
        vm.prank(bob);
        evc.handlerBatch(items);
        assertFalse(evc.isControllerEnabled(alice, controller));

        // -------------- FOURTH BATCH -------------------------
        items = new IEVC.BatchItem[](1);

        items[0].onBehalfOfAccount = alice;
        items[0].targetContract = otherVault;
        items[0].value = 0;
        items[0].data = abi.encodeWithSelector(Target.revertEmptyTest.selector);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_EmptyError.selector);
        evc.handlerBatch(items);

        // -------------- FIFTH BATCH -------------------------
        // batch callback test
        items = new IEVC.BatchItem[](1);

        items[0].onBehalfOfAccount = alice;
        items[0].targetContract = address(this);
        items[0].value = 0;
        items[0].data = abi.encode(keccak256(abi.encode(seed)));

        expectedHash = keccak256(items[0].data);
        evc.handlerBatch(items);
    }

    function test_RevertIfInvalidBatchItem_Batch(address alice, uint256 value, bytes calldata data) external {
        vm.assume(alice != address(0));
        vm.assume(value > 0);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0].onBehalfOfAccount = alice;
        items[0].targetContract = address(evc);
        items[0].value = 0;
        items[0].data = data;

        vm.expectRevert(Errors.EVC_InvalidAddress.selector);
        evc.batch(items);

        items[0].onBehalfOfAccount = address(0);
        items[0].targetContract = address(evc);
        items[0].value = value;
        items[0].data = data;

        vm.expectRevert(Errors.EVC_InvalidValue.selector);
        evc.batch(items);
    }

    // for coverage
    function test_RevertIfSimulationBatchNested_BatchRevert_BatchSimulation(address alice) external {
        vm.assume(alice != address(evc));

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);

        items[0].onBehalfOfAccount = alice;
        items[0].targetContract = address(0);
        items[0].value = 0;
        items[0].data = "";

        evc.setChecksDeferred(true);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_SimulationBatchNested.selector);
        evc.batchRevert(items);

        vm.prank(alice);
        vm.expectRevert(Errors.EVC_SimulationBatchNested.selector);
        evc.batchSimulation(items);
    }

    function test_RevertIfChecksReentrancy_AcquireChecksLock_Batch(address alice) external {
        vm.assume(alice != address(evc));
        evc.setChecksInProgress(true);
        vm.expectRevert(abi.encodeWithSelector(Errors.EVC_ChecksReentrancy.selector));
        evc.batch(new IEVC.BatchItem[](0));
        evc.setChecksInProgress(false);

        address vault = address(new VaultMalicious(evc));
        vm.assume(alice != vault);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0].onBehalfOfAccount = alice;
        items[0].targetContract = vault;
        items[0].value = 0;
        items[0].data = abi.encodeWithSelector(Vault.requireChecksWithSimulationCheck.selector, alice, false);

        // internal batch in the malicious vault reverts with EVC_ChecksReentrancy error,
        // check VaultMalicious implementation
        VaultMalicious(vault).setExpectedErrorSelector(Errors.EVC_ChecksReentrancy.selector);

        vm.prank(alice);
        vm.expectRevert(bytes("malicious vault"));
        evc.batch(items);
    }

    function test_RevertIfChecksReentrancy_AcquireChecksLock_BatchRevert_BatchSimulation(address alice) external {
        vm.assume(alice != address(evc));

        evc.setChecksInProgress(true);
        vm.expectRevert(abi.encodeWithSelector(Errors.EVC_ChecksReentrancy.selector));
        evc.batchRevert(new IEVC.BatchItem[](0));

        vm.expectRevert(abi.encodeWithSelector(Errors.EVC_ChecksReentrancy.selector));
        evc.batchSimulation(new IEVC.BatchItem[](0));
        evc.setChecksInProgress(false);

        address vault = address(new VaultMalicious(evc));
        vm.assume(alice != vault);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0].onBehalfOfAccount = alice;
        items[0].targetContract = vault;
        items[0].value = 0;
        items[0].data = abi.encodeWithSelector(Vault.requireChecksWithSimulationCheck.selector, alice, true);

        // internal batch in the malicious vault reverts with EVC_ChecksReentrancy error,
        // check VaultMalicious implementation
        // error will be encoded in the result
        IEVC.BatchItemResult[] memory expectedBatchItemsResult = new IEVC.BatchItemResult[](1);
        IEVC.StatusCheckResult[] memory expectedAccountsStatusCheckResult = new IEVC.StatusCheckResult[](1);
        IEVC.StatusCheckResult[] memory expectedVaultsStatusCheckResult = new IEVC.StatusCheckResult[](1);

        expectedBatchItemsResult[0].success = true;
        expectedBatchItemsResult[0].result = "";

        expectedAccountsStatusCheckResult[0].checkedAddress = alice;
        expectedAccountsStatusCheckResult[0].isValid = true;
        expectedAccountsStatusCheckResult[0].result = "";

        expectedVaultsStatusCheckResult[0].checkedAddress = vault;
        expectedVaultsStatusCheckResult[0].isValid = false;
        expectedVaultsStatusCheckResult[0].result = abi.encodeWithSignature("Error(string)", "malicious vault");

        VaultMalicious(vault).setExpectedErrorSelector(Errors.EVC_ChecksReentrancy.selector);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.EVC_RevertedBatchResult.selector,
                expectedBatchItemsResult,
                expectedAccountsStatusCheckResult,
                expectedVaultsStatusCheckResult
            )
        );
        evc.batchRevert(items);

        // same should happen for batchSimulation() but without reverting with standard error
        VaultMalicious(vault).setExpectedErrorSelector(Errors.EVC_ChecksReentrancy.selector);

        vm.prank(alice);
        (
            IEVC.BatchItemResult[] memory batchItemsResult,
            IEVC.StatusCheckResult[] memory accountsStatusCheckResult,
            IEVC.StatusCheckResult[] memory vaultsStatusCheckResult
        ) = evc.batchSimulation(items);

        assertEq(batchItemsResult.length, 1);
        assertEq(batchItemsResult[0].success, expectedBatchItemsResult[0].success);
        assertEq(batchItemsResult[0].result, expectedBatchItemsResult[0].result);

        assertEq(accountsStatusCheckResult.length, 1);
        assertEq(accountsStatusCheckResult[0].checkedAddress, expectedAccountsStatusCheckResult[0].checkedAddress);
        assertEq(accountsStatusCheckResult[0].isValid, expectedAccountsStatusCheckResult[0].isValid);
        assertEq(accountsStatusCheckResult[0].result, expectedAccountsStatusCheckResult[0].result);

        assertEq(vaultsStatusCheckResult.length, 1);
        assertEq(vaultsStatusCheckResult[0].checkedAddress, expectedVaultsStatusCheckResult[0].checkedAddress);
        assertEq(vaultsStatusCheckResult[0].isValid, expectedVaultsStatusCheckResult[0].isValid);
        assertEq(vaultsStatusCheckResult[0].result, expectedVaultsStatusCheckResult[0].result);
    }

    function test_RevertIfControlCollateralReentrancy_AcquireControlCollateralLock_Batch(address alice) external {
        vm.assume(alice != address(0) && alice != address(evc));

        evc.setControlCollateralInProgress(true);
        vm.expectRevert(abi.encodeWithSelector(Errors.EVC_ControlCollateralReentrancy.selector));
        evc.batch(new IEVC.BatchItem[](0));
        evc.setControlCollateralInProgress(false);

        address controller = address(new Vault(evc));
        address collateral = address(new VaultMalicious(evc));

        vm.prank(alice);
        evc.enableController(alice, controller);

        vm.prank(alice);
        evc.enableCollateral(alice, collateral);

        // internal batch in the malicious vault reverts with EVC_ControlCollateralReentrancy error,
        // check VaultMalicious implementation
        VaultMalicious(collateral).setExpectedErrorSelector(Errors.EVC_ControlCollateralReentrancy.selector);

        vm.prank(controller);
        vm.expectRevert("callBatch/expected-error");
        evc.controlCollateral(collateral, alice, 0, abi.encodeWithSelector(VaultMalicious.callBatch.selector));
    }

    function test_RevertIfControlCollateralReentrancy_AcquireControlCollateralLock_BatchRevert_BatchSimulation(
        address alice
    ) external {
        vm.assume(alice != address(0) && alice != address(evc));

        evc.setControlCollateralInProgress(true);
        vm.expectRevert(abi.encodeWithSelector(Errors.EVC_ControlCollateralReentrancy.selector));
        evc.batchRevert(new IEVC.BatchItem[](0));

        vm.expectRevert(abi.encodeWithSelector(Errors.EVC_ControlCollateralReentrancy.selector));
        evc.batchSimulation(new IEVC.BatchItem[](0));

        evc.setControlCollateralInProgress(false);

        address controller = address(new Vault(evc));
        address collateral = address(new VaultMalicious(evc));

        vm.prank(alice);
        evc.enableController(alice, controller);

        vm.prank(alice);
        evc.enableCollateral(alice, collateral);

        // internal batch in the malicious vault reverts with EVC_ControlCollateralReentrancy error,
        // check VaultMalicious implementation
        VaultMalicious(collateral).setExpectedErrorSelector(Errors.EVC_ControlCollateralReentrancy.selector);

        vm.prank(controller);
        vm.expectRevert("callBatch/expected-error");
        evc.controlCollateral(collateral, alice, 0, abi.encodeWithSelector(VaultMalicious.callBatch.selector));
    }

    function test_RevertIfValueExceedsBalance_Batch(address alice, uint128 seed) external {
        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(seed > 0);

        address vault = address(new Vault(evc));
        vm.assume(alice != vault);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0].onBehalfOfAccount = alice;
        items[0].targetContract = vault;
        items[0].value = seed;
        items[0].data = abi.encodeWithSelector(Vault.requireChecks.selector, alice);

        // reverts if value exceeds balance
        vm.deal(alice, seed);
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_InvalidValue.selector);
        evc.batch{value: seed - 1}(items);

        // succeeds if value does not exceed balance
        vm.prank(alice);
        evc.batch{value: seed}(items);
    }

    function test_BatchRevert_BatchSimulation(address alice) external {
        vm.assume(alice != address(evc));

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        IEVC.BatchItemResult[] memory expectedBatchItemsResult = new IEVC.BatchItemResult[](1);
        IEVC.StatusCheckResult[] memory expectedAccountsStatusCheckResult = new IEVC.StatusCheckResult[](1);
        IEVC.StatusCheckResult[] memory expectedVaultsStatusCheckResult = new IEVC.StatusCheckResult[](1);

        address controller = address(new Vault(evc));
        vm.assume(alice != controller);

        vm.prank(alice);
        evc.enableController(alice, controller);

        items[0].onBehalfOfAccount = alice;
        items[0].targetContract = controller;
        items[0].value = 0;
        items[0].data = abi.encodeWithSelector(Vault.requireChecks.selector, alice);

        expectedBatchItemsResult[0].success = true;
        expectedBatchItemsResult[0].result = "";

        expectedAccountsStatusCheckResult[0].checkedAddress = alice;
        expectedAccountsStatusCheckResult[0].isValid = true;
        expectedAccountsStatusCheckResult[0].result = abi.encode(IVault.checkAccountStatus.selector);

        expectedVaultsStatusCheckResult[0].checkedAddress = controller;
        expectedVaultsStatusCheckResult[0].isValid = true;
        expectedVaultsStatusCheckResult[0].result = abi.encode(IVault.checkVaultStatus.selector);

        // regular batch doesn't revert
        vm.prank(alice);
        evc.batch(items);

        {
            vm.prank(alice);
            try evc.batchRevert(items) {
                assert(false);
            } catch (bytes memory err) {
                assertEq(bytes4(err), Errors.EVC_RevertedBatchResult.selector);

                assembly {
                    err := add(err, 4)
                }
                (
                    IEVC.BatchItemResult[] memory batchItemsResult,
                    IEVC.StatusCheckResult[] memory accountsStatusCheckResult,
                    IEVC.StatusCheckResult[] memory vaultsStatusCheckResult
                ) = abi.decode(err, (IEVC.BatchItemResult[], IEVC.StatusCheckResult[], IEVC.StatusCheckResult[]));

                assertEq(expectedBatchItemsResult.length, batchItemsResult.length);
                assertEq(expectedBatchItemsResult[0].success, batchItemsResult[0].success);
                assertEq(keccak256(expectedBatchItemsResult[0].result), keccak256(batchItemsResult[0].result));

                assertEq(expectedAccountsStatusCheckResult.length, accountsStatusCheckResult.length);
                assertEq(
                    expectedAccountsStatusCheckResult[0].checkedAddress, accountsStatusCheckResult[0].checkedAddress
                );
                assertEq(expectedAccountsStatusCheckResult[0].isValid, accountsStatusCheckResult[0].isValid);
                assertEq(
                    keccak256(expectedAccountsStatusCheckResult[0].result),
                    keccak256(accountsStatusCheckResult[0].result)
                );

                assertEq(expectedVaultsStatusCheckResult.length, vaultsStatusCheckResult.length);
                assertEq(expectedVaultsStatusCheckResult[0].checkedAddress, vaultsStatusCheckResult[0].checkedAddress);
                assertEq(expectedVaultsStatusCheckResult[0].isValid, vaultsStatusCheckResult[0].isValid);
                assertEq(
                    keccak256(expectedVaultsStatusCheckResult[0].result), keccak256(vaultsStatusCheckResult[0].result)
                );
            }
        }

        {
            vm.prank(alice);
            (
                IEVC.BatchItemResult[] memory batchItemsResult,
                IEVC.StatusCheckResult[] memory accountsStatusCheckResult,
                IEVC.StatusCheckResult[] memory vaultsStatusCheckResult
            ) = evc.batchSimulation(items);

            assertEq(expectedBatchItemsResult.length, batchItemsResult.length);
            assertEq(expectedBatchItemsResult[0].success, batchItemsResult[0].success);
            assertEq(keccak256(expectedBatchItemsResult[0].result), keccak256(batchItemsResult[0].result));

            assertEq(expectedAccountsStatusCheckResult.length, accountsStatusCheckResult.length);
            assertEq(expectedAccountsStatusCheckResult[0].checkedAddress, accountsStatusCheckResult[0].checkedAddress);
            assertEq(expectedAccountsStatusCheckResult[0].isValid, accountsStatusCheckResult[0].isValid);
            assertEq(
                keccak256(expectedAccountsStatusCheckResult[0].result), keccak256(accountsStatusCheckResult[0].result)
            );

            assertEq(expectedVaultsStatusCheckResult.length, vaultsStatusCheckResult.length);
            assertEq(expectedVaultsStatusCheckResult[0].checkedAddress, vaultsStatusCheckResult[0].checkedAddress);
            assertEq(expectedVaultsStatusCheckResult[0].isValid, vaultsStatusCheckResult[0].isValid);
            assertEq(keccak256(expectedVaultsStatusCheckResult[0].result), keccak256(vaultsStatusCheckResult[0].result));
        }

        // invalidate both checks
        Vault(controller).setVaultStatusState(1);
        Vault(controller).setAccountStatusState(1);

        // update expected behavior
        expectedAccountsStatusCheckResult[0].isValid = false;
        expectedAccountsStatusCheckResult[0].result =
            abi.encodeWithSignature("Error(string)", "account status violation");

        expectedVaultsStatusCheckResult[0].isValid = false;
        expectedVaultsStatusCheckResult[0].result = abi.encodeWithSignature("Error(string)", "vault status violation");

        // regular batch reverts now
        vm.prank(alice);
        vm.expectRevert(bytes("account status violation"));
        evc.batch(items);

        {
            vm.prank(alice);
            try evc.batchRevert(items) {
                assert(false);
            } catch (bytes memory err) {
                assertEq(bytes4(err), Errors.EVC_RevertedBatchResult.selector);

                assembly {
                    err := add(err, 4)
                }
                (
                    IEVC.BatchItemResult[] memory batchItemsResult,
                    IEVC.StatusCheckResult[] memory accountsStatusCheckResult,
                    IEVC.StatusCheckResult[] memory vaultsStatusCheckResult
                ) = abi.decode(err, (IEVC.BatchItemResult[], IEVC.StatusCheckResult[], IEVC.StatusCheckResult[]));

                assertEq(expectedBatchItemsResult.length, batchItemsResult.length);
                assertEq(expectedBatchItemsResult[0].success, batchItemsResult[0].success);
                assertEq(keccak256(expectedBatchItemsResult[0].result), keccak256(batchItemsResult[0].result));

                assertEq(expectedAccountsStatusCheckResult.length, accountsStatusCheckResult.length);
                assertEq(
                    expectedAccountsStatusCheckResult[0].checkedAddress, accountsStatusCheckResult[0].checkedAddress
                );
                assertEq(expectedAccountsStatusCheckResult[0].isValid, accountsStatusCheckResult[0].isValid);
                assertEq(
                    keccak256(expectedAccountsStatusCheckResult[0].result),
                    keccak256(accountsStatusCheckResult[0].result)
                );

                assertEq(expectedVaultsStatusCheckResult.length, vaultsStatusCheckResult.length);
                assertEq(expectedVaultsStatusCheckResult[0].checkedAddress, vaultsStatusCheckResult[0].checkedAddress);
                assertEq(expectedVaultsStatusCheckResult[0].isValid, vaultsStatusCheckResult[0].isValid);
                assertEq(
                    keccak256(expectedVaultsStatusCheckResult[0].result), keccak256(vaultsStatusCheckResult[0].result)
                );
            }
        }

        {
            vm.prank(alice);
            (
                IEVC.BatchItemResult[] memory batchItemsResult,
                IEVC.StatusCheckResult[] memory accountsStatusCheckResult,
                IEVC.StatusCheckResult[] memory vaultsStatusCheckResult
            ) = evc.batchSimulation(items);

            assertEq(expectedBatchItemsResult.length, batchItemsResult.length);
            assertEq(expectedBatchItemsResult[0].success, batchItemsResult[0].success);
            assertEq(keccak256(expectedBatchItemsResult[0].result), keccak256(batchItemsResult[0].result));

            assertEq(expectedAccountsStatusCheckResult.length, accountsStatusCheckResult.length);
            assertEq(expectedAccountsStatusCheckResult[0].checkedAddress, accountsStatusCheckResult[0].checkedAddress);
            assertEq(expectedAccountsStatusCheckResult[0].isValid, accountsStatusCheckResult[0].isValid);
            assertEq(
                keccak256(expectedAccountsStatusCheckResult[0].result), keccak256(accountsStatusCheckResult[0].result)
            );

            assertEq(expectedVaultsStatusCheckResult.length, vaultsStatusCheckResult.length);
            assertEq(expectedVaultsStatusCheckResult[0].checkedAddress, vaultsStatusCheckResult[0].checkedAddress);
            assertEq(expectedVaultsStatusCheckResult[0].isValid, vaultsStatusCheckResult[0].isValid);
            assertEq(keccak256(expectedVaultsStatusCheckResult[0].result), keccak256(vaultsStatusCheckResult[0].result));
        }
    }

    function test_RevertIfBatchRevertDoesntRevert_BatchSimulation(address alice) external {
        vm.assume(alice != address(evc));

        IEVC evc_noRevert = new EthereumVaultConnectorNoRevert();
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_BatchPanic.selector);
        evc_noRevert.batchSimulation(new IEVC.BatchItem[](0));
    }
}
