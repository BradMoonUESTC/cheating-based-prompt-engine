// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";

contract EthereumVaultConnectorHandler is EthereumVaultConnectorHarness {
    using Set for SetStorage;

    function handlerControlCollateral(
        address targetContract,
        address onBehalfOfAccount,
        uint256 value,
        bytes calldata data
    ) public payable returns (bytes memory result) {
        (bool success,) = msg.sender.call(abi.encodeWithSelector(Vault.clearChecks.selector));
        success;
        clearExpectedChecks();

        result = super.controlCollateral(targetContract, onBehalfOfAccount, value, data);

        verifyVaultStatusChecks();
        verifyAccountStatusChecks();
    }
}

contract ControlCollateralTest is Test {
    EthereumVaultConnectorHandler internal evc;

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

    function test_ControlCollateral(address alice, uint96 seed) public {
        vm.assume(alice != address(0) && alice != address(evc));

        address collateral = address(new Vault(evc));
        address controller = address(new Vault(evc));
        vm.assume(collateral != address(evc));
        vm.assume(!evc.haveCommonOwner(alice, controller));

        vm.prank(alice);
        evc.enableCollateral(alice, collateral);

        vm.prank(alice);
        evc.enableController(alice, controller);

        bytes memory data = abi.encodeWithSelector(
            Target(collateral).controlCollateralTest.selector, address(evc), address(evc), seed, alice
        );

        vm.deal(controller, seed);
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(
            controller, evc.getAddressPrefix(alice), alice, collateral, Target.controlCollateralTest.selector
        );
        vm.prank(controller);
        bytes memory result = evc.handlerControlCollateral{value: seed}(collateral, alice, seed, data);
        assertEq(abi.decode(result, (uint256)), seed);

        evc.clearExpectedChecks();
        Vault(controller).clearChecks();
    }

    function test_RevertIfChecksReentrancy_ControlCollateral(address alice, uint256 seed) public {
        vm.assume(alice != address(0) && alice != address(evc));

        address collateral = address(new Vault(evc));
        address controller = address(new Vault(evc));
        vm.assume(collateral != address(evc));

        vm.prank(alice);
        evc.enableCollateral(alice, collateral);

        vm.prank(alice);
        evc.enableController(alice, controller);

        evc.setChecksInProgress(true);

        bytes memory data = abi.encodeWithSelector(
            Target(address(evc)).controlCollateralTest.selector, address(evc), address(evc), seed, alice
        );

        vm.deal(alice, seed);
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_ChecksReentrancy.selector);
        evc.controlCollateral{value: seed}(collateral, alice, seed, data);
    }

    function test_RevertIfControlCollateralReentrancy_ControlCollateral(address alice, uint256 seed) public {
        vm.assume(alice != address(0) && alice != address(evc));

        address collateral = address(new Vault(evc));
        address controller = address(new Vault(evc));
        vm.assume(collateral != address(evc));

        vm.prank(alice);
        evc.enableCollateral(alice, collateral);

        vm.prank(alice);
        evc.enableController(alice, controller);

        evc.setControlCollateralInProgress(true);

        bytes memory data = abi.encodeWithSelector(
            Target(address(evc)).controlCollateralTest.selector, address(evc), address(evc), seed, alice
        );

        vm.deal(alice, seed);
        vm.prank(alice);
        vm.expectRevert(Errors.EVC_ControlCollateralReentrancy.selector);
        evc.controlCollateral{value: seed}(collateral, alice, seed, data);
    }

    function test_RevertIfNoControllerEnabled_ControlCollateral(address alice, uint256 seed) public {
        vm.assume(alice != address(0) && alice != address(evc));

        address collateral = address(new Vault(evc));
        address controller = address(new Vault(evc));

        vm.assume(collateral != address(evc));

        vm.prank(alice);
        evc.enableCollateral(alice, collateral);

        bytes memory data = abi.encodeWithSelector(
            Target(collateral).controlCollateralTest.selector, address(evc), address(evc), seed, alice
        );

        vm.deal(controller, seed);
        vm.prank(controller);
        vm.expectRevert(Errors.EVC_ControllerViolation.selector);
        evc.controlCollateral{value: seed}(collateral, alice, seed, data);
    }

    function test_RevertIfMultipleControllersEnabled_ControlCollateral(address alice, uint256 seed) public {
        vm.assume(alice != address(0) && alice != address(evc));

        address collateral = address(new Vault(evc));
        address controller_1 = address(new Vault(evc));
        address controller_2 = address(new Vault(evc));

        vm.assume(collateral != address(evc));

        // mock checks deferred to enable multiple controllers
        evc.setChecksDeferred(true);

        vm.prank(alice);
        evc.enableCollateral(alice, collateral);

        vm.prank(alice);
        evc.enableController(alice, controller_1);

        vm.prank(alice);
        evc.enableController(alice, controller_2);

        bytes memory data = abi.encodeWithSelector(
            Target(collateral).controlCollateralTest.selector, address(evc), address(evc), seed, alice
        );

        vm.deal(controller_1, seed);
        vm.prank(controller_1);
        vm.expectRevert(Errors.EVC_ControllerViolation.selector);
        evc.controlCollateral{value: seed}(collateral, alice, seed, data);
    }

    function test_RevertIfMsgSenderIsNotEnabledController_ControlCollateral(
        address alice,
        address randomAddress,
        uint256 seed
    ) public {
        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(uint160(randomAddress) > 10 && randomAddress != address(evc));

        address collateral = address(new Vault(evc));
        address controller = address(new Vault(evc));

        vm.assume(collateral != address(evc));
        vm.assume(randomAddress != controller);

        vm.prank(alice);
        evc.enableCollateral(alice, collateral);

        vm.prank(alice);
        evc.enableController(alice, controller);

        bytes memory data = abi.encodeWithSelector(
            Target(collateral).controlCollateralTest.selector, address(evc), address(evc), seed, alice
        );

        vm.deal(randomAddress, seed);
        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(Errors.EVC_NotAuthorized.selector));
        evc.controlCollateral{value: seed}(collateral, alice, seed, data);
    }

    function test_RevertIfTargetContractIsNotEnabledCollateral_ControlCollateral(
        address alice,
        address targetContract,
        uint256 seed
    ) public {
        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(targetContract != address(evc));

        address collateral = address(new Vault(evc));
        address controller = address(new Vault(evc));

        vm.assume(targetContract != collateral && targetContract != controller);

        vm.prank(alice);
        evc.enableCollateral(alice, collateral);

        vm.prank(alice);
        evc.enableController(alice, controller);

        bytes memory data = abi.encodeWithSelector(
            Target(collateral).controlCollateralTest.selector, address(evc), address(evc), seed, alice
        );

        vm.deal(controller, seed);
        vm.prank(controller);
        vm.expectRevert(abi.encodeWithSelector(Errors.EVC_NotAuthorized.selector));
        evc.controlCollateral{value: seed}(targetContract, alice, seed, data);
    }

    function test_RevertIfValueExceedsBalance_ControlCollateral(address alice, uint128 seed) public {
        vm.assume(alice != address(0) && alice != address(evc));
        vm.assume(seed > 0);

        address collateral = address(new Vault(evc));
        address controller = address(new Vault(evc));
        vm.assume(collateral != address(evc) && controller != address(evc));

        vm.prank(alice);
        evc.enableCollateral(alice, collateral);

        vm.prank(alice);
        evc.enableController(alice, controller);

        bytes memory data = abi.encodeWithSelector(
            Target(address(evc)).controlCollateralTest.selector, address(evc), address(evc), seed, alice
        );

        // reverts if value exceeds balance
        vm.deal(controller, seed);
        vm.prank(controller);
        vm.expectRevert(Errors.EVC_InvalidValue.selector);
        evc.controlCollateral{value: seed - 1}(collateral, alice, seed, data);

        // succeeds if value does not exceed balance
        vm.prank(controller);
        evc.controlCollateral{value: seed}(collateral, alice, seed, data);
    }

    function test_RevertIfInternalCallIsUnsuccessful_ControlCollateral(address alice) public {
        // call setUp() explicitly for Diligence Fuzzing tool to pass
        setUp();

        vm.assume(alice != address(0));
        vm.assume(alice != address(evc));

        address collateral = address(new Vault(evc));
        address controller = address(new Vault(evc));
        vm.assume(collateral != address(evc) && controller != address(evc));

        vm.prank(alice);
        evc.enableCollateral(alice, collateral);

        vm.prank(alice);
        evc.enableController(alice, controller);

        bytes memory data = abi.encodeWithSelector(Target(collateral).revertEmptyTest.selector);

        vm.prank(controller);
        vm.expectRevert(Errors.EVC_EmptyError.selector);
        evc.controlCollateral(collateral, alice, 0, data);
    }
}
