// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {SafeERC20Lib} from "../../../../../src/EVault/shared/lib/SafeERC20Lib.sol";
import {IRMMax} from "../../../../mocks/IRMMax.sol";

import {IEVault, IRMTestDefault} from "../../EVaultTestBase.t.sol";

import "forge-std/console2.sol";

import "../../../../../src/EVault/shared/types/Types.sol";
import "../../../../../src/EVault/shared/Constants.sol";

contract VaultTest_Nested is EVaultTestBase {
    using TypesLib for uint256;

    address depositor;
    address borrower;

    IEVault public eTSTNested;
    IEVault public eTSTDoubleNested;

    function setUp() public override {
        super.setUp();

        eTSTNested = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(eTST), address(oracle), unitOfAccount))
        );
        eTSTNested.setInterestRateModel(address(new IRMTestDefault()));

        depositor = makeAddr("depositor");
        borrower = makeAddr("borrower");

        // Setup

        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 1e18);
        eTST.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);

        eTSTNested.setLTV(address(eTST2), 0.8e4, 0.8e4, 0);

        // Depositor

        startHoax(depositor);

        assetTST.mint(depositor, type(uint256).max);
        assetTST.approve(address(eTST), type(uint256).max);
        eTST.deposit(100e18, depositor);
        vm.stopPrank();
    }

    function test_basicDeposit() public {
        startHoax(depositor);

        eTST.approve(address(eTSTNested), type(uint256).max);
        eTSTNested.deposit(10e18, depositor);

        assertEq(eTST.balanceOf(depositor), 90e18);
        assertEq(eTSTNested.balanceOf(depositor), 10e18);
    }

    function test_basicBorrow() public {
        startHoax(depositor);

        eTST.approve(address(eTSTNested), type(uint256).max);
        eTSTNested.deposit(10e18, depositor);
        vm.stopPrank();

        startHoax(borrower);

        assetTST2.mint(borrower, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTSTNested));

        eTSTNested.borrow(5e18, borrower);
        assertEq(eTST.balanceOf(borrower), 5e18);
    }

    function test_basicBorrowAndRedeem() public {
        startHoax(depositor);

        eTST.approve(address(eTSTNested), type(uint256).max);
        eTSTNested.deposit(10e18, depositor);
        vm.stopPrank();

        startHoax(borrower);

        assetTST2.mint(borrower, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTSTNested));

        eTSTNested.borrow(5e18, borrower);

        eTST.redeem(5e18, borrower, borrower);

        assertEq(eTST.balanceOf(borrower), 0);
        assertEq(assetTST.balanceOf(borrower), 5e18);
    }

    function test_borrowAndOriginalDepositorWithdraws() public {
        startHoax(depositor);

        eTST.approve(address(eTSTNested), type(uint256).max);
        eTSTNested.deposit(10e18, depositor);
        vm.stopPrank();

        startHoax(borrower);

        assetTST2.mint(borrower, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTSTNested));

        eTSTNested.borrow(5e18, borrower);

        vm.stopPrank();

        startHoax(depositor);

        // expect this to revert as there is some amount borrowed
        vm.expectRevert(Errors.E_InsufficientCash.selector);
        eTSTNested.redeem(10e18, depositor, depositor);

        uint256 maxRedeemAmount = eTSTNested.maxRedeem(depositor);
        eTSTNested.redeem(maxRedeemAmount, depositor, depositor);

        assertEq(eTSTNested.balanceOf(depositor), 10e18 - maxRedeemAmount, "eTSTNested Balance");
        assertEq(eTST.balanceOf(depositor), 90e18 + maxRedeemAmount, "eTST Balance");
    }

    function test_doubleNestedDepositAndBorrow() public {
        eTSTDoubleNested = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(eTSTNested), address(oracle), unitOfAccount))
        );
        eTSTDoubleNested.setInterestRateModel(address(new IRMTestDefault()));

        eTSTDoubleNested.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);

        startHoax(depositor);

        eTST.approve(address(eTSTNested), type(uint256).max);
        eTSTNested.deposit(20e18, depositor);

        eTSTNested.approve(address(eTSTDoubleNested), type(uint256).max);
        eTSTDoubleNested.deposit(15e18, depositor);

        assertEq(eTSTNested.balanceOf(depositor), 5e18);
        assertEq(eTSTDoubleNested.balanceOf(depositor), 15e18);

        vm.stopPrank();

        startHoax(borrower);

        assetTST2.mint(borrower, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTSTDoubleNested));

        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        eTSTNested.borrow(5e18, borrower);

        eTSTDoubleNested.borrow(5e18, borrower);
        assertEq(eTSTNested.balanceOf(borrower), 5e18);
    }

    function test_depositWithdraw() public {
        startHoax(depositor);

        eTST.approve(address(eTSTNested), type(uint256).max);
        eTSTNested.deposit(10e18, depositor);

        assertEq(eTSTNested.balanceOf(depositor), 10e18);
        assertEq(eTST.balanceOf(depositor), 90e18); //slightly different as we minted 100e18 to start

        uint256 maxRedeemAmount = eTSTNested.maxRedeem(depositor);
        eTSTNested.redeem(maxRedeemAmount, depositor, depositor);

        assertEq(eTSTNested.balanceOf(depositor), 0);
        assertEq(eTST.balanceOf(depositor), 100e18);
    }

    function test_borrowLiquidateAndRepay() public {
        startHoax(depositor);

        eTST.approve(address(eTSTNested), type(uint256).max);
        eTSTNested.deposit(10e18, depositor);

        vm.stopPrank();

        startHoax(borrower);

        // deposit collateral
        assetTST2.mint(borrower, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(20e18, borrower);

        // try to borrow, fails without controller & collateral enabled
        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        eTSTNested.borrow(5e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTSTNested));

        vm.stopPrank();
        eTSTNested.setLTV(address(eTST2), 0, 0, 0);
        startHoax(borrower);
        // try to borrow, fails because LTV is too low
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTSTNested.borrow(5e18, borrower);

        vm.stopPrank();
        eTSTNested.setLTV(address(eTST2), 0.8e4, 0.8e4, 0);
        startHoax(borrower);

        // successful borrow
        eTSTNested.borrow(5e18, borrower);

        assertEq(eTST.balanceOf(address(eTSTNested)), 5e18);
        assertEq(eTSTNested.debtOf(borrower), 5e18);
        assertEq(assetTST.balanceOf(address(eTST)), 100e18);

        vm.stopPrank();

        startHoax(depositor);

        // withdraw from base
        uint256 maxRedeemAmount = eTST.maxRedeem(depositor);
        eTST.redeem(maxRedeemAmount, depositor, depositor);

        assertEq(eTST.balanceOf(depositor), 0);
        assertEq(eTSTNested.debtOf(borrower), 5e18);
        assertEq(assetTST.balanceOf(address(eTST)), 10e18);

        vm.stopPrank();

        address liquidator = makeAddr("liquidator");

        startHoax(borrower);

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST2.transfer(liquidator, 19e18);

        // transfer collateral to liquidator
        eTST2.transfer(liquidator, 10e18);
        vm.stopPrank();

        oracle.setPrice(address(assetTST), unitOfAccount, 1.65e18);

        startHoax(liquidator);

        (uint256 collateralValue, uint256 liabilityValue) = eTSTNested.accountLiquidity(borrower, false);
        assertApproxEqAbs((collateralValue * 1e18) / liabilityValue, 0.969e18, 1e15);

        evc.enableCollateral(liquidator, address(eTST2));
        evc.enableController(liquidator, address(eTSTNested));

        assetTST2.approve(address(eTST2), type(uint256).max);

        (uint256 maxRepay, uint256 yield) = eTSTNested.checkLiquidation(liquidator, borrower, address(eTST2));

        // liquidate nested liability
        eTSTNested.liquidate(borrower, address(eTST2), maxRepay, 0);

        assertEq(eTST2.balanceOf(liquidator), yield + 10e18);
        assertEq(eTSTNested.debtOf(liquidator), maxRepay);

        vm.stopPrank();
        startHoax(depositor);
        assetTST.transfer(liquidator, 10e18);
        vm.stopPrank();

        startHoax(liquidator);

        assetTST.approve(address(eTST), type(uint256).max);
        eTST.deposit(10e18, liquidator);

        eTST.approve(address(eTSTNested), type(uint256).max);
        uint256 outstandingDebt = eTSTNested.debtOf(liquidator);
        assertEq(outstandingDebt, maxRepay);

        // repay outstanding debt
        eTSTNested.repay(outstandingDebt, liquidator);
        assertEq(eTSTNested.debtOf(liquidator), 0);
    }

    function test_repayWhenNotHealthy() public {
        startHoax(depositor);

        eTST.approve(address(eTSTNested), type(uint256).max);
        eTSTNested.deposit(10e18, depositor);

        vm.stopPrank();

        startHoax(borrower);

        assetTST2.mint(borrower, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTSTNested));

        vm.stopPrank();
        eTSTNested.setLTV(address(eTST2), 0.8e4, 0.8e4, 0);
        startHoax(borrower);
        eTSTNested.borrow(5e18, borrower);

        oracle.setPrice(address(assetTST), unitOfAccount, 1.65e18);

        // account unhealthy
        (uint256 collateralValue, uint256 liabilityValue) = eTSTNested.accountLiquidity(borrower, false);
        assertApproxEqAbs((collateralValue * 1e18) / liabilityValue, 0.969e18, 1e15);

        eTST.approve(address(eTSTNested), type(uint256).max);
        eTSTNested.repay(5e18, borrower);

        // repaid borrow, back to healthy
        (collateralValue, liabilityValue) = eTSTNested.accountLiquidity(borrower, false);
        assertEq(collateralValue, 8e18);
        assertEq(liabilityValue, 0);

        eTSTNested.borrow(3e18, borrower);
        oracle.setPrice(address(assetTST), unitOfAccount, 3e18);

        // account unhealthy again
        (collateralValue, liabilityValue) = eTSTNested.accountLiquidity(borrower, false);
        assertApproxEqAbs((collateralValue * 1e18) / liabilityValue, 0.888e18, 1e15);

        // partial repay fails
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTSTNested.repay(0.1e18, borrower);

        eTSTNested.repay(3e18, borrower);

        // back to healthy
        (collateralValue, liabilityValue) = eTSTNested.accountLiquidity(borrower, false);
        assertEq(collateralValue, 8e18);
        assertEq(liabilityValue, 0);
    }
}
