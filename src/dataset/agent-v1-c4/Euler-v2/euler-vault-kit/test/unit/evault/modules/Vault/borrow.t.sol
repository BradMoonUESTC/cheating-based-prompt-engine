// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {SafeERC20Lib} from "../../../../../src/EVault/shared/lib/SafeERC20Lib.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IRMMax} from "../../../../mocks/IRMMax.sol";
import {IRMTestFixed} from "../../../../mocks/IRMTestFixed.sol";
import {IRMFailed} from "../../../../mocks/IRMFailed.sol";
import {IRMOverBound} from "../../../../mocks/IRMOverBound.sol";
import {Events as EVCEvents} from "ethereum-vault-connector/Events.sol";
import "forge-std/Test.sol";

import "../../../../../src/EVault/shared/types/Types.sol";
import "../../../../../src/EVault/shared/Constants.sol";

contract VaultTest_Borrow is EVaultTestBase {
    using TypesLib for uint256;

    address depositor;
    address borrower;
    address borrower2;

    function setUp() public override {
        super.setUp();

        depositor = makeAddr("depositor");
        borrower = makeAddr("borrower");
        borrower2 = makeAddr("borrower_2");

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

        vm.stopPrank();
    }

    function test_basicBorrow() public {
        startHoax(borrower);

        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        eTST.borrow(5e18, borrower);

        evc.enableController(borrower, address(eTST));

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(5e18, borrower);

        // still no borrow hence possible to disable controller
        assertEq(evc.isControllerEnabled(borrower, address(eTST)), true);
        eTST.disableController();
        assertEq(evc.isControllerEnabled(borrower, address(eTST)), false);
        evc.enableController(borrower, address(eTST));
        assertEq(evc.isControllerEnabled(borrower, address(eTST)), true);

        evc.enableCollateral(borrower, address(eTST2));

        eTST.borrow(5e18, borrower);
        assertEq(assetTST.balanceOf(borrower), 5e18);
        assertEq(eTST.debtOf(borrower), 5e18);
        assertEq(eTST.debtOfExact(borrower), 5e18 << INTERNAL_DEBT_PRECISION_SHIFT);

        assertEq(eTST.totalBorrows(), 5e18);
        assertEq(eTST.totalBorrowsExact(), 5e18 << INTERNAL_DEBT_PRECISION_SHIFT);

        // no longer possible to disable controller
        vm.expectRevert(Errors.E_OutstandingDebt.selector);
        eTST.disableController();

        // Should be able to borrow up to 9, so this should fail:

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(4.0001e18, borrower);

        // Disable collateral should fail

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        evc.disableCollateral(borrower, address(eTST2));

        // Repay

        assetTST.approve(address(eTST), type(uint256).max);
        eTST.repay(type(uint256).max, borrower);

        evc.disableCollateral(borrower, address(eTST2));
        assertEq(evc.getCollaterals(borrower).length, 0);

        eTST.disableController();
        assertEq(evc.getControllers(borrower).length, 0);
    }

    function test_basicBorrowWithInterest() public {
        startHoax(borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(5e18, borrower);

        skip(1 days);

        uint256 currDebt = eTST.debtOf(borrower);
        assertApproxEqAbs(currDebt, 5.0001e18, 0.0001e18);

        assertEq(eTST.debtOfExact(borrower) >> INTERNAL_DEBT_PRECISION_SHIFT, currDebt - 1); // currDebt was rounded up
        assertEq(eTST.debtOfExact(borrower), eTST.totalBorrowsExact());

        // Repay too much

        assetTST.mint(borrower, 100e18);
        assetTST.approve(address(eTST), type(uint256).max);

        vm.expectRevert(Errors.E_RepayTooMuch.selector);
        eTST.repay(currDebt + 1, borrower);

        // Repay right amount

        eTST.repay(currDebt, borrower);

        assertEq(eTST.debtOf(borrower), 0);
        assertEq(eTST.debtOfExact(borrower), 0);

        assertEq(eTST.totalBorrows(), 0);
        assertEq(eTST.totalBorrowsExact(), 0);
    }

    function test_repayWithSharesWithExtra() public {
        startHoax(borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        assetTST.mint(borrower, 100e18);
        assetTST.approve(address(eTST), type(uint256).max);

        eTST.deposit(3e18, borrower);
        eTST.borrow(2e18, borrower);

        assertEq(eTST.balanceOf(borrower), 3e18);
        assertEq(eTST.debtOf(borrower), 2e18);

        eTST.repayWithShares(type(uint256).max, borrower);

        assertEq(eTST.balanceOf(borrower), 1e18);
        assertEq(eTST.debtOf(borrower), 0);
    }

    function test_repayWithPermit2() public {
        startHoax(borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(5e18, borrower);
        assertEq(assetTST.balanceOf(borrower), 5e18);

        // deposit won't succeed without any approval
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Lib.E_TransferFromFailed.selector,
                abi.encodeWithSignature("Error(string)", "ERC20: transfer amount exceeds allowance"),
                abi.encodeWithSelector(IAllowanceTransfer.AllowanceExpired.selector, 0)
            )
        );
        eTST.repay(type(uint256).max, borrower);

        // approve permit2 contract to spend the tokens
        assetTST.approve(permit2, type(uint160).max);

        // approve the vault to spend the tokens via permit2
        IAllowanceTransfer(permit2).approve(address(assetTST), address(eTST), type(uint160).max, type(uint48).max);

        // repay succeeds now
        eTST.repay(type(uint256).max, borrower);

        assertEq(eTST.debtOf(borrower), 0);
    }

    function test_pullDebt_when_from_equal_account() public {
        startHoax(borrower);
        uint256 amountToBorrow = 5e18;

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(amountToBorrow, borrower);
        assertEq(assetTST.balanceOf(borrower), amountToBorrow);

        vm.expectRevert(Errors.E_SelfTransfer.selector);
        eTST.pullDebt(amountToBorrow, borrower);
    }

    function test_pullDebt_zero_amount() public {
        startHoax(borrower);
        uint256 amountToBorrow = 5e18;

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(amountToBorrow, borrower);
        assertEq(assetTST.balanceOf(borrower), amountToBorrow);
        vm.stopPrank();

        startHoax(borrower2);

        evc.enableCollateral(borrower2, address(eTST2));
        evc.enableController(borrower2, address(eTST));

        eTST.pullDebt(0, borrower);
        vm.stopPrank();

        assertEq(eTST.debtOf(borrower), amountToBorrow);
        assertEq(eTST.debtOf(borrower2), 0);
    }

    function test_pullDebt_full_amount() public {
        startHoax(borrower);
        uint256 amountToBorrow = 5e18;

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(amountToBorrow, borrower);
        assertEq(assetTST.balanceOf(borrower), amountToBorrow);

        // transfering some minted asset to borrower2
        assetTST2.transfer(borrower2, 10e18);
        vm.stopPrank();

        startHoax(borrower2);

        // deposit into eTST2 to cover the liability from pullDebt
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, borrower2);

        evc.enableCollateral(borrower2, address(eTST2));
        evc.enableController(borrower2, address(eTST));

        eTST.pullDebt(type(uint256).max, borrower);
        vm.stopPrank();

        assertEq(assetTST.balanceOf(borrower), amountToBorrow);
        assertEq(assetTST.balanceOf(borrower2), 0);
        assertEq(eTST.debtOf(borrower), 0);
        assertEq(eTST.debtOf(borrower2), amountToBorrow);
    }

    function test_pullDebt_amount_gt_debt() public {
        startHoax(borrower);
        uint256 amountToBorrow = 5e18;

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(amountToBorrow, borrower);
        assertEq(assetTST.balanceOf(borrower), amountToBorrow);
        assertEq(eTST.debtOf(borrower), amountToBorrow);
        vm.stopPrank();

        startHoax(borrower2);

        evc.enableCollateral(borrower2, address(eTST2));
        evc.enableController(borrower2, address(eTST));

        vm.expectRevert(Errors.E_InsufficientDebt.selector);
        eTST.pullDebt(amountToBorrow + 1, borrower);
        vm.stopPrank();
    }

    function test_ControllerRequiredOps(address controller, uint112 amount, address account) public {
        vm.assume(controller.code.length == 0 && uint160(controller) > 256 && controller != console2.CONSOLE_ADDRESS);
        vm.assume(account != address(0) && account != controller && account != address(evc));
        vm.assume(amount > 0);

        vm.etch(controller, address(eTST).code);
        IEVault(controller).initialize(address(this));

        vm.startPrank(account);

        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        IEVault(controller).borrow(amount, account);

        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        IEVault(controller).pullDebt(amount, account);

        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        IEVault(controller).liquidate(account, account, amount, amount);

        evc.enableController(account, controller);
    }

    function test_Borrow_RevertsWhen_ReceiverIsSubaccount() public {
        // Configure vault as non-EVC compatible: protections on
        eTST.setConfigFlags(eTST.configFlags() & ~CFG_EVC_COMPATIBLE_ASSET);

        startHoax(borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        address subaccBase = address(uint160(borrower) >> 8 << 8);

        // addresses within sub-accounts range revert
        for (uint160 i; i < 256; i++) {
            address subacc = address(uint160(subaccBase) | i);
            if (subacc != borrower) vm.expectRevert(Errors.E_BadAssetReceiver.selector);
            eTST.borrow(1, subacc);
        }
        assertEq(assetTST.balanceOf(borrower), 1);

        // address outside of sub-accounts range are accepted
        address otherAccount = address(uint160(subaccBase) - 1);
        eTST.borrow(1, otherAccount);
        assertEq(assetTST.balanceOf(otherAccount), 1);

        otherAccount = address(uint160(subaccBase) + 256);
        eTST.borrow(1, otherAccount);
        assertEq(assetTST.balanceOf(otherAccount), 1);

        vm.stopPrank();

        // governance switches the protection off
        eTST.setConfigFlags(eTST.configFlags() | CFG_EVC_COMPATIBLE_ASSET);

        startHoax(borrower);

        // borrow is allowed again
        {
            address subacc = address(uint160(borrower) ^ 42);
            assertEq(assetTST.balanceOf(subacc), 0);
            eTST.borrow(1, subacc);
            assertEq(assetTST.balanceOf(subacc), 1);
        }
    }

    function test_rpowOverflow() public {
        eTST.setInterestRateModel(address(new IRMMax()));

        startHoax(borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(1, borrower);

        uint256 accum1 = eTST.interestAccumulator();

        // Skip forward to observe accumulator advancing
        skip(365 * 2 days);
        eTST.touch();
        uint256 accum2 = eTST.interestAccumulator();
        assertTrue(accum2 > accum1);

        // Observe accumulator increasing, without writing it to storage:
        skip(365 * 3 days);
        uint256 accum3 = eTST.interestAccumulator();
        assertTrue(accum3 > accum2);

        // Skip forward more, so that rpow() will overflow
        skip(365 * 3 days);
        uint256 accum4 = eTST.interestAccumulator();
        assertTrue(accum4 == accum2); // Accumulator goes backwards

        // Withdrawing assets is still possible in this state
        startHoax(depositor);
        uint256 prevBal = assetTST.balanceOf(depositor);
        eTST.withdraw(90e18, depositor, depositor);
        assertEq(assetTST.balanceOf(depositor), prevBal + 90e18);
    }

    function test_accumOverflow() public {
        eTST.setInterestRateModel(address(new IRMMax()));

        startHoax(borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(1, borrower);

        uint256 accum1 = eTST.interestAccumulator();

        // Wait 5 years, touching pool each time so that rpow() will not overflow
        for (uint256 i; i < 5; i++) {
            skip(365 * 1 days);
            eTST.touch();
        }

        uint256 accum2 = eTST.interestAccumulator();
        assertTrue(accum2 > accum1);

        // After the 6th year, the accumulator would overflow so it stops growing
        skip(365 * 1 days);
        eTST.touch();
        assertTrue(eTST.interestAccumulator() == accum2);

        // Withdrawing assets is still possible in this state
        startHoax(depositor);
        uint256 prevBal = assetTST.balanceOf(depositor);
        eTST.withdraw(90e18, depositor, depositor);
        assertEq(assetTST.balanceOf(depositor), prevBal + 90e18);
    }

    uint256 tempInterestRate;

    function myCallback() external {
        startHoax(borrower);
        eTST.borrow(1e18, borrower);

        // This interest rate is invoked by immediately calling computeInterestRateView() on the IRM,
        // as opposed to using the stored value.
        tempInterestRate = eTST.interestRate();
    }

    function test_interestRateViewMidBatch() public {
        startHoax(borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        uint256 origInterestRate = eTST.interestRate();
        evc.call(address(this), borrower, 0, abi.encodeWithSelector(VaultTest_Borrow.myCallback.selector));

        assertTrue(tempInterestRate > origInterestRate);
        assertEq(tempInterestRate, eTST.interestRate()); // Value computed at end of batch is identical
    }

    function test_totalSharesOverflow() external {
        eTST.setInterestRateModel(address(new IRMMax()));

        startHoax(depositor);

        eTST.deposit(MAX_SANE_AMOUNT - eTST.cash() - 1e18, depositor);

        uint256 initialSupply = MAX_SANE_AMOUNT - 1e18;
        // total shares is at the limit
        assertEq(eTST.totalSupply(), initialSupply);
        assertEq(eTST.totalAssets(), initialSupply);

        startHoax(borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(5e18, borrower);

        assertEq(eTST.totalSupply(), initialSupply);
        assertEq(eTST.totalAssets(), initialSupply);
        assertEq(eTST.totalBorrows(), 5e18);
        assertEq(eTST.accumulatedFees(), 0);

        skip(20 days);

        // borrows increased
        assertApproxEqAbs(eTST.totalBorrows(), 8.27e18, 0.01e18);
        // and supply with fees
        uint256 newSupply = eTST.totalSupply();
        uint256 fees = eTST.accumulatedFees();
        assertGt(newSupply, initialSupply);
        assertGt(fees, 0);

        uint256 snapshot = vm.snapshot();

        skip(30 days);

        // borrows increased again
        assertApproxEqAbs(eTST.totalBorrows(), 17.64e18, 0.01e18);
        // but supply with fees now overflows, so it snaps back to initial supply
        assertEq(eTST.totalSupply(), initialSupply);
        assertEq(eTST.accumulatedFees(), 0);

        // Let's try it again, but we'll lock the fees in midway

        vm.revertTo(snapshot);

        // update storage
        eTST.touch();
        assertApproxEqAbs(eTST.totalBorrows(), 8.27e18, 0.01e18);
        assertEq(eTST.totalSupply(), newSupply);
        assertEq(eTST.accumulatedFees(), fees);

        skip(30 days);

        assertApproxEqAbs(eTST.totalBorrows(), 17.64e18, 0.01e18);
        // fees stop accruing, but are at the locked in level
        assertEq(eTST.totalSupply(), newSupply);
        assertEq(eTST.accumulatedFees(), fees);
    }

    function test_totalBorrowsOverflow() external {
        eTST.setInterestRateModel(address(new IRMMax()));

        startHoax(depositor);

        eTST.deposit(MAX_SANE_AMOUNT - eTST.cash(), depositor);

        // stock up on collateral
        startHoax(address(this));
        oracle.setPrice(address(eTST2), unitOfAccount, 2e18);

        startHoax(borrower);
        eTST2.deposit(MAX_SANE_AMOUNT - eTST2.cash(), borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(MAX_SANE_AMOUNT / 2, borrower);

        assertEq(eTST.totalBorrows(), MAX_SANE_AMOUNT / 2);

        skip(25 days);

        // total borrows increase as well as user debt
        assertGt(eTST.totalBorrows(), MAX_SANE_AMOUNT / 2);
        assertGt(eTST.debtOf(borrower), MAX_SANE_AMOUNT / 2);

        skip(25 days);

        // total borrows overflow and snap back to stored values
        assertEq(eTST.totalBorrows(), MAX_SANE_AMOUNT / 2);
        assertEq(eTST.debtOf(borrower), MAX_SANE_AMOUNT / 2);

        // withdrawals are possible
        startHoax(depositor);
        uint256 balanceBefore = assetTST.balanceOf(depositor);
        eTST.withdraw(1e18, depositor, depositor);
        assertEq(assetTST.balanceOf(depositor), balanceBefore + 1e18);

        // user can borrow more for free
        startHoax(borrower);

        eTST.borrow(10e18, borrower);

        skip(1 days);

        assertEq(eTST.totalBorrows(), MAX_SANE_AMOUNT / 2 + 10e18);
        assertEq(eTST.debtOf(borrower), MAX_SANE_AMOUNT / 2 + 10e18);

        // if repaid not enough to make the total borrows fit, no interest is charged
        assetTST.approve(address(eTST), type(uint256).max);
        eTST.repay(10e18, borrower);

        assertEq(eTST.totalBorrows(), MAX_SANE_AMOUNT / 2);
        assertEq(eTST.debtOf(borrower), MAX_SANE_AMOUNT / 2);

        // if repay is large enough, all pending interest will be charged on the remainder

        eTST.repay(MAX_SANE_AMOUNT / 2 - 100, borrower);

        assertEq(eTST.totalBorrows(), 362);
        assertEq(eTST.debtOf(borrower), 362);
    }

    function test_borrowLogs(
        uint256 borrow1,
        uint256 borrow2,
        uint256 repay1,
        uint256 repay2,
        uint256 skip1,
        uint256 skip2,
        uint256 skip3,
        uint256 skip4
    ) public {
        borrow1 = bound(borrow1, 1e18, 2.5e18);
        borrow2 = bound(borrow2, 1e18, 2.5e18);
        repay1 = bound(repay1, 0.1e18, 1.5e18);
        repay2 = bound(repay2, 1, 0.00001e18);

        skip1 = bound(skip1, 1, 7 days);
        skip2 = bound(skip2, 1, 7 days);
        skip3 = bound(skip3, 7 days, 14 days);
        skip4 = bound(skip4, 1, 7 days);

        eTST.setInterestRateModel(address(new IRMTestFixed()));
        address dTST = eTST.dToken();

        startHoax(borrower);

        evc.enableController(borrower, address(eTST));
        evc.enableCollateral(borrower, address(eTST2));
        assetTST.approve(address(eTST), type(uint256).max);
        assetTST.mint(borrower, 1000e18);

        // First borrow

        assertEq(eTST.debtOf(borrower), 0);

        vm.expectEmit();
        emit Events.Borrow(borrower, borrow1);
        vm.expectEmit(dTST);
        emit Events.Transfer(address(0), borrower, borrow1);

        eTST.borrow(borrow1, borrower);
        uint256 prevDebt = eTST.debtOf(borrower);
        assertEq(prevDebt, borrow1);

        // Skip time ahead, borrow more

        skip(skip1);
        uint256 interest1 = eTST.debtOf(borrower) - prevDebt;

        vm.expectEmit();
        emit Events.InterestAccrued(borrower, interest1);
        vm.expectEmit();
        emit Events.Borrow(borrower, borrow2);
        vm.expectEmit(dTST);
        emit Events.Transfer(address(0), borrower, borrow2 + interest1);

        eTST.borrow(borrow2, borrower);
        prevDebt = eTST.debtOf(borrower);

        // Skip again, repay some

        skip(skip2);
        uint256 interest2 = eTST.debtOf(borrower) - prevDebt;
        assertTrue(repay1 > interest2); // Interest should be small

        vm.expectEmit();
        emit Events.InterestAccrued(borrower, interest2);
        vm.expectEmit();
        emit Events.Repay(borrower, repay1);
        vm.expectEmit(dTST);
        emit Events.Transfer(borrower, address(0), repay1 - interest2);

        eTST.repay(repay1, borrower);
        prevDebt = eTST.debtOf(borrower);

        // Skip forward, repay tiny (so interest exceeds repay amount)

        skip(skip3);
        uint256 interest3 = eTST.debtOf(borrower) - prevDebt;
        assertTrue(interest3 > repay2); // Interest should be small

        vm.expectEmit();
        emit Events.InterestAccrued(borrower, interest3);
        vm.expectEmit();
        emit Events.Repay(borrower, repay2);
        vm.expectEmit(dTST);
        emit Events.Transfer(address(0), borrower, interest3 - repay2); // Actually increases debt

        eTST.repay(repay2, borrower);
        prevDebt = eTST.debtOf(borrower);

        // Skip again, repay everything

        skip(skip4);
        uint256 interest4 = eTST.debtOf(borrower) - prevDebt;

        vm.expectEmit();
        emit Events.InterestAccrued(borrower, interest4);
        vm.expectEmit();
        emit Events.Repay(borrower, prevDebt + interest4);
        vm.expectEmit(dTST);
        emit Events.Transfer(borrower, address(0), prevDebt); // Interest is netted out, repay amount appears less

        eTST.repay(type(uint256).max, borrower);

        assertEq(eTST.debtOf(borrower), 0);
    }

    function test_borrowLogsTransferDebt() external {
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        startHoax(borrower);

        evc.enableController(borrower, address(eTST));
        evc.enableCollateral(borrower, address(eTST2));
        assetTST.approve(address(eTST), type(uint256).max);
        assetTST.mint(borrower, 1000e18);

        eTST.borrow(1, borrower);

        assetTST2.transfer(borrower2, type(uint256).max / 2);

        startHoax(borrower2);

        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, borrower2);

        evc.enableController(borrower2, address(eTST));
        evc.enableCollateral(borrower2, address(eTST2));
        assetTST.approve(address(eTST), type(uint256).max);
        assetTST.mint(borrower2, 1000e18);

        eTST.borrow(1, borrower2);

        skip(10 days);

        // a little interest accrued (0.3%)
        assertEq(owedTo1e5(eTST.debtOfExact(borrower)), 1.00274e5);
        assertEq(owedTo1e5(eTST.debtOfExact(borrower2)), 1.00274e5);

        // record interest in storage
        eTST.borrow(1, borrower2);

        skip(10 days);

        // more accrued. Small debt fractions are in storage of both accounts and will be accrued currently
        assertEq(owedTo1e5(eTST.debtOfExact(borrower2)), 2.00823e5);

        // now borrower2 in LogBorrow would receiveamount = 2, prevOwed = 3, owed = 4.
        // Amount is adjusted to 1 and interest accrued is 0, so no event is emitted
        vm.recordLogs();
        vm.expectEmit();
        emit Events.Borrow(borrower2, 1);
        eTST.pullDebt(2, borrower);

        assertEq(vm.getRecordedLogs().length, 11); // InterestAccrued would be the 12th event
    }

    function test_noIRM() public {
        uint256 amount = 1e18;

        startHoax(address(this));
        eTST.setInterestRateModel(address(0));

        assertEq(eTST.interestRateModel(), address(0));

        uint256 ir = eTST.interestRate();
        assertEq(ir, 0);

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        evc.enableCollateral(borrower, address(eTST2));

        eTST.borrow(amount, borrower);

        assertEq(eTST.debtOf(borrower), amount);

        skip(100 days);

        assertEq(eTST.debtOf(borrower), amount);
    }

    function test_failIRM() public {
        uint256 amount = 1e18;

        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMFailed()));

        uint256 ir = eTST.interestRate();
        assertEq(ir, 0);

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        evc.enableCollateral(borrower, address(eTST2));

        eTST.borrow(amount, borrower);

        assertEq(eTST.debtOf(borrower), amount);

        skip(100 days);

        assertEq(eTST.debtOf(borrower), amount);
    }

    function test_outOfBoundIRM() public {
        uint256 amount = 1e18;

        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMOverBound()));

        uint256 ir = eTST.interestRate();
        assertEq(ir, MAX_ALLOWED_INTEREST_RATE);

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        evc.enableCollateral(borrower, address(eTST2));

        eTST.borrow(amount, borrower);

        assertEq(eTST.debtOf(borrower), amount);

        skip(100 days);

        assertGt(eTST.debtOf(borrower), amount);
    }

    function test_pullDebt_noDust() public {
        uint256 amountToBorrow = 5e18;

        startHoax(borrower);
        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));
        eTST.borrow(amountToBorrow, borrower);

        assertEq(assetTST.balanceOf(borrower), amountToBorrow);

        assetTST2.transfer(borrower2, 10e18);

        startHoax(borrower2);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, borrower2);
        evc.enableCollateral(borrower2, address(eTST2));
        evc.enableController(borrower2, address(eTST));

        skip(10 days);

        uint256 borrowed = eTST.debtOf(borrower);

        // try to pull a little bit more than owed
        vm.expectRevert(Errors.E_InsufficientDebt.selector);
        eTST.pullDebt(borrowed + 1, borrower);

        //try to pull a little bit less than owed
        eTST.pullDebt(borrowed - 1, borrower);

        assertEq(assetTST.balanceOf(borrower), amountToBorrow);
        assertEq(assetTST.balanceOf(borrower2), 0);
        assertEq(eTST.debtOf(borrower), 0);
        assertEq(eTST.debtOf(borrower2), borrowed);
    }

    function test_repay_onlyInterest() public {
        uint256 amountToBorrow = 5e18;

        startHoax(borrower);
        assetTST.approve(address(eTST), type(uint256).max);
        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));
        eTST.borrow(amountToBorrow, borrower);

        assertEq(assetTST.balanceOf(borrower), amountToBorrow);

        skip(10 days);

        uint256 borrowed = eTST.debtOf(borrower);

        vm.recordLogs();

        eTST.repay(borrowed - amountToBorrow, borrower);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        //event DToken aren't emitted
        assertEq(entries.length, 6);
        assertEq(entries[0].topics[0], EVCEvents.CallWithContext.selector);
        assertEq(entries[1].topics[0], Events.Transfer.selector);
        assertEq(entries[2].topics[0], Events.InterestAccrued.selector);
        assertEq(entries[3].topics[0], Events.Repay.selector);
        assertEq(entries[4].topics[0], Events.VaultStatus.selector);
        assertEq(entries[5].topics[0], EVCEvents.VaultStatusCheck.selector);
    }

    function owedTo1e5(uint256 debt) internal pure returns (uint256) {
        return (debt * 1e5) >> INTERNAL_DEBT_PRECISION_SHIFT;
    }
}
