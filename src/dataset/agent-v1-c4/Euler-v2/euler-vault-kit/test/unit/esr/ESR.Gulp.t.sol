// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import "./lib/ESRTest.sol";

contract ESRGulpTest is ESRTest {
    function testGulpNoPreviousInterest() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);

        uint256 interestAmount = 10e18;
        // Mint interest directly into the contract
        asset.mint(address(esr), interestAmount);
        esr.gulp();

        EulerSavingsRate.ESRSlot memory esrSlot = esr.getESRSlot();

        assertEq(esr.totalAssets(), depositAmount);
        assertEq(esrSlot.interestLeft, interestAmount);
        assertEq(esrSlot.lastInterestUpdate, block.timestamp);
        assertEq(esrSlot.interestSmearEnd, block.timestamp + esr.INTEREST_SMEAR());
    }

    function testDoubleGulpNoTimePassed() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);

        uint256 interestAmount = 10e18;
        // Mint interest directly into the contract
        asset.mint(address(esr), interestAmount);
        esr.gulp();
        // Mint interest directly into the contract
        asset.mint(address(esr), interestAmount);
        esr.gulp();

        EulerSavingsRate.ESRSlot memory esrSlot = esr.getESRSlot();

        assertEq(esr.totalAssets(), depositAmount);
        assertEq(esrSlot.interestLeft, interestAmount * 2);
        assertEq(esrSlot.lastInterestUpdate, block.timestamp);
        assertEq(esrSlot.interestSmearEnd, block.timestamp + esr.INTEREST_SMEAR());
    }

    function testDoubleGulpHalfOfPreviousDistributed() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);

        uint256 interestAmount = 10e18;
        // Mint interest directly into the contract
        asset.mint(address(esr), interestAmount);
        esr.gulp();
        skip(esr.INTEREST_SMEAR() / 2);
        // Mint interest directly into the contract
        asset.mint(address(esr), interestAmount);
        esr.gulp();

        EulerSavingsRate.ESRSlot memory esrSlot = esr.getESRSlot();

        assertEq(esr.totalAssets(), depositAmount + interestAmount / 2);
        assertEq(esrSlot.interestLeft, interestAmount + interestAmount / 2);
        assertEq(esrSlot.lastInterestUpdate, block.timestamp);
        assertEq(esrSlot.interestSmearEnd, block.timestamp + esr.INTEREST_SMEAR());
    }

    function testDoubleGulpPreviousDistributed() public {
        uint256 depositAmount = 100e18;
        doDeposit(user, depositAmount);

        uint256 interestAmount = 10e18;
        // Mint interest directly into the contract
        asset.mint(address(esr), interestAmount);
        esr.gulp();
        skip(esr.INTEREST_SMEAR());
        // Mint interest directly into the contract
        asset.mint(address(esr), interestAmount);
        esr.gulp();

        EulerSavingsRate.ESRSlot memory esrSlot = esr.getESRSlot();

        assertEq(esr.totalAssets(), depositAmount + interestAmount);
        assertEq(esrSlot.interestLeft, interestAmount);
        assertEq(esrSlot.lastInterestUpdate, block.timestamp);
        assertEq(esrSlot.interestSmearEnd, block.timestamp + esr.INTEREST_SMEAR());
    }
}
