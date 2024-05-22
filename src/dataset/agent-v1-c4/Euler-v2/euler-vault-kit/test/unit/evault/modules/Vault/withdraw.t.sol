// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {SafeERC20Lib} from "../../../../../src/EVault/shared/lib/SafeERC20Lib.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IEVault} from "../../../../../src/EVault/IEVault.sol";
import {TestERC20} from "../../../../mocks/TestERC20.sol";
import {IRMTestZero} from "../../../../mocks/IRMTestZero.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";

import "../../../../../src/EVault/shared/types/Types.sol";
import "../../../../../src/EVault/shared/Constants.sol";

import "forge-std/Test.sol";

contract VaultTest_Withdraw is EVaultTestBase {
    using TypesLib for uint256;

    address lender;
    address borrower;

    TestERC20 assetTST3;
    IEVault public eTST3;

    function setUp() public override {
        super.setUp();

        lender = makeAddr("lender");
        borrower = makeAddr("borrower");

        // Setup

        assetTST3 = new TestERC20("Test TST 3", "TST3", 18, false);
        eTST3 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST3), address(oracle), unitOfAccount))
        );

        eTST.setInterestRateModel(address(new IRMTestZero()));
        eTST2.setInterestRateModel(address(new IRMTestZero()));
        eTST3.setInterestRateModel(address(new IRMTestZero()));

        oracle.setPrice(address(eTST), unitOfAccount, 2.2e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 0.4e18);
        oracle.setPrice(address(eTST3), unitOfAccount, 2.2e18);

        eTST.setLTV(address(eTST2), 0.3e4, 0.3e4, 0);

        // Lender

        startHoax(lender);

        assetTST.mint(lender, type(uint256).max);
        assetTST.approve(address(eTST), type(uint256).max);
        eTST.deposit(100e18, lender);

        assetTST3.mint(lender, 200e18);
        assetTST3.approve(address(eTST3), type(uint256).max);
        eTST3.deposit(100e18, lender);

        // Borrower

        startHoax(borrower);

        assetTST2.mint(borrower, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, borrower);

        vm.stopPrank();
    }

    function test_basicMaxWithdraw() public {
        uint256 maxWithdrawAmount = eTST2.maxWithdraw(borrower);
        uint256 expectedBurnedShares = eTST2.previewWithdraw(maxWithdrawAmount);

        uint256 assetBalanceBefore = assetTST2.balanceOf(borrower);
        uint256 eVaultSharesBalanceBefore = eTST2.balanceOf(borrower);

        // Should only be able to withdraw up to maxWithdraw, so these should fail:

        vm.prank(borrower);
        vm.expectRevert(Errors.E_InsufficientCash.selector);
        eTST2.withdraw(maxWithdrawAmount + 1, borrower, borrower);

        startHoax(lender);
        assetTST2.mint(lender, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(100e18, lender);
        vm.stopPrank();

        startHoax(borrower);
        vm.expectRevert(Errors.E_InsufficientBalance.selector);
        eTST2.withdraw(maxWithdrawAmount + 1, borrower, borrower);

        vm.expectRevert(Errors.E_InsufficientBalance.selector);
        eTST2.withdraw(maxWithdrawAmount + 1e18, borrower, borrower);

        // Withdrawing the maximum should pass
        eTST2.withdraw(maxWithdrawAmount, borrower, borrower);

        // Assert asset & eVault share balances change as expected
        uint256 assetBalanceAfter = assetTST2.balanceOf(borrower);
        uint256 eVaultSharesBalanceAfter = eTST2.balanceOf(borrower);

        assertEq(assetBalanceAfter - assetBalanceBefore, maxWithdrawAmount);
        assertEq(eVaultSharesBalanceBefore - eVaultSharesBalanceAfter, expectedBurnedShares);
    }

    function test_maxWithdrawWithController() public {
        startHoax(borrower);

        assertEq(eTST2.maxWithdraw(borrower), 10e18);

        evc.enableController(borrower, address(eTST));
        assertEq(eTST2.maxWithdraw(borrower), 0);

        eTST.disableController();
        assertEq(eTST2.maxWithdraw(borrower), 10e18);
    }

    function test_basicMaxRedeem() public {
        uint256 maxRedeemAmount = eTST2.maxRedeem(borrower);
        uint256 expectedRedeemedAssets = eTST2.previewRedeem(maxRedeemAmount);

        uint256 assetBalanceBefore = assetTST2.balanceOf(borrower);
        uint256 eVaultSharesBalanceBefore = eTST2.balanceOf(borrower);

        // Should only be able to redeem up to maxRedeem, so these should fail:

        vm.prank(borrower);
        vm.expectRevert(Errors.E_InsufficientCash.selector);
        eTST2.redeem(maxRedeemAmount + 1, borrower, borrower);

        startHoax(lender);
        assetTST2.mint(lender, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(100e18, lender);
        vm.stopPrank();

        startHoax(borrower);
        vm.expectRevert(Errors.E_InsufficientBalance.selector);
        eTST2.redeem(maxRedeemAmount + 1, borrower, borrower);

        vm.expectRevert(Errors.E_InsufficientBalance.selector);
        eTST2.redeem(maxRedeemAmount + 1e18, borrower, borrower);

        // Withdrawing the maximum should pass
        eTST2.redeem(maxRedeemAmount, borrower, borrower);

        // Assert asset & eVault share balances change as expected
        uint256 assetBalanceAfter = assetTST2.balanceOf(borrower);
        uint256 eVaultSharesBalanceAfter = eTST2.balanceOf(borrower);

        assertEq(assetBalanceAfter - assetBalanceBefore, expectedRedeemedAssets);
        assertEq(eVaultSharesBalanceBefore - eVaultSharesBalanceAfter, maxRedeemAmount);
    }

    function test_maxRedeemWithController() public {
        startHoax(borrower);

        assertEq(eTST2.maxRedeem(borrower), 10e18);

        evc.enableController(borrower, address(eTST));
        assertEq(eTST2.maxRedeem(borrower), 0);

        eTST.disableController();
        assertEq(eTST2.maxRedeem(borrower), 10e18);
    }

    function test_Withdraw_RevertsWhen_ReceiverIsSubaccount() public {
        // Configure vault as non-EVC compatible: protections on
        eTST.setConfigFlags(eTST.configFlags() & ~CFG_EVC_COMPATIBLE_ASSET);

        startHoax(lender);
        address subacc = address(uint160(lender) ^ 42);

        // lender is not known to EVC yet
        eTST.withdraw(1, subacc, lender);
        assertEq(assetTST.balanceOf(subacc), 1);

        // lender is registered in EVC
        evc.enableCollateral(lender, address(eTST));

        // addresses within sub-accounts range revert
        vm.expectRevert(Errors.E_BadAssetReceiver.selector);
        eTST.withdraw(1, subacc, lender);

        // address outside of sub-accounts range are accepted
        address otherAccount = address(uint160(lender) ^ 256);
        eTST.withdraw(1, otherAccount, lender);
        assertEq(assetTST.balanceOf(otherAccount), 1);

        vm.stopPrank();

        // governance switches the protections off
        eTST.setConfigFlags(eTST.configFlags() | CFG_EVC_COMPATIBLE_ASSET);

        startHoax(lender);
        // withdrawal is allowed again
        eTST.withdraw(1, subacc, lender);
        assertEq(assetTST.balanceOf(subacc), 2);
    }

    function test_Redeem_RevertsWhen_ReceiverIsSubaccount() public {
        // Configure vault as non-EVC compatible: protections on
        eTST.setConfigFlags(eTST.configFlags() & ~CFG_EVC_COMPATIBLE_ASSET);

        startHoax(lender);
        address subacc = address(uint160(lender) ^ 42);

        // lender is not known to EVC yet
        eTST.redeem(1, subacc, lender);
        assertEq(assetTST.balanceOf(subacc), 1);

        // lender is registered in EVC
        evc.enableCollateral(lender, address(eTST));

        // addresses within sub-accounts range revert
        vm.expectRevert(Errors.E_BadAssetReceiver.selector);
        eTST.redeem(1, subacc, lender);

        // address outside of sub-accounts range are accepted
        address otherAccount = address(uint160(lender) ^ 256);
        eTST.redeem(1, otherAccount, lender);
        assertEq(assetTST.balanceOf(otherAccount), 1);

        vm.stopPrank();

        // governance switches the protections off
        eTST.setConfigFlags(eTST.configFlags() | CFG_EVC_COMPATIBLE_ASSET);

        startHoax(lender);
        // redeem is allowed again
        eTST.redeem(1, subacc, lender);
        assertEq(assetTST.balanceOf(subacc), 2);
    }

    //can't withdraw deposit not entered as collateral when account unhealthy
    function test_withdraw_accountUnhealthy() public {
        startHoax(borrower);
        eTST2.deposit(90e18, borrower);
        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 1.09e18, 0.01e18);

        // depositing but not entering collateral
        assetTST3.mint(borrower, 10e18);
        assetTST3.approve(address(eTST3), type(uint256).max);
        eTST3.deposit(1e18, borrower);

        // account unhealthy
        oracle.setPrice(address(eTST), unitOfAccount, 2.5e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 0.96e18, 0.001e18);

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST3.withdraw(1e18, borrower, borrower);
    }

    //max withdraw with borrow - deposit not enabled as collateral
    function test_withdraw_depositNotEnabledAsCollateral() public {
        startHoax(borrower);
        eTST2.deposit(90e18, borrower);
        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST2));
        evc.enableCollateral(lender, address(eTST3));

        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 1.09e18, 0.01e18);

        assetTST3.mint(borrower, 100e18);
        startHoax(borrower);
        assetTST3.approve(address(eTST3), type(uint256).max);
        eTST3.deposit(1e18, borrower);

        assertEq(eTST3.maxRedeem(borrower), 0);

        oracle.setPrice(address(eTST), unitOfAccount, 2.5e18);
        oracle.setPrice(address(eTST3), unitOfAccount, 2.5e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 0.96e18, 0.001e18);

        // TST3 is not enabled as collateral, but it's withdrawal is prevented in unhealthy state

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST3.redeem(1, borrower, borrower);

        assertEq(eTST3.maxRedeem(borrower), 0);
    }
}
