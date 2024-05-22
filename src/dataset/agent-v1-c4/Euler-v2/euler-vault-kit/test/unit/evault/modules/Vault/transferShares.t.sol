// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";

//transfer eVault balances, without interest
contract VaultTest_TransferShares is EVaultTestBase {
    address user1;
    address user2;
    address user3;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        assetTST.mint(user1, 1000);
        startHoax(user1);
        assetTST.approve(address(eTST), type(uint256).max);

        assetTST.mint(user2, 1000);
        startHoax(user2);
        assetTST.approve(address(eTST), type(uint256).max);

        assetTST.mint(user3, 1000);
        startHoax(user3);
        assetTST.approve(address(eTST), type(uint256).max);
    }

    function test_basicTransfer() public {
        startHoax(user1);
        eTST.deposit(1000, user1);

        assertEq(eTST.balanceOf(user1), 1000);
        assertEq(eTST.balanceOf(user2), 0);

        vm.expectEmit();
        emit Events.Transfer(user1, user2, 400);
        vm.expectEmit();
        emit Events.VaultStatus(1000, 0, 0, 1000, 1e27, 0, block.timestamp);
        eTST.transfer(user2, 400);

        assertEq(eTST.balanceOf(user1), 600);
        assertEq(eTST.balanceOf(user2), 400);
    }

    //transfer with zero amount is a no-op
    function test_transfer_zeroAmount() public {
        startHoax(user1);
        eTST.deposit(1000, user1);

        eTST.transfer(user2, 500);

        assertEq(eTST.balanceOf(user1), 500);
        assertEq(eTST.balanceOf(user2), 500);

        // no-op, balances of sender and recipient not affected
        vm.expectEmit();
        emit Events.Transfer(user1, user2, 0);
        vm.expectEmit();
        emit Events.VaultStatus(1000, 0, 0, 1000, 1e27, 0, block.timestamp);
        eTST.transfer(user2, 0);
    }

    //transfer between sub-accounts with zero amount is a no-op
    function test_transfer_betweenSubAccounts_zeroAmount() public {
        startHoax(user1);
        eTST.deposit(1000, user1);

        eTST.transfer(user2, 500);
        assertEq(eTST.balanceOf(user1), 500);
        assertEq(eTST.balanceOf(user2), 500);

        eTST.transfer(getSubAccount(user1, 1), 200);

        // no-op, balances of sender and recipient not affected
        vm.expectEmit();
        emit Events.Transfer(getSubAccount(user1, 1), getSubAccount(user1, 255), 0);
        vm.expectEmit();
        emit Events.VaultStatus(1000, 0, 0, 1000, 1e27, 0, block.timestamp);
        eTST.transferFrom(getSubAccount(user1, 1), getSubAccount(user1, 255), 0);

        assertEq(eTST.balanceOf(user1), 300);
        assertEq(eTST.balanceOf(getSubAccount(user1, 1)), 200);
        assertEq(eTST.balanceOf(getSubAccount(user1, 255)), 0);
    }

    function test_transfer_maxAmount() public {
        startHoax(user1);
        eTST.deposit(1000, user1);

        // MAX_UINT is *not* a short-cut for this:
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST.transfer(user2, type(uint256).max);

        vm.expectEmit();
        emit Events.Transfer(user1, user2, 1000);
        vm.expectEmit();
        emit Events.VaultStatus(1000, 0, 0, 1000, 1e27, 0, block.timestamp);
        eTST.transferFromMax(user1, user2);

        assertEq(eTST.balanceOf(user1), 0);
        assertEq(eTST.balanceOf(user2), 1000);
    }

    function test_approve_maxAmount() public {
        startHoax(user2);
        eTST.deposit(1000, user2);

        assertEq(eTST.balanceOf(user2), 1000);
        assertEq(eTST.allowance(user2, user1), 0);

        startHoax(address(this));

        vm.expectRevert(Errors.E_InsufficientAllowance.selector);
        eTST.transferFrom(user2, user3, 300);
        vm.expectRevert(Errors.E_InsufficientAllowance.selector);
        eTST.transferFrom(user2, user3, 300);

        startHoax(user2);
        vm.expectEmit();
        emit Events.Approval(user2, user1, type(uint256).max);
        eTST.approve(user1, type(uint256).max);

        assertEq(eTST.allowance(user2, user1), type(uint256).max);

        startHoax(user1);
        vm.expectEmit();
        emit Events.Transfer(user2, user3, 300);
        eTST.transferFrom(user2, user3, 300);

        startHoax(user3);
        vm.expectRevert(Errors.E_InsufficientAllowance.selector);
        eTST.transferFrom(user2, user3, 100);

        assertEq(eTST.balanceOf(user2), 700);
        assertEq(eTST.balanceOf(user3), 300);
        assertEq(eTST.allowance(user2, user1), type(uint256).max);
    }

    function test_approve_limitAmount() public {
        startHoax(user2);
        eTST.deposit(1000, user2);

        vm.expectEmit();
        emit Events.Approval(user2, user1, 200);
        eTST.approve(user1, 200);

        assertEq(eTST.allowance(user2, user1), 200);

        startHoax(user1);
        vm.expectRevert(Errors.E_InsufficientAllowance.selector);
        eTST.transferFrom(user2, user3, 201);

        eTST.transferFrom(user2, user3, 150);

        assertEq(eTST.balanceOf(user2), 850);
        assertEq(eTST.balanceOf(user3), 150);
        assertEq(eTST.allowance(user2, user1), 50);
    }

    function test_transfer_betweenSubAccounts() public {
        startHoax(user1);
        eTST.deposit(1000, user1);

        eTST.transfer(getSubAccount(user1, 1), 700);
        // sub-accounts are not recognized by the vault itself
        vm.expectRevert(Errors.E_InsufficientAllowance.selector);
        eTST.transferFrom(getSubAccount(user1, 1), getSubAccount(user1, 255), 400);

        startHoax(getSubAccount(user1, 1));

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: getSubAccount(user1, 1),
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.approve.selector, user1, 500)
        });
        evc.batch(items);

        eTST.transferFrom(getSubAccount(user1, 1), getSubAccount(user1, 255), 400);
    }

    //self-transfer with valid amount
    function test_transfer_selfTransfer_validAmount() public {
        startHoax(user1);
        eTST.deposit(1000, user1);

        assertEq(eTST.balanceOf(user1), 1000);

        // revert on self-transfer of eVault
        vm.expectRevert(Errors.E_SelfTransfer.selector);
        eTST.transfer(user1, 10);

        assertEq(eTST.balanceOf(user1), 1000);
    }

    //self-transfer with zero amount
    function test_transfer_selfTransfer_zeroAmount() public {
        startHoax(user1);
        eTST.deposit(1000, user1);

        assertEq(eTST.balanceOf(user1), 1000);

        // revert on self-transfer of eVault
        vm.expectRevert(Errors.E_SelfTransfer.selector);
        eTST.transfer(user1, 0);

        assertEq(eTST.balanceOf(user1), 1000);
    }

    //self-transfer with max amount exceeding balance
    function test_transfer_selfTransfer_maxAmount() public {
        startHoax(user1);
        eTST.deposit(1000, user1);

        assertEq(eTST.balanceOf(user1), 1000);

        // revert on self-transfer of eVault
        vm.expectRevert(Errors.E_SelfTransfer.selector);
        eTST.transfer(user1, 1);

        assertEq(eTST.balanceOf(user1), 1000);
    }
}
