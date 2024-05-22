// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ESynth, IEVC, Ownable} from "../../../src/Synths/ESynth.sol";

contract ESynthTotalSupplyTest is Test {
    ESynth synth;
    address owner = makeAddr("owner");
    address ignored1 = makeAddr("ignored1");
    address ignored2 = makeAddr("ignored2");
    address ignored3 = makeAddr("ignored3");

    function setUp() public {
        vm.startPrank(owner);
        synth = new ESynth(IEVC(makeAddr("evc")), "TestSynth", "TS");
        synth.setCapacity(owner, 1000000e18);
        vm.stopPrank();
    }

    function test_addIgnoredForTotalSupply_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        synth.addIgnoredForTotalSupply(ignored1);
    }

    function test_addIgnored() public {
        vm.prank(owner);
        bool success = synth.addIgnoredForTotalSupply(ignored1);

        address[] memory ignored = synth.getAllIgnoredForTotalSupply();
        assertEq(ignored.length, 1);
        assertEq(ignored[0], ignored1);
        assertTrue(success);
    }

    function test_addIgnored_duplicate() public {
        vm.startPrank(owner);
        synth.addIgnoredForTotalSupply(ignored1);
        bool success = synth.addIgnoredForTotalSupply(ignored1);
        vm.stopPrank();

        address[] memory ignored = synth.getAllIgnoredForTotalSupply();
        assertEq(ignored.length, 1);
        assertEq(ignored[0], ignored1);
        assertFalse(success);
    }

    function test_removeIgnoredForTotalSupply_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        synth.removeIgnoredForTotalSupply(ignored1);
    }

    function test_removeIgnored() public {
        vm.startPrank(owner);
        synth.addIgnoredForTotalSupply(ignored1);
        bool success = synth.removeIgnoredForTotalSupply(ignored1);
        vm.stopPrank();

        address[] memory ignored = synth.getAllIgnoredForTotalSupply();
        assertEq(ignored.length, 0);
        assertTrue(success);
    }

    function test_removeIgnored_notFound() public {
        vm.startPrank(owner);
        bool success = synth.removeIgnoredForTotalSupply(ignored1);
        vm.stopPrank();

        address[] memory ignored = synth.getAllIgnoredForTotalSupply();
        assertEq(ignored.length, 0);
        assertFalse(success);
    }

    function test_totalSupply_nothingIgnored() public {
        vm.startPrank(owner);
        synth.mint(ignored1, 100);
        synth.mint(ignored2, 200);
        synth.mint(ignored3, 300);
        vm.stopPrank();

        assertEq(synth.totalSupply(), 600);
    }

    function test_TotalSupplyAddresses_ignored() public {
        vm.startPrank(owner);
        synth.mint(ignored1, 100);
        synth.mint(ignored2, 200);
        synth.mint(ignored3, 300);
        synth.addIgnoredForTotalSupply(ignored1);
        synth.addIgnoredForTotalSupply(ignored2);
        vm.stopPrank();

        assertEq(synth.totalSupply(), 300);
    }
}
