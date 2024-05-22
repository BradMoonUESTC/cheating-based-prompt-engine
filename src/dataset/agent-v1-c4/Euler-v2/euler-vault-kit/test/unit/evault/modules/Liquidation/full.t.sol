// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";

import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {IEVault} from "../../../../../src/EVault/IEVault.sol";
import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {TestERC20} from "../../../../mocks/TestERC20.sol";
import {IRMTestFixed} from "../../../../mocks/IRMTestFixed.sol";
import {IRMTestZero} from "../../../../mocks/IRMTestZero.sol";

import "forge-std/Test.sol";

contract VaultLiquidation_Test is EVaultTestBase {
    address lender;
    address borrower;
    address borrower2;
    address bystander;

    TestERC20 assetWETH;
    TestERC20 assetTST3;
    TestERC20 assetTST4;

    IEVault public eWETH;
    IEVault public eTST3;
    IEVault public eTST4;

    function setUp() public override {
        super.setUp();

        lender = makeAddr("lender");
        borrower = makeAddr("borrower");
        borrower2 = makeAddr("borrower2");
        bystander = makeAddr("bystander");

        assetWETH = new TestERC20("Test WETH", "WETH", 18, false);
        assetTST3 = new TestERC20("Test TST 3", "TST3", 18, false);

        assetTST4 = new TestERC20("Test TST 4", "TST4", 6, false);

        eTST.setInterestFee(0.23e4);
        eTST2.setInterestFee(0.23e4);

        eTST.setInterestRateModel(address(new IRMTestZero()));
        eTST2.setInterestRateModel(address(new IRMTestZero()));

        eWETH = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetWETH), address(oracle), unitOfAccount))
        );
        eWETH.setInterestRateModel(address(new IRMTestZero()));

        eTST3 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST3), address(oracle), unitOfAccount))
        );
        eTST3.setInterestRateModel(address(new IRMTestZero()));

        eTST4 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST4), address(oracle), unitOfAccount))
        );
        eTST4.setInterestRateModel(address(new IRMTestZero()));

        eTST.setLTV(address(eWETH), 0.3e4, 0.3e4, 0);
        eTST.setLTV(address(eTST2), 0.3e4, 0.3e4, 0);

        oracle.setPrice(address(assetTST), unitOfAccount, 2.2e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 0.4e18);
        oracle.setPrice(address(assetTST3), unitOfAccount, 2.2e18);
        oracle.setPrice(address(assetWETH), unitOfAccount, 1e18);

        startHoax(lender);

        assetWETH.mint(lender, 200e18);
        assetWETH.approve(address(eWETH), type(uint256).max);

        eWETH.deposit(100e18, lender);

        assetTST.mint(lender, 200e18);
        assetTST.approve(address(eTST), type(uint256).max);

        eTST.deposit(100e18, lender);

        assetTST2.mint(lender, 200e18);
        assetTST2.approve(address(eTST2), type(uint256).max);

        assetTST3.mint(lender, 200e18);
        assetTST3.approve(address(eTST3), type(uint256).max);

        eTST3.deposit(100e18, lender);

        startHoax(borrower);

        assetTST2.mint(borrower, 100e18);
        assetTST2.approve(address(eTST2), type(uint256).max);

        assetTST3.mint(borrower, 100e18);
        assetTST3.approve(address(eTST3), type(uint256).max);

        eTST2.deposit(100e18, borrower);
        evc.enableCollateral(borrower, address(eTST2));

        startHoax(bystander);

        assetTST.mint(bystander, 100e18);
        assetTST.approve(address(eTST), type(uint256).max);

        eTST.deposit(30e18, bystander);

        assetTST2.mint(bystander, 100e18);
        assetTST2.approve(address(eTST2), type(uint256).max);

        eTST2.deposit(18e18, bystander);
        evc.enableCollateral(bystander, address(eTST2));
    }

    function test_noViolation() public {
        // Liquidator not in controller
        startHoax(lender);
        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        eTST.liquidate(borrower, address(eTST), 1, 0);

        evc.enableController(lender, address(eTST));

        vm.expectRevert(Errors.E_BadCollateral.selector);
        eTST.liquidate(borrower, address(eTST), 1, 0);

        // User not in collateral:
        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.3e4, 0.3e4, 0);

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));

        startHoax(lender);
        vm.expectRevert(Errors.E_CollateralDisabled.selector);
        eTST.liquidate(borrower, address(eTST3), 1, 0);

        // User healthy:
        startHoax(borrower);
        eTST.borrow(5e18, borrower);

        startHoax(lender);
        vm.expectRevert(Errors.E_ExcessiveRepayAmount.selector);
        eTST.liquidate(borrower, address(eTST2), 1, 0);

        // no-op
        vm.expectEmit(true, true, true, true);
        emit Events.Liquidate(lender, borrower, address(eTST2), 0, 0);

        eTST.liquidate(borrower, address(eTST2), 0, 0);

        assertEq(eTST2.balanceOf(borrower), 100e18);
        assertEq(eTST.debtOf(borrower), 5e18);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertEq(maxRepay, 0);
        assertEq(maxYield, 0);
    }

    function test_selfLiquidation() public {
        startHoax(lender);
        evc.enableController(lender, address(eTST));

        vm.expectRevert(Errors.E_SelfLiquidation.selector);
        eTST.liquidate(lender, address(eTST2), 1, 0);
    }

    function test_noOracle() public {
        IEVault eTSTx = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(0), unitOfAccount))
        );

        startHoax(borrower);
        vm.expectRevert(Errors.E_NoPriceOracle.selector);
        evc.enableController(borrower, address(eTSTx));

        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        eTSTx.liquidate(borrower, address(eTST2), 1, 0);
    }

    function test_basicFullLiquidation() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        (address[] memory collaterals, uint256[] memory collateralValues, uint256 _liabilityValue) =
            eTST.accountLiquidityFull(borrower, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 1.09e18, 0.01e18);
        assertEq(collaterals.length, 1);
        assertEq(collaterals[0], address(eTST2));
        assertEq(collateralValues[0], 100e18 * 0.4e18 * 0.3e4 / 1e18 / 1e4);
        assertEq(liabilityValue, _liabilityValue);

        // enable collateral with no deposit to verify accountLiquidityFull behavior
        vm.stopPrank();
        vm.prank(borrower);
        evc.enableCollateral(borrower, address(eTST3));
        startHoax(address(this));

        oracle.setPrice(address(assetTST), unitOfAccount, 2.5e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        (collaterals, collateralValues, _liabilityValue) = eTST.accountLiquidityFull(borrower, false);
        assertEq(collaterals.length, 2);
        assertEq(collaterals[0], address(eTST2));
        assertEq(collateralValues[0], 100e18 * 0.4e18 * 0.3e4 / 1e18 / 1e4);
        assertEq(collaterals[1], address(eTST3));
        assertEq(collateralValues[1], 0);
        assertEq(liabilityValue, _liabilityValue);

        uint256 healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 0.96e18, 0.001e18);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));

        // If repay amount is 0, it's a no-op
        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), 0, 0);

        // Nothing changed:
        (uint256 newMaxRepay, uint256 newMaxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertEq(maxRepay, newMaxRepay);
        assertEq(maxYield, newMaxYield);

        uint256 yieldAssets = eTST2.convertToAssets(maxYield);
        uint256 valYield = oracle.getQuote(yieldAssets, address(eTST2), unitOfAccount);
        uint256 valRepay = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);

        assertApproxEqAbs(valRepay, valYield * healthScore / 1e18, 0.000000001e18);

        // Try to repay too much
        vm.expectRevert(Errors.E_ExcessiveRepayAmount.selector);
        eTST.liquidate(borrower, address(eTST2), maxRepay + 1, 0);

        // minYield too low
        vm.expectRevert(Errors.E_MinYield.selector);
        eTST.liquidate(borrower, address(eTST2), maxRepay, maxYield + 1);

        // Successful liquidation
        uint256 feeAssets = eTST.accumulatedFeesAssets();
        assertEq(feeAssets, 0);

        // repay full debt
        uint256 debtOf = eTST.debtOf(borrower);
        assertEq(debtOf, maxRepay);

        uint256 snapshot = vm.snapshot();

        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

        vm.revertTo(snapshot);

        // max uint is equivalent to maxRepay
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);

        // liquidator:
        debtOf = eTST.debtOf(lender);
        assertEq(debtOf, maxRepay);

        uint256 balance = eTST2.balanceOf(lender);
        assertEq(balance, maxYield);

        // violator:
        startHoax(borrower);
        assertEq(eTST.debtOf(borrower), 0);

        eTST.disableController();
        assertEq(evc.getControllers(borrower).length, 0);
        assertApproxEqAbs(eTST2.balanceOf(borrower), 100e18 - maxYield, 0.0000000000011e18);

        // Confirming innocent bystander's balance not changed:
        assertApproxEqAbs(eTST.balanceOf(bystander), 30e18, 0.01e18);
        assertApproxEqAbs(eTST2.balanceOf(bystander), 18e18, 0.01e18);
    }

    function test_partialLiquidation() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);

        oracle.setPrice(address(assetTST), unitOfAccount, 2.5e18);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));

        uint256 partialRepay = maxRepay / 4;
        uint256 partialYield = partialRepay * maxYield / maxRepay;

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), partialRepay, 0);

        // liquidator:
        uint256 debtOf = eTST.debtOf(lender);
        assertEq(debtOf, partialRepay);

        // Yield is proportional to how much was repaid
        uint256 balance = eTST2.balanceOf(lender);
        assertEq(balance, partialYield);

        // reserves:
        uint256 reserves = eTST.accumulatedFeesAssets();

        // violator:
        assertEq(eTST.debtOf(borrower), 5e18 - partialRepay + reserves);
        assertEq(eTST2.balanceOf(borrower), 100e18 - partialYield);

        // Confirming innocent bystander's balance not changed:
        assertEq(eTST.balanceOf(bystander), 30e18);
        assertEq(eTST2.balanceOf(bystander), 18e18);
    }

    function test_reEnterViolator() public {
        startHoax(lender);
        evc.enableController(lender, address(eTST));

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));

        oracle.setPrice(address(assetTST), unitOfAccount, 2.5e18);

        (uint256 maxRepay,) = eTST.checkLiquidation(lender, borrower, address(eTST2));

        // set the liquidator to be operator of the violator in order to be able act on violator's account and defer its
        // liquidity check
        evc.setAccountOperator(borrower, lender, true);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: borrower,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.borrow.selector, 1e18, borrower)
        });

        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: lender,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.liquidate.selector, borrower, address(eTST2), maxRepay, 0)
        });

        startHoax(lender);
        vm.expectRevert(Errors.E_ViolatorLiquidityDeferred.selector);
        evc.batch(items);
    }

    //extreme collateral/borrow factors
    function test_extremeCollateralFactors() public {
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);
        eTST.setLTV(address(eTST2), 0.99e4, 0.99e4, 0);

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        eTST.borrow(17e18, borrower);

        oracle.setPrice(address(assetTST), unitOfAccount, 2.7e18);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertEq(maxYield, 100e18);

        startHoax(address(this));
        eTST.setConfigFlags(1 << 0); //disable debt socialization

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

        // pool takes a loss
        (, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        uint256 liability = getRiskAdjustedValue(17e18 - maxRepay, 2.7e18, 1e18);
        assertEq(liabilityValue, liability);

        // liquidator:
        assertEq(eTST.debtOf(lender), maxRepay);
        assertEq(eTST.balanceOf(lender), maxYield);
    }

    function test_multipleCollaterals() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        eTST.borrow(4e18, borrower);

        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);

        startHoax(borrower);
        assetWETH.mint(borrower, 200e18);
        assetWETH.approve(address(eWETH), type(uint256).max);
        eWETH.deposit(1e18, borrower);
        evc.enableCollateral(borrower, address(eWETH));

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 1.39e18, 0.01e18);

        // borrow increases in value
        oracle.setPrice(address(assetTST), unitOfAccount, 3.15e18);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eWETH));

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 0.976e18, 0.01e18);

        // liquidate TST, which is limited to amount owed
        startHoax(lender);
        eTST.liquidate(borrower, address(eWETH), maxRepay, 0);

        // wasn't sufficient to fully restore health score
        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        uint256 liability = getRiskAdjustedValue(4e18 - maxRepay, 3.15e18, 2.5e18);
        uint256 collateralTST2 = getRiskAdjustedValue(100e18, 0.4e18, 0.75e18);
        uint256 collateralWETH = getRiskAdjustedValue(1e18 - maxYield, 0.4e18, 0.75e18);
        assertApproxEqAbs(
            collateralValue * 1e18 / liabilityValue, (collateralTST2 + collateralWETH) * 1e18 / liability, 0.001e18
        );

        // liquidator:
        assertEq(eTST.debtOf(lender), maxRepay);
        assertEq(eTST2.balanceOf(lender), 0);
        assertEq(eWETH.balanceOf(lender), 100e18 + maxYield);

        // violator:
        assertEq(eTST.debtOf(borrower), 4e18 - maxRepay);
        assertEq(eTST2.balanceOf(borrower), 100e18);
        assertEq(eWETH.balanceOf(borrower), 0);
    }

    function test_minCollateralFactor() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        startHoax(address(this));

        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);
        eTST.setLTV(address(eTST2), 1, 1, 0);

        // Can't exit market
        startHoax(borrower);
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        evc.disableCollateral(borrower, address(eTST2));

        (uint256 maxRepay,) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertEq(eTST.debtOf(borrower), maxRepay);

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);

        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 0.0003636e18, 0.0000001e18);

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

        startHoax(borrower);
        eTST.disableController();

        vm.expectRevert(Errors.E_NoLiability.selector);
        eTST.checkLiquidation(lender, borrower, address(eTST2));
    }

    // borrower2 will be violator, using TST4 (6 decimals) as collateral

    function test_non18DecimalCollateral() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST4));

        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);
        eTST.setLTV(address(eTST4), 0.28e4, 0.28e4, 0);

        oracle.setPrice(address(eTST4), unitOfAccount, 17e30);

        assetTST4.mint(borrower2, 100e6);
        startHoax(borrower2);
        assetTST4.approve(address(eTST4), type(uint256).max);

        eTST4.deposit(10e6, borrower2);
        evc.enableCollateral(borrower2, address(eTST4));
        evc.enableController(borrower2, address(eTST));
        eTST.borrow(20e18, borrower2);

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower2, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 1.08e18, 0.01e18);

        oracle.setPrice(address(eTST4), unitOfAccount, 15.5e30);
        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower2, address(eTST4));

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower2, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 0.986e18, 0.001e18);

        // Successful liquidation
        assertEq(eTST.accumulatedFeesAssets(), 0);
        assertEq(eTST.debtOf(borrower2), 20e18);

        startHoax(lender);
        eTST.liquidate(borrower2, address(eTST4), maxRepay, 0);

        // liquidator:
        assertEq(eTST.debtOf(lender), maxRepay);
        assertEq(eTST4.balanceOf(lender), maxYield);

        // reserves:
        uint256 reserves = eTST.accumulatedFeesAssets();

        // violator:
        assertEq(eTST.debtOf(borrower2), 20e18 - maxRepay + reserves);
        assertEq(eTST4.balanceOf(borrower2), 10e6 - maxYield);
    }

    // liquidation with high collateral exchange rate
    function test_highExchangeRateCollateral() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);
        eTST2.setLTV(address(eTST), 0.95e4, 0.95e4, 0);

        // Increase TST2 interest rate
        assetTST.mint(borrower2, 100e18);
        startHoax(borrower2);
        assetTST.approve(address(eTST), type(uint256).max);
        eTST.deposit(100e18, borrower2);
        evc.enableCollateral(borrower2, address(eTST));
        evc.enableController(borrower2, address(eTST2));
        eTST2.borrow(50e18, borrower2);

        startHoax(address(this));
        eTST2.setInterestRateModel(address(new IRMTestFixed()));
        skip(10110 days);
        eTST2.touch();
        eTST2.setInterestRateModel(address(new IRMTestZero()));

        oracle.setPrice(address(assetTST), unitOfAccount, 16e18);

        // exchange rate is 5.879
        assertApproxEqAbs(eTST2.convertToAssets(1e18), 5.879e18, 0.001e18);
        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        uint256 healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 0.881e18, 0.001e18);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));

        uint256 valYield = oracle.getQuote(maxYield, address(eTST2), unitOfAccount);
        uint256 valRepay = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);
        assertApproxEqAbs(valRepay, valYield * healthScore / 1e18, 0.000000001e18);

        uint256 shares = eTST2.convertToShares(maxYield);
        uint256 yieldReverse = eTST2.convertToAssets(shares);
        // rounding errors
        assertEq(maxYield - yieldReverse, 4);

        uint256 snapshot = vm.snapshot();

        uint256 balanceWithInterest = eTST2.balanceOf(borrower);

        startHoax(lender);

        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

        // liquidator
        assertEq(eTST.debtOf(lender), maxRepay);
        assertEq(eTST2.balanceOf(lender), maxYield);

        // violator
        assertEq(eTST.debtOf(borrower), 0);
        assertEq(eTST2.balanceOf(borrower), balanceWithInterest - maxYield);

        vm.revertTo(snapshot);

        // all collateral is liquidatable
        oracle.setPrice(address(assetTST), unitOfAccount, 100e18);

        (, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertEq(maxYield, 100e18);

        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);

        assertEq(eTST2.balanceOf(lender), 100e18);
        assertEq(eTST2.balanceOf(borrower), 0);
    }

    function test_debtSocialization() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);
        eTST.setLTV(address(eTST2), 0.99e4, 0.99e4, 0);

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        eTST.borrow(17e18, borrower);

        startHoax(bystander);
        evc.enableController(bystander, address(eTST));
        eTST.borrow(1e18, bystander);

        assertEq(eTST.totalBorrows(), 18e18);

        uint256 snapshot = vm.snapshot();

        oracle.setPrice(address(assetTST), unitOfAccount, 2.7e18);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));

        assertEq(maxYield, 100e18);

        address[] memory collaterals = evc.getCollaterals(borrower);
        assertEq(collaterals.length, 1);

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValue, 0);
        assertEq(liabilityValue, 0);

        // 17 borrowed - repay is socialized. 1 + repay remains
        assertEq(eTST.totalBorrows(), 1e18 + maxRepay);

        // liquidator:
        assertEq(eTST.debtOf(lender), maxRepay);
        assertEq(eTST.balanceOf(lender), maxYield);

        vm.revertTo(snapshot);

        // no socialization with other collateral balance
        startHoax(borrower);
        evc.enableCollateral(borrower, address(eTST3));
        // just 1 wei
        eTST3.deposit(1, borrower);

        oracle.setPrice(address(assetTST), unitOfAccount, 2.7e18);

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));

        assertEq(maxYield, 100e18);

        startHoax(address(this));
        eTST.setConfigFlags(1 << 0);

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

        // pool takes a loss
        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        uint256 liability = getRiskAdjustedValue(17e18 - maxRepay, 2.7e18, 1e18);
        assertEq(liabilityValue, liability);

        // liquidator:
        assertEq(eTST.debtOf(lender), maxRepay);
        assertEq(eTST.balanceOf(lender), maxYield);
    }

    function test_zeroCollateralWorth() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(borrower);
        evc.enableCollateral(borrower, address(eTST3));
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 1.09e18, 0.01e18);

        oracle.setPrice(address(assetTST2), unitOfAccount, 0);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValue, 0);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        // no repay, yield full collateral balance
        assertEq(maxRepay, 0);
        assertEq(maxYield, 100e18);

        startHoax(lender);
        vm.expectRevert(Errors.E_ExcessiveRepayAmount.selector);
        eTST.liquidate(borrower, address(eTST2), 1, 0);

        // violator
        assertEq(eTST.debtOf(borrower), 5e18);
        assertEq(eTST2.balanceOf(borrower), 100e18);

        uint256 snapshot = vm.snapshot();

        // without debt socialization collateral is seized, but debt stays
        startHoax(address(this));
        eTST.setConfigFlags(1 << 0);

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), 0, 0);

        // violator
        assertEq(eTST.debtOf(borrower), 5e18);
        assertEq(eTST2.balanceOf(borrower), 0);

        // liquidator:
        assertEq(eTST.debtOf(lender), 0);
        assertEq(eTST2.balanceOf(lender), 100e18);

        // total borrows
        assertEq(eTST.totalBorrows(), 5e18);

        // debt socialization switched on, no yield and no repay, but liquidation socializes debt

        startHoax(address(this));
        eTST.setConfigFlags(0);

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        // no repay, no yield
        assertEq(maxRepay, 0);
        assertEq(maxYield, 0);

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), 0, 0);

        // violator
        assertEq(eTST.debtOf(borrower), 0);
        assertEq(eTST2.balanceOf(borrower), 0);

        // liquidator:
        assertEq(eTST.debtOf(lender), 0);
        assertEq(eTST2.balanceOf(lender), 100e18);

        // total borrows
        assertEq(eTST.totalBorrows(), 0);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        // One wei of a second collateral (even worthless) will prevent socialization

        startHoax(borrower);
        eTST3.deposit(1, borrower);
        oracle.setPrice(address(eTST3), unitOfAccount, 0);

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), 0, 0);

        // violator
        assertEq(eTST.debtOf(borrower), 5e18);
        assertEq(eTST2.balanceOf(borrower), 0);

        // liquidator:
        assertEq(eTST.debtOf(lender), 0);
        assertEq(eTST2.balanceOf(lender), 100e18);

        // total borrows
        assertEq(eTST.totalBorrows(), 5e18);

        // second collateral can be liquidated to socialize debt
        startHoax(lender);
        eTST.liquidate(borrower, address(eTST3), 0, 0);

        // violator
        assertEq(eTST.debtOf(borrower), 0);
        assertEq(eTST3.balanceOf(borrower), 0);

        // liquidator:
        assertEq(eTST.debtOf(lender), 0);
        assertEq(eTST3.balanceOf(lender), 100e18 + 1);

        // total borrows
        assertEq(eTST.totalBorrows(), 0);
    }

    function test_zeroLTVCollateral() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(borrower);
        evc.enableCollateral(borrower, address(eTST3));
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        startHoax(address(this));
        eTST.setLTV(address(eTST2), 0, 0, 0);

        (uint256 collateralValueRA,) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValueRA, 0);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertEq(maxRepay, 5e18);
        // max discount - 20%
        uint256 discountedYieldValue = oracle.getQuote(5e18, address(assetTST), unitOfAccount) * 1e18 / 0.8e18;
        uint256 collateralValue = oracle.getQuote(100e18, address(eTST2), unitOfAccount);
        assertEq(maxYield, 100e18 * discountedYieldValue / collateralValue);

        startHoax(lender);
        // liquidated collateral doesn't support debt
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);

        // liquidator needs other support
        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.9e4, 0.9e4, 0);

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);

        // liquidator
        assertEq(eTST2.balanceOf(lender), maxYield);
        assertEq(eTST.debtOf(lender), maxRepay);

        // violator
        assertEq(eTST.debtOf(borrower), 0);
        assertEq(eTST2.balanceOf(borrower), 100e18 - maxYield);
    }

    //repay adjusted rounds down to 0
    function test_RepayAdjustedRoundsToZero() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(borrower);
        evc.enableCollateral(borrower, address(eTST3));
        evc.enableController(borrower, address(eTST));

        // reset deposit
        eTST2.withdraw(100e18, borrower, borrower);
        eTST2.deposit(45, borrower);

        eTST.borrow(2, borrower);

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValue * 1e18 / liabilityValue, 1.25e18);

        oracle.setPrice(address(assetTST), unitOfAccount, 20e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValue * 1e18 / liabilityValue, 0.125e18);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        // liability value = 40
        // collateral value (not RA) = 18
        // yield value initially = 40/0.8 = 50
        // repay value initially = 40
        // collateral value < yield, so:
        //  repay value = 18 * 0.8 = 14
        //  yield value = 18
        // => repay = 14 * 2 / 40 = 0 (rounded down)
        // yield = 18 * 45 / 18 = 40

        // no repay, yield full collateral balance
        assertEq(maxRepay, 0);
        assertEq(maxYield, 45);

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), 0, 0);

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        // no repay, no yield
        assertEq(maxRepay, 0);
        assertEq(maxYield, 0);

        eTST.liquidate(borrower, address(eTST2), 0, 0);

        //violator
        assertEq(eTST.debtOf(borrower), 0);
        assertEq(eTST2.balanceOf(borrower), 0);

        // liquidator:
        assertEq(eTST.debtOf(lender), 0);
        assertEq(eTST2.balanceOf(lender), 45);

        // total borrows
        assertEq(eTST.totalBorrows(), 0);
    }

    // yield value converted to balance rounds down to 0. equivalent to pullDebt
    function test_zeroYieldValue() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(borrower);
        evc.enableCollateral(borrower, address(eTST3));
        evc.enableController(borrower, address(eTST));

        // reset deposit
        eTST2.withdraw(100e18, borrower, borrower);
        eTST2.deposit(1, borrower);

        oracle.setPrice(address(assetTST), unitOfAccount, 0.001e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 15e18);

        eTST.borrow(3000, borrower);
        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 1.33e18, 0.01e18);

        oracle.setPrice(address(assetTST), unitOfAccount, 0.002e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 0.66e18, 0.01e18);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertEq(maxYield, 0);
        assertEq(maxRepay, 3000);

        // min yield stops unprofitable liquidation
        startHoax(lender);
        vm.expectRevert(Errors.E_MinYield.selector);
        eTST.liquidate(borrower, address(eTST2), maxRepay, 1);

        // liquidator doesn't have collateral to support debt taken on
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

        // provide some collateral
        eTST2.deposit(10, lender);
        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

        //violator
        assertEq(eTST.debtOf(borrower), 0);
        // violator's collateral unchanged
        assertEq(eTST2.balanceOf(borrower), 1);

        // liquidator:
        assertEq(eTST.debtOf(lender), 3000);
        assertEq(eTST2.balanceOf(lender), 10);

        // total borrows
        assertEq(eTST.totalBorrows(), 3000);
    }

    function test_ltvRamping() public {
        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        uint256 healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 1.09e18, 0.01e18);

        uint256 snapshot = vm.snapshot();
        // ramp TST2 LTV down by half over 100 seconds
        eTST.setLTV(address(eTST2), 0.15e4, 0.15e4, 100);

        // account borrowing collateral value cut by half immediately
        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, healthScore / 2, 0.01e18);

        snapshot = vm.snapshot();
        startHoax(borrower);
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(1, borrower);

        vm.revertTo(snapshot);

        // but liquidation is not possible yet
        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, healthScore, 0.01e18);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertEq(maxRepay, 0);
        assertEq(maxYield, 0);

        // with time liquidation HS ramps down to target

        // 10% of ramp duration - liquidation HS > 1 still
        skip(10);
        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, healthScore * 0.95e4 / 1e4, 0.01e18); // HS = 1.036

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertEq(maxRepay, 0);
        assertEq(maxYield, 0);

        // 15% - liquidation HS almost at 1
        skip(5);
        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, healthScore * 0.925e4 / 1e4, 0.01e18); // HS = 1.009

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertEq(maxRepay, 0);
        assertEq(maxYield, 0);

        // 17% of ramp duration - liquidation now possible for a small discount
        skip(2);
        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, healthScore * 0.915e4 / 1e4, 0.01e18); // HS = 0.998

        snapshot = vm.snapshot();
        // LTV is ramping down with every second. If we check liquidation now, during liquidation ltv will be different
        assertEq(eTST.LTVLiquidation(address(eTST2)), 2745);
        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);
        skip(1);
        assertEq(eTST.LTVLiquidation(address(eTST2)), 2730);

        vm.revertTo(snapshot);

        // to get exact results, checkLiquidation should be made in the same block as the liquidation
        snapshot = vm.snapshot();
        eTST.touch();

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, healthScore * 0.915e4 / 1e4, 0.01e18);
        uint256 discount = 1e18 - collateralValue * 1e18 / liabilityValue;

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertApproxEqAbs(maxRepay, 5e18, 0.01e18);
        assertApproxEqAbs(maxYield, 27.55e18, 0.01e18);

        uint256 repayValue = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);
        uint256 yieldValue = oracle.getQuote(maxYield, address(eTST2), unitOfAccount);

        // discount checks out
        assertApproxEqAbs(repayValue * 1e18 / yieldValue, 1e18 - discount, 0.000000001e18);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

        // violator
        assertEq(eTST.debtOf(borrower), 0);
        // maxYield matches liquidation block exactly
        assertEq(eTST2.balanceOf(borrower), 100e18 - maxYield);

        // liquidator:
        assertEq(eTST.debtOf(lender), maxRepay);
        assertEq(eTST2.balanceOf(lender), maxYield);

        vm.revertTo(snapshot);

        // 50% of ramp duration - almost max discount
        skip(33);
        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, healthScore * 0.75e4 / 1e4, 0.01e18);

        snapshot = vm.snapshot();
        eTST.touch();

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, healthScore * 0.75e4 / 1e4, 0.01e18);

        discount = 1e18 - collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(discount, 0.181e18, 0.001e18);

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertApproxEqAbs(maxRepay, 5e18, 0.01e18);
        assertApproxEqAbs(maxYield, 33.61e18, 0.01e18);

        repayValue = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);
        yieldValue = oracle.getQuote(maxYield, address(eTST2), unitOfAccount);

        assertApproxEqAbs(repayValue * 1e18 / yieldValue, 1e18 - discount, 0.000000001e18);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

        // violator
        assertEq(eTST.debtOf(borrower), 0);
        // maxYield matches liquidation block exactly
        assertEq(eTST2.balanceOf(borrower), 100e18 - maxYield);

        // liquidator:
        assertEq(eTST.debtOf(lender), maxRepay);
        assertEq(eTST2.balanceOf(lender), maxYield);

        vm.revertTo(snapshot);

        // 70% of ramp duration - max discount
        skip(20);
        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, healthScore * 0.65e4 / 1e4, 0.01e18);

        snapshot = vm.snapshot();
        eTST.touch(); // mine a block

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, healthScore * 0.65e4 / 1e4, 0.01e18);

        // 1 - HS > 29%, discount maxes out at 20%
        assertApproxEqAbs(1e18 - collateralValue * 1e18 / liabilityValue, 0.29e18, 0.001e18);
        discount = 0.2e18;

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertApproxEqAbs(maxRepay, 5e18, 0.01e18);
        assertApproxEqAbs(maxYield, 34.37e18, 0.01e18);

        repayValue = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);
        yieldValue = oracle.getQuote(maxYield, address(eTST2), unitOfAccount);

        assertApproxEqAbs(repayValue * 1e18 / yieldValue, 1e18 - discount, 0.000000001e18);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

        // violator
        assertEq(eTST.debtOf(borrower), 0);
        // maxYield matches liquidation block exactly
        assertEq(eTST2.balanceOf(borrower), 100e18 - maxYield);

        // liquidator:
        assertEq(eTST.debtOf(lender), maxRepay);
        assertEq(eTST2.balanceOf(lender), maxYield);

        vm.revertTo(snapshot);

        // 100% of ramp duration - max discount
        skip(30);
        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, healthScore / 2, 0.01e18);

        snapshot = vm.snapshot();
        eTST.touch(); // mine a block

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, healthScore / 2, 0.01e18);

        // 1 - HS > 45%, discount maxes out at 20%
        assertApproxEqAbs(1e18 - collateralValue * 1e18 / liabilityValue, 0.454e18, 0.001e18);
        discount = 0.2e18;

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertApproxEqAbs(maxRepay, 5e18, 0.01e18);
        assertApproxEqAbs(maxYield, 34.37e18, 0.01e18);

        repayValue = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);
        yieldValue = oracle.getQuote(maxYield, address(eTST2), unitOfAccount);

        // discount checks out
        assertApproxEqAbs(repayValue * 1e18 / yieldValue, 1e18 - discount, 0.000000001e18);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

        // violator
        assertEq(eTST.debtOf(borrower), 0);

        // maxYield matches liquidation block exactly
        assertEq(eTST2.balanceOf(borrower), 100e18 - maxYield);

        // liquidator:
        assertEq(eTST.debtOf(lender), maxRepay);
        assertEq(eTST2.balanceOf(lender), maxYield);

        vm.revertTo(snapshot);
    }

    function test_liquidationWithBidAskPricing() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 1.09e18, 0.01e18);

        // Liability price increases slightly, but still healthy
        // bid = ask = mid price

        oracle.setPrice(address(assetTST), unitOfAccount, 2.3e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        uint256 healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 1.043e18, 0.001e18);

        uint256 maxRepay;
        uint256 maxYield;

        {
            // accountLiquidity for liquidation purposes is identical

            (uint256 collateralValueL, uint256 liabilityValueL) = eTST.accountLiquidity(borrower, true);
            assertEq(collateralValue, collateralValueL);
            assertEq(liabilityValue, liabilityValueL);

            // Liquidation not possible

            (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
            assertEq(maxRepay, 0);
            assertEq(maxYield, 0);
        }

        uint256 origCollateralValue = collateralValue;
        uint256 origLiabilityValue = liabilityValue;

        // liability's bid price decreases

        oracle.setPrices(address(assetTST), unitOfAccount, 2.2e18, 2.3e18);

        // ... and it has no effect

        (uint256 newCollateralValue, uint256 newLiabilityValue) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValue, newCollateralValue);
        assertEq(liabilityValue, newLiabilityValue);

        // liability ask price increases

        oracle.setPrices(address(assetTST), unitOfAccount, 2.2e18, 2.4e18);

        // Now in borrowing mode, liability's value increases

        (newCollateralValue, newLiabilityValue) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValue, newCollateralValue);
        assertGt(newLiabilityValue, liabilityValue);

        {
            // But liquidation mode values are unaffected

            (uint256 collateralValueL, uint256 liabilityValueL) = eTST.accountLiquidity(borrower, true);
            assertEq(origCollateralValue, collateralValueL);
            assertEq(origLiabilityValue, liabilityValueL);
        }

        liabilityValue = newLiabilityValue;

        // Now collateral's ask price increases

        oracle.setPrices(address(assetTST2), unitOfAccount, 0.4e18, 0.5e18);

        // ... and it has no effect

        (newCollateralValue, newLiabilityValue) = eTST.accountLiquidity(borrower, false);
        assertEq(collateralValue, newCollateralValue);
        assertEq(liabilityValue, newLiabilityValue);

        // collateral bid price changes

        oracle.setPrices(address(assetTST2), unitOfAccount, 0.3e18, 0.5e18);

        // Now in borrowing mode, liability's value increases

        (newCollateralValue, newLiabilityValue) = eTST.accountLiquidity(borrower, false);
        assertGt(collateralValue, newCollateralValue);
        assertEq(liabilityValue, newLiabilityValue);

        {
            // But liquidation mode values are unaffected

            (uint256 collateralValueL, uint256 liabilityValueL) = eTST.accountLiquidity(borrower, true);
            assertEq(origCollateralValue, collateralValueL);
            assertEq(origLiabilityValue, liabilityValueL);
        }

        collateralValue = newCollateralValue;

        // Now we are in violation, since the bid/ask prices have resulted in our risk-adjusted
        // liability value exceeding the risk-adjusted collateral value.

        assertGt(liabilityValue, collateralValue);

        // So, trying to borrow 1 more wei will fail:

        startHoax(borrower);
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(1, borrower);

        // But the user is not liquidatable, because mid-point prices have not changed

        startHoax(address(this));

        {
            (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
            assertEq(maxRepay, 0);
            assertEq(maxYield, 0);
        }

        // Now make the mid-points start to move against the user

        oracle.setPrice(address(assetTST), unitOfAccount, 2.39e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 0.301e18);

        // Now these values store the liquidation mode versions:

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);

        healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 0.755e18, 0.001e18);

        // The discount is max - 20% on mid point prices

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));

        uint256 repayValue = oracle.getQuote(maxRepay, address(eTST), unitOfAccount);
        uint256 yieldValue = oracle.getQuote(maxYield, address(eTST2), unitOfAccount);

        assertApproxEqAbs(yieldValue, repayValue * 1e18 / 0.8e18, 1);

        uint256 violatorsOriginalCollateral = eTST2.balanceOf(borrower);

        startHoax(lender);

        // max uint is equivalent to maxRepay
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);

        // liquidator:
        assertEq(eTST.debtOf(lender), maxRepay);
        assertEq(eTST2.balanceOf(lender), maxYield);

        // violator:
        assertEq(eTST.debtOf(borrower), 0);
        assertEq(eTST2.balanceOf(borrower), violatorsOriginalCollateral - maxYield);
    }

    function test_liquidationWhenUnitOfAccountIsAsset() public {
        // set up liquidator to support the debt

        IEVault eTSTx = IEVault(
            factory.createProxy(
                address(0), true, abi.encodePacked(address(assetTST), address(oracle), address(assetTST))
            )
        );
        eTSTx.setLTV(address(eTST2), 0.95e4, 0.95e4, 0);
        eTSTx.setMaxLiquidationDiscount(0.2e4);

        oracle.setPrice(address(assetTST2), address(assetTST), 0.5e18);

        startHoax(lender);
        evc.enableCollateral(lender, address(eTST2));
        evc.enableController(lender, address(eTSTx));
        assetTST.approve(address(eTSTx), type(uint256).max);
        eTSTx.deposit(100e18, lender);
        eTST2.deposit(10e18, lender);

        startHoax(borrower);
        evc.enableController(borrower, address(eTSTx));
        eTSTx.borrow(40e18, borrower);

        (uint256 collateralValue, uint256 liabilityValue) = eTSTx.accountLiquidity(borrower, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 1.18e18, 0.01e18);

        // liability value is denominated in the asset itself
        assertEq(liabilityValue, 40e18);

        oracle.setPrice(address(assetTST2), address(assetTST), 0.42e18);

        (collateralValue,) = eTSTx.accountLiquidity(borrower, false);
        assertEq(collateralValue * 1e18 / liabilityValue, 0.9975e18);

        (uint256 maxRepay, uint256 maxYield) = eTSTx.checkLiquidation(lender, borrower, address(eTST2));

        assertEq(liabilityValue, maxRepay);

        uint256 repayValue = maxRepay;
        uint256 yieldValue = oracle.getQuote(maxYield, address(eTST2), address(assetTST));

        assertApproxEqAbs(yieldValue, repayValue * 1e18 / 0.9975e18, 1);

        uint256 violatorsOriginalCollateral = eTST2.balanceOf(borrower);
        uint256 lendersOriginalCollateral = eTST2.balanceOf(lender);

        startHoax(lender);

        eTSTx.liquidate(borrower, address(eTST2), type(uint256).max, 0);

        // liquidator:
        assertEq(eTSTx.debtOf(lender), maxRepay);
        assertEq(eTST2.balanceOf(lender), lendersOriginalCollateral + maxYield);

        // violator:
        assertEq(eTSTx.debtOf(borrower), 0);
        assertEq(eTST2.balanceOf(borrower), violatorsOriginalCollateral - maxYield);
    }

    function test_borrowingVsLiquidationLTV() public {
        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        // set up liquidator to support the debt
        startHoax(lender);
        eTST2.deposit(200e18, lender);

        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        // set liquidation LTV higher than borrowing

        startHoax(address(this));
        eTST.setLTV(address(eTST2), 0.3e4, 0.5e4, 0);
        startHoax(borrower);

        // account is healthy in both modes, able to borrow more, no liquidation

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);
        uint256 healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 1.09e18, 0.01e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 1.81e18, 0.01e18);

        eTST.borrow(0.0001e18, borrower);

        (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertEq(maxRepay, 0);
        assertEq(maxYield, 0);

        // collateral price moves against the borrower, account still healthy in both modes

        oracle.setPrice(address(assetTST2), unitOfAccount, 0.39e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 1.06e18, 0.01e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 1.77e18, 0.01e18);

        eTST.borrow(0.0001e18, borrower);

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertEq(maxRepay, 0);
        assertEq(maxYield, 0);

        // collateral price drops further, account can't borrow any more, but can't be liquidated either

        oracle.setPrice(address(assetTST2), unitOfAccount, 0.35e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 0.95e18, 0.01e18); // NOT HEALTHY

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 1.59e18, 0.01e18); // HEALTHY

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(0.0001e18, borrower);

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertEq(maxRepay, 0);
        assertEq(maxYield, 0);

        // liquidation is no-op
        uint256 collateralBefore = eTST2.balanceOf(borrower);
        uint256 debtBefore = eTST.debtOf(borrower);
        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);
        startHoax(borrower);
        assertEq(collateralBefore, eTST2.balanceOf(borrower));
        assertEq(debtBefore, eTST.debtOf(borrower));

        // price drops further, now liquidation is possible

        oracle.setPrice(address(assetTST2), unitOfAccount, 0.2e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 0.54e18, 0.01e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 0.9e18, 0.01e18);

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(0.0001e18, borrower);

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertGt(maxRepay, 0);
        assertGt(maxYield, 0);

        // liquidation can be performed
        uint256 snapshot = vm.snapshot();
        collateralBefore = eTST2.balanceOf(borrower);
        debtBefore = eTST.debtOf(borrower);
        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);
        startHoax(borrower);

        assertEq(collateralBefore, eTST2.balanceOf(borrower) + maxYield);
        assertEq(debtBefore, eTST.debtOf(borrower) + maxRepay);

        // bonus according to liquidation LTV health score

        uint256 yieldAssets = eTST2.convertToAssets(maxYield);
        uint256 valYield = oracle.getQuote(yieldAssets, address(eTST2), unitOfAccount);
        uint256 valRepay = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);

        assertApproxEqAbs(valRepay, valYield * healthScore / 1e18, 0.000000001e18);

        vm.revertTo(snapshot);

        // price drops further, liquidation bonus follows liquidation health score

        oracle.setPrice(address(assetTST2), unitOfAccount, 0.19e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 0.51e18, 0.01e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 0.86e18, 0.01e18);

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(0.0001e18, borrower);

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertGt(maxRepay, 0);
        assertGt(maxYield, 0);

        snapshot = vm.snapshot();
        collateralBefore = eTST2.balanceOf(borrower);
        debtBefore = eTST.debtOf(borrower);
        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);
        startHoax(borrower);

        assertEq(collateralBefore, eTST2.balanceOf(borrower) + maxYield);
        assertEq(debtBefore, eTST.debtOf(borrower) + maxRepay);

        // bonus grows with health score

        yieldAssets = eTST2.convertToAssets(maxYield);
        valYield = oracle.getQuote(yieldAssets, address(eTST2), unitOfAccount);
        valRepay = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);

        assertApproxEqAbs(valRepay, valYield * healthScore / 1e18, 0.000000001e18);

        vm.revertTo(snapshot);

        // discount maxes out

        oracle.setPrice(address(assetTST2), unitOfAccount, 0.15e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, false);
        healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 0.4e18, 0.01e18);

        (collateralValue, liabilityValue) = eTST.accountLiquidity(borrower, true);
        healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 0.68e18, 0.01e18);

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(0.0001e18, borrower);

        (maxRepay, maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        assertGt(maxRepay, 0);
        assertGt(maxYield, 0);

        snapshot = vm.snapshot();
        collateralBefore = eTST2.balanceOf(borrower);
        debtBefore = eTST.debtOf(borrower);
        startHoax(lender);
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);
        startHoax(borrower);

        assertEq(collateralBefore, eTST2.balanceOf(borrower) + maxYield);
        assertEq(debtBefore, eTST.debtOf(borrower) + maxRepay);

        yieldAssets = eTST2.convertToAssets(maxYield);
        valYield = oracle.getQuote(yieldAssets, address(eTST2), unitOfAccount);
        valRepay = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);

        // max discount
        assertApproxEqAbs(valRepay, valYield * (1e18 - 0.2e18) / 1e18, 0.000000001e18);
    }

    function test_setMaxLiquidationDiscount() public {
        // unauthorized
        startHoax(lender);
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setMaxLiquidationDiscount(0.1e4);

        // too big
        startHoax(address(this));
        vm.expectRevert(Errors.E_ConfigAmountTooLargeToEncode.selector);
        eTST.setMaxLiquidationDiscount(1e4 + 1);

        // set ok
        eTST.setMaxLiquidationDiscount(0.111e4);
        assertEq(0.111e4, eTST.maxLiquidationDiscount());
    }

    function test_liquidationWithCustomMaxDiscount() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);

        // enable collateral with no deposit to verify accountLiquidityFull behavior
        vm.stopPrank();
        vm.prank(borrower);
        evc.enableCollateral(borrower, address(eTST3));
        startHoax(address(this));

        oracle.setPrice(address(assetTST), unitOfAccount, 2.8e18);

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);

        uint256 healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 0.857e18, 0.001e18);

        uint256 snapshot = vm.snapshot();

        // set custom max discount - 11%
        {
            startHoax(address(this));
            eTST.setMaxLiquidationDiscount(0.11e4);
            uint256 expectedDiscountFactor = 0.89e18;

            (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));

            uint256 yieldAssets = eTST2.convertToAssets(maxYield);
            uint256 valYield = oracle.getQuote(yieldAssets, address(eTST2), unitOfAccount);
            uint256 valRepay = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);

            assertApproxEqAbs(valRepay, valYield * expectedDiscountFactor / 1e18, 0.000000001e18);

            // repay full debt
            uint256 debtOf = eTST.debtOf(borrower);
            assertEq(debtOf, maxRepay);

            startHoax(lender);
            eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

            // liquidator:
            debtOf = eTST.debtOf(lender);
            assertEq(debtOf, maxRepay);

            uint256 balance = eTST2.balanceOf(lender);
            assertEq(balance, maxYield);

            // violator:
            startHoax(borrower);
            assertEq(eTST.debtOf(borrower), 0);

            eTST.disableController();
            assertEq(evc.getControllers(borrower).length, 0);
            assertApproxEqAbs(eTST2.balanceOf(borrower), 100e18 - maxYield, 0.0000000000011e18);
        }

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        // set custom max discount - 1%
        {
            startHoax(address(this));
            eTST.setMaxLiquidationDiscount(0.01e4);
            uint256 expectedDiscountFactor = 0.99e18;

            (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));

            uint256 yieldAssets = eTST2.convertToAssets(maxYield);
            uint256 valYield = oracle.getQuote(yieldAssets, address(eTST2), unitOfAccount);
            uint256 valRepay = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);

            assertApproxEqAbs(valRepay, valYield * expectedDiscountFactor / 1e18, 0.000000001e18);

            // repay full debt
            uint256 debtOf = eTST.debtOf(borrower);
            assertEq(debtOf, maxRepay);

            startHoax(lender);
            eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

            // liquidator:
            debtOf = eTST.debtOf(lender);
            assertEq(debtOf, maxRepay);

            uint256 balance = eTST2.balanceOf(lender);
            assertEq(balance, maxYield);

            // violator:
            startHoax(borrower);
            assertEq(eTST.debtOf(borrower), 0);

            eTST.disableController();
            assertEq(evc.getControllers(borrower).length, 0);
            assertApproxEqAbs(eTST2.balanceOf(borrower), 100e18 - maxYield, 0.0000000000011e18);
        }

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        // set custom max discount - 0%
        {
            startHoax(address(this));
            eTST.setMaxLiquidationDiscount(0);
            uint256 expectedDiscountFactor = 1e18;

            (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));

            uint256 yieldAssets = eTST2.convertToAssets(maxYield);
            uint256 valYield = oracle.getQuote(yieldAssets, address(eTST2), unitOfAccount);
            uint256 valRepay = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);

            assertApproxEqAbs(valRepay, valYield * expectedDiscountFactor / 1e18, 0.000000001e18);

            // repay full debt
            uint256 debtOf = eTST.debtOf(borrower);
            assertEq(debtOf, maxRepay);

            startHoax(lender);
            eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

            // liquidator:
            debtOf = eTST.debtOf(lender);
            assertEq(debtOf, maxRepay);

            uint256 balance = eTST2.balanceOf(lender);
            assertEq(balance, maxYield);

            // violator:
            startHoax(borrower);
            assertEq(eTST.debtOf(borrower), 0);

            eTST.disableController();
            assertEq(evc.getControllers(borrower).length, 0);
            assertApproxEqAbs(eTST2.balanceOf(borrower), 100e18 - maxYield, 0.0000000000011e18);
        }

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        // set custom max discount - 0.0001% (min)
        {
            startHoax(address(this));
            eTST.setMaxLiquidationDiscount(1);
            uint256 expectedDiscountFactor = 0.9999e18;

            (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));

            uint256 yieldAssets = eTST2.convertToAssets(maxYield);
            uint256 valYield = oracle.getQuote(yieldAssets, address(eTST2), unitOfAccount);
            uint256 valRepay = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);

            assertApproxEqAbs(valRepay, valYield * expectedDiscountFactor / 1e18, 0.000000001e18);

            // repay full debt
            uint256 debtOf = eTST.debtOf(borrower);
            assertEq(debtOf, maxRepay);

            startHoax(lender);
            eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

            // liquidator:
            debtOf = eTST.debtOf(lender);
            assertEq(debtOf, maxRepay);

            uint256 balance = eTST2.balanceOf(lender);
            assertEq(balance, maxYield);

            // violator:
            startHoax(borrower);
            assertEq(eTST.debtOf(borrower), 0);

            eTST.disableController();
            assertEq(evc.getControllers(borrower).length, 0);
            assertApproxEqAbs(eTST2.balanceOf(borrower), 100e18 - maxYield, 0.0000000000011e18);
        }

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        // set custom max discount - 15% - still above the health score
        {
            startHoax(address(this));
            eTST.setMaxLiquidationDiscount(0.15e4);
            uint256 expectedDiscountFactor = healthScore;

            (uint256 maxRepay, uint256 maxYield) = eTST.checkLiquidation(lender, borrower, address(eTST2));

            uint256 yieldAssets = eTST2.convertToAssets(maxYield);
            uint256 valYield = oracle.getQuote(yieldAssets, address(eTST2), unitOfAccount);
            uint256 valRepay = oracle.getQuote(maxRepay, address(assetTST), unitOfAccount);

            assertApproxEqAbs(valRepay, valYield * expectedDiscountFactor / 1e18, 0.000000001e18);

            // repay full debt
            uint256 debtOf = eTST.debtOf(borrower);
            assertEq(debtOf, maxRepay);

            startHoax(lender);
            eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

            // liquidator:
            debtOf = eTST.debtOf(lender);
            assertEq(debtOf, maxRepay);

            uint256 balance = eTST2.balanceOf(lender);
            assertEq(balance, maxYield);

            // violator:
            startHoax(borrower);
            assertEq(eTST.debtOf(borrower), 0);

            eTST.disableController();
            assertEq(evc.getControllers(borrower).length, 0);
            assertApproxEqAbs(eTST2.balanceOf(borrower), 100e18 - maxYield, 0.0000000000011e18);
        }
    }

    function test_setCoolOff() public {
        // only admin
        startHoax(lender);
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setLiquidationCoolOffTime(1);

        startHoax(address(this));
        eTST.setLiquidationCoolOffTime(1);
        assertEq(eTST.liquidationCoolOffTime(), 1);

        eTST.setLiquidationCoolOffTime(1 hours);
        assertEq(eTST.liquidationCoolOffTime(), 1 hours);

        eTST.setLiquidationCoolOffTime(type(uint16).max);
        assertEq(eTST.liquidationCoolOffTime(), type(uint16).max);

        eTST.setLiquidationCoolOffTime(0);
        assertEq(eTST.liquidationCoolOffTime(), 0);
    }

    function test_liquidationWithCoolOff() public {
        // set up liquidator to support the debt
        startHoax(lender);
        evc.enableController(lender, address(eTST));
        evc.enableCollateral(lender, address(eTST3));
        evc.enableCollateral(lender, address(eTST2));

        startHoax(borrower);
        evc.enableController(borrower, address(eTST));
        eTST.borrow(5e18, borrower);

        startHoax(address(this));
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);

        vm.stopPrank();
        vm.prank(borrower);
        evc.enableCollateral(borrower, address(eTST3));

        // prices change inside the same block

        startHoax(address(this));

        oracle.setPrice(address(assetTST), unitOfAccount, 2.5e18);

        (uint256 collateralValue, uint256 liabilityValue) = eTST.accountLiquidity(borrower, false);

        uint256 healthScore = collateralValue * 1e18 / liabilityValue;
        assertApproxEqAbs(healthScore, 0.96e18, 0.001e18);

        uint256 snapshot = vm.snapshot();

        // 1 second
        startHoax(address(this));
        eTST.setLiquidationCoolOffTime(1 seconds);

        vm.expectRevert(Errors.E_LiquidationCoolOff.selector);
        eTST.checkLiquidation(lender, borrower, address(eTST2));

        startHoax(lender);
        vm.expectRevert(Errors.E_LiquidationCoolOff.selector);
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);

        // can liquidate one second later
        skip(1);
        (uint256 maxRepay,) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);

        vm.revertTo(snapshot);

        // 30 seconds
        startHoax(address(this));
        eTST.setLiquidationCoolOffTime(30 seconds);
        startHoax(lender);

        vm.expectRevert(Errors.E_LiquidationCoolOff.selector);
        eTST.checkLiquidation(lender, borrower, address(eTST2));

        vm.expectRevert(Errors.E_LiquidationCoolOff.selector);
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);

        // not yet
        skip(15);
        vm.expectRevert(Errors.E_LiquidationCoolOff.selector);
        eTST.checkLiquidation(lender, borrower, address(eTST2));

        vm.expectRevert(Errors.E_LiquidationCoolOff.selector);
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);

        // not yet
        skip(14);
        vm.expectRevert(Errors.E_LiquidationCoolOff.selector);
        eTST.checkLiquidation(lender, borrower, address(eTST2));

        vm.expectRevert(Errors.E_LiquidationCoolOff.selector);
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);

        // can liquidate after cool off
        skip(1);
        (maxRepay,) = eTST.checkLiquidation(lender, borrower, address(eTST2));
        eTST.liquidate(borrower, address(eTST2), maxRepay, 0);
    }

    function getRiskAdjustedValue(uint256 amount, uint256 price, uint256 factor) public pure returns (uint256) {
        return amount * price / 1e18 * factor / 1e18;
    }
}
