// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {Errors as EVCErrors} from "ethereum-vault-connector/Errors.sol";
import {IEVault} from "../../../../../src/EVault/IEVault.sol";
import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {TestERC20} from "../../../../mocks/TestERC20.sol";
import {IRMTestZero} from "../../../../mocks/IRMTestZero.sol";
import "../../../../../src/EVault/shared/types/Types.sol";

contract VaultTest_BorrowIsolation is EVaultTestBase {
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

        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestZero()));
        eTST2.setInterestRateModel(address(new IRMTestZero()));
        eTST3.setInterestRateModel(address(new IRMTestZero()));

        eTST2.setLTV(address(eTST), 0.3e4, 0.3e4, 0);
        eTST.setLTV(address(eTST2), 0.3e4, 0.3e4, 0);
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

        assetTST.mint(user1, 100e18);
        assetTST2.mint(user2, 100e18);

        startHoax(user1);
        eTST.deposit(10e18, user1);

        startHoax(user2);
        eTST2.deposit(10e18, user2);

        oracle.setPrice(address(eTST), unitOfAccount, 2e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 0.083e18);

        skip(31 * 60);
    }

    function test_borrowIsolated() public {
        // First borrow is OK
        startHoax(user2);
        evc.enableController(user2, address(eTST));
        eTST.borrow(0.1e18, user2);

        // Can't enable another controller
        vm.expectRevert(EVCErrors.EVC_ControllerViolation.selector);
        evc.enableController(user2, address(eTST2));
    }

    //multiple borrows are possible while in deferred liquidity
    function test_multipleBorrows() public {
        startHoax(user2);
        evc.enableController(user2, address(eTST));
        eTST.borrow(0.1e18, user2);

        // second borrow reverts
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 0.00000000001e18, user2)
        });

        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        evc.batch(items);

        // unless it's repaid in the same batch
        items = new IEVC.BatchItem[](4);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user2, address(eTST2))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 0.00000000001e18, user2)
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.repay.selector, type(uint256).max, user2)
        });
        items[3] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.disableController.selector)
        });

        evc.batch(items);
        assertEq(eTST2.debtOf(user2), 0);

        // 3rd borrow
        // outstanding borrow
        assetTST3.mint(user1, 100e18);
        startHoax(user1);
        assetTST3.approve(address(eTST3), type(uint256).max);
        eTST3.deposit(100e18, user1);

        items = new IEVC.BatchItem[](6);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user2, address(eTST2))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user2, address(eTST3))
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 0.00000000001e18, user2)
        });
        items[3] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST3),
            value: 0,
            data: abi.encodeWithSelector(eTST3.borrow.selector, 0.00000000001e18, user2)
        });
        items[4] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.repay.selector, type(uint256).max, user2)
        });
        items[5] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.disableController.selector)
        });

        startHoax(user2);
        vm.expectRevert(EVCErrors.EVC_ControllerViolation.selector);
        evc.batch(items);

        // both repaid
        assetTST3.approve(address(eTST3), type(uint256).max);

        items = new IEVC.BatchItem[](8);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user2, address(eTST2))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user2, address(eTST3))
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 0.00000000001e18, user2)
        });
        items[3] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST3),
            value: 0,
            data: abi.encodeWithSelector(eTST3.borrow.selector, 0.00000000001e18, user2)
        });
        items[4] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.repay.selector, type(uint256).max, user2)
        });
        items[5] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.disableController.selector)
        });
        items[6] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST3),
            value: 0,
            data: abi.encodeWithSelector(eTST3.repay.selector, type(uint256).max, user2)
        });
        items[7] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST3),
            value: 0,
            data: abi.encodeWithSelector(eTST3.disableController.selector)
        });

        evc.batch(items);

        assertEq(eTST3.debtOf(user2), 0);
        assertEq(eTST2.debtOf(user2), 0);
        assertEq(evc.getControllers(user2)[0], address(eTST));

        // both repaid in reverse order
        assetTST3.approve(address(eTST3), type(uint256).max);

        items = new IEVC.BatchItem[](8);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user2, address(eTST2))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user2, address(eTST3))
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 0.00000000001e18, user2)
        });
        items[3] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST3),
            value: 0,
            data: abi.encodeWithSelector(eTST3.borrow.selector, 0.00000000001e18, user2)
        });
        items[4] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST3),
            value: 0,
            data: abi.encodeWithSelector(eTST3.repay.selector, type(uint256).max, user2)
        });
        items[5] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST3),
            value: 0,
            data: abi.encodeWithSelector(eTST3.disableController.selector)
        });
        items[6] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.repay.selector, type(uint256).max, user2)
        });
        items[7] = IEVC.BatchItem({
            onBehalfOfAccount: user2,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.disableController.selector)
        });

        evc.batch(items);

        assertEq(eTST3.debtOf(user2), 0);
        assertEq(eTST2.debtOf(user2), 0);
        assertEq(evc.getControllers(user2)[0], address(eTST));
    }
}
