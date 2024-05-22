// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {GovernanceModule} from "../../../../../src/EVault/modules/Governance.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {IEVault} from "../../../../../src/EVault/IEVault.sol";
import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {TestERC20} from "../../../../mocks/TestERC20.sol";
import {IRMTestFixed} from "../../../../mocks/IRMTestFixed.sol";
import {IRMTestZero} from "../../../../mocks/IRMTestZero.sol";
import "../../../../../src/EVault/shared/types/Types.sol";

contract VaultTest_Caps is EVaultTestBase {
    using TypesLib for uint256;

    address user1;
    address user2;

    TestERC20 assetTST3;
    IEVault public eTST3;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        assetTST3 = new TestERC20("Test TST 3", "TST3", 18, false);
        eTST3 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST3), address(oracle), unitOfAccount))
        );

        eTST.setLTV(address(eTST2), 0.3e4, 0.3e4, 0);
        eTST.setLTV(address(eTST3), 1e4, 1e4, 0);

        oracle.setPrice(address(eTST), unitOfAccount, 0.01e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 0.083e18);
        oracle.setPrice(address(eTST3), unitOfAccount, 0.083e18);

        vm.startPrank(user1);

        assetTST.mint(user1, type(uint256).max);
        assetTST.approve(address(eTST), type(uint256).max);
        evc.enableCollateral(user1, address(eTST));
        evc.enableController(user1, address(eTST));

        assetTST3.mint(user1, 200e18);
        assetTST3.approve(address(eTST3), type(uint256).max);
        eTST3.deposit(100e18, user1);
        evc.enableCollateral(user1, address(eTST3));

        assetTST2.approve(address(eTST2), type(uint256).max);
        evc.enableCollateral(user1, address(eTST2));

        vm.startPrank(user2);

        assetTST2.mint(user2, 100e18);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, user2);
        evc.enableCollateral(user2, address(eTST2));

        assetTST.approve(address(eTST), type(uint256).max);
        evc.enableCollateral(user2, address(eTST));

        vm.stopPrank();

        skip(31 * 60);
    }

    function test_SetCaps_Integrity(uint16 supplyCap, uint16 borrowCap) public {
        uint256 supplyCapAmount = AmountCap.wrap(supplyCap).resolve();
        uint256 borrowCapAmount = AmountCap.wrap(borrowCap).resolve();
        vm.assume(supplyCapAmount <= MAX_SANE_AMOUNT && borrowCapAmount <= MAX_SANE_AMOUNT);

        vm.expectEmit();
        emit GovernanceModule.GovSetCaps(supplyCap, borrowCap);

        eTST.setCaps(supplyCap, borrowCap);

        (uint16 supplyCap_, uint16 borrowCap_) = eTST.caps();
        assertEq(supplyCap_, supplyCap);
        assertEq(borrowCap_, borrowCap);
    }

    function test_SetCaps_SupplyCapMaxMethods(uint16 supplyCap, address userA) public {
        uint256 supplyCapAmount = AmountCap.wrap(supplyCap).resolve();
        vm.assume(supplyCapAmount <= MAX_SANE_AMOUNT);

        eTST.setCaps(supplyCap, 0);

        assertEq(eTST.maxDeposit(userA), supplyCapAmount);
        assertEq(eTST.maxMint(userA), supplyCapAmount);
    }

    function test_SetCaps_RevertsWhen_SupplyCap_AmountTooLarge(uint16 supplyCap, uint16 borrowCap) public {
        vm.assume(
            supplyCap > 0 && AmountCap.wrap(supplyCap).resolve() > 2 * MAX_SANE_AMOUNT
                && AmountCap.wrap(borrowCap).resolve() < MAX_SANE_AMOUNT
        );

        vm.expectRevert(Errors.E_BadSupplyCap.selector);
        eTST.setCaps(supplyCap, borrowCap);
    }

    function test_SetCaps_RevertsWhen_BorrowCap_AmountTooLarge(uint16 supplyCap, uint16 borrowCap) public {
        vm.assume(
            AmountCap.wrap(supplyCap).resolve() < 2 * MAX_SANE_AMOUNT && borrowCap > 0
                && AmountCap.wrap(borrowCap).resolve() > MAX_SANE_AMOUNT
        );

        vm.expectRevert(Errors.E_BadBorrowCap.selector);
        eTST.setCaps(supplyCap, borrowCap);
    }

    function test_SetCaps_AccessControl(address caller) public {
        vm.assume(caller != eTST.governorAdmin());
        vm.expectRevert(Errors.E_Unauthorized.selector);
        vm.prank(caller);
        eTST.setCaps(0, 0);
    }

    function test_SupplyCap_UnlimitedByDefault() public {
        (uint16 supplyCap,) = eTST.caps();
        assertEq(supplyCap, 0);

        vm.prank(user1);
        eTST.deposit(MAX_SANE_AMOUNT, user1);
        assertEq(eTST.totalSupply(), MAX_SANE_AMOUNT);

        vm.expectRevert();
        vm.prank(user1);
        eTST.deposit(1, user1);
    }

    function test_SupplyCap_CanBeZero() public {
        eTST.setCaps(1, 0);
        vm.expectRevert();
        vm.prank(user1);
        eTST.deposit(1, user1);
    }

    function test_SupplyCap_WhenUnder_IncreasingActions(uint16 supplyCap, uint256 initAmount, uint256 amount) public {
        setUpCollateral();
        uint256 remaining = setUpUnderSupplyCap(supplyCap, initAmount);
        amount = bound(amount, 1, MAX_SANE_AMOUNT);
        bool shouldRevert = amount > remaining;
        uint256 snapshot = vm.snapshot();

        vm.revertTo(snapshot);
        if (shouldRevert) vm.expectRevert();
        vm.prank(user1);
        eTST.deposit(amount, user1);

        vm.revertTo(snapshot);
        if (shouldRevert) vm.expectRevert();
        vm.prank(user1);
        eTST.mint(amount, user1);
    }

    function test_SupplyCap_WhenAt_IncreasingActions(uint16 supplyCap, uint256 amount) public {
        setUpCollateral();
        setUpAtSupplyCap(supplyCap);
        amount = bound(amount, 1, MAX_SANE_AMOUNT);
        uint256 snapshot = vm.snapshot();

        vm.revertTo(snapshot);
        vm.expectRevert();
        vm.prank(user1);
        eTST.deposit(amount, user1);

        vm.revertTo(snapshot);
        vm.expectRevert();
        vm.prank(user1);
        eTST.mint(amount, user1);
    }

    function test_SupplyCap_WhenOver_IncreasingActions(uint16 supplyCapOrig, uint16 supplyCapNow, uint256 amount)
        public
    {
        setUpCollateral();
        setUpOverSupplyCap(supplyCapOrig, supplyCapNow);
        amount = bound(amount, 1, MAX_SANE_AMOUNT);
        uint256 snapshot = vm.snapshot();

        vm.revertTo(snapshot);
        vm.expectRevert();
        vm.prank(user1);
        eTST.deposit(amount, user1);

        vm.revertTo(snapshot);
        vm.expectRevert();
        vm.prank(user1);
        eTST.mint(amount, user1);
    }

    function test_SupplyCap_WhenUnder_DecreasingActions(uint16 supplyCap, uint256 initAmount, uint256 amount) public {
        setUpCollateral();
        uint256 remaining = setUpUnderSupplyCap(supplyCap, initAmount);
        amount = bound(amount, 1, AmountCap.wrap(supplyCap).resolve() - remaining);
        uint256 snapshot = vm.snapshot();

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.withdraw(amount, user1, user1);

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.redeem(amount, user1, user1);

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.repayWithShares(amount, user1);
    }

    function test_SupplyCap_WhenAt_DecreasingActions(uint16 supplyCap, uint256 amount) public {
        setUpCollateral();
        setUpAtSupplyCap(supplyCap);
        amount = bound(amount, 1, AmountCap.wrap(supplyCap).resolve());
        uint256 snapshot = vm.snapshot();

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.withdraw(amount, user1, user1);

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.redeem(amount, user1, user1);

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.repayWithShares(amount, user1);
    }

    function test_SupplyCap_WhenOver_DecreasingActions(uint16 supplyCapOrig, uint16 supplyCapNow, uint256 amount)
        public
    {
        setUpCollateral();
        setUpOverSupplyCap(supplyCapOrig, supplyCapNow);
        (supplyCapNow,) = eTST.caps();
        amount = bound(amount, 1, AmountCap.wrap(supplyCapNow).resolve());
        uint256 snapshot = vm.snapshot();

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.withdraw(amount, user1, user1);

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.redeem(amount, user1, user1);

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.repayWithShares(amount, user1);
    }

    function test_BorrowCap_UnlimitedByDefault() public {
        setUpCollateral();
        vm.prank(user1);
        eTST.deposit(MAX_SANE_AMOUNT, user1);

        (, uint16 borrowCap) = eTST.caps();
        assertEq(borrowCap, 0);

        vm.prank(user1);
        eTST.borrow(MAX_SANE_AMOUNT, user1);

        vm.expectRevert();
        vm.prank(user1);
        eTST.borrow(1, user1);
    }

    function test_BorrowCap_CanBeZero() public {
        setUpCollateral();
        vm.prank(user1);
        eTST.deposit(MAX_SANE_AMOUNT, user1);

        eTST.setCaps(0, 1);

        vm.expectRevert();
        vm.prank(user1);
        eTST.deposit(1, user1);
    }

    function test_BorrowCap_WhenUnder_Borrow(uint16 borrowCap, uint256 initAmount, uint256 amount) public {
        uint256 remaining = setUpUnderBorrowCap(borrowCap, initAmount);
        amount = bound(amount, 1, remaining);
        bool shouldRevert = amount > remaining;
        uint256 snapshot = vm.snapshot();

        vm.revertTo(snapshot);
        if (shouldRevert) vm.expectRevert();
        vm.prank(user1);
        eTST.borrow(amount, user1);
    }

    function test_BorrowCap_WhenAt_Borrow(uint16 borrowCap, uint256 amount) public {
        setUpAtBorrowCap(borrowCap);
        amount = bound(amount, 1, MAX_SANE_AMOUNT);
        uint256 snapshot = vm.snapshot();

        vm.revertTo(snapshot);
        vm.expectRevert();
        vm.prank(user1);
        eTST.borrow(amount, user1);
    }

    function test_BorrowCap_WhenOver_Borrow(uint16 borrowCapOrig, uint16 borrowCapNow, uint256 amount) public {
        setUpOverBorrowCap(borrowCapOrig, borrowCapNow);
        amount = bound(amount, 1, MAX_SANE_AMOUNT);
        uint256 snapshot = vm.snapshot();

        vm.revertTo(snapshot);
        vm.expectRevert();
        vm.prank(user1);
        eTST.borrow(amount, user1);
    }

    function test_BorrowCap_WhenUnder_DecreasingActions(uint16 borrowCap, uint256 initAmount, uint256 amount) public {
        uint256 remaining = setUpUnderBorrowCap(borrowCap, initAmount);
        amount = bound(amount, 0, AmountCap.wrap(borrowCap).resolve() - remaining);
        uint256 snapshot = vm.snapshot();

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.repay(amount, user1);

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.repayWithShares(amount, user1);
    }

    function test_BorrowCap_WhenAt_DecreasingActions(uint16 borrowCap, uint256 amount) public {
        setUpAtBorrowCap(borrowCap);
        amount = bound(amount, 1, AmountCap.wrap(borrowCap).resolve());
        uint256 snapshot = vm.snapshot();

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.repay(amount, user1);

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.repayWithShares(amount, user1);
    }

    function test_BorrowCap_WhenOver_DecreasingActions(uint16 borrowCapOrig, uint16 borrowCapNow, uint256 amount)
        public
    {
        setUpOverBorrowCap(borrowCapOrig, borrowCapNow);
        amount = bound(amount, 1, AmountCap.wrap(borrowCapOrig).resolve());
        uint256 snapshot = vm.snapshot();

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.repay(amount, user1);

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.repayWithShares(amount, user1);
    }

    function test_BorrowCap_WhenOver_InterestAccrual(
        uint16 borrowCapOrig,
        uint16 borrowCapNow,
        uint256 amount,
        uint24 skipAmount
    ) public {
        setUpOverBorrowCap(borrowCapOrig, borrowCapNow);
        amount = bound(amount, 1, AmountCap.wrap(borrowCapOrig).resolve());
        vm.assume(skipAmount > 0);

        uint256 origOwed = eTST.debtOf(user1);
        skip(skipAmount);
        vm.assume(eTST.debtOf(user1) > origOwed);

        uint256 snapshot = vm.snapshot();

        vm.revertTo(snapshot);
        vm.expectRevert();
        vm.prank(user1);
        eTST.borrow(amount, user1);

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.touch();

        vm.revertTo(snapshot);
        vm.prank(user1);
        eTST.repay(amount, user1);
    }

    function setUpUnderSupplyCap(uint16 supplyCap, uint256 initAmount) internal returns (uint256) {
        uint256 supplyCapAmount = AmountCap.wrap(supplyCap).resolve();
        vm.assume(supplyCapAmount > 1 && supplyCapAmount < MAX_SANE_AMOUNT);
        eTST.setCaps(supplyCap, 0);

        initAmount = bound(initAmount, 1, supplyCapAmount - 1);

        vm.prank(user1);
        eTST.deposit(initAmount, user1);

        return supplyCapAmount - initAmount;
    }

    function setUpAtSupplyCap(uint16 supplyCap) internal {
        uint256 supplyCapAmount = AmountCap.wrap(supplyCap).resolve();
        vm.assume(supplyCapAmount != 0 && supplyCapAmount <= MAX_SANE_AMOUNT);

        eTST.setCaps(supplyCap, 0);
        vm.prank(user1);
        eTST.deposit(supplyCapAmount, user1);
    }

    function setUpOverSupplyCap(uint16 supplyCapOrig, uint16 supplyCapNow) internal {
        uint256 supplyCapOrigAmount = AmountCap.wrap(supplyCapOrig).resolve();
        vm.assume(supplyCapOrigAmount > 1 && supplyCapOrigAmount <= MAX_SANE_AMOUNT);

        supplyCapNow = uint16(
            bound(supplyCapNow & 63, 0, supplyCapOrig & 63) | bound(supplyCapNow >> 6, 0, supplyCapOrig >> 6) << 6
        );
        vm.assume(supplyCapOrig != supplyCapNow);

        uint256 supplyCapNewAmount = AmountCap.wrap(supplyCapNow).resolve();
        vm.assume(supplyCapNewAmount != 0 && supplyCapNewAmount < supplyCapOrigAmount);

        eTST.setCaps(supplyCapOrig, 0);
        vm.prank(user1);
        eTST.deposit(supplyCapOrigAmount, user1);
        eTST.setCaps(supplyCapNow, 0);
    }

    function setUpUnderBorrowCap(uint16 borrowCap, uint256 initAmount) internal returns (uint256) {
        setUpCollateral();

        uint256 borrowCapAmount = AmountCap.wrap(borrowCap).resolve();
        vm.assume(borrowCapAmount > 1 && borrowCapAmount < MAX_SANE_AMOUNT);
        eTST.setCaps(0, borrowCap);

        initAmount = bound(initAmount, 0, borrowCapAmount - 1);

        vm.prank(user1);
        eTST.deposit(borrowCapAmount, user1);
        vm.prank(user1);
        eTST.borrow(initAmount, user1);

        return borrowCapAmount - initAmount;
    }

    function setUpAtBorrowCap(uint16 borrowCap) internal {
        setUpCollateral();

        uint256 borrowCapAmount = AmountCap.wrap(borrowCap).resolve();
        vm.assume(borrowCapAmount != 0 && borrowCapAmount < MAX_SANE_AMOUNT);
        eTST.setCaps(0, borrowCap);

        vm.prank(user1);
        eTST.deposit(borrowCapAmount, user1);
        vm.prank(user1);
        eTST.borrow(borrowCapAmount, user1);
    }

    function setUpOverBorrowCap(uint16 borrowCapOrig, uint16 borrowCapNow) internal {
        uint256 borrowCapOrigAmount = AmountCap.wrap(borrowCapOrig).resolve();
        vm.assume(borrowCapOrigAmount > 1 && borrowCapOrigAmount <= MAX_SANE_AMOUNT);

        borrowCapNow = uint16(
            bound(borrowCapNow & 63, 0, borrowCapOrig & 63) | bound(borrowCapNow >> 6, 0, borrowCapOrig >> 6) << 6
        );
        vm.assume(borrowCapOrig != borrowCapNow);

        uint256 borrowCapNewAmount = AmountCap.wrap(borrowCapNow).resolve();
        vm.assume(borrowCapNewAmount != 0 && borrowCapNewAmount < borrowCapOrigAmount);

        setUpCollateral();

        eTST.setCaps(0, borrowCapOrig);
        vm.prank(user1);
        eTST.deposit(borrowCapOrigAmount, user1);
        vm.prank(user1);
        eTST.borrow(borrowCapOrigAmount, user1);
        eTST.setCaps(0, borrowCapNow);
    }

    function setUpCollateral() internal {
        eTST.setLTV(address(eTST2), 1e4, 1e4, 0);

        vm.startPrank(user1);
        assetTST2.mint(user1, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(MAX_SANE_AMOUNT / 100, user1);

        evc.enableController(user1, address(eTST));
        evc.enableCollateral(user1, address(eTST2));

        oracle.setPrice(address(assetTST), unitOfAccount, 1 ether);
        oracle.setPrice(address(assetTST2), unitOfAccount, 1000 ether);
        vm.stopPrank();
    }

    function test_deposit_simpleSupplyCap() public {
        startHoax(user1);
        eTST.deposit(10e18, user1);

        assertEq(eTST.cash(), 10e18);
        assertEq(eTST.maxDeposit(user1), MAX_SANE_AMOUNT - 10e18);
        assertEq(eTST.maxMint(user1), MAX_SANE_AMOUNT - 10e18);

        // Deposit prevented:
        startHoax(address(this));
        eTST.setCaps(7059, 0);
        assertEq(eTST.maxDeposit(user1), 1e18);
        assertEq(eTST.maxMint(user1), 1e18);
        startHoax(user1);
        vm.expectRevert(Errors.E_SupplyCapExceeded.selector);
        eTST.deposit(2e18, user1);

        // Raise Cap and it succeeds:
        startHoax(address(this));
        eTST.setCaps(8339, 0);
        assertEq(eTST.maxDeposit(user1), 3e18);
        startHoax(user1);
        eTST.deposit(2e18, user1);

        // New limit prevents additional deposits:
        vm.expectRevert(Errors.E_SupplyCapExceeded.selector);
        eTST.deposit(2e18, user1);

        // Lower supply cap. Withdrawal still works, even though it's not enough withdrawn to solve the policy
        // violation:
        startHoax(address(this));
        eTST.setCaps(32018, 0);
        assertEq(eTST.maxDeposit(user1), 0);
        assertEq(eTST.maxMint(user1), 0);
        startHoax(user1);
        eTST.withdraw(3e18, user1, user1);
        assertEq(eTST.totalSupply(), 9e18);

        // Deposit doesn't work
        vm.expectRevert(Errors.E_SupplyCapExceeded.selector);
        eTST.deposit(0.1e18, user1);
    }

    function test_mint_simpleSupplyCap() public {
        startHoax(user1);
        eTST.deposit(10e18, user1);
        assertEq(eTST.totalSupply(), 10e18);

        // Mint prevented:
        startHoax(address(this));
        eTST.setCaps(7059, 0);
        startHoax(user1);
        vm.expectRevert(Errors.E_SupplyCapExceeded.selector);
        eTST.mint(2e18, user1);

        // Raise Cap and it succeeds:
        startHoax(address(this));
        eTST.setCaps(8339, 0);
        startHoax(user1);
        eTST.mint(2e18, user1);

        // New limit prevents additional minting:
        vm.expectRevert(Errors.E_SupplyCapExceeded.selector);
        eTST.mint(2e18, user1);

        // Lower supply cap. Withdrawal still works, even though it's not enough withdrawn to solve the policy
        // violation:
        startHoax(address(this));
        eTST.setCaps(32018, 0);
        startHoax(user1);
        eTST.withdraw(3e18, user1, user1);

        assertEq(eTST.totalSupply(), 9e18);

        // Mint doesn't work
        startHoax(user1);
        vm.expectRevert(Errors.E_SupplyCapExceeded.selector);
        eTST.mint(0.1e18, user1);
    }

    function test_borrow_simpleBorrowCap() public {
        startHoax(user1);
        eTST.deposit(10e18, user1);
        eTST.borrow(5e18, user1);

        assertEq(eTST.totalBorrows(), 5e18);

        // Borrow prevented:
        startHoax(address(this));
        eTST.setCaps(0, 38418);
        startHoax(user1);
        vm.expectRevert(Errors.E_BorrowCapExceeded.selector);
        eTST.borrow(2e18, user1);

        // Raise Cap and it succeeds:
        startHoax(address(this));
        eTST.setCaps(0, 51218);
        startHoax(user1);
        eTST.borrow(2e18, user1);

        // New limit prevents additional borrows:
        vm.expectRevert(Errors.E_BorrowCapExceeded.selector);
        eTST.borrow(2e18, user1);

        // Jump time so that new total borrow exceeds the borrow cap due to the interest accrued
        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestFixed()));
        assertApproxEqAbs(eTST.totalBorrows(), 7e18, 0.001e18);

        skip(2 * 365 * 24 * 60 * 60); // 2 years

        assertApproxEqAbs(eTST.totalBorrows(), 8.55e18, 0.001e18);

        // Touch still works, updating total borrows in storage
        skip(1);
        eTST.touch();
        assertApproxEqAbs(eTST.totalBorrows(), 8.55e18, 0.001e18);

        // Repay still works, even though it's not enough repaid to solve the policy violation:
        startHoax(user1);
        eTST.repay(0.05e18, user1);

        // Repay with shares also works

        eTST.repayWithShares(0.1e18, user1);

        assertApproxEqAbs(eTST.totalBorrows(), 8.4e18, 0.001e18);

        // Borrow doesn't work
        vm.expectRevert(Errors.E_BorrowCapExceeded.selector);
        eTST.borrow(0.1e18, user1);
    }

    function test_deferralOfSupplyCapCheck() public {
        startHoax(user1);
        eTST.deposit(10e18, user1);
        // Current supply 10, supply cap 15
        assertEq(eTST.totalSupply(), 10e18);

        startHoax(address(this));
        eTST.setCaps(9619, 0);

        // Deferring doesn't allow us to leave the asset in policy violation:
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.deposit.selector, 10e18, user1)
        });

        startHoax(user1);
        vm.expectRevert(Errors.E_SupplyCapExceeded.selector);
        evc.batch(items);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.mint.selector, 10e18, user1)
        });

        startHoax(user1);
        vm.expectRevert(Errors.E_SupplyCapExceeded.selector);
        evc.batch(items);

        // Transient violations don't fail the batch:
        items = new IEVC.BatchItem[](2);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.deposit.selector, 10e18, user1)
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.withdraw.selector, 8e18, user1, user1)
        });

        startHoax(user1);
        evc.batch(items);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.mint.selector, 10e18, user1)
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.redeem.selector, 8e18, user1, user1)
        });

        startHoax(user1);
        evc.batch(items);

        assertEq(eTST.totalSupply(), 14e18);
    }

    function test_deferralOfBorrowCapCheck() public {
        startHoax(user1);
        eTST.deposit(10e18, user1);
        // Current borrow 0, borrow cap 5

        assertEq(eTST.totalBorrows(), 0);
        startHoax(address(this));
        eTST.setCaps(0, 32018);

        // Deferring doesn't allow us to leave the asset in policy violation:
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.borrow.selector, 6e18, user1)
        });

        startHoax(user1);
        vm.expectRevert(Errors.E_BorrowCapExceeded.selector);
        evc.batch(items);

        // Transient violations don't fail the batch:
        items = new IEVC.BatchItem[](2);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.borrow.selector, 6e18, user1)
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.repay.selector, 2e18, user1)
        });

        startHoax(user1);
        evc.batch(items);

        assertEq(eTST.totalBorrows(), 4e18);
    }

    function test_simpleOperationPausing() public {
        startHoax(user1);
        eTST.deposit(15e18, user1);

        // Deposit prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_DEPOSIT);
        startHoax(user1);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.deposit(5e18, user1);

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        startHoax(user1);
        eTST.deposit(5e18, user1);

        // Mint prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_MINT);
        startHoax(user1);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.mint(5e18, user1);

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        startHoax(user1);
        eTST.mint(5e18, user1);

        // Withdrawal prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_WITHDRAW);
        startHoax(user1);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.withdraw(5e18, user1, user1);

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        startHoax(user1);
        eTST.withdraw(5e18, user1, user1);

        // Redeem prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_REDEEM);
        startHoax(user1);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.redeem(5e18, user1, user1);

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        startHoax(user1);
        eTST.redeem(5e18, user1, user1);

        // setup
        startHoax(user1);
        evc.enableController(user1, address(eTST));

        // Borrow prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_BORROW);
        startHoax(user1);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.borrow(5e18, user1);

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        startHoax(user1);
        eTST.borrow(5e18, user1);
        eTST.borrow(5e18, user1);

        // Repay prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_REPAY);
        startHoax(user1);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.repay(1e18, user1);

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        startHoax(user1);
        eTST.repay(1e18, user1);

        // Repay with shares prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_REPAY_WITH_SHARES);
        startHoax(user1);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.repayWithShares(type(uint256).max, user1);

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        startHoax(user1);
        eTST.repayWithShares(type(uint256).max, user1);

        // eVault transfer prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_TRANSFER);
        startHoax(user1);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.transfer(getSubAccount(user1, 1), 5e18);

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        startHoax(user1);
        eTST.transfer(getSubAccount(user1, 1), 5e18);

        // setup
        startHoax(user2);
        evc.enableController(user2, address(eTST));
        evc.enableCollateral(user2, address(eTST));
        startHoax(user1);
        evc.enableController(user1, address(eTST));
        eTST.deposit(10e18, user1);
        eTST.borrow(5e18, user1);

        // Debt transfer prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_PULL_DEBT);
        startHoax(user2);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.pullDebt(1e18, user1);

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        startHoax(user2);
        eTST.pullDebt(1e18, user1);

        //Vault touch prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_TOUCH);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.touch();

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        eTST.touch();

        //Convert fees prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_CONVERT_FEES);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.convertFees();

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        eTST.convertFees();

        //Liquidation prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_LIQUIDATE);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        startHoax(user2);
        eTST.liquidate(user1, address(eTST2), 0, 0);

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        startHoax(user2);
        eTST.liquidate(user1, address(eTST2), 0, 0);

        //Skim prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_SKIM);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        startHoax(user1);
        eTST.skim(0, user1);

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        startHoax(user1);
        eTST.skim(0, user1);

        //Vault status check prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_VAULT_STATUS_CHECK);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        startHoax(address(eTST));
        evc.requireVaultStatusCheck();

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        startHoax(address(eTST));
        evc.requireVaultStatusCheck();

        //FlashLoan prevented:
        startHoax(address(this));
        eTST.setHookConfig(address(0), OP_FLASHLOAN);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.flashLoan(10, abi.encode(address(eTST), address(assetTST), 10));

        // Remove pause and it succeeds:
        startHoax(address(this));
        eTST.setHookConfig(address(0), 0);
        eTST.flashLoan(10, abi.encode(address(eTST), address(assetTST), 10));
    }

    function test_complexScenario() public {
        startHoax(user1);
        eTST.deposit(10e18, user1);

        startHoax(address(this));
        eTST2.setLTV(address(eTST), 1e4, 1e4, 0);
        oracle.setPrice(address(eTST2), unitOfAccount, 0.01e18);

        assertEq(eTST.totalSupply(), 10e18);
        assertEq(eTST2.totalSupply(), 10e18);
        assertEq(eTST.totalBorrows(), 0);
        assertEq(eTST2.totalBorrows(), 0);

        eTST.setCaps(9619, 0);
        eTST2.setCaps(0, 32018);
        eTST2.setHookConfig(address(0), OP_REPAY_WITH_SHARES);

        // This won't work because the end state violates market policies:

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](6);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.disableController.selector)
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user1, address(eTST2))
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.deposit.selector, 7e18, user1)
        });
        items[3] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 7e18, user1)
        });
        items[4] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.withdraw.selector, 1e18, user1, user1)
        });
        items[5] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.repay.selector, 3e18, user1)
        });

        startHoax(user1);
        vm.expectRevert(Errors.E_SupplyCapExceeded.selector);
        evc.batch(items);

        items[4] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.withdraw.selector, 3e18, user1, user1)
        });
        items[5] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.repay.selector, 1e18, user1)
        });

        startHoax(user1);
        vm.expectRevert(Errors.E_BorrowCapExceeded.selector);
        evc.batch(items);

        // Succeeeds if there's no violation:

        items[5] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.repay.selector, 3e18, user1)
        });

        startHoax(user1);
        evc.batch(items);

        eTST.withdraw(4e18, user1, user1);
        eTST2.repay(type(uint256).max, user1);
        // Fails again if repayWithShares item added:
        eTST.disableController();

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user1, address(eTST2))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.deposit.selector, 7e18, user1)
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 7e18, user1)
        });
        items[3] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.repayWithShares.selector, 0, user1)
        });
        items[4] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.withdraw.selector, 1e18, user1, user1)
        });
        items[5] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.repay.selector, 3e18, user1)
        });

        startHoax(user1);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        evc.batch(items);

        // Succeeds if wind item added for TST instead of TST2:
        items = new IEVC.BatchItem[](9);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user1, address(eTST))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user1, address(eTST2))
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.deposit.selector, 7e18, user1)
        });
        items[3] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 7e18, user1)
        });
        items[4] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.repayWithShares.selector, 0, user1)
        });
        items[5] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.withdraw.selector, 4e18, user1, user1)
        });
        items[6] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.repay.selector, type(uint256).max, user1)
        });
        items[7] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.repay.selector, type(uint256).max, user1)
        });
        items[8] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.disableController.selector)
        });

        startHoax(user1);
        evc.batch(items);

        // checkpoint:
        assertEq(eTST.totalSupply(), 13e18);
        assertEq(eTST2.totalSupply(), 10e18);
        assertEq(eTST.totalBorrows(), 0);
        assertEq(eTST2.totalBorrows(), 0);

        // set new market policies:
        startHoax(address(this));
        eTST.setCaps(6419, 6418);
        eTST2.setCaps(6418, 6418);
        eTST2.setHookConfig(address(0), 0);

        items = new IEVC.BatchItem[](8);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user1, address(eTST2))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, getSubAccount(user1, 1), address(eTST2))
        });
        // this exceeds the borrow cap temporarily
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 7e18, user1)
        });
        // this exceeds the supply cap temporarily
        items[3] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.deposit.selector, type(uint256).max, getSubAccount(user1, 1))
        });
        // this exceeds the borrow cap temporarily
        items[4] = IEVC.BatchItem({
            onBehalfOfAccount: getSubAccount(user1, 1),
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.pullDebt.selector, type(uint256).max, user1)
        });
        // this exceeds the supply cap temporarily
        items[5] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.deposit.selector, 1e18, user1)
        });
        // this should repay TST2 debt and deposits, leaving the TST2 borrow cap no longer violated
        // TST2 supply cap is not an issue, although exceeded, total balances stayed the same within the transaction
        items[6] = IEVC.BatchItem({
            onBehalfOfAccount: getSubAccount(user1, 1),
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.repayWithShares.selector, type(uint256).max, getSubAccount(user1, 1))
        });
        // this should withdraw more TST than deposited, leaving the TST supply cap no longer violated
        items[7] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.withdraw.selector, 2e18, user1, user1)
        });

        startHoax(user1);
        evc.batch(items);

        assertEq(eTST.totalSupply(), 12e18);
        assertEq(eTST2.totalSupply(), 10e18);
        assertEq(eTST.totalBorrows(), 0);
        assertEq(eTST2.totalBorrows(), 0);
    }

    function onFlashLoan(bytes memory data) external {
        (address eTSTAddress, address assetTSTAddress, uint256 repayAmount) =
            abi.decode(data, (address, address, uint256));

        IERC20(assetTSTAddress).transfer(eTSTAddress, repayAmount);
    }

    // This test verifies an edge case behaviour: When a user repays, totalAssets (cash + totalBorrows)
    // is supposed to be unaffected because the totalBorrows goes down the same amount cash goes up.
    // However, since the amount repaid (added to cash) is rounded up but the amount deducted from
    // totalBorrows is precise but also rounded up when necessary, totalAssets can appear to increase
    // by 1 wei. Because of this, a repay could cause an E_SupplyCapExceeded exception if the supply
    // cap is currently exceeded. To prevent this, the totalAssets recorded in the snapshot uses a
    // rounded *down* totalBorrows.

    function test_CanRepayWhenSupplyCapReduced() public {
        setUpCollateral();
        assetTST.mint(user2, 500e18);
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        // Setup two borrowers:

        startHoax(user1);
        eTST.deposit(50e18, user2);
        eTST.borrow(5e18, user1);
        vm.stopPrank();

        startHoax(user2);
        assetTST.approve(address(eTST), type(uint256).max);
        evc.enableController(user2, address(eTST));
        eTST.borrow(5e18, user2);
        vm.stopPrank();

        // Set a supply cap below current supply

        eTST.setCaps(uint16((0.01e2 << 6) | 18), 0);

        // Jump ahead in time so some fractional interest accrues:

        skip(15 * 60);

        // First user repays in full:

        vm.prank(user1);
        eTST.repay(type(uint256).max, user1);

        // Second user repays in 2 chunks:

        startHoax(user2);
        eTST.repay(1e18, user2);
        eTST.repay(type(uint256).max, user2);
        vm.stopPrank();

        assertEq(eTST.debtOf(user1), 0);
        assertEq(eTST.debtOf(user2), 0);
        assertEq(eTST.totalBorrows(), 1); // residual dust is rounded up
    }
}
