// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ESVaultTestBase, ESynth} from "./ESVaultTestBase.t.sol";
import {MockHook} from "../evault/EVaultTestBase.t.sol";

contract ESVaultTestAllocate is ESVaultTestBase {
    function setUp() public override {
        super.setUp();

        assetTSTAsSynth.setCapacity(address(this), 10000e18);
    }

    function test_allocate_from_non_synth() public {
        vm.expectRevert(MockHook.E_OnlyAssetCanDeposit.selector);
        eTST.deposit(100, address(this));

        vm.expectRevert(MockHook.E_OperationDisabled.selector);
        eTST.mint(100, address(this));

        vm.expectRevert(MockHook.E_OperationDisabled.selector);
        eTST.skim(100, address(this));

        assertEq(eTST.maxDeposit(address(this)), type(uint112).max - eTST.cash());

        assertEq(eTST.maxMint(address(this)), type(uint112).max - eTST.totalSupply());

        assertEq(eTST.maxRedeem(address(this)), eTST.balanceOf(address(this)));
    }

    function test_allocate_from_synth() public {
        assetTSTAsSynth.mint(address(assetTSTAsSynth), 100);
        assetTSTAsSynth.allocate(address(eTST), 100);

        assertEq(assetTSTAsSynth.isIgnoredForTotalSupply(address(eTST)), true);
        assertEq(assetTST.balanceOf(address(eTST)), 100);
        assertEq(eTST.balanceOf(address(assetTST)), 100);
    }
}
