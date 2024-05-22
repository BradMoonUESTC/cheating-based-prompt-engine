// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";

import "../../../../../src/EVault/shared/types/Types.sol";
import "../../../../../src/EVault/shared/Constants.sol";

contract VaultTest_LTV is EVaultTestBase {
    using TypesLib for uint256;

    address depositor;
    address borrower;

    function setUp() public override {
        super.setUp();

        // Setup

        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 1e18);

        depositor = makeAddr("depositor");
        borrower = makeAddr("borrower");
    }

    function test_rampDown() public {
        eTST.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);

        assertEq(eTST.LTVBorrow(address(eTST2)), 0.9e4);

        eTST.setLTV(address(eTST2), 0.4e4, 0.4e4, 1000);

        assertEq(eTST.LTVBorrow(address(eTST2)), 0.4e4);
        assertEq(eTST.LTVLiquidation(address(eTST2)), 0.9e4);

        skip(200);

        assertEq(eTST.LTVBorrow(address(eTST2)), 0.4e4);
        assertEq(eTST.LTVLiquidation(address(eTST2)), 0.8e4);

        skip(300);

        assertEq(eTST.LTVBorrow(address(eTST2)), 0.4e4);
        assertEq(eTST.LTVLiquidation(address(eTST2)), 0.65e4);

        skip(500);

        assertEq(eTST.LTVBorrow(address(eTST2)), 0.4e4);
        assertEq(eTST.LTVLiquidation(address(eTST2)), 0.4e4);
    }

    function test_rampUp() public {
        // ramping up is not allowed
        vm.expectRevert(Errors.E_LTVLiquidation.selector);
        eTST.setLTV(address(eTST2), 0.8e4, 0.8e4, 1000);

        eTST.setLTV(address(eTST2), 0.8e4, 0.8e4, 0);

        // ramping to stay the same is not allowed
        vm.expectRevert(Errors.E_LTVLiquidation.selector);
        eTST.setLTV(address(eTST2), 0.8e4, 0.8e4, 1000);

        eTST.setLTV(address(eTST2), 0.1e4, 0.1e4, 1000);

        skip(250);

        assertEq(eTST.LTVBorrow(address(eTST2)), 0.1e4);
        assertEq(eTST.LTVLiquidation(address(eTST2)), 0.625e4);

        // ramp up on a way down is not allowed
        vm.expectRevert(Errors.E_LTVLiquidation.selector);
        eTST.setLTV(address(eTST2), 0.65e4, 0.65e4, 1000);

        // can jump immediatelly
        eTST.setLTV(address(eTST2), 0.65e4, 0.65e4, 0);

        // ramp down again
        eTST.setLTV(address(eTST2), 0.1e4, 0.1e4, 1000);

        skip(250);

        assertEq(eTST.LTVLiquidation(address(eTST2)), 0.5125e4);

        // can retarget - set a lower LTV with a new ramp
        eTST.setLTV(address(eTST2), 0.5e4, 0.5e4, 100);

        skip(50);

        assertEq(eTST.LTVBorrow(address(eTST2)), 0.5e4);
        assertEq(eTST.LTVLiquidation(address(eTST2)), 0.5062e4);

        skip(50);

        // on new target
        assertEq(eTST.LTVBorrow(address(eTST2)), 0.5e4);
        assertEq(eTST.LTVLiquidation(address(eTST2)), 0.5e4);
    }

    function test_ltvSelfCollateral() public {
        vm.expectRevert(Errors.E_InvalidLTVAsset.selector);
        eTST.setLTV(address(eTST), 0.5e4, 0.5e4, 0);
    }

    function test_ltvRange() public {
        vm.expectRevert(Errors.E_ConfigAmountTooLargeToEncode.selector);
        eTST.setLTV(address(eTST2), 1e4 + 1, 1e4 + 1, 0);
    }

    function test_clearLtv() public {
        eTST.setLTV(address(eTST2), 0.5e4, 0.5e4, 0);

        startHoax(borrower);
        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));
        vm.stopPrank();

        // No borrow, liquidation is a no-op
        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(depositor, borrower, address(eTST2));
        assertEq(maxRepay, 0);
        assertEq(maxYield, 0);

        // setting LTV to 0 doesn't change anything yet
        eTST.setLTV(address(eTST2), 0, 0, 0);

        (maxRepay, maxYield) = eTST.checkLiquidation(depositor, borrower, address(eTST2));
        assertEq(maxRepay, 0);
        assertEq(maxYield, 0);

        // collateral without LTV
        vm.expectRevert(Errors.E_BadCollateral.selector);
        eTST.checkLiquidation(depositor, borrower, address(eTST));

        // same error after clearing LTV
        eTST.clearLTV(address(eTST2));
        vm.expectRevert(Errors.E_BadCollateral.selector);
        eTST.checkLiquidation(depositor, borrower, address(eTST2));
    }

    function test_ltvList() public {
        assertEq(eTST.LTVList().length, 0);

        eTST.setLTV(address(eTST2), 0.8e4, 0.8e4, 0);

        assertEq(eTST.LTVList().length, 1);
        assertEq(eTST.LTVList()[0], address(eTST2));

        eTST.setLTV(address(eTST2), 0.0e4, 0.0e4, 0);

        assertEq(eTST.LTVList().length, 1);
        assertEq(eTST.LTVList()[0], address(eTST2));

        eTST.setLTV(address(eTST2), 0.4e4, 0.4e4, 0);

        assertEq(eTST.LTVList().length, 1);
        assertEq(eTST.LTVList()[0], address(eTST2));
    }

    function test_ltvList_explicitZero() public {
        assertEq(eTST.LTVList().length, 0);

        eTST.setLTV(address(eTST2), 0.0e4, 0.0e4, 0);

        assertEq(eTST.LTVBorrow(address(eTST2)), 0.0e4);
        assertEq(eTST.LTVLiquidation(address(eTST2)), 0.0e4);

        assertEq(eTST.LTVList().length, 1);
        assertEq(eTST.LTVList()[0], address(eTST2));

        eTST.setLTV(address(eTST2), 0.0e4, 0.0e4, 0);

        assertEq(eTST.LTVList().length, 1);
        assertEq(eTST.LTVList()[0], address(eTST2));
    }

    function test_setLTV_borrowLTV() public {
        assertEq(eTST.LTVList().length, 0);

        //borrowLTV == liquidationLTV
        eTST.setLTV(address(eTST2), 0.1e4, 0.1e4, 0);

        assertEq(eTST.LTVBorrow(address(eTST2)), 0.1e4);
        assertEq(eTST.LTVLiquidation(address(eTST2)), 0.1e4);

        //borrowLTV < liquidationLTV
        eTST.setLTV(address(eTST2), 0.06e4, 0.1e4, 0);

        assertEq(eTST.LTVBorrow(address(eTST2)), 0.06e4);
        assertEq(eTST.LTVLiquidation(address(eTST2)), 0.1e4);

        vm.expectRevert(Errors.E_LTVBorrow.selector);
        //borrowLTV > liquidationLTV
        eTST.setLTV(address(eTST2), 0.2e4, 0.1e4, 0);
    }

    function test_borrowLTV() public {
        startHoax(depositor);
        assetTST.mint(depositor, 100e18);
        assetTST.approve(address(eTST), type(uint256).max);
        eTST.deposit(100e18, depositor);

        startHoax(borrower);
        assetTST2.mint(borrower, 100e18);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(100e18, borrower);
        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        startHoax(address(this));
        eTST.setLTV(address(eTST2), 0.2e4, 0.9e4, 0);

        uint256 borrowLTV = eTST.LTVBorrow(address(eTST2));
        assertEq(borrowLTV, 0.2e4);

        uint256 snapshot = vm.snapshot();

        (uint256 collateralValue,) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValue, eTST2.balanceOf(borrower) * borrowLTV / 1e4);

        startHoax(borrower);
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(collateralValue, borrower);

        eTST.borrow(collateralValue - 1, borrower);

        vm.revertTo(snapshot);

        startHoax(address(this));
        eTST.setLTV(address(eTST2), 0.1e4, 0.9e4, 0);

        borrowLTV = eTST.LTVBorrow(address(eTST2));
        assertEq(borrowLTV, 0.1e4);

        (collateralValue,) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValue, eTST2.balanceOf(borrower) * borrowLTV / 1e4);

        startHoax(borrower);
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(collateralValue, borrower);

        eTST.borrow(collateralValue - 1, borrower);

        vm.revertTo(snapshot);

        startHoax(address(this));
        eTST.setLTV(address(eTST2), 0, 0.9e4, 0);

        borrowLTV = eTST.LTVBorrow(address(eTST2));
        assertEq(borrowLTV, 0);

        (collateralValue,) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValue, eTST2.balanceOf(borrower) * borrowLTV / 1e4);

        startHoax(borrower);
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(1, borrower);

        vm.revertTo(snapshot);

        startHoax(address(this));
        eTST.setLTV(address(eTST2), 0.1e4, 0.2e4, 100);

        borrowLTV = eTST.LTVBorrow(address(eTST2));
        assertEq(borrowLTV, 0.1e4);

        (collateralValue,) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValue, eTST2.balanceOf(borrower) * borrowLTV / 1e4);

        startHoax(borrower);
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(collateralValue, borrower);

        skip(50);

        borrowLTV = eTST.LTVBorrow(address(eTST2));
        assertEq(borrowLTV, 0.1e4);

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(collateralValue, borrower);

        eTST.borrow(collateralValue - 1, borrower);
    }

    function test_liqudationLTV() public {
        eTST.setLTV(address(eTST2), 0.3e4, 0.3e4, 0);

        startHoax(depositor);
        assetTST.mint(depositor, 20e18);
        assetTST.approve(address(eTST), type(uint256).max);
        eTST.deposit(20e18, depositor);

        startHoax(borrower);
        assetTST2.mint(borrower, 20e18);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(20e18, borrower);
        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        //check account borrowing collateral value
        uint256 borrowLTV = eTST.LTVBorrow(address(eTST2));
        assertEq(borrowLTV, 3000);

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValue, eTST2.balanceOf(borrower) * borrowLTV / 1e4);

        startHoax(address(this));
        eTST.setLTV(address(eTST2), 0.15e4, 0.15e4, 100);

        borrowLTV = eTST.LTVBorrow(address(eTST2));
        assertEq(borrowLTV, 1500);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValue, eTST2.balanceOf(borrower) * borrowLTV / 1e4);
        assertLe(collateralValue * 1e18 / liabilityValue, 1e18); // HS < 1

        //check account liquidation collateral value
        uint256 liqudationLTV = eTST.LTVLiquidation(address(eTST2));
        assertEq(liqudationLTV, 3000);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertEq(collateralValue, eTST2.balanceOf(borrower) * liqudationLTV / 1e4);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(depositor, borrower, address(eTST2));
        assertEq(maxRepay, 0);
        assertEq(maxYield, 0);

        skip(20);

        liqudationLTV = eTST.LTVLiquidation(address(eTST2));
        assertEq(liqudationLTV, 2700);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertEq(collateralValue, eTST2.balanceOf(borrower) * liqudationLTV / 1e4);

        (maxRepay, maxYield) = eTST.checkLiquidation(depositor, borrower, address(eTST2));
        assertEq(maxRepay, 0);
        assertEq(maxYield, 0);

        skip(40);

        liqudationLTV = eTST.LTVLiquidation(address(eTST2));
        assertEq(liqudationLTV, 2100);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertEq(collateralValue, eTST2.balanceOf(borrower) * liqudationLTV / 1e4);
        assertLe(collateralValue * 1e18 / liabilityValue, 1e18); // HS < 1

        (maxRepay, maxYield) = eTST.checkLiquidation(depositor, borrower, address(eTST2));
        assertNotEq(maxRepay, 0);
        assertNotEq(maxYield, 0);
    }
}
