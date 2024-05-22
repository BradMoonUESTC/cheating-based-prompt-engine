// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import "./lib/ESRTest.sol";

import "forge-std/Test.sol";

contract ESRFuzzTest is ESRTest {
    function invariant_interestLeftGreaterThanAccruedInterest() public view {
        EulerSavingsRate.ESRSlot memory esrSlot = esr.getESRSlot();
        uint256 accruedInterest = esr.interestAccrued();
        assertGe(esrSlot.interestLeft, accruedInterest);
    }

    // totalAssets should be equal to the balance after SMEAR has passed
    // function invariant_totalAssetsShouldBeEqualToBalanceAfterSMEAR() public {
    //     vm.assume(asset.balanceOf(address(esr)) <= type(uint168).max);
    //     esr.gulp();
    //     skip(esr.INTEREST_SMEAR()); // make sure smear has passed
    //     assertEq(esr.totalAssets(), asset.balanceOf(address(esr)));
    // }

    function testFuzz_interestAccrued_under_uint168(uint256 interestAmount, uint256 depositAmount, uint256 timePassed)
        public
    {
        depositAmount = bound(depositAmount, 0, type(uint112).max);
        // this makes sure that the mint won't cause overflow in token accounting
        interestAmount = bound(interestAmount, 0, type(uint112).max - depositAmount);
        timePassed = bound(timePassed, block.timestamp, type(uint40).max);
        doDeposit(user, depositAmount);
        asset.mint(address(esr), interestAmount);
        esr.gulp();
        vm.warp(timePassed);
        uint256 interestAccrued = esr.interestAccrued();
        assertLe(interestAccrued, type(uint168).max);
    }

    // this tests shows that when you have a very small deposit and a very large interestAmount minted to the contract
    function testFuzz_gulp_under_uint168(uint256 interestAmount, uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 0, type(uint112).max);
        interestAmount = bound(interestAmount, 0, type(uint256).max - depositAmount); // this makes sure that the mint
            // won't cause overflow

        asset.mint(address(esr), interestAmount);
        doDeposit(user, depositAmount);

        esr.gulp();

        EulerSavingsRate.ESRSlot memory esrSlot = esr.updateInterestAndReturnESRSlotCache();

        if (interestAmount <= type(uint168).max) {
            assertEq(esrSlot.interestLeft, interestAmount);
        } else {
            assertEq(esrSlot.interestLeft, type(uint168).max);
        }
    }

    // fuzz test that any deposits added are added to the totalAssetsDeposited
    function testFuzz_deposit(uint256 depositAmount, uint256 depositAmount2) public {
        depositAmount = bound(depositAmount, 0, type(uint112).max);
        depositAmount2 = bound(depositAmount2, 0, type(uint112).max - depositAmount); // prevents overflow
        doDeposit(address(1), depositAmount);
        doDeposit(address(2), depositAmount2);
        assertEq(esr.totalAssets(), depositAmount + depositAmount2);
    }

    // fuzz test that any withdraws are subtracted from the totalAssetsDeposited
    function testFuzz_withdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 0, type(uint112).max);
        withdrawAmount = bound(withdrawAmount, 0, depositAmount);
        doDeposit(address(1), depositAmount);
        vm.startPrank(address(1));
        esr.withdraw(withdrawAmount, address(1), address(1));
        vm.stopPrank();
        assertEq(esr.totalAssets(), depositAmount - withdrawAmount);
    }
}
