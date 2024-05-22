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

contract VaultTest_PullDebt is EVaultTestBase {
    address user1;
    address user2;

    TestERC20 assetTST3;
    IEVault public eTST3;

    TestERC20 assetTST4;
    IEVault public eTST4;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        assetTST3 = new TestERC20("Test TST 3", "TST3", 18, false);
        assetTST4 = new TestERC20("Test TST 3", "TST3", 6, false);

        eTST3 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST3), address(oracle), unitOfAccount))
        );
        eTST4 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST4), address(oracle), unitOfAccount))
        );

        eTST.setInterestRateModel(address(new IRMTestZero()));
        eTST4.setInterestRateModel(address(new IRMTestZero()));

        startHoax(user1);
        assetTST.approve(address(eTST), type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        assetTST3.approve(address(eTST3), type(uint256).max);
        assetTST4.approve(address(eTST4), type(uint256).max);

        startHoax(user2);
        assetTST.approve(address(eTST), type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        assetTST3.approve(address(eTST3), type(uint256).max);
        assetTST4.approve(address(eTST4), type(uint256).max);

        assetTST.mint(user1, 100e18);
        assetTST3.mint(user1, 1000e18);
        assetTST4.mint(user1, 100e18);

        assetTST2.mint(user2, 100e18);
        assetTST3.mint(user2, 100e18);
        assetTST4.mint(user2, 100e18);

        startHoax(user1);
        eTST.deposit(1e18, user1);
        eTST3.deposit(1000e18, user1);
        eTST4.deposit(1e18, user1);
        evc.enableCollateral(user1, address(eTST));
        evc.enableCollateral(user1, address(eTST3));

        startHoax(user2);
        eTST2.deposit(50e18, user2);
        eTST3.deposit(1e18, user2);
        eTST4.deposit(1e18, user2);
        evc.enableCollateral(user2, address(eTST2));
        evc.enableCollateral(user2, address(eTST3));
        evc.enableCollateral(user2, address(eTST4));

        oracle.setPrice(address(eTST), unitOfAccount, 0.01e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 0.05e18);
        oracle.setPrice(address(eTST3), unitOfAccount, 0.00001e18);
        oracle.setPrice(address(eTST4), unitOfAccount, 0.00001e18);

        skip(31 * 60);

        startHoax(address(this));
        eTST.setLTV(address(eTST2), 0.3e4, 0.3e4, 0);
        eTST.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);
        eTST4.setLTV(address(eTST2), 0.3e4, 0.3e4, 0);
        eTST4.setLTV(address(eTST3), 0.95e4, 0.95e4, 0);
    }

    //basic transfers to self
    function test_pullDebt_basic() public {
        startHoax(user2);
        evc.enableController(user2, address(eTST));
        eTST.borrow(0.25e18, user2);

        assertEq(eTST.debtOf(user1), 0);
        assertEq(eTST.debtOf(user2), 0.25e18);

        startHoax(user1);
        evc.enableController(user1, address(eTST));

        // can't pullDebt to self
        startHoax(user2);
        vm.expectRevert(Errors.E_SelfTransfer.selector);
        eTST.pullDebt(0.1e18, user2);

        // but you can always transferFrom to yourself from someone else (assuming you have enough collateral)
        startHoax(user1);
        vm.expectEmit();
        emit Events.Transfer(user2, address(0), 0.1e18);
        vm.expectEmit();
        emit Events.Transfer(address(0), user1, 0.1e18);
        eTST.pullDebt(0.1e18, user2);

        assertEq(eTST.debtOf(user1), 0.1e18);
        assertEq(eTST.debtOf(user2), 0.15e18);

        assertEq(evc.getCollaterals(user1)[0], address(eTST));
        assertEq(evc.getCollaterals(user1)[1], address(eTST3));

        // Add some interest-dust, and then do a max transfer
        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        skip(1800);

        startHoax(user1);
        eTST.pullDebt(type(uint256).max, user2);

        assertApproxEqAbs(eTST.debtOf(user1), 0.2500014e18, 0.0000001e18);
        assertEq(eTST.debtOf(user2), 0);
    }

    function test_pullDebt_lowerDecimals_partialTransfer() public {
        startHoax(address(this));
        eTST4.setInterestRateModel(address(new IRMTestFixed()));

        startHoax(user2);
        evc.enableController(user2, address(eTST4));
        evc.enableController(getSubAccount(user2, 1), address(eTST4));

        eTST4.borrow(8000e6, user2);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: getSubAccount(user2, 1),
            targetContract: address(eTST4),
            value: 0,
            data: abi.encodeWithSelector(eTST4.pullDebt.selector, type(uint256).max, user2)
        });
        startHoax(user2);
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        evc.batch(items);

        eTST2.deposit(50e18, user2);
        eTST2.transfer(getSubAccount(user2, 1), 50e18);
        evc.enableCollateral(getSubAccount(user2, 1), address(eTST2));

        skip(60);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: getSubAccount(user2, 1),
            targetContract: address(eTST4),
            value: 0,
            data: abi.encodeWithSelector(eTST4.pullDebt.selector, 1000e6, user2)
        });

        vm.expectEmit();
        emit Events.Transfer(user2, address(0), 999.998477e6);
        vm.expectEmit();
        emit Events.Transfer(address(0), getSubAccount(user2, 1), 1000e6);
        evc.batch(items);

        assertEq(eTST4.debtOf(user2), 7000.001523e6);
        assertEq(eTST4.debtOf(getSubAccount(user2, 1)), 1000e6);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: getSubAccount(user2, 1),
            targetContract: address(eTST4),
            value: 0,
            data: abi.encodeWithSelector(eTST4.pullDebt.selector, 7000.01e6, user2)
        });

        vm.expectRevert(Errors.E_InsufficientDebt.selector);
        evc.batch(items);

        skip(10);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: getSubAccount(user2, 1),
            targetContract: address(eTST4),
            value: 0,
            data: abi.encodeWithSelector(eTST4.pullDebt.selector, 7000e6, user2)
        });
        evc.batch(items);

        assertEq(eTST4.debtOf(user2), 0.001745e6);
    }

    function test_pullDebt_lowerDecimals_fullTransfer() public {
        startHoax(address(this));
        eTST4.setInterestRateModel(address(new IRMTestFixed()));

        startHoax(user2);
        evc.enableController(user2, address(eTST4));
        evc.enableController(getSubAccount(user2, 1), address(eTST4));

        eTST4.borrow(8000e6, user2);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: getSubAccount(user2, 1),
            targetContract: address(eTST4),
            value: 0,
            data: abi.encodeWithSelector(eTST4.pullDebt.selector, type(uint256).max, user2)
        });
        vm.expectRevert(Errors.E_AccountLiquidity.selector);
        evc.batch(items);

        eTST2.deposit(50e18, user2);
        eTST2.transfer(getSubAccount(user2, 1), 50e18);
        evc.enableCollateral(getSubAccount(user2, 1), address(eTST2));

        skip(60);

        evc.batch(items);

        assertEq(eTST4.debtOf(user2), 0);
        assertEq(eTST4.debtOf(getSubAccount(user2, 1)), 8000.001523e6);
    }
}
