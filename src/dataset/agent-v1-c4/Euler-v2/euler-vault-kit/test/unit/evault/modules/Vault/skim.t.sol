// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";

import "../../../../../src/EVault/shared/types/Types.sol";

contract VaultTest_Skim is EVaultTestBase {
    using TypesLib for uint256;

    address user;

    function setUp() public override {
        super.setUp();

        user = makeAddr("user");

        assetTST.mint(user, type(uint256).max);
        hoax(user);
        assetTST.approve(address(eTST), type(uint256).max);
    }

    function test_simpleSkim() public {
        uint256 amount = 20e18;
        vm.startPrank(user);
        assetTST.transfer(address(eTST), amount);

        uint256 value = 1e7;

        assertEq(eTST.balanceOf(user), 0);

        eTST.skim(value, user);

        assertEq(eTST.balanceOf(user), value);
        assertEq(eTST.cash(), value);

        eTST.withdraw(1e7, user, user);
        assertEq(assetTST.balanceOf(address(eTST)), amount - value);
    }

    function test_RevertIfInsufficientAssets() public {
        uint256 amount = 20e18;
        vm.startPrank(user);
        assetTST.transfer(address(eTST), amount);

        uint256 value1 = 22e18;

        assertEq(eTST.balanceOf(user), 0);

        vm.expectRevert(Errors.E_InsufficientAssets.selector);
        eTST.skim(value1, user);

        uint256 value2 = 1e18;

        eTST.skim(value2, user);
        assertEq(eTST.balanceOf(user), value2);

        eTST.skim(value2, user);
        assertEq(eTST.balanceOf(user), value2 * 2);

        uint256 value3 = 18e18;

        eTST.skim(value3, user);
        assertEq(eTST.balanceOf(user), amount);

        vm.expectRevert(Errors.E_InsufficientAssets.selector);
        eTST.skim(1, user);
    }

    function test_zeroAmount() public {
        uint256 amount = 20e18;
        vm.startPrank(user);
        assetTST.transfer(address(eTST), amount);

        uint256 value = 0;

        assertEq(eTST.balanceOf(user), 0);

        uint256 result = eTST.skim(value, user);

        assertEq(result, value);
        assertEq(eTST.balanceOf(user), value);
    }

    function test_maxAmount() public {
        uint256 amount = 20e18;
        vm.startPrank(user);
        assetTST.transfer(address(eTST), amount);

        uint256 value = type(uint256).max;

        assertEq(eTST.balanceOf(user), 0);

        uint256 result = eTST.skim(value, user);

        assertEq(result, amount);
        assertEq(eTST.balanceOf(user), amount);

        eTST.skim(value, user);
        assertEq(eTST.balanceOf(user), amount);
    }

    function test_maxSaneAmount() public {
        uint256 amount = MAX_SANE_AMOUNT;
        vm.startPrank(user);
        assetTST.transfer(address(eTST), amount);

        uint256 value = MAX_SANE_AMOUNT;

        assertEq(eTST.balanceOf(user), 0);

        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST.skim(value + 1, user);

        uint256 result = eTST.skim(value, user);

        assertEq(result, value);
        assertEq(eTST.balanceOf(user), value);

        vm.expectRevert(Errors.E_InsufficientAssets.selector);
        eTST.skim(1, user);
    }

    function test_zeroAddressReceiver() public {
        uint256 amount = 20e18;
        vm.startPrank(user);
        assetTST.transfer(address(eTST), amount);

        uint256 value = 1e18;

        vm.expectRevert(Errors.E_BadSharesReceiver.selector);
        eTST.skim(value, address(0));
    }

    function test_burnAddressReceiver() public {
        uint256 amount = 20e18;
        vm.startPrank(user);
        assetTST.transfer(address(eTST), amount);

        uint256 value = 1e18;

        eTST.skim(value, address(1));
        assertEq(eTST.balanceOf(user), 0);
    }
}
