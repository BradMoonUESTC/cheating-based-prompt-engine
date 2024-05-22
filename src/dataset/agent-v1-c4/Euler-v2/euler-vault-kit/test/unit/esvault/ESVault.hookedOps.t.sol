// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ESVaultTestBase, ESynth} from "./ESVaultTestBase.t.sol";
import {Errors} from "../../../src/EVault/shared/Errors.sol";

contract ESVaultTestHookedOps is ESVaultTestBase {
    function setUp() public override {
        super.setUp();
    }

    function test_hooked_ops_after_init() public view {
        (address hookTarget, uint32 hookedOps) = eTST.hookConfig();
        assertEq(hookTarget, SYNTH_VAULT_HOOK_TARGET);
        assertEq(hookedOps, SYNTH_VAULT_HOOKED_OPS);
    }

    function test_hooked_ops_disabled_if_no_hook_target() public {
        (, uint32 hookedOps) = eTST.hookConfig();
        eTST.setHookConfig(address(0), hookedOps);

        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.deposit(100, address(this));

        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.mint(100, address(this));

        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.redeem(100, address(this), address(this));

        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.skim(100, address(this));

        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.repayWithShares(100, address(this));
    }
}
