// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {IRMTestLinear} from "../../../../mocks/IRMTestLinear.sol";
import {SafeERC20Lib} from "../../../../../src/EVault/shared/lib/SafeERC20Lib.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

contract VaultTest_MaliciousToken is EVaultTestBase {
    address user1;
    address user2;
    address user3;

    uint256 maxRepay;
    uint256 maxYield;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        startHoax(address(this));
        eTST2.setLTV(address(eTST), 0.3e4, 0.3e4, 0);

        assetTST.mint(user1, 200e18);
        startHoax(user1);
        assetTST.approve(address(eTST), type(uint256).max);
        eTST.deposit(100e18, user1);
        evc.enableCollateral(user1, address(eTST));

        assetTST2.mint(user2, 100e18);
        startHoax(user2);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(100e18, user1);

        assetTST.mint(user3, 1000e18);
        startHoax(user3);
        assetTST.approve(address(eTST), type(uint256).max);
        eTST.deposit(1000e18, user3);
        evc.enableCollateral(user3, address(eTST));

        assetTST2.approve(address(eTST2), type(uint256).max);

        oracle.setPrice(address(eTST), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 1e18);
    }

    function test_transferRetunsVoid() public {
        assetTST.configure("transfer/return-void", bytes("0"));
        startHoax(user1);
        vm.expectRevert(Errors.E_InsufficientBalance.selector);
        eTST.withdraw(101e18, user1, user1);
        eTST.withdraw(100e18, user1, user1);
        assertEq(eTST.balanceOf(user1), 0);
        assertEq(assetTST.balanceOf(user1), 200e18);
    }

    function test_transferFromReturnsVoid() public {
        assetTST.configure("transfer-from/return-void", bytes("0"));
        startHoax(user1);
        eTST.deposit(100e18, user1);
        assertEq(eTST.balanceOf(user1), 200e18);
        assertEq(assetTST.balanceOf(user1), 0);
    }

    function test_borrow_transferReverts() public {
        assetTST.configure("transfer/revert", bytes("0"));
        startHoax(user2);
        evc.enableController(user2, address(eTST));
        vm.expectRevert("revert behaviour");
        eTST.borrow(1e18, user2);
    }

    function test_withdraw_transferReverts() public {
        assetTST.configure("transfer/revert", bytes("0"));
        startHoax(user1);
        vm.expectRevert("revert behaviour");
        eTST.withdraw(1e18, user1, user1);
    }

    function test_repay_transferFromReverts() public {
        startHoax(user3);
        evc.enableController(user3, address(eTST2));
        eTST2.borrow(1e18, user3);
        assetTST2.mint(user3, 1e18);
        assetTST2.configure("transfer-from/revert", bytes("0"));
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Lib.E_TransferFromFailed.selector,
                abi.encodeWithSignature("Error(string)", "revert behaviour"),
                abi.encodeWithSelector(IAllowanceTransfer.AllowanceExpired.selector, 0)
            )
        );
        eTST2.repay(1e18, user3);
    }

    function test_deposit_transferFromReverts() public {
        assetTST.configure("transfer-from/revert", bytes("0"));
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Lib.E_TransferFromFailed.selector,
                abi.encodeWithSignature("Error(string)", "revert behaviour"),
                abi.encodeWithSelector(IAllowanceTransfer.AllowanceExpired.selector, 0)
            )
        );
        startHoax(user1);
        eTST.deposit(1e18, user1);
    }

    function test_deposit_transferFromReenters() public {
        assetTST.configure(
            "transfer-from/call",
            abi.encode(address(eTST), abi.encodeWithSelector(eTST.withdraw.selector, 1e18, user1, user1))
        );
        startHoax(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Lib.E_TransferFromFailed.selector,
                abi.encodeWithSignature("E_Reentrancy()"),
                abi.encodeWithSelector(IAllowanceTransfer.AllowanceExpired.selector, 0)
            )
        );
        eTST.deposit(1e18, user1);
    }

    function test_deposit_transferFromReentersViewMethod() public {
        assetTST.configure(
            "transfer-from/call", abi.encode(address(eTST), abi.encodeWithSelector(eTST.maxWithdraw.selector, user1))
        );
        startHoax(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Lib.E_TransferFromFailed.selector,
                abi.encodeWithSignature("E_Reentrancy()"),
                abi.encodeWithSelector(IAllowanceTransfer.AllowanceExpired.selector, 0)
            )
        );
        eTST.deposit(1e18, user1);
    }

    function test_canLiquidate_transferReverts() public {
        setupLiquidation();
        assetTST2.configure("transfer/revert", bytes("0"));
        verifyLiquidation();
    }

    function test_canLiquidate_transferFromReverts() public {
        setupLiquidation();
        assetTST2.configure("transfer-from/revert", bytes("0"));
        verifyLiquidation();
    }

    function test_canLiquidate_balanceOfConsumesAllGas() public {
        setupLiquidation();
        assetTST2.configure("balance-of/consume-all-gas", bytes("0"));
        verifyLiquidation();
    }

    function test_canLiquidate_balanceOfReturnsMaxUint() public {
        setupLiquidation();
        assetTST2.configure("balance-of/set-amount", abi.encode(type(uint256).max));
        verifyLiquidation();
    }

    function test_canLiquidate_balanceOfReturnsZero() public {
        setupLiquidation();
        assetTST2.configure("balance-of/set-amount", abi.encode(0));
        verifyLiquidation();
    }

    function test_canLiquidate_balanceOfReverts() public {
        setupLiquidation();
        assetTST2.configure("balance-of/revert", bytes("0"));
        verifyLiquidation();
    }

    function test_canLiquidate_balanceOfPanics() public {
        setupLiquidation();
        assetTST2.configure("balance-of/panic", bytes("0"));
        verifyLiquidation();
    }

    function setupLiquidation() internal {
        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestLinear()));
        eTST2.setInterestRateModel(address(new IRMTestLinear()));

        startHoax(user1);
        evc.enableController(user1, address(eTST2));
        eTST2.borrow(29e18, user1);

        oracle.setPrice(address(eTST), unitOfAccount, 0.5e18);

        (maxRepay, maxYield) = eTST2.checkLiquidation(user3, user1, address(eTST));
        (uint256 collateralValue, uint256 liabilityValue) = eTST2.accountLiquidity(user1, false);
        assertApproxEqAbs(collateralValue * 1e18 / liabilityValue, 0.5e18, 0.02e18);

        startHoax(user3);
        evc.enableController(user3, address(eTST2));
    }

    function verifyLiquidation() internal {
        startHoax(user3);
        eTST2.liquidate(user1, address(eTST), maxRepay, 0);

        // liquidator:
        assertEq(eTST2.debtOf(user3), maxRepay);
        assertApproxEqAbs(eTST.balanceOf(user3), 1000e18 + maxYield, 0.000001e18);

        // violator:
        assertApproxEqAbs(eTST2.debtOf(user1), 29e18 - maxRepay, 0.1e18);
        assertApproxEqAbs(eTST.balanceOf(user1), 100e18 - maxYield, 0.000001e18);
    }
}
