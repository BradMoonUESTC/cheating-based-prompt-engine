// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase, EthereumVaultConnector, IEVault} from "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import "../../../../../src/EVault/shared/Constants.sol";
import "../../../../../src/EVault/shared/types/Types.sol";
import "../../../../../src/EVault/shared/Events.sol";
import "forge-std/Vm.sol";

contract Governance_PauseOps is EVaultTestBase {
    address notGovernor;
    address borrower;
    address depositor;
    address liquidator1;
    address liquidator2;
    uint256 constant MINT_AMOUNT = 100e18;

    function setUp() public override {
        super.setUp();
        notGovernor = makeAddr("notGovernor");
        borrower = makeAddr("borrower");
        depositor = makeAddr("depositor");
        liquidator1 = makeAddr("liquidator1");
        liquidator2 = makeAddr("liquidator2");
        // ----------------- Setup vaults --------------------
        eTST.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);
        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 1e18);
        // ----------------- Setup depositor -----------------
        vm.startPrank(depositor);
        assetTST.mint(depositor, type(uint256).max);
        assetTST.approve(address(eTST), type(uint256).max);
        eTST.deposit(MINT_AMOUNT, depositor);
        vm.stopPrank();
        vm.label(depositor, "DEPOSITOR");
        // ----------------- Setup borrower -----------------
        vm.startPrank(borrower);
        assetTST2.mint(borrower, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(MINT_AMOUNT, borrower);
        vm.stopPrank();
        vm.label(borrower, "BORROWER");
        // ----------------- this is the pause guardian -----------------
        vm.label(address(this), "PAUSE_GUARDIAN/ADMIN");
    }

    function testFuzz_setHookConfigShouldFailIfNotGovernor(uint32 newDisabledOps) public {
        vm.prank(notGovernor);
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setHookConfig(address(0), newDisabledOps);
    }

    // // disabled ops should fail if governor is not set
    function testFuzz_setHookConfigShouldFailIfGovernorNotSet(uint32 newDisabledOps) public {
        eTST.setGovernorAdmin(address(0));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setHookConfig(address(0), newDisabledOps);
    }

    function testFuzz_onlyGovernorShouldBeAbleToSetGovernor(address newGovernor) public {
        eTST.setGovernorAdmin(newGovernor);
        assertEq(eTST.governorAdmin(), newGovernor);
    }

    function testFuzz_onlyGovernorShouldBeAbleToSetDisabledOps(uint32 newDisabledOps) public {
        newDisabledOps = uint32(bound(newDisabledOps, 0, OP_MAX_VALUE - 1));
        eTST.setHookConfig(address(0), newDisabledOps);
        (, uint32 disabledOps) = eTST.hookConfig();
        assertEq(disabledOps, newDisabledOps);
    }

    function testFuzz_disablingDepositOpsShouldFailAfterDisabled(uint256 amount, address receiver) public {
        amount = bound(amount, 1, MINT_AMOUNT);
        vm.assume(receiver != address(0));

        eTST.setHookConfig(address(0), OP_DEPOSIT);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.deposit(amount, receiver);

        // re-enable
        eTST.setHookConfig(address(0), 0);
        vm.prank(depositor);
        eTST.deposit(amount, receiver);
    }

    function testFuzz_disablingMintOpsShouldFailAfterDisabled(uint256 amount, address receiver) public {
        amount = bound(amount, 1, MINT_AMOUNT);
        vm.assume(receiver != address(0));

        eTST.setHookConfig(address(0), OP_MINT);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.mint(amount, receiver);

        // re-enable
        eTST.setHookConfig(address(0), 0);
        vm.prank(depositor);
        eTST.mint(amount, receiver);
    }

    function testFuzz_disablingWithdrawOpsShouldFailAfterDisabled(uint256 amount, address receiver, address owner)
        public
    {
        amount = bound(amount, 1, MINT_AMOUNT);
        vm.assume(receiver != address(0));

        eTST.setHookConfig(address(0), OP_WITHDRAW);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.withdraw(amount, receiver, owner);

        // re-enable
        eTST.setHookConfig(address(0), 0);
        vm.prank(depositor);
        eTST.withdraw(amount, receiver, depositor); // depositor should be able to withdraw
    }

    function testFuzz_disablingRedeemOpsShouldFailAfterDisabled(uint256 amount, address receiver, address owner)
        public
    {
        eTST.setHookConfig(address(0), OP_REDEEM);
        vm.assume(receiver != address(this));
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.redeem(amount, receiver, owner);

        // re-enable
        eTST.setHookConfig(address(0), 0);
        vm.prank(depositor);
        // type(uint256).max redeems all of the shares
        eTST.redeem(type(uint256).max, depositor, depositor); // depositor should be able to redeem
    }

    function testFuzz_disablingTransferOpsShouldFailAfterDisabled(address to, uint256 amount) public {
        eTST.setHookConfig(address(0), OP_TRANSFER);
        vm.assume(to != address(this) && to != depositor && to != address(0));
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.transfer(to, amount);

        // re-enable
        eTST.setHookConfig(address(0), 0);
        uint256 balance = eTST.balanceOf(depositor);
        vm.prank(depositor);
        eTST.transfer(to, balance);
    }

    function testFuzz_skimmingDisabledOpsShouldFailAfterDisabled(uint256 amount, address receiver) public {
        eTST.setHookConfig(address(0), OP_SKIM);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.skim(amount, receiver);

        // re-enable
        eTST.setHookConfig(address(0), 0);
        vm.prank(depositor);
        // type(uint256).max skims all of the shares
        eTST.skim(type(uint256).max, receiver);
    }

    function testFuzz_borrowingDisabledOpsShouldFailAfterDisabled(uint256 amount) public {
        eTST.setHookConfig(address(0), OP_BORROW);
        evc.enableController(address(this), address(eTST));
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.borrow(amount, address(this));

        // re-enable
        eTST.setHookConfig(address(0), 0);
        vm.startPrank(borrower);
        evc.enableController(borrower, address(eTST));
        evc.enableCollateral(borrower, address(eTST2));
        amount = bound(amount, 1, MINT_AMOUNT / 2);
        eTST.borrow(amount, borrower);
        vm.stopPrank();
    }

    function testFuzz_repayingDisabledOpsShouldFailAfterDisabled(uint256 amount, address receiver) public {
        eTST.setHookConfig(address(0), OP_REPAY);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.repay(amount, receiver);

        // re-enable
        eTST.setHookConfig(address(0), 0);
        vm.prank(borrower);
        eTST.repay(type(uint256).max, receiver);
    }

    function testFuzz_repayingWithSharesDisabledOpsShouldFailAfterDisabled(uint256 amount, address receiver) public {
        eTST.setHookConfig(address(0), OP_REPAY_WITH_SHARES);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.repayWithShares(amount, receiver);

        // re-enable
        eTST.setHookConfig(address(0), 0);
        vm.prank(borrower);
        eTST.repayWithShares(amount, borrower);
    }

    function testFuzz_pullingDebtDisabledOpsShouldFailAfterDisabled(uint256 amount, address from) public {
        eTST.setHookConfig(address(0), OP_PULL_DEBT);
        evc.enableController(address(this), address(eTST));
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.pullDebt(amount, from);

        // re-enable
        eTST.setHookConfig(address(0), 0);
        vm.startPrank(depositor);
        evc.enableController(depositor, address(eTST));
        eTST.pullDebt(type(uint256).max, borrower);
    }

    function testFuzz_convertingFeesDisabledOpsShouldFailAfterDisabled() public {
        eTST.setHookConfig(address(0), OP_CONVERT_FEES);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.convertFees();

        // re-enable
        eTST.setHookConfig(address(0), 0);
        eTST.convertFees();
    }

    function testFuzz_liquidatingDisabledOpsShouldFailAfterDisabled(
        address violator,
        address collateral,
        uint256 repayAssets,
        uint256 minYieldBalance
    ) public {
        eTST.setHookConfig(address(0), OP_LIQUIDATE);
        evc.enableController(address(this), address(eTST));
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.liquidate(violator, collateral, repayAssets, minYieldBalance);

        // re-enable
        eTST.setHookConfig(address(0), 0);
        liquidateSetup(address(this));
    }

    function testFuzz_flashLoanDisabledOpsShouldFailAfterDisabled(uint256 amount, bytes calldata data) public {
        eTST.setHookConfig(address(0), OP_FLASHLOAN);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.flashLoan(amount, data);

        amount = bound(amount, 1, MINT_AMOUNT);
        // re-enable
        eTST.setHookConfig(address(0), 0);
        eTST.flashLoan(amount, abi.encode(amount, address(assetTST)));
    }

    function testFuzz_touchDisabledOpsShouldFailAfterDisabled() public {
        eTST.setHookConfig(address(0), OP_TOUCH);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.touch();

        // re-enable
        eTST.setHookConfig(address(0), 0);
        eTST.touch();
    }

    function testFuzz_socializeDebtDisabledOpsShouldFailAfterDisabled() public {
        eTST.setConfigFlags(CFG_DONT_SOCIALIZE_DEBT);
        // we need this in order to reset the borrower state as its before liquidation
        // the disabled OP only disables socialize debt and not the liquidation itself
        uint256 snapshotBeforeFirstLiquidation = vm.snapshot();
        vm.recordLogs();
        liquidateSetup(liquidator1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            bytes32 topic = entries[i].topics[0];
            assertNotEq(topic, Events.DebtSocialized.selector);
        }

        // re-enable
        vm.revertTo(snapshotBeforeFirstLiquidation);
        eTST.setConfigFlags(0);
        vm.recordLogs();
        liquidateSetup(liquidator2);
        Vm.Log[] memory entriesReEnabled = vm.getRecordedLogs();
        bool foundLog = false;
        for (uint256 i = 0; i < entriesReEnabled.length; i++) {
            bytes32 topic = entriesReEnabled[i].topics[0];
            if (topic == Events.DebtSocialized.selector) {
                foundLog = true;
                break;
            }
        }
        assertTrue(foundLog);
    }

    function testFuzz_validateAssetsReceiverDisabledShouldFailBorrowAfterDisabled(uint256 amount, address receiver)
        public
    {
        amount = bound(amount, 1, MINT_AMOUNT / 2);
        vm.assume(receiver != address(0));

        address subacc = address(uint160(borrower) >> 8 << 8);

        vm.startPrank(borrower);
        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));
        vm.expectRevert(Errors.E_BadAssetReceiver.selector); //! note this is a different error
        eTST.borrow(amount, subacc);
        vm.stopPrank();

        eTST.setConfigFlags(CFG_EVC_COMPATIBLE_ASSET);

        vm.startPrank(borrower);
        eTST.borrow(amount, subacc);
        vm.stopPrank();

        eTST.setConfigFlags(0);
        vm.startPrank(borrower);
        // should be disabled again
        vm.expectRevert(Errors.E_BadAssetReceiver.selector); //! note this is a different error
        eTST.borrow(amount, subacc);
    }

    // helpers
    // handles the on flashloan receiving and transfers back the funds so the fl can pass
    function onFlashLoan(bytes calldata data) external {
        // decode data as amount and address
        (uint256 amount, address eTSTAddr) = abi.decode(data, (uint256, address));
        // return the amount to the
        IERC20(eTSTAddr).transfer(address(eTST), amount);
    }

    function liquidateSetup(address liquidator) internal {
        vm.startPrank(borrower);
        evc.enableController(borrower, address(eTST));
        evc.enableCollateral(borrower, address(eTST2));
        eTST.borrow(8 * MINT_AMOUNT / 10, borrower);
        vm.stopPrank();

        oracle.setPrice(address(assetTST2), unitOfAccount, 0.5e17);

        vm.startPrank(liquidator);
        evc.enableCollateral(liquidator, address(eTST2));
        evc.enableController(liquidator, address(eTST));
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);
        vm.stopPrank();
    }
}
