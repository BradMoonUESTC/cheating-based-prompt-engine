// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../EVaultTestBase.t.sol";
import {EVault} from "../../../../../src/EVault/EVault.sol";

import "../../../../../src/EVault/shared/types/Types.sol";

contract EVaultHarness is EVault {
    using TypesLib for uint256;

    constructor(Integrations memory integrations, DeployedModules memory modules) EVault(integrations, modules) {}

    function setCash_(uint256 value) public {
        vaultStorage.cash = Assets.wrap(uint112(value));
    }

    function setTotalBorrow_(uint256 value) public {
        vaultStorage.totalBorrows = Owed.wrap(uint144(value << INTERNAL_DEBT_PRECISION_SHIFT));
    }

    function setTotalBorrowExact_(uint256 value) public {
        vaultStorage.totalBorrows = Owed.wrap(uint144(value));
    }

    function setTotalShares_(uint256 value) public {
        vaultStorage.totalShares = Shares.wrap(uint112(value));
    }
}

contract VaultTest_Conversion is EVaultTestBase {
    address user1;

    EVaultHarness public eTST0;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");

        address evaultImpl = address(new EVaultHarness(integrations, modules));
        vm.prank(admin);
        factory.setImplementation(evaultImpl);

        eTST0 = EVaultHarness(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTST0.setInterestRateModel(address(new IRMTestDefault()));
    }

    function test_maxDeposit_checkFreeTotalShares() public {
        assertEq(eTST0.cash(), 0);
        assertEq(eTST0.totalSupply(), 0);

        uint256 maxAssets = eTST0.maxDeposit(user1);
        assertEq(maxAssets, MAX_SANE_AMOUNT);

        eTST0.setCash_(1e18);
        eTST0.setTotalShares_(MAX_SANE_AMOUNT - 1000e18);

        assertEq(eTST0.cash(), 1e18);
        assertEq(eTST0.totalSupply(), MAX_SANE_AMOUNT - 1000e18);

        uint256 remainingCash = MAX_SANE_AMOUNT - eTST0.cash();
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST0.convertToShares(remainingCash);

        uint256 remainingShares = MAX_SANE_AMOUNT - eTST0.totalSupply();
        maxAssets = eTST0.maxDeposit(user1);
        assertEq(maxAssets, eTST0.convertToAssets(remainingShares));

        startHoax(user1);
        assetTST.mint(user1, maxAssets);
        assetTST.approve(address(eTST0), type(uint256).max);
        eTST0.deposit(maxAssets, user1);
        assertEq(assetTST.balanceOf(user1), 0);

        maxAssets = eTST0.maxDeposit(user1);
        assertEq(maxAssets, 0);
        assertGt(eTST0.convertToShares(1), MAX_SANE_AMOUNT - eTST0.totalSupply());

        assetTST.mint(user1, 1);
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST0.deposit(1, user1);
    }

    function test_maxMint_checkFreeTotalShares() public {
        assertEq(eTST0.cash(), 0);
        assertEq(eTST0.totalSupply(), 0);

        uint256 maxShares = eTST0.maxMint(user1);
        assertEq(maxShares, MAX_SANE_AMOUNT);

        eTST0.setCash_(1e18);
        eTST0.setTotalShares_(MAX_SANE_AMOUNT - 1000e18);

        assertEq(eTST0.cash(), 1e18);
        assertEq(eTST0.totalSupply(), MAX_SANE_AMOUNT - 1000e18);

        uint256 remainingCash = MAX_SANE_AMOUNT - eTST0.cash();
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST0.convertToShares(remainingCash);

        uint256 remainingShares = MAX_SANE_AMOUNT - eTST0.totalSupply();
        maxShares = eTST0.maxMint(user1);
        assertEq(maxShares, remainingShares);

        startHoax(user1);
        assetTST.mint(user1, maxShares);
        assetTST.approve(address(eTST0), type(uint256).max);
        eTST0.mint(maxShares, user1);
        assertEq(eTST0.balanceOf(user1), maxShares);

        maxShares = eTST0.maxMint(user1);
        assertEq(maxShares, 0);
        assertGt(eTST0.totalSupply(), 0);

        assetTST.mint(user1, 1);
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST0.mint(1, user1);
    }

    function test_maxDeposit_canUnderEstimate() public {
        startHoax(user1);
        assetTST.mint(user1, type(uint256).max);
        assetTST.approve(address(eTST0), type(uint256).max);

        // with exchange rate == 1, maxDeposit is exact
        eTST0.setCash_(1e18);
        eTST0.setTotalShares_(1e18);

        uint256 snapshot = vm.snapshot();

        uint256 max = eTST0.maxDeposit(user1);
        eTST0.deposit(max, user1);

        vm.expectRevert();
        eTST0.deposit(1, user1);

        vm.revertTo(snapshot);

        // with exchange rates > 1, it can underestimate
        eTST0.setCash_(1.5e18);
        eTST0.setTotalShares_(1e18);

        snapshot = vm.snapshot();

        max = eTST0.maxDeposit(user1);
        eTST0.deposit(max, user1);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        // can deposit more than maxDeposit
        eTST0.deposit(max + 1, user1);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        uint256 realMax = MAX_SANE_AMOUNT - 1.5e18;
        eTST0.deposit(realMax, user1);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        vm.expectRevert();
        eTST0.deposit(realMax + 1, user1);

        assertEq(realMax - max, 1);

        vm.revertTo(snapshot);

        // with exchange rates < 1, it can underestimate
        eTST0.setCash_(1e18);
        eTST0.setTotalShares_(1.5e18);

        snapshot = vm.snapshot();

        max = eTST0.maxDeposit(user1);
        eTST0.deposit(max, user1);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        // can deposit more than maxDeposit
        eTST0.deposit(max + 1, user1);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        realMax = eTST0.previewMint(eTST0.maxMint(user1) + 1) - 1;
        eTST0.deposit(realMax, user1);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        vm.expectRevert();
        eTST0.deposit(realMax + 1, user1);

        assertEq(realMax - max, 1);
    }

    function testFuzz_convertToAssets_previewReedem(uint256 cash, uint256 shares, uint256 borrows, uint256 redeem)
        public
    {
        cash = bound(cash, 1, MAX_SANE_AMOUNT / 2);
        borrows = bound(borrows, 0, MAX_SANE_AMOUNT);
        vm.assume(cash + borrows <= MAX_SANE_AMOUNT);
        shares = bound(shares, cash + borrows, MAX_SANE_AMOUNT);
        redeem = bound(redeem, 1, shares);

        startHoax(user1);
        assetTST.mint(user1, cash);
        assetTST.mint(address(eTST0), type(uint256).max - cash);
        assetTST.approve(address(eTST0), type(uint256).max);
        eTST0.deposit(cash, user1);

        startHoax(address(this));
        eTST0.setTotalShares_(shares);
        eTST0.setTotalBorrow_(borrows);

        assertEq(eTST0.totalBorrows(), borrows);
        assertEq(eTST0.cash(), cash);
        assertEq(eTST0.totalSupply(), shares);

        uint256 predictedAssets = eTST0.previewRedeem(redeem);
        assertEq(eTST0.convertToAssets(redeem), predictedAssets);

        startHoax(user1);
        if (predictedAssets == 0) {
            vm.expectRevert(Errors.E_ZeroAssets.selector);
            eTST0.redeem(redeem, user1, user1);
            return;
        }

        if (predictedAssets > eTST0.cash()) {
            vm.expectRevert(Errors.E_InsufficientCash.selector);
            eTST0.redeem(redeem, user1, user1);
            return;
        }

        if (redeem > eTST0.balanceOf(user1)) {
            vm.expectRevert(Errors.E_InsufficientBalance.selector);
            eTST0.redeem(redeem, user1, user1);
            return;
        }

        eTST0.redeem(redeem, user1, user1);
        assertEq(assetTST.balanceOf(user1), predictedAssets);
    }

    function testFuzz_previewWithdraw(uint256 cash, uint256 shares, uint256 borrows, uint256 withdraw) public {
        cash = bound(cash, 1, MAX_SANE_AMOUNT / 2);
        borrows = bound(borrows, 0, MAX_SANE_AMOUNT);
        vm.assume(cash + borrows <= MAX_SANE_AMOUNT);
        shares = bound(shares, cash + borrows, MAX_SANE_AMOUNT);
        withdraw = bound(withdraw, 1, cash);

        startHoax(user1);
        assetTST.mint(user1, cash);
        assetTST.mint(address(eTST0), type(uint256).max - cash);
        assetTST.approve(address(eTST0), type(uint256).max);
        eTST0.deposit(cash, user1);

        startHoax(address(this));
        eTST0.setTotalShares_(shares);
        eTST0.setTotalBorrow_(borrows);

        assertEq(eTST0.totalBorrows(), borrows);
        assertEq(eTST0.cash(), cash);
        assertEq(eTST0.totalSupply(), shares);

        uint256 predictedShares = eTST0.previewWithdraw(withdraw);

        startHoax(user1);
        if (predictedShares > eTST0.balanceOf(user1)) {
            vm.expectRevert(Errors.E_InsufficientBalance.selector);
            eTST0.withdraw(withdraw, user1, user1);
            return;
        }

        uint256 resultValue = eTST0.withdraw(withdraw, user1, user1);
        assertEq(resultValue, predictedShares);
        assertEq(eTST0.balanceOf(user1) + predictedShares, cash);
    }

    function testFuzz_roundTripConversions(uint256 cash, uint256 shares, uint256 borrows, uint256 assets) public {
        assets = bound(assets, 1, MAX_SANE_AMOUNT / 2);
        cash = bound(cash, assets, MAX_SANE_AMOUNT - 1);
        borrows = bound(borrows, 0, MAX_SANE_AMOUNT);
        vm.assume(cash + borrows <= MAX_SANE_AMOUNT);
        shares = bound(shares, cash + borrows, MAX_SANE_AMOUNT);

        eTST0.setTotalShares_(shares);
        eTST0.setTotalBorrow_(borrows);
        eTST0.setCash_(cash);

        // assets
        uint256 amount = assets;
        uint256 roundTrip = eTST0.previewMint(eTST0.previewWithdraw(amount));
        assertLe(amount, roundTrip);

        // shares
        amount = eTST.convertToShares(assets);
        roundTrip = eTST0.previewDeposit(eTST0.previewRedeem(amount));
        assertGe(amount, roundTrip);
    }

    function testFuzz_maxWithdraw(uint256 cash, uint256 shares, uint256 borrows, uint256 deposit) public {
        deposit = bound(deposit, 1, MAX_SANE_AMOUNT / 2);
        cash = bound(cash, deposit, MAX_SANE_AMOUNT - 1);
        borrows = bound(borrows, 0, MAX_SANE_AMOUNT);
        vm.assume(cash + borrows <= MAX_SANE_AMOUNT);
        shares = bound(shares, cash + borrows, MAX_SANE_AMOUNT);

        startHoax(user1);
        assetTST.mint(user1, deposit);
        assetTST.mint(address(eTST0), type(uint256).max - deposit);
        assetTST.approve(address(eTST0), type(uint256).max);
        eTST0.deposit(deposit, user1);

        startHoax(address(this));
        eTST0.setTotalShares_(shares);
        eTST0.setTotalBorrow_(borrows);
        eTST0.setCash_(cash);

        assertEq(eTST0.cash(), cash);
        assertEq(eTST0.totalSupply(), shares);
        assertEq(eTST0.totalBorrows(), borrows);

        uint256 maxAssets = eTST0.maxWithdraw(user1);

        uint256 snapshot = vm.snapshot();

        startHoax(user1);
        eTST0.withdraw(maxAssets, user1, user1);
        assertEq(assetTST.balanceOf(user1), maxAssets);

        vm.revertTo(snapshot);

        vm.expectRevert();
        eTST0.withdraw(maxAssets + 1, user1, user1);
    }

    function testFuzz_convertToShares_previewDeposit(uint256 cash, uint256 shares, uint256 borrows, uint256 deposit)
        public
    {
        cash = bound(cash, 1, MAX_SANE_AMOUNT / 1000);
        borrows = bound(borrows, 0, MAX_SANE_AMOUNT / 1000);
        vm.assume(cash + borrows <= MAX_SANE_AMOUNT);
        uint256 totalAssets = cash + borrows;

        // To avoid conversion errors, + 1e20 and type(uint64).max are used
        shares = bound(shares, totalAssets, totalAssets + 1e20);
        deposit = bound(deposit, 1, type(uint64).max);

        startHoax(address(this));
        eTST0.setTotalShares_(shares);
        eTST0.setCash_(cash);
        eTST0.setTotalBorrow_(borrows);

        assertEq(eTST0.totalBorrows(), borrows);
        assertEq(eTST0.cash(), cash);
        assertEq(eTST0.totalSupply(), shares);
        assertEq(eTST0.balanceOf(user1), 0);

        uint256 predictedShares = eTST0.previewDeposit(deposit);
        assertEq(eTST0.convertToShares(deposit), predictedShares);

        startHoax(user1);
        assetTST.mint(user1, deposit);
        assetTST.approve(address(eTST0), type(uint256).max);

        if (eTST0.convertToShares(deposit) + shares > MAX_SANE_AMOUNT) {
            vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
            eTST0.deposit(deposit, user1);
            return;
        }

        if (eTST0.convertToShares(deposit) == 0) {
            vm.expectRevert(Errors.E_ZeroShares.selector);
            eTST0.deposit(deposit, user1);
            return;
        }

        uint256 resultShares = eTST0.deposit(deposit, user1);

        assertEq(resultShares, predictedShares);
        assertEq(eTST0.balanceOf(user1), predictedShares);
    }

    function testFuzz_maxDeposit(uint256 cash, uint256 shares, uint256 borrows, uint16 supplyCap) public {
        uint256 supplyCapAmount = AmountCap.wrap(supplyCap).resolve();
        vm.assume(supplyCapAmount > 0 && supplyCapAmount <= MAX_SANE_AMOUNT);

        cash = bound(cash, 1, supplyCapAmount);
        borrows = bound(borrows, 0, supplyCapAmount - cash);

        shares = bound(shares, cash + borrows, MAX_SANE_AMOUNT);

        startHoax(address(this));
        eTST0.setCaps(supplyCap, 0);
        eTST0.setCash_(cash);
        eTST0.setTotalBorrow_(borrows);
        eTST0.setTotalShares_(shares);

        assertEq(eTST0.totalBorrows(), borrows);
        assertEq(eTST0.cash(), cash);
        assertEq(eTST0.totalSupply(), shares);

        uint256 maxAssets = eTST0.maxDeposit(user1);

        startHoax(user1);
        assetTST.mint(user1, type(uint256).max);
        assetTST.approve(address(eTST0), type(uint256).max);

        eTST0.deposit(maxAssets, user1);
    }

    function testFuzz_maxMint(uint256 cash, uint256 shares, uint256 borrows, uint16 supplyCap) public {
        uint256 supplyCapAmount = AmountCap.wrap(supplyCap).resolve();
        vm.assume(supplyCapAmount > 1 && supplyCapAmount <= MAX_SANE_AMOUNT);

        cash = bound(cash, 1e8, MAX_SANE_AMOUNT);
        borrows = bound(borrows, 0, MAX_SANE_AMOUNT);
        vm.assume(cash + borrows <= MAX_SANE_AMOUNT);
        uint256 totalAssets = cash + borrows;

        shares = bound(shares, totalAssets, MAX_SANE_AMOUNT);

        startHoax(address(this));
        eTST0.setCaps(supplyCap, 0);
        eTST0.setCash_(cash);
        eTST0.setTotalBorrow_(borrows);
        eTST0.setTotalShares_(shares);

        assertEq(eTST0.totalBorrows(), borrows);
        assertEq(eTST0.cash(), cash);
        assertEq(eTST0.totalSupply(), shares);

        uint256 maxShares = eTST0.maxMint(user1);

        startHoax(user1);
        assetTST.mint(user1, type(uint256).max);
        assetTST.approve(address(eTST0), type(uint256).max);

        uint256 snapshot = vm.snapshot();

        eTST0.mint(maxShares, user1);

        vm.revertTo(snapshot);

        vm.expectRevert();
        eTST0.mint(maxShares + 1, user1);
    }

    function testFuzz_previewMint(uint256 cash, uint256 shares, uint256 borrows, uint256 mint) public {
        cash = bound(cash, 1, MAX_SANE_AMOUNT / 1000);
        borrows = bound(borrows, 0, MAX_SANE_AMOUNT / 1000);
        uint256 totalAssets = cash + borrows;

        // To avoid conversion errors, + 1e20 and type(uint64).max are used
        shares = bound(shares, totalAssets, totalAssets + 1e20);
        mint = bound(mint, 1, type(uint64).max);

        startHoax(address(this));
        eTST0.setTotalShares_(shares);
        eTST0.setCash_(cash);
        eTST0.setTotalBorrow_(borrows);

        assertEq(eTST0.totalBorrows(), borrows);
        assertEq(eTST0.cash(), cash);
        assertEq(eTST0.totalSupply(), shares);
        assertEq(eTST0.balanceOf(user1), 0);

        uint256 predictedAssets = eTST0.previewMint(mint);

        startHoax(user1);
        assetTST.mint(user1, type(uint256).max);
        assetTST.approve(address(eTST0), type(uint256).max);

        uint256 resultAssets = eTST0.mint(mint, user1);
        assertEq(resultAssets, predictedAssets);

        uint256 spentAssets = type(uint256).max - assetTST.balanceOf(user1);
        assertEq(spentAssets, predictedAssets);

        assertEq(eTST0.balanceOf(user1), mint);
    }

    function testFuzz_maxRedeem(uint256 cash, uint256 shares, uint256 borrows, uint256 deposit) public {
        cash = bound(cash, 1, MAX_SANE_AMOUNT - 1);
        borrows = bound(borrows, 0, MAX_SANE_AMOUNT);
        vm.assume(cash + borrows <= MAX_SANE_AMOUNT);
        shares = bound(shares, cash + borrows, MAX_SANE_AMOUNT);
        deposit = bound(deposit, 1, cash);

        startHoax(user1);
        assetTST.mint(user1, deposit);
        assetTST.mint(address(eTST0), type(uint256).max - deposit);
        assetTST.approve(address(eTST0), type(uint256).max);
        eTST0.deposit(deposit, user1);

        startHoax(address(this));
        eTST0.setCash_(cash);
        eTST0.setTotalShares_(shares);
        eTST0.setTotalBorrow_(borrows);

        assertEq(eTST0.totalBorrows(), borrows);
        assertEq(eTST0.cash(), cash);
        assertEq(eTST0.totalSupply(), shares);
        assertEq(eTST0.balanceOf(user1), deposit);

        uint256 maxValue = eTST0.maxRedeem(user1);

        startHoax(user1);

        uint256 snapshot = vm.snapshot();

        eTST0.redeem(maxValue, user1, user1);

        vm.revertTo(snapshot);

        vm.expectRevert();
        eTST0.redeem(maxValue + 1, user1, user1);
    }

    function testFuzz_maxRedeemZeroAssets() public {
        uint256 cash = 0;
        uint256 shares = 0;
        uint256 borrows = 2;
        uint256 deposit = 0;

        cash = bound(cash, 1, MAX_SANE_AMOUNT - 1);
        borrows = bound(borrows, 0, MAX_SANE_AMOUNT);
        vm.assume(cash + borrows <= MAX_SANE_AMOUNT);
        shares = bound(shares, cash + borrows, MAX_SANE_AMOUNT);
        deposit = bound(deposit, 1, cash);

        startHoax(user1);
        assetTST.mint(user1, deposit);
        assetTST.mint(address(eTST0), type(uint256).max - deposit);
        assetTST.approve(address(eTST0), type(uint256).max);
        eTST0.deposit(deposit, user1);

        startHoax(address(this));
        eTST0.setCash_(cash);
        eTST0.setTotalShares_(shares);
        eTST0.setTotalBorrowExact_(borrows);

        assertEq(eTST0.totalBorrowsExact(), borrows);
        assertEq(eTST0.cash(), cash);
        assertEq(eTST0.totalSupply(), shares);
        assertEq(eTST0.balanceOf(user1), deposit);

        // borrows exact = 2, total borrows rounded up = 1
        // cash = 1
        // total supply = 3
        // => exchange rate = 2 / 3 < 1
        // deposit = 1
        // => balance = 1, but trying to withdraw it would round down to 0, throwing with E_ZeroAssetsS

        assertEq(0, eTST0.maxRedeem(user1));
        assertEq(0, eTST0.maxWithdraw(user1));
    }

    function testFuzz_maxDepositZeroShares() public {
        uint256 cash = MAX_SANE_AMOUNT / 4 * 3;
        uint256 shares = MAX_SANE_AMOUNT - 1;
        uint256 borrows = (MAX_SANE_AMOUNT << INTERNAL_DEBT_PRECISION_SHIFT) / 4 * 3;
        uint256 deposit = 0;

        startHoax(user1);
        assetTST.mint(user1, deposit);
        assetTST.mint(address(eTST0), type(uint256).max - deposit);
        assetTST.approve(address(eTST0), type(uint256).max);
        eTST0.deposit(deposit, user1);

        startHoax(address(this));
        eTST0.setCash_(cash);
        eTST0.setTotalShares_(shares);
        eTST0.setTotalBorrowExact_(borrows);

        assertEq(eTST0.totalBorrowsExact(), borrows);
        assertEq(eTST0.cash(), cash);
        assertEq(eTST0.totalSupply(), shares);
        assertEq(eTST0.balanceOf(user1), deposit);

        assertEq(eTST0.maxMint(user1), 1);

        // max mint = 1, to assets:  floor(1.5 / 1) = 1, to shares: floor(1 / 1.5) = 0
        // trying to deposit 1 asset would round shares down to zero and revert with E_ZeroShares
        assertEq(eTST0.maxDeposit(user1), 0);

        eTST0.deposit(0, user1);
    }
}
