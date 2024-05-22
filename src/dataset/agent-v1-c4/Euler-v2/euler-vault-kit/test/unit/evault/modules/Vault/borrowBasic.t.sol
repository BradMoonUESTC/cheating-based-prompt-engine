// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {IRMTestZero} from "../../../../mocks/IRMTestZero.sol";
import {IRMTestFixed} from "../../../../mocks/IRMTestFixed.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import "../../../../../src/EVault/shared/types/Types.sol";

contract VaultTest_BorrowBasic is EVaultTestBase {
    using TypesLib for uint256;

    address depositor;
    address borrower;

    function setUp() public override {
        super.setUp();

        depositor = makeAddr("depositor");
        borrower = makeAddr("borrower");

        assetTST.mint(depositor, 100e18);
        assetTST.mint(borrower, 100e18);
        assetTST2.mint(borrower, 100e18);

        startHoax(depositor);
        assetTST.approve(address(eTST), type(uint256).max);
        eTST.deposit(1e18, depositor);

        startHoax(borrower);
        assetTST.approve(address(eTST), type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(50e18, borrower);
        evc.enableCollateral(borrower, address(eTST2));

        oracle.setPrice(address(assetTST), unitOfAccount, 0.01e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 0.05e18);

        skip(31 * 60);

        startHoax(address(this));
        eTST.setLTV(address(eTST2), 0.21e4, 0.21e4, 0);
    }

    function test_borrow_noInterest() public {
        eTST.setInterestRateModel(address(new IRMTestZero()));

        address[] memory collaterals = evc.getCollaterals(borrower);
        assertEq(collaterals.length, 1);
        assertEq(collaterals[0], address(eTST2));

        // Repay when max nothing owed is a no-op
        startHoax(borrower);
        eTST.repay(type(uint256).max, borrower);

        vm.expectRevert(Errors.E_RepayTooMuch.selector);
        eTST.repay(100e18, borrower);

        // Liability vault must be the EVC controller
        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        eTST.borrow(0.4e18, borrower);

        evc.enableController(borrower, address(eTST));

        // Two separate borrows, .4 and .1:
        vm.expectRevert(Errors.E_BadAssetReceiver.selector);
        eTST.borrow(0.5e18, getSubAccount(borrower, 1));

        vm.expectEmit();
        emit Events.Transfer(address(0), borrower, 0.4e18);
        eTST.borrow(0.4e18, borrower);

        eTST.borrow(0.1e18, borrower);

        // Make sure the borrow market is recorded
        collaterals = evc.getCollaterals(borrower);
        assertEq(collaterals.length, 1);
        assertEq(collaterals[0], address(eTST2));

        address[] memory controllers = evc.getControllers(borrower);
        assertEq(controllers.length, 1);
        assertEq(controllers[0], address(eTST));

        assertEq(assetTST.balanceOf(borrower), 100e18 + 0.5e18);
        assertEq(eTST.balanceOf(borrower), 0);
        assertEq(eTST.debtOf(borrower), 0.5e18);

        // Wait 1 day
        skip(1 days);

        // No interest was charged
        assertEq(eTST.debtOf(borrower), 0.5e18);

        vm.expectEmit();
        emit Events.Transfer(borrower, address(0), 0.5e18);
        eTST.repay(0.5e18, borrower);

        assertEq(assetTST.balanceOf(borrower), 100e18);
        assertEq(eTST.balanceOf(borrower), 0);
        assertEq(eTST.debtOf(borrower), 0);

        assertEq(eTST.totalBorrows(), 0);
        assertEq(eTST.totalBorrowsExact(), 0);

        // controller is released
        eTST.disableController();
        controllers = evc.getControllers(borrower);
        assertEq(controllers.length, 0);
    }

    function test_borrow_verySmallInterest() public {
        startHoax(borrower);
        evc.enableController(borrower, address(eTST));

        assertEq(eTST.interestAccumulator(), 1e27);

        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        assertEq(eTST.interestAccumulator(), 1e27);

        // Mint some extra so we can pay interest
        assetTST.mint(borrower, 0.1e18);
        skip(1);
        assertEq(eTST.interestAccumulator(), 1.00000000317097919837645865e27);

        startHoax(borrower);
        eTST.borrow(0.5e18, borrower);
        assertEq(eTST.debtOf(borrower), 0.5e18);

        skip(1);
        assertEq(eTST.interestAccumulator(), 1.000000006341958406808026376e27);

        // 1 block later, notice amount owed is rounded up:
        assertEq(eTST.debtOf(borrower), 0.5000000015854896e18);
        assertApproxEqAbs(
            eTST.debtOfExact(borrower), debtExact(0.500000001585489599188229324e27), 0.00000000000000001e18
        );

        // Use max uint to actually pay off full amount:
        eTST.repay(type(uint256).max, borrower);

        assertEq(eTST.debtOf(borrower), 0);
        assertEq(eTST.debtOfExact(borrower), 0);

        assertEq(eTST.totalBorrows(), 0);
        assertEq(eTST.totalBorrowsExact(), 0);

        eTST.disableController();

        assertEq(evc.getControllers(borrower).length, 0);
    }

    function test_fractionalDebtAmount() public {
        startHoax(borrower);
        evc.enableController(borrower, address(eTST));

        assertEq(eTST.interestAccumulator(), 1e27);

        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        assertEq(eTST.interestAccumulator(), 1e27);

        // Mint some extra so we can pay interest
        assetTST.mint(borrower, 0.1e18);
        skip(1);
        assertEq(eTST.interestAccumulator(), 1.00000000317097919837645865e27);

        startHoax(borrower);
        eTST.borrow(0.5e18, borrower);
        assertEq(eTST.debtOf(borrower), 0.5e18);

        skip(1);
        assertEq(eTST.interestAccumulator(), 1.000000006341958406808026376e27);

        // Turn off interest, but 1 block later so amount owed is rounded up:
        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestZero()));

        assertEq(eTST.debtOf(borrower), 0.5000000015854896e18);
        assertApproxEqAbs(
            eTST.debtOfExact(borrower), debtExact(0.500000001585489599188229324e27), 0.00000000000000001e18
        );

        startHoax(borrower);
        eTST.repay(0.500000001585489599e18, borrower);

        assertEq(eTST.debtOf(borrower), 1);
        assertEq(eTST.debtOfExact(borrower), 2 ** 31);

        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestFixed()));
        skip(1);
        eTST.setInterestRateModel(address(new IRMTestZero()));

        assertEq(eTST.debtOf(borrower), 2);
        assertApproxEqAbs(eTST.debtOfExact(borrower), debtExact(1.000000003e9), 0.00000000000000001e18);

        startHoax(borrower);
        eTST.repay(2, borrower);

        assertEq(eTST.debtOfExact(borrower), 0);

        eTST.disableController();
        assertEq(evc.getControllers(borrower).length, 0);
    }

    function test_amountsAtLimit() public {
        eTST.setInterestRateModel(address(new IRMTestZero()));

        // Try to borrow more tokens than exist in the pool:
        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        vm.expectRevert(Errors.E_InsufficientCash.selector);
        eTST.borrow(100000e18, borrower);

        // Max uint specifies all the tokens in the pool, which is 1 TST:
        assertEq(assetTST.balanceOf(address(eTST)), 1e18);
        assertEq(assetTST.balanceOf(borrower), 100e18);
        assertEq(eTST.debtOf(borrower), 0);

        eTST.borrow(type(uint256).max, borrower);

        assertEq(assetTST.balanceOf(address(eTST)), 0);
        assertEq(assetTST.balanceOf(borrower), 100e18 + 1e18);
        assertEq(eTST.debtOf(borrower), 1e18);
    }

    function test_maxOwedAndAssetsConversions() public pure {
        assertEq(MAX_SANE_DEBT_AMOUNT.toOwed().toAssetsUp().toUint(), MAX_SANE_AMOUNT);
        assertEq(MAX_SANE_AMOUNT.toAssets().toOwed().toUint(), MAX_SANE_DEBT_AMOUNT);
    }

    function debtExact(uint256 value) internal pure returns (uint256) {
        return value * (2 ** 31) / (10 ** 9);
    }
}
