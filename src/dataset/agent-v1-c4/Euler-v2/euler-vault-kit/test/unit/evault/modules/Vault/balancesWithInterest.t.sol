// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {SafeERC20Lib} from "../../../../../src/EVault/shared/lib/SafeERC20Lib.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IRMTestFixed} from "../../../../mocks/IRMTestFixed.sol";
import {IRMTestZero} from "../../../../mocks/IRMTestZero.sol";
import {RPow} from "../../../../../src/EVault/shared/lib/RPow.sol";
import {IEVault} from "../../../../../src/EVault/IEVault.sol";

contract VaultTest_BalancesWithInterest is EVaultTestBase {
    uint256 SECONDS_PER_YEAR = 365.2425 days;
    uint256 ONE = 1e27;
    uint256 CONFIG_SCALE = 1e4;

    address user1;
    address user2;
    address user3;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        assetTST.mint(user1, 100e18);
        assetTST.mint(user2, 100e18);

        startHoax(user1);
        assetTST.approve(address(eTST), type(uint256).max);
        startHoax(user2);
        assetTST.approve(address(eTST), type(uint256).max);

        assetTST2.mint(user3, 100e18);
        startHoax(user3);
        assetTST2.approve(address(eTST2), type(uint256).max);
        evc.enableCollateral(user3, address(eTST2));
        evc.enableController(user3, address(eTST));
        eTST2.deposit(50e18, user3);

        oracle.setPrice(address(assetTST), unitOfAccount, 0.1e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 0.2e18);

        startHoax(address(this));
        eTST.setLTV(address(eTST2), 0.21e4, 0.21e4, 0);

        skip(31 * 60);
    }

    function test_basicInterestEarningFlow_noReserves() public {
        startHoax(admin);
        protocolConfig.setInterestFeeRange(0, 1e4);
        startHoax(address(this));
        eTST.setInterestFee(0);
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        startHoax(user1);
        eTST.deposit(1e18, user1);
        skip(1);
        assertEq(eTST.maxWithdraw(user1), 1e18);
        assertEq(eTST.balanceOf((user1)), 1e18);

        startHoax(user3);
        eTST.borrow(1e18, user3);
        assertEq(assetTST.balanceOf(address(eTST)), 0);
        assertEq(assetTST.balanceOf(user3), 1e18);
        assertEq(eTST.debtOf(user3), 1e18);

        // Go ahead 1 year (+ 1 second because I did it this way by accident at first, don't want to bother redoing
        // calculations below)
        skip(365 days + 1);
        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestZero()));

        // 10% APY interest charged:
        assertEq(eTST.debtOf(user3), 1.105170921404897917e18);

        // eVault balanceOf unchanged:
        assertEq(eTST.balanceOf(user1), 1e18);

        // eVault shares value increases (one less wei than the amount owed):
        assertApproxEqAbs(eTST.convertToAssets(1e18), 1.105170921404897916e18, 0.00000001e18);

        // Now wallet2 deposits and gets different exchange rate
        assertEq(eTST.balanceOf(user2), 0);
        startHoax(user2);

        eTST.deposit(1e18, user2);
        assertApproxEqAbs(eTST.balanceOf(user2), 0.904e18, 0.001e18);
        assertEq(assetTST.balanceOf(address(eTST)), 1e18);
        assertEq(eTST.maxWithdraw(user2), 0.999999999999999999e18);

        // Go ahead 1 year
        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestFixed()));
        skip(365 days);
        eTST.setInterestRateModel(address(new IRMTestZero()));

        // balanceOf calls stay the same
        uint256 userBalance = eTST.balanceOf(user1);
        uint256 user2Balance = eTST.balanceOf(user2);
        assertEq(userBalance, 1e18);
        assertApproxEqAbs(user2Balance, 0.904e18, 0.001e18);
        assertApproxEqAbs(eTST.totalSupply(), 1.904e18, 0.001e18);

        // Earnings:
        assertEq(eTST.maxWithdraw(user2), 0.999999999999999999e18);
        startHoax(user1);
        eTST.deposit(2e18, user1);
        assertEq(eTST.convertToAssets(userBalance), 1.166190218540982148e18);
        assertEq(eTST.maxWithdraw(user2), 1.05521254310475996e18);
        assertApproxEqAbs(eTST.totalAssets(), 4.221402761645908298e18, 0.000000000000000001e18);

        // More interest is now owed:
        assertEq(eTST.debtOf(user3), 1.221402761645908299e18);
    }

    function test_basicInterestEarningFlow_withReserves() public {
        startHoax(user1);
        eTST.deposit(1e18, user1);

        startHoax(address(this));
        eTST.setInterestFee(0.1e4);
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        startHoax(user3);
        eTST.borrow(1e18, user3);

        (uint256 borrowAPY, uint256 supplyAPY) = getVaultInfo(address(eTST));
        assertEq(borrowAPY, 0.105244346078570209478701625e27);
        assertEq(supplyAPY, 0.094239711147365655602112334e27);

        // Go ahead 1 year, with no reserve credits in between
        skip(365.2425 days);

        eTST.touch();
        assertApproxEqAbs(uint256(eTST.totalBorrows() * 1e18 / eTST.totalSupply()), 1.094719911470713189e18, 0.01e18);

        // Interest charged, matches borrowAPY above:
        assertEq(eTST.debtOf(user3), 1.10524434607857021e18);

        // eVault balanceOf unchanged:
        assertEq(eTST.balanceOf(user1), 1e18);

        // eVault maxWithdraw increases. 10% less than the amount owed, because of reserve fee. Matches
        // "untouchedSupplyAPY" above:
        assertApproxEqAbs(eTST.convertToAssets(1e18), 1.094719911470713189e18, 0.00000001e18);

        // Conversion methods
        assertApproxEqAbs(eTST.convertToAssets(1e18), 1.094719911470713189e18, 0.00000001e18);
        assertApproxEqAbs(eTST.convertToAssets(2e18), 1.094719911470713189e18 * 2, 0.00000001e18);
        assertApproxEqAbs(eTST.convertToShares(1.094719911470713189e18 / uint256(2)), 0.5e18, 0.000000000001e18);

        assertApproxEqAbs(eTST.accumulatedFeesAssets(), 0.010524434607856782e18, 0.000000001e18);

        // Jump another year:
        skip(365.2425 days);

        // More interest charged (prev balance * (1+borrowAPY)):
        assertEq(eTST.debtOf(user3), 1.221565064538646276e18);

        // More interest earned (prev balance * (1+untouchedSupplyAPY)):
        assertApproxEqAbs(eTST.convertToAssets(1e18), 1.198411684570446122e18, 0.00000001e18);

        // Original reserve balance times supplyAPY, plus 10% of current interest accrued
        assertApproxEqAbs(eTST.accumulatedFeesAssets(), 0.023153379968200152e18, 0.00000001e18);
    }

    function test_splitInterestEarningFlow_withReserves() public {
        startHoax(user1);
        eTST.deposit(1e18, user1);
        startHoax(user2);
        eTST.deposit(1e18, user2);

        startHoax(address(this));
        eTST.setInterestFee(0.1e4);
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        startHoax(user3);
        eTST.borrow(1e18, user3);

        (uint256 borrowAPY, uint256 supplyAPY) = getVaultInfo(address(eTST));
        assertEq(borrowAPY, 0.105244346078570209478701625e27);
        assertEq(supplyAPY, 0.046059133709789858497725776e27);

        // Go ahead 1 year
        skip(365.2425 days);
        eTST.touch();

        // Same as in basic case:
        assertEq(eTST.debtOf(user3), 1.10524434607857021e18);

        // eVault maxWithdraw increases. 10% less than the amount owed, because of reserve fee. Matches
        // untouchedSupplyAPY above:
        assertEq(eTST.convertToAssets(eTST.balanceOf(user1)), 1.047359955735333033e18);
        assertEq(eTST.convertToAssets(eTST.balanceOf(user2)), 1.047359955735333033e18);

        // Same as in basic case:
        assertApproxEqAbs(eTST.accumulatedFeesAssets(), 0.010524434607856782e18, 0.0000000000000001e18);

        // Get new APYs:
        (borrowAPY, supplyAPY) = getVaultInfo(address(eTST));
        assertEq(borrowAPY, 0.105244346078570209478701625e27);
        assertEq(supplyAPY, 0.048416583057772105811320948e27);

        skip(365.2425 days);

        // More interest charged (prev balance * (1+borrowAPY)):
        assertEq(eTST.debtOf(user3), 1.221565064538646276e18);

        // More interest earned (prev balance * (1+supplyAPY)):
        assertEq(eTST.convertToAssets(eTST.balanceOf(user1)), 1.099442601860420398e18);
        assertEq(eTST.convertToAssets(eTST.balanceOf(user2)), 1.099442601860420398e18);

        // Original reserve balance times supplyAPY, plus 10% of current interest accrued
        assertApproxEqAbs(eTST.accumulatedFeesAssets(), 0.022679860817706035e18, 0.0000000000000001e18);
    }

    function test_poolDonationIsIgnored() public {
        startHoax(user1);
        eTST.deposit(1e18, user1);

        startHoax(address(this));
        eTST.setInterestFee(0.1e4);
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        startHoax(user3);
        eTST.borrow(1e18, user3);

        (uint256 borrowAPY, uint256 supplyAPY) = getVaultInfo(address(eTST));
        assertEq(borrowAPY, 0.105244346078570209478701625e27);
        assertEq(supplyAPY, 0.094239711147365655602112334e27);

        startHoax(user2);
        assetTST.transfer(address(eTST), 1e18);

        // no change
        (borrowAPY, supplyAPY) = getVaultInfo(address(eTST));
        assertEq(borrowAPY, 0.105244346078570209478701625e27);
        assertEq(supplyAPY, 0.094239711147365655602112334e27);

        // Go ahead 1 year
        skip(365.2425 days);
        eTST.touch();

        // Donation ignored
        assertApproxEqAbs(eTST.convertToAssets(eTST.balanceOf(user1)), 1.0947199e18, 0.0000001e18);

        // Reserves still 10%:
        assertApproxEqAbs(eTST.accumulatedFeesAssets(), 0.010524434e18, 0.0000001e18);
    }

    function test_deposit_roundDownInternalBalance() public {
        startHoax(user2);
        eTST.deposit(1e18, user2);

        startHoax(admin);
        protocolConfig.setInterestFeeRange(0, 1e4);
        startHoax(address(this));
        eTST.setInterestFee(0);
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        startHoax(user3);
        eTST.borrow(1e18, user3);

        // Jump ahead
        skip((365 days) * 10);
        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestZero()));

        assertEq(eTST.balanceOf(user1), 0);

        // Exchange rate is ~2.718. Too small, rounded away:
        startHoax(user1);
        vm.expectRevert(Errors.E_ZeroShares.selector);
        eTST.deposit(1, user1);

        // Still too small:
        vm.expectRevert(Errors.E_ZeroShares.selector);
        eTST.deposit(2, user1);

        // This works:
        uint256 snapshot = vm.snapshot();
        eTST.deposit(3, user1);
        assertEq(eTST.balanceOf(user1), 1);

        vm.revertTo(snapshot);

        // This works too:
        snapshot = vm.snapshot();
        eTST.deposit(200, user1);
        assertEq(eTST.balanceOf(user1), 73); // floor(200 / 2.718)

        vm.revertTo(snapshot);
    }

    function test_withdraw_roundUpInternalBalance() public {
        startHoax(user2);
        eTST.deposit(1e18, user2);
        startHoax(user1);
        eTST.deposit(2, user1);

        startHoax(admin);
        protocolConfig.setInterestFeeRange(0, 1e4);
        startHoax(address(this));
        eTST.setInterestFee(0);
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        startHoax(user3);
        eTST.borrow(1e18, user3);

        // Jump ahead
        skip(365 days);
        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestZero()));

        // Still haven't earned enough interest to actually make any gain:
        assertEq(eTST.balanceOf(user1), 2);
        assertEq(assetTST.balanceOf(user1), 99.999999999999999998e18);

        startHoax(user1);
        eTST.withdraw(2, user1, user1);

        assertEq(eTST.balanceOf(user1), 0);
        assertEq(assetTST.balanceOf(user1), 100e18);
    }

    function test_repayWithShares_exchangeRateRounding() public {
        startHoax(user2);
        eTST.deposit(1e18, user2);
        startHoax(user1);
        eTST.deposit(1, user1);

        startHoax(admin);
        protocolConfig.setInterestFeeRange(0, 1e4);
        startHoax(address(this));
        eTST.setInterestFee(0);
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        startHoax(user3);
        eTST.borrow(1e18, user3);

        // Jump ahead
        skip((365 days) * 20);
        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestZero()));

        assertEq(eTST.balanceOf(user1), 1);
        assertEq(assetTST.balanceOf(user1), 99.999999999999999999e18);

        startHoax(user1);
        eTST.withdraw(1, user1, user1);

        // Now exchange rate is != 1
        assetTST2.mint(user1, 100e18);
        startHoax(user1);
        assetTST2.approve(address(eTST2), type(uint256).max);
        evc.enableCollateral(user1, address(eTST2));
        eTST2.deposit(50e18, user1);
        evc.enableController(user1, address(eTST));

        uint256 snapshot = vm.snapshot();

        eTST.mint(1, user1);
        eTST.borrow(eTST.previewMint(1), user1);
        uint256 balance = eTST.convertToAssets(eTST.balanceOf(user1));

        // debt is rounded up on previewMint
        assertEq(eTST.debtOf(user1), balance + 1);

        eTST.repayWithShares(type(uint256).max, user1);
        assertEq(eTST.maxWithdraw(user1), 0);
        // debt still present
        assertEq(eTST.debtOf(user1), 1);
        address[] memory controllers = evc.getControllers(user1);
        assertEq(controllers.length, 1);
        assertEq(controllers[0], address(eTST));

        vm.revertTo(snapshot);

        // with interest accrued
        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestFixed()));
        startHoax(user1);
        evc.enableController(user1, address(eTST));

        eTST.mint(1, user1);
        eTST.borrow(eTST.previewMint(1), user1);

        skip(20 days);

        balance = eTST.convertToAssets(eTST.balanceOf(user1));

        // debt rounded up
        assertEq(eTST.debtOf(user1), balance + 1 + 1);

        eTST.repayWithShares(type(uint256).max, user1);

        assertEq(eTST.maxWithdraw(user1), 0);
        assertEq(eTST.debtOf(user1), 2);
        controllers = evc.getControllers(user1);
        assertEq(controllers.length, 1);
        assertEq(controllers[0], address(eTST));
        vm.expectRevert(Errors.E_OutstandingDebt.selector);
        eTST.disableController();
    }

    function getVaultInfo(address vault)
        internal
        view
        returns (uint256 borrowInterestRateAPY, uint256 supplyInterestRateAPY)
    {
        uint256 interestFee = IEVault(vault).interestFee();
        uint256 borrowInterestRateSPY = IEVault(vault).interestRate();
        uint256 totalCash = IEVault(vault).cash();
        uint256 totalBorrowed = IEVault(vault).totalBorrows();
        return computeInterestRates(borrowInterestRateSPY, totalCash, totalBorrowed, interestFee);
    }

    function computeInterestRates(uint256 borrowSPY, uint256 cash, uint256 borrows, uint256 interestFee)
        internal
        view
        returns (uint256 borrowAPY, uint256 supplyAPY)
    {
        uint256 totalAssets = cash + borrows;
        bool overflowBorrow;
        bool overflowSupply;

        uint256 supplySPY =
            totalAssets == 0 ? 0 : borrowSPY * borrows * (CONFIG_SCALE - interestFee) / totalAssets / CONFIG_SCALE;
        (borrowAPY, overflowBorrow) = RPow.rpow(borrowSPY + ONE, SECONDS_PER_YEAR, ONE);
        (supplyAPY, overflowSupply) = RPow.rpow(supplySPY + ONE, SECONDS_PER_YEAR, ONE);

        if (overflowBorrow || overflowSupply) return (0, 0);

        borrowAPY -= ONE;
        supplyAPY -= ONE;
    }
}
