// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../EVaultTestBase.t.sol";

contract Governance_InterestRates is EVaultTestBase {
    using TypesLib for uint256;

    address depositor;
    address borrower;

    function setUp() public override {
        super.setUp();

        depositor = makeAddr("depositor");
        borrower = makeAddr("borrower");

        // Setup

        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 1e18);

        eTST.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);

        // Depositor

        startHoax(depositor);

        assetTST.mint(depositor, type(uint256).max);
        assetTST.approve(address(eTST), type(uint256).max);
        eTST.deposit(100e18, depositor);

        // Borrower

        startHoax(borrower);

        assetTST2.mint(borrower, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(5e18, borrower);
    }

    function test_Governance_setInterestRateModel_setAddressZero() public {
        assertEq(eTST.totalAssets(), 100e18);

        skip(1 days);

        uint256 beforePause = eTST.totalAssets();

        // some interest accrued
        assertGt(beforePause, 100e18);

        vm.stopPrank();
        address previousIRM = eTST.interestRateModel();
        eTST.setInterestRateModel(address(0));

        // the previous interest accrued is recorded in the accumulator
        assertEq(beforePause, eTST.totalAssets());

        skip(10 days);

        // no change
        assertEq(beforePause, eTST.totalAssets());

        // set the previous IRM back
        eTST.setInterestRateModel(previousIRM);
        // no change yet
        assertEq(beforePause, eTST.totalAssets());

        skip(1);

        // interest starts accruing again
        assertGt(eTST.totalAssets(), beforePause);
        assertApproxEqRel(eTST.totalAssets(), beforePause, 0.0000000001e18);
    }
}
