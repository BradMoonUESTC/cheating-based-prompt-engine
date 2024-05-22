// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {SafeERC20Lib} from "../../../../../src/EVault/shared/lib/SafeERC20Lib.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

contract VaultTest_BalancesNoInterest is EVaultTestBase {
    address user1;
    address user2;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        assetTST.mint(user1, 10e18);
        assetTST.mint(user2, 10e18);

        startHoax(user1);
        assetTST.approve(address(eTST), type(uint256).max);
        startHoax(user2);
        assetTST.approve(address(eTST), type(uint256).max);
    }

    function test_basicDeposit() public {
        startHoax(user1);
        vm.expectRevert(Errors.E_InsufficientCash.selector);
        eTST.withdraw(1, user1, user1);

        startHoax(user2);
        eTST.deposit(10e18, user2); // so pool size is big enough

        startHoax(user1);
        vm.expectRevert(Errors.E_InsufficientBalance.selector);
        eTST.withdraw(1, user1, user1);

        assertEq(assetTST.balanceOf(user1), 10e18);

        vm.expectEmit();
        emit Events.Transfer(address(0), user1, 10e18);
        vm.expectEmit();
        emit Events.Deposit(user1, user1, 10e18, 10e18);
        vm.expectEmit();
        emit Events.VaultStatus(20e18, 0, 0, 20e18, 1e27, 0, block.timestamp);
        eTST.deposit(10e18, user1);

        assertEq(assetTST.balanceOf(user1), 0);
        assertEq(eTST.balanceOf(user1), 10e18);
        assertEq(eTST.maxWithdraw(user1), 10e18);

        // some unrelated token not affected
        assertEq(assetTST2.balanceOf(user1), 0);
        assertEq(eTST2.balanceOf(user1), 0);

        vm.expectRevert(Errors.E_InsufficientBalance.selector);
        eTST.withdraw(10e18 + 1, user1, user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Lib.E_TransferFromFailed.selector,
                abi.encodeWithSignature("Error(string)", "ERC20: transfer amount exceeds balance"),
                abi.encodeWithSelector(IAllowanceTransfer.AllowanceExpired.selector, 0)
            )
        );
        eTST.deposit(1, user1);

        vm.expectEmit();
        emit Events.Transfer(user1, address(0), 10e18);
        vm.expectEmit();
        emit Events.Withdraw(user1, user1, user1, 10e18, 10e18);
        vm.expectEmit();
        emit Events.VaultStatus(10e18, 0, 0, 10e18, 1e27, 0, block.timestamp);
        eTST.withdraw(10e18, user1, user1);

        assertEq(assetTST.balanceOf(user1), 10e18);
        assertEq(eTST.balanceOf(user1), 0);

        vm.expectRevert(Errors.E_InsufficientBalance.selector);
        eTST.withdraw(1, user1, user1);
    }

    function test_multipleDeposits() public {
        startHoax(user1);
        eTST.deposit(10e18, user1);

        startHoax(user2);
        eTST.deposit(10e18, user2);

        // first user
        assertEq(eTST.balanceOf(user1), 10e18);
        assertEq(eTST.maxWithdraw(user1), 10e18);

        // second user
        assertEq(eTST.balanceOf(user2), 10e18);
        assertEq(eTST.maxWithdraw(user2), 10e18);

        // Total supply is the two balances above
        assertEq(eTST.totalSupply(), 10e18 + 10e18);

        startHoax(user1);
        vm.expectRevert(Errors.E_InsufficientBalance.selector);
        eTST.withdraw(10e18 + 1, user1, user1);

        startHoax(user2);
        vm.expectRevert(Errors.E_InsufficientBalance.selector);
        eTST.withdraw(10e18 + 1, user2, user2);

        startHoax(user1);
        eTST.withdraw(10e18, user1, user1);

        vm.expectRevert(Errors.E_InsufficientBalance.selector);
        eTST.withdraw(1, user1, user1);

        startHoax(user2);
        vm.expectRevert(Errors.E_InsufficientCash.selector);
        eTST.withdraw(20e18, user2, user2);

        eTST.withdraw(4e18, user2, user2);

        vm.expectRevert(Errors.E_InsufficientCash.selector);
        eTST.withdraw(6.00001e18 + 1, user2, user2);

        eTST.withdraw(6e18, user2, user2);

        assertEq(eTST.balanceOf(user1), 0);
        assertEq(eTST.balanceOf(user2), 0);
        assertEq(eTST.totalSupply(), 0);

        assertEq(assetTST.balanceOf(user1), 10e18);
        assertEq(assetTST.balanceOf(user1), 10e18);
    }

    function test_maxDepositAndWithdraw() public {
        startHoax(user1);
        eTST.deposit(type(uint256).max, user1);

        assertEq(assetTST.balanceOf(user1), 0);
        assertEq(eTST.balanceOf(user1), 10e18);

        eTST.redeem(type(uint256).max, user1, user1);

        assertEq(assetTST.balanceOf(user1), 10e18);
        assertEq(eTST.balanceOf(user1), 0);
    }
}
