// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {ConfigAmountLib} from "../../../../../src/EVault/shared/types/ConfigAmount.sol";

contract BalanceForwarderTest_Hooks is EVaultTestBase {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    MockBalanceTracker MBT;

    function setUp() public override {
        super.setUp();
        MBT = MockBalanceTracker(balanceTracker);

        assetTST.mint(alice, 1000 ether);
        vm.prank(alice);
        assetTST.approve(address(eTST), 1000 ether);
        vm.prank(alice);
        eTST.deposit(10 ether, alice);

        // alice, bob: enabled tracking, charlie: disabled tracking
        vm.prank(alice);
        eTST.enableBalanceForwarder();

        vm.prank(bob);
        eTST.enableBalanceForwarder();
    }

    function test_OnEnableForwarder_ZeroBalance() public {
        vm.prank(charlie);
        eTST.enableBalanceForwarder();

        assertEq(MBT.calls(charlie, 0, false), 1);
        assertBalance(charlie, 0);
    }

    function test_OnEnableForwarder_AlreadyEnabled() public {
        vm.prank(charlie);
        eTST.enableBalanceForwarder();
        vm.prank(charlie);
        eTST.enableBalanceForwarder();

        assertEq(MBT.calls(charlie, 0, false), 2);
        assertBalance(charlie, 0);
    }

    function test_OnEnableForwarder_NonZeroBalance() public {
        assetTST.mint(charlie, 1000 ether);
        vm.prank(charlie);
        assetTST.approve(address(eTST), 1000 ether);
        vm.prank(charlie);
        eTST.deposit(10 ether, charlie);

        vm.prank(charlie);
        eTST.enableBalanceForwarder();

        assertEq(MBT.calls(charlie, 10 ether, false), 1);
        assertBalance(charlie, 10 ether);
    }

    function test_OnDisableForwarder_ZeroBalance() public {
        vm.prank(charlie);
        eTST.disableBalanceForwarder();

        assertEq(MBT.calls(charlie, 0, false), 1);
        assertBalance(charlie, 0);
    }

    function test_OnDisableForwarder_AlreadyDisabled() public {
        vm.prank(charlie);
        eTST.disableBalanceForwarder();
        vm.prank(charlie);
        eTST.disableBalanceForwarder();

        assertEq(MBT.calls(charlie, 0 ether, false), 2);
        assertBalance(charlie, 0);
    }

    function test_OnDisableForwarder_NonZeroBalance() public {
        assetTST.mint(charlie, 1000 ether);
        vm.prank(charlie);
        assetTST.approve(address(eTST), 1000 ether);
        vm.prank(charlie);
        eTST.deposit(10 ether, charlie);

        vm.prank(charlie);
        eTST.enableBalanceForwarder();

        vm.prank(charlie);
        eTST.disableBalanceForwarder();

        assertEq(MBT.calls(charlie, 0, false), 1);
        assertEq(MBT.balance(charlie), 0);
    }

    function test_OnTransfer_Origin() public {
        vm.prank(alice);
        eTST.transfer(bob, 1 ether);
        assertEq(MBT.calls(alice, 9 ether, false), 1);
        assertBalance(alice, 9 ether);
    }

    function test_OnTransfer_Receiver() public {
        vm.prank(alice);
        eTST.transfer(bob, 1 ether);
        assertEq(MBT.calls(bob, 1 ether, false), 1);
        assertBalance(bob, 1 ether);
    }

    function test_OnTransferFrom_Origin() public {
        vm.prank(alice);
        eTST.transferFrom(alice, bob, 1 ether);
        assertEq(MBT.calls(alice, 9 ether, false), 1);
        assertBalance(alice, 9 ether);
    }

    function test_OnTransferFrom_Receiver() public {
        vm.prank(alice);
        eTST.transferFrom(alice, bob, 1 ether);
        assertEq(MBT.calls(bob, 1 ether, false), 1);
        assertBalance(bob, 1 ether);
    }

    function test_OnTransferFromMax_Origin() public {
        vm.prank(alice);
        eTST.transferFromMax(alice, bob);
        assertEq(MBT.calls(alice, 0, false), 1);
        assertBalance(alice, 0);
    }

    function test_OnTransferFromMax_Receiver() public {
        vm.prank(alice);
        eTST.transferFromMax(alice, bob);
        assertEq(MBT.calls(bob, 10 ether, false), 1);
        assertBalance(bob, 10 ether);
    }

    function test_OnDeposit_ToSelf() public {
        vm.prank(alice);
        eTST.deposit(1 ether, alice);
        assertEq(MBT.calls(alice, 11 ether, false), 1);
        assertBalance(alice, 11 ether);
    }

    function test_OnDeposit_ToOther() public {
        vm.prank(alice);
        eTST.deposit(1 ether, bob);
        assertEq(MBT.calls(bob, 1 ether, false), 1);
        assertEq(MBT.balance(bob), 1 ether);
        assertBalance(alice, 10 ether);
    }

    function test_OnMint_ToSelf() public {
        vm.prank(alice);
        eTST.mint(1 ether, alice);
        assertEq(MBT.calls(alice, 11 ether, false), 1);
        assertBalance(alice, 11 ether);
    }

    function test_OnMint_ToOther() public {
        vm.prank(alice);
        eTST.mint(1 ether, bob);
        assertEq(MBT.calls(bob, 1 ether, false), 1);
        assertEq(MBT.balance(bob), 1 ether);
        assertBalance(alice, 10 ether);
    }

    function test_OnWithdraw_FromSelf() public {
        vm.prank(alice);
        eTST.withdraw(1 ether, alice, alice);
        assertEq(MBT.calls(alice, 9 ether, false), 1);
        assertBalance(alice, 9 ether);
    }

    function test_OnWithdraw_FromOther() public {
        vm.prank(alice);
        eTST.approve(bob, 1 ether);
        vm.prank(bob);
        eTST.withdraw(1 ether, bob, alice);
        assertEq(MBT.calls(alice, 9 ether, false), 1);
        assertBalance(alice, 9 ether);
    }

    function test_OnRedeem_FromSelf() public {
        vm.prank(alice);
        eTST.redeem(1 ether, alice, alice);
        assertEq(MBT.calls(alice, 9 ether, false), 1);
        assertBalance(alice, 9 ether);
    }

    function test_OnRedeem_FromOther() public {
        vm.prank(alice);
        eTST.approve(bob, 1 ether);
        vm.prank(bob);
        eTST.redeem(1 ether, bob, alice);
        assertEq(MBT.calls(alice, 9 ether, false), 1);
        assertBalance(alice, 9 ether);
    }

    function test_OnLiquidation() public {
        vm.skip(true);
    }

    function test_OnRepayWithShares_FromSelf() public {
        setUpBorrow(alice);

        vm.startPrank(alice);
        eTST.borrow(2 ether, alice);
        eTST.deposit(2 ether, alice);

        eTST.repayWithShares(1 ether, alice);
        assertEq(MBT.calls(alice, 11 ether, false), 1);
        assertBalance(alice, 11 ether);
    }

    function test_OnRepayWithShares_FromOther() public {
        setUpBorrow(alice);

        vm.startPrank(alice);
        eTST.borrow(2 ether, alice);
        eTST.deposit(2 ether, alice);

        eTST.repayWithShares(1 ether, bob);
        assertEq(MBT.calls(alice, 12 ether, false), 1);
        assertBalance(alice, 12 ether);
    }

    function test_OnConvertFees() public {
        setUpBorrow(alice);

        vm.prank(alice);
        eTST.deposit(1 ether, bob);

        skip(300);

        address govFeeReceiver = makeAddr("govFeeReceiver");
        eTST.setFeeReceiver(govFeeReceiver);

        vm.prank(protocolFeeReceiver);
        eTST.enableBalanceForwarder();
        vm.prank(govFeeReceiver);
        eTST.enableBalanceForwarder();

        uint256 fees = eTST.accumulatedFees();

        assertEq(MBT.calls(protocolFeeReceiver, 0, false), 1);
        assertEq(MBT.calls(govFeeReceiver, 0, false), 1);

        vm.prank(alice);
        eTST.convertFees();

        uint256 governorFees = fees * 9e17 / 1e18;
        uint256 protocolFees = fees - governorFees;

        assertEq(MBT.calls(protocolFeeReceiver, protocolFees, false), 1);
        assertEq(MBT.calls(govFeeReceiver, governorFees, false), 1);
    }

    function assertBalance(address user, uint256 balance) internal view {
        assertEq(MBT.balance(user), balance);
        assertEq(eTST.balanceOf(user), balance);
    }

    function setUpBorrow(address user) internal {
        eTST.setLTV(address(eTST2), 1e4, 1e4, 0);

        vm.startPrank(user);
        assetTST2.mint(user, 1000 ether);
        assetTST2.approve(address(eTST2), 1000 ether);
        eTST2.deposit(1000 ether, user);

        evc.enableController(user, address(eTST));
        evc.enableCollateral(user, address(eTST2));

        oracle.setPrice(address(assetTST), unitOfAccount, 1 ether);
        oracle.setPrice(address(assetTST2), unitOfAccount, 1 ether);
        vm.stopPrank();
    }
}
