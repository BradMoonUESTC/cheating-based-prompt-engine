// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {IEVault} from "../../../../../src/EVault/IEVault.sol";
import {TestERC20} from "../../../../mocks/TestERC20.sol";
import "../../../../../src/EVault/shared/types/Types.sol";

contract VaultTest_AmountLimits is EVaultTestBase {
    address user1;
    address user2;

    TestERC20 assetTST3;
    IEVault public eTST3;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        assetTST3 = new TestERC20("Test TST 3", "TST3", 0, false);
        eTST3 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST3), address(oracle), unitOfAccount))
        );

        assetTST.mint(user1, type(uint256).max / 2);
        startHoax(user1);
        assetTST.approve(address(eTST), type(uint256).max);

        assetTST.mint(user2, type(uint256).max / 2);
        startHoax(user2);
        assetTST.approve(address(eTST), type(uint256).max);
    }

    function test_depositsAndWithdrawals() public {
        // Reads balanceOf on TST, which returns amount too large
        startHoax(user1);
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST.deposit(type(uint256).max, user1);

        // Specifies direct amount too large
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST.deposit(type(uint256).max - 1, user1);
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST.withdraw(type(uint256).max - 1, user1, user1);

        // One too large
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST.deposit(MAX_SANE_AMOUNT + 1, user1);
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST.withdraw(MAX_SANE_AMOUNT + 1, user1, user1);

        // Ok after reducing by 1
        eTST.deposit(MAX_SANE_AMOUNT, user1);

        // Now another deposit to push us over the top
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST.deposit(1, user1);

        // And from another account, poolSize will be too large
        startHoax(user2);
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST.deposit(1, user2);

        assertEq(eTST.balanceOf(user1), MAX_SANE_AMOUNT);
        assertEq(eTST.maxWithdraw(user1), MAX_SANE_AMOUNT);
        assertEq(eTST.totalSupply(), MAX_SANE_AMOUNT);
        assertEq(eTST.totalAssets(), MAX_SANE_AMOUNT);

        // Withdraw exact balance
        uint256 snapshot = vm.snapshot();

        startHoax(user1);
        eTST.withdraw(MAX_SANE_AMOUNT, user1, user1);

        assertEq(eTST.balanceOf(user1), 0);
        assertEq(eTST.maxWithdraw(user1), 0);
        assertEq(eTST.totalSupply(), 0);
        assertEq(eTST.totalAssets(), 0);

        vm.revertTo(snapshot);

        // redeem max for full balance
        startHoax(user1);
        eTST.redeem(type(uint256).max, user1, user1);

        // check balances
        assertEq(eTST.balanceOf(user1), 0);
        assertEq(eTST.maxWithdraw(user1), 0);
        assertEq(eTST.totalSupply(), 0);
        assertEq(eTST.totalAssets(), 0);
    }

    function test_lowerDecimals() public {
        assetTST3.mint(user1, type(uint256).max);
        startHoax(user1);
        assetTST3.approve(address(eTST3), type(uint256).max);

        // Reads balanceOf on TST, which returns amount too large
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST3.deposit(type(uint256).max, user1);

        // Specifies direct amount too large
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST3.deposit(type(uint256).max - 1, user1);
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST3.withdraw(type(uint256).max - 1, user1, user1);

        // One too large
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST3.deposit(MAX_SANE_AMOUNT + 1, user1);
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST3.withdraw(MAX_SANE_AMOUNT + 1, user1, user1);

        // OK, by 1
        eTST3.deposit(MAX_SANE_AMOUNT, user1);

        assertEq(eTST3.balanceOf(user1), MAX_SANE_AMOUNT);
        assertEq(eTST3.maxWithdraw(user1), MAX_SANE_AMOUNT);
        assertEq(eTST3.totalSupply(), MAX_SANE_AMOUNT);
        assertEq(eTST3.totalAssets(), MAX_SANE_AMOUNT);

        // Withdraw exact balance
        uint256 snapshot = vm.snapshot();

        startHoax(user1);
        eTST3.withdraw(MAX_SANE_AMOUNT, user1, user1);

        assertEq(eTST3.balanceOf(user1), 0);
        assertEq(eTST3.maxWithdraw(user1), 0);
        assertEq(eTST3.totalSupply(), 0);
        assertEq(eTST3.totalAssets(), 0);

        vm.revertTo(snapshot);

        // redeem max for full balance
        startHoax(user1);
        eTST3.redeem(type(uint256).max, user1, user1);

        // check balances
        assertEq(eTST3.balanceOf(user1), 0);
        assertEq(eTST3.maxWithdraw(user1), 0);
        assertEq(eTST3.totalSupply(), 0);
        assertEq(eTST3.totalAssets(), 0);
    }

    function test_depositOverAssetLimit() public {
        // configure TST to transfer requested amount + 1 wei
        assetTST.configure("transfer/inflationary", abi.encode(1));
        startHoax(user1);
        eTST.deposit(MAX_SANE_AMOUNT, user1);

        startHoax(user2);
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST.deposit(1, user2);
    }
}
