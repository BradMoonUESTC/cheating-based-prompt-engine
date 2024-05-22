// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {IEVault} from "../../../../../src/EVault/IEVault.sol";
import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {TestERC20} from "../../../../mocks/TestERC20.sol";
import {IRMTestFixed} from "../../../../mocks/IRMTestFixed.sol";
import {IRMTestZero} from "../../../../mocks/IRMTestZero.sol";
import "../../../../../src/EVault/shared/types/Types.sol";
import {Errors as EVCErrors} from "ethereum-vault-connector/Errors.sol";

contract VaultTest_Liquidity is EVaultTestBase {
    address user1;
    address user2;
    address user3;

    TestERC20 assetTST3;
    IEVault public eTST3;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        assetTST3 = new TestERC20("Test TST 3", "TST3", 18, false);

        eTST3 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST3), address(oracle), unitOfAccount))
        );

        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestZero()));
        eTST2.setInterestRateModel(address(new IRMTestZero()));
        eTST3.setInterestRateModel(address(new IRMTestZero()));

        eTST.setLTV(address(eTST2), 0.3e4, 0.3e4, 0);
        eTST2.setLTV(address(eTST), 0.3e4, 0.3e4, 0);
        eTST3.setLTV(address(eTST), 0.3e4, 0.3e4, 0);
        eTST3.setLTV(address(eTST2), 0.3e4, 0.3e4, 0);

        startHoax(user1);
        assetTST.approve(address(eTST), type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        evc.enableCollateral(user1, address(eTST));
        evc.enableCollateral(user1, address(eTST2));

        startHoax(user2);
        assetTST.approve(address(eTST), type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        evc.enableCollateral(user2, address(eTST));
        evc.enableCollateral(user2, address(eTST2));

        startHoax(user3);
        assetTST.approve(address(eTST), type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        evc.enableCollateral(user3, address(eTST));
        evc.enableCollateral(user3, address(eTST2));

        assetTST.mint(user1, 100e18);
        assetTST2.mint(user2, 100e18);
        assetTST2.mint(user3, 100e18);

        startHoax(user1);
        eTST.deposit(10e18, user1);

        startHoax(user2);
        eTST2.deposit(10e18, user2);

        oracle.setPrice(address(eTST), unitOfAccount, 2e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 0.083e18);

        skip(31 * 60);
    }

    function test_borrowIsolation() public {
        startHoax(user2);
        evc.enableController(user2, address(eTST));
        eTST.borrow(0.1e18, user2);

        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        eTST2.borrow(0.00000000001e18, user2);

        vm.expectRevert(EVCErrors.EVC_ControllerViolation.selector);
        evc.enableController(user2, address(eTST2));
    }

    function test_simpleLiquidity() public {
        startHoax(user2);
        evc.enableController(user2, address(eTST));
        eTST.borrow(0.1e18, user2);

        (, uint256[] memory collateralValues, uint256 liabilityValue) = eTST.accountLiquidityFull(user2, false);
        assertEq(collateralValues[0], 0);
        assertEq(collateralValues[1], (10 * 0.083 * 0.75 * 0.4) * 1e18);
        assertEq(liabilityValue, (0.1 * 2) * 1e18);

        // No liquidation possible:
        startHoax(user1);
        evc.enableController(user1, address(eTST));
        vm.expectRevert(Errors.E_ExcessiveRepayAmount.selector);
        eTST.liquidate(user2, address(eTST2), 1e18, 0);

        startHoax(user2);
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.borrow(0.0246e18, user2);

        eTST.borrow(0.0244e18, user2);

        (, collateralValues, liabilityValue) = eTST.accountLiquidityFull(user2, false);
        assertEq(collateralValues[0], 0);
        assertEq(collateralValues[1], (10 * 0.083 * 0.75 * 0.4) * 1e18);
        assertEq(liabilityValue, (0.1 + 0.0244) * 2 * 1e18);

        assertEq(eTST.debtOf(user2), 0.1244e18);
    }

    function test_transferEToken() public {
        startHoax(user2);
        evc.enableController(user2, address(eTST));
        eTST.borrow(0.1e18, user2);

        assertEq(eTST2.balanceOf(user2), 10e18);
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST2.transfer(user3, 10e18);

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST2.transfer(user3, 1.969e18);

        eTST2.transfer(user3, 1.967e18);

        (, uint256[] memory collateralValues, uint256 liabilityValue) = eTST.accountLiquidityFull(user2, false);
        assertApproxEqAbs(liabilityValue, 0.2 * 1e18, 0.001e18);
        assertApproxEqAbs(collateralValues[1], 0.2 * 1e18, 0.001e18);

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST2.transfer(user3, 0.002e18);
    }

    function test_pullDebt() public {
        startHoax(user2);
        evc.enableController(user2, address(eTST));
        eTST.borrow(0.1e18, user2);

        (, uint256[] memory collateralValues, uint256 liabilityValue) = eTST.accountLiquidityFull(user2, false);
        assertApproxEqAbs(liabilityValue, 0.2 * 1e18, 0);

        startHoax(user3);
        eTST2.deposit(6e18, user3);

        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        eTST.pullDebt(0.0748e18, user2);

        evc.enableController(user3, address(eTST));

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        eTST.pullDebt(0.0748e18, user2);

        eTST.pullDebt(0.0746e18, user2);

        (, collateralValues, liabilityValue) = eTST.accountLiquidityFull(user3, false);
        assertApproxEqAbs(liabilityValue, 0.1494 * 1e18, 0.01e18);
        assertApproxEqAbs(collateralValues[1], (6 * 0.083 * 0.75 * 0.4) * 1e18, 0.001e18);

        (, collateralValues, liabilityValue) = eTST.accountLiquidityFull(user2, false);
        assertApproxEqAbs(liabilityValue, (0.2 - 0.1494) * 1e18, 0.01e18);
        assertApproxEqAbs(collateralValues[1], (10 * 0.083 * 0.75 * 0.4) * 1e18, 0.01e18);
    }

    function test_pullAllDebt() public {
        startHoax(user2);
        evc.enableController(user2, address(eTST));
        eTST.borrow(0.1e18, user2);

        (, uint256[] memory collateralValues, uint256 liabilityValue) = eTST.accountLiquidityFull(user2, false);
        assertApproxEqAbs(liabilityValue, 0.2 * 1e18, 0);

        // wallet3 deposits 10 TST2, same as wallet2
        startHoax(user3);
        eTST2.deposit(10e18, user3);
        evc.enableController(user3, address(eTST));

        // transfer full debt
        eTST.pullDebt(type(uint256).max, user2);

        (, collateralValues, liabilityValue) = eTST.accountLiquidityFull(user3, false);
        assertApproxEqAbs(liabilityValue, 0.2 * 1e18, 0.01e18);
        assertApproxEqAbs(collateralValues[1], (10 * 0.083 * 0.75 * 0.4) * 1e18, 0.001e18);

        startHoax(user2);
        eTST.disableController();

        vm.expectRevert(Errors.E_NoLiability.selector);
        eTST.accountLiquidityFull(user2, false);
    }

    function test_disableCollateral() public {
        assertEq(evc.getCollaterals(user2).length, 2);
        assertEq(evc.getCollaterals(user2)[0], address(eTST));
        assertEq(evc.getCollaterals(user2)[1], address(eTST2));

        startHoax(user2);
        evc.enableController(user2, address(eTST));
        eTST.borrow(0.1e18, user2);

        // can exit collateral from liability market
        evc.disableCollateral(user2, address(eTST));
        assertEq(evc.getCollaterals(user2).length, 1);
        assertEq(evc.getCollaterals(user2)[0], address(eTST2));

        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        evc.disableCollateral(user2, address(eTST2));

        assetTST.mint(user2, 1e18);
        eTST.repay(type(uint256).max, user2);
        evc.disableCollateral(user2, address(eTST2));
        eTST.disableController();

        assertEq(evc.getCollaterals(user2).length, 0);
        assertEq(evc.getControllers(user2).length, 0);
    }
}
