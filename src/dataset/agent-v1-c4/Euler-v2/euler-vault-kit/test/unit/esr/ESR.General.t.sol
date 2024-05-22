// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import "./lib/ESRTest.sol";
import "../../mocks/MockMinimalStatusCheck.sol";

contract ESRGeneralTest is ESRTest {
    MockMinimalStatusCheck public statusCheck;

    function setUp() public override {
        super.setUp();
        statusCheck = new MockMinimalStatusCheck();
    }

    function test_totalAssetsShouldAddTheInterest() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);
        uint256 interestAmount = 10e18;

        asset.mint(address(esr), interestAmount);
        esr.gulp();

        // pass the time for the interest to be added
        skip(esr.INTEREST_SMEAR());

        assertEq(esr.totalAssets(), depositAmount + interestAmount);
    }

    function test_totalAssetsShouldAddTheInterestAndTheDeposits() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);
        uint256 interestAmount = 10e18;

        asset.mint(address(esr), interestAmount);
        esr.gulp();

        // pass the time for the interest to be added
        skip(esr.INTEREST_SMEAR());

        uint256 depositAmount2 = 100e18;
        doDeposit(user, depositAmount2);

        assertEq(esr.totalAssets(), depositAmount + interestAmount + depositAmount2);
    }

    function test_gulpBetweenShouldNotAffectTotalAssets() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);
        uint256 interestAmount = 10e18;
        asset.mint(address(esr), interestAmount);
        esr.gulp();

        skip(esr.INTEREST_SMEAR() / 2);
        // gulp will push the interest by 2 weeks again
        // so we need to skip 2 weeks to accrue the interest to the totalAssets
        esr.gulp();

        skip(esr.INTEREST_SMEAR());
        assertEq(esr.totalAssets(), depositAmount + interestAmount);
    }

    // if updeateInterestAndReturnESRSlotCache is called twice the interest amount at
    // the end of the second call should be the same as the first call
    function test_multipleUpdateInterestAndReturnESRSlotCache() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);
        uint256 interestAmount = 10e18;
        asset.mint(address(esr), interestAmount);
        esr.gulp();
        skip(esr.INTEREST_SMEAR() / 2);
        uint256 interestAccruedHalfWay = esr.interestAccrued();
        esr.updateInterestAndReturnESRSlotCache();
        skip(esr.INTEREST_SMEAR() / 2);
        uint256 interestAccruedAllTheWay = esr.interestAccrued();
        esr.updateInterestAndReturnESRSlotCache();
        assertEq(interestAccruedHalfWay, interestAmount / 2);
        assertEq(interestAccruedAllTheWay, interestAmount / 2);
        assertEq(esr.totalAssets(), depositAmount + interestAmount);
    }

    // test redeem after SMEAR has ended
    function test_redeemAfterSMEAREnd() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);
        uint256 interestAmount = 10e18;
        asset.mint(address(esr), interestAmount);
        esr.gulp();
        skip(esr.INTEREST_SMEAR());
        uint256 shares = esr.balanceOf(user);
        uint256 previewRedeem = esr.previewRedeem(shares);

        vm.startPrank(user);
        esr.redeem(shares, user, user);
        vm.stopPrank();

        uint256 balanceAfter = asset.balanceOf(user);
        assertEq(balanceAfter, previewRedeem);
    }

    // test withdraw after SMEAR has ended
    function test_withdrawAfterSMEAREnd() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);
        uint256 interestAmount = 10e18;
        asset.mint(address(esr), interestAmount);
        esr.gulp();
        skip(esr.INTEREST_SMEAR());
        uint256 shares = esr.balanceOf(user);
        uint256 previewRedeem = esr.previewRedeem(shares);

        vm.startPrank(user);
        esr.withdraw(previewRedeem, user, user);
        vm.stopPrank();

        uint256 balanceAfter = asset.balanceOf(user);
        assertEq(balanceAfter, previewRedeem);
    }

    // test the transfer of vault token
    function test_transferVaultToken() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);

        // transfer the vault token to another address
        uint256 balanceOfUser = esr.balanceOf(user);

        vm.startPrank(user);
        esr.transfer(address(1), balanceOfUser);
        vm.stopPrank();

        uint256 balanceOfAddress1 = esr.balanceOf(address(1));
        assertEq(balanceOfAddress1, balanceOfUser);
    }

    // test the transferFrom and approve of the vault token
    function test_transferFromVaultToken() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);

        // transfer the vault token to another address
        uint256 balanceOfUser = esr.balanceOf(user);

        vm.startPrank(user);
        esr.approve(address(1), balanceOfUser);
        vm.stopPrank();

        vm.startPrank(address(1));
        esr.transferFrom(user, address(1), balanceOfUser);
        vm.stopPrank();

        uint256 balanceOfAddress1 = esr.balanceOf(address(1));
        assertEq(balanceOfAddress1, balanceOfUser);
    }

    // test the result of maxWithdraw when no controller is set
    function test_MaxWithdrawNoControllerSet() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);
        uint256 maxWithdraw = esr.maxWithdraw(user);
        assertEq(maxWithdraw, depositAmount);
    }

    // test the result of maxWithdraw when controller is set
    function test_maxWithdrawControllerSet() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);
        vm.prank(user);
        evc.enableController(address(user), address(statusCheck));
        uint256 maxWithdraw = esr.maxWithdraw(user);
        assertEq(maxWithdraw, 0);
    }

    // test the result of maxRedeem when no controller is set
    function test_maxRedeemNoControllerSet() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);
        uint256 shares = esr.balanceOf(user);
        uint256 maxRedeem = esr.maxRedeem(user);
        assertEq(maxRedeem, shares);
    }

    // test the result of maxRedeem when controller is set
    function test_maxRedeemControllerSet() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);
        vm.prank(user);
        evc.enableController(address(user), address(statusCheck));
        uint256 maxRedeem = esr.maxRedeem(user);
        assertEq(maxRedeem, 0);
    }
}
