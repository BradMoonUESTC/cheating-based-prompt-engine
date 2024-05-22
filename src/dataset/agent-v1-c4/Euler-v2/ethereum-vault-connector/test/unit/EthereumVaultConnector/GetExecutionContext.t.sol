// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";

contract GetExecutionContextTest is Test {
    EthereumVaultConnectorHarness internal evc;

    function setUp() public {
        evc = new EthereumVaultConnectorHarness();
    }

    function test_GetExecutionContext(address account, uint8 seed) external {
        vm.assume(account != address(0) && account != address(evc));

        address controller = address(new Vault(evc));

        vm.expectRevert(Errors.EVC_OnBehalfOfAccountNotAuthenticated.selector);
        evc.getCurrentOnBehalfOfAccount(controller);

        uint256 context = evc.getRawExecutionContext();
        assertEq(context, 1 << 200);

        if (seed % 2 == 0) {
            vm.prank(account);
            evc.enableController(account, controller);
        }
        evc.setChecksDeferred(seed % 3 == 0 ? true : false);
        evc.setOnBehalfOfAccount(account);
        evc.setChecksInProgress(seed % 4 == 0 ? true : false);
        evc.setControlCollateralInProgress(seed % 5 == 0 ? true : false);
        evc.setOperatorAuthenticated(seed % 6 == 0 ? true : false);
        evc.setSimulation(seed % 7 == 0 ? true : false);

        (address onBehalfOfAccount, bool controllerEnabled) = evc.getCurrentOnBehalfOfAccount(controller);
        context = evc.getRawExecutionContext();

        assertEq(onBehalfOfAccount, account);
        assertEq(controllerEnabled, seed % 2 == 0 ? true : false);
        assertEq(
            context & 0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, uint256(uint160(account))
        );
        assertEq(
            context & 0x0000000000000000000000FF0000000000000000000000000000000000000000 != 0,
            seed % 3 == 0 ? true : false
        );
        assertEq(evc.areChecksDeferred(), seed % 3 == 0 ? true : false);
        assertEq(
            context & 0x00000000000000000000FF000000000000000000000000000000000000000000 != 0,
            seed % 4 == 0 ? true : false
        );
        assertEq(evc.areChecksInProgress(), seed % 4 == 0 ? true : false);
        assertEq(
            context & 0x000000000000000000FF00000000000000000000000000000000000000000000 != 0,
            seed % 5 == 0 ? true : false
        );
        assertEq(evc.isControlCollateralInProgress(), seed % 5 == 0 ? true : false);
        assertEq(
            context & 0x0000000000000000FF0000000000000000000000000000000000000000000000 != 0,
            seed % 6 == 0 ? true : false
        );
        assertEq(evc.isOperatorAuthenticated(), seed % 6 == 0 ? true : false);
        assertEq(
            context & 0x00000000000000FF000000000000000000000000000000000000000000000000 != 0,
            seed % 7 == 0 ? true : false
        );
        assertEq(evc.isSimulationInProgress(), seed % 7 == 0 ? true : false);
    }
}
