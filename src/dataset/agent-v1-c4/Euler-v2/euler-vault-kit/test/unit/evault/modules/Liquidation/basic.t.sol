// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {SafeERC20Lib} from "../../../../../src/EVault/shared/lib/SafeERC20Lib.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

import {console} from "forge-std/Test.sol";

import "../../../../../src/EVault/shared/types/Types.sol";
import "../../../../../src/EVault/shared/Constants.sol";

contract LiquidationUnitTest is EVaultTestBase {
    using TypesLib for uint256;

    address depositor;
    address borrower;
    address liquidator;
    address random;

    function setUp() public override {
        super.setUp();

        depositor = makeAddr("depositor");
        borrower = makeAddr("borrower");
        liquidator = makeAddr("liquidator");
        random = makeAddr("random");

        // Setup

        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 1e18);

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
    }

    function test_basicLiquidation_all_collateral() public {
        // in this test scenario, all debt value * discount = all collateral value

        // mimick the behaviour of liquidator depositing some collateral to have an end healthy position
        uint256 assetTST2LiquidatorInitialBalance = 5e18;
        startHoax(borrower);
        assetTST2.transfer(liquidator, assetTST2LiquidatorInitialBalance);
        startHoax(liquidator);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(assetTST2LiquidatorInitialBalance, liquidator);

        startHoax(borrower);

        eTST2.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(5e18, borrower);
        assertEq(assetTST.balanceOf(borrower), 5e18);
        vm.stopPrank();

        startHoax(liquidator);

        (uint256 maxRepay, uint256 yield) = eTST.checkLiquidation(liquidator, borrower, address(eTST2));
        assertEq(maxRepay, 0);
        assertEq(yield, 0);

        oracle.setPrice(address(eTST2), unitOfAccount, 5e17);

        (maxRepay, yield) = eTST.checkLiquidation(liquidator, borrower, address(eTST2));

        uint256 collateralValue = eTST2.balanceOf(borrower) * 5e17 / 1e18;
        uint256 liquiditycollateralValue = collateralValue * uint256(eTST.LTVLiquidation(address(eTST2))) / 1e4;
        uint256 liabilityValue = eTST.debtOf(borrower);
        uint256 discountFactor = liquiditycollateralValue * 1e18 / liabilityValue;
        uint256 expectedMaxRepayValue = collateralValue * discountFactor / 1e18;
        uint256 expectedMaxYieldValue = collateralValue;
        uint256 expectedRepayValue = expectedMaxRepayValue * eTST.debtOf(borrower) / liabilityValue;
        uint256 expectedYield = expectedMaxYieldValue * eTST2.balanceOf(borrower) / collateralValue;

        assertEq(maxRepay, expectedRepayValue);
        assertEq(yield, expectedYield);

        evc.enableCollateral(liquidator, address(eTST2));
        evc.enableController(liquidator, address(eTST));
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);

        assertEq(eTST.debtOf(liquidator), maxRepay);
        assertEq(eTST2.balanceOf(liquidator), yield + assetTST2LiquidatorInitialBalance);
        assertEq(eTST.debtOf(borrower), 0);
        assertEq(eTST2.balanceOf(borrower), 0);
    }

    function test_liquidation_gt_maxRepay() public {
        startHoax(borrower);

        eTST2.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(5e18, borrower);
        assertEq(assetTST.balanceOf(borrower), 5e18);
        vm.stopPrank();

        startHoax(liquidator);

        oracle.setPrice(address(eTST2), unitOfAccount, 5e17);

        (uint256 maxRepay,) = eTST.checkLiquidation(liquidator, borrower, address(eTST2));

        evc.enableCollateral(liquidator, address(eTST2));
        evc.enableController(liquidator, address(eTST));

        vm.expectRevert(Errors.E_ExcessiveRepayAmount.selector);
        eTST.liquidate(borrower, address(eTST2), maxRepay * 2, 0);
    }

    function test_liquidation_minYeild_gt_yield() public {
        startHoax(borrower);

        eTST2.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(5e18, borrower);
        assertEq(assetTST.balanceOf(borrower), 5e18);
        vm.stopPrank();

        startHoax(liquidator);

        oracle.setPrice(address(eTST2), unitOfAccount, 5e17);

        (uint256 maxRepay, uint256 yield) = eTST.checkLiquidation(liquidator, borrower, address(eTST2));

        evc.enableCollateral(liquidator, address(eTST2));
        evc.enableController(liquidator, address(eTST));

        vm.expectRevert(Errors.E_MinYield.selector);
        eTST.liquidate(borrower, address(eTST2), maxRepay, yield * 2);
    }

    function test_basicLiquidation_worthless_collateral() public {
        startHoax(borrower);

        eTST2.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(5e18, borrower);
        assertEq(assetTST.balanceOf(borrower), 5e18);
        vm.stopPrank();

        startHoax(liquidator);

        oracle.setPrice(address(eTST2), unitOfAccount, 0);

        (uint256 maxRepay, uint256 yield) = eTST.checkLiquidation(liquidator, borrower, address(eTST2));
        assertEq(maxRepay, 0);

        evc.enableCollateral(liquidator, address(eTST2));
        evc.enableController(liquidator, address(eTST));
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);

        assertEq(eTST.debtOf(liquidator), maxRepay);
        assertEq(eTST2.balanceOf(liquidator), yield);
        assertEq(eTST.debtOf(borrower), 0);
        assertEq(eTST2.balanceOf(borrower), 0);
    }
}
