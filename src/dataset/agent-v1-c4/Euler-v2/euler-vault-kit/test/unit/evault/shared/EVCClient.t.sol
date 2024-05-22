// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EVaultTestBase,
    EVault,
    Base,
    Dispatch,
    TypesLib,
    GenericFactory,
    IRMTestDefault,
    TestERC20
} from "../EVaultTestBase.t.sol";
import {EVCClient, IEVC} from "../../../../src/EVault/shared/EVCClient.sol";
import "../../../../src/EVault/shared/types/Types.sol";
import {stdError} from "forge-std/StdError.sol";

contract EVCClientUnitTest is EVaultTestBase {
    using TypesLib for uint256;

    address depositor;
    address borrower;

    TestERC20 assetTST3;

    IEVault eTST3;

    function setUp() public override {
        super.setUp();

        depositor = makeAddr("depositor");
        borrower = makeAddr("borrower");

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

        vm.stopPrank();

        // create third random vault
        assetTST3 = new TestERC20("Test Token 3", "TST3", 18, false);
        eTST3 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST3), address(oracle), unitOfAccount))
        );
        eTST3.setInterestRateModel(address(new IRMTestDefault()));
    }

    function test_functionWithNo_callThroughEVC() public {
        VaultWithBug bVault = VaultWithBug(setUpBuggyVault());

        vm.startPrank(borrower);
        assetTST2.approve(address(bVault), type(uint256).max);
        bVault.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(bVault));

        vm.expectRevert(stdError.assertionError);
        bVault.borrow100X(5e18, borrower);
        vm.stopPrank();
    }

    function test_non_CONTROLLER_NEUTRAL_OPS_without_enableController() public {
        startHoax(borrower);

        // OP_BORROW
        evc.enableCollateral(borrower, address(eTST2));

        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        eTST.borrow(5e18, borrower);

        // OP_PULL_DEBT
        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        eTST.pullDebt(5e18, borrower);

        vm.stopPrank();

        // OP_LIQUIDATE
        address liquidator = makeAddr("liquidator");
        startHoax(liquidator);
        evc.enableCollateral(liquidator, address(eTST2));
        vm.expectRevert(Errors.E_ControllerDisabled.selector);
        eTST.liquidate(borrower, address(eTST2), type(uint256).max, 0);
        vm.stopPrank();
    }

    function test_validateController_E_NoLiability() public {
        startHoax(borrower);

        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        vm.stopPrank();

        address liquidator = makeAddr("liquidator");
        startHoax(liquidator);
        vm.expectRevert(Errors.E_NoLiability.selector);
        eTST.checkLiquidation(liquidator, borrower, address(eTST2));
    }

    function test_validateController_E_NotController() public {
        startHoax(borrower);

        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST2));
        vm.stopPrank();

        address liquidator = makeAddr("liquidator");
        startHoax(liquidator);
        vm.expectRevert(Errors.E_NotController.selector);
        eTST.checkLiquidation(liquidator, borrower, address(eTST2));
    }

    function test_validateController_E_TransientState() public {
        startHoax(borrower);

        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, borrower);

        evc.enableCollateral(borrower, address(eTST2));
        evc.enableController(borrower, address(eTST));

        eTST.borrow(5e18, borrower);
        assertEq(assetTST.balanceOf(borrower), 5e18);
        vm.stopPrank();

        vm.startPrank(borrower);

        address liquidator = makeAddr("liquidator");

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);

        items[0].onBehalfOfAccount = address(0);
        items[0].targetContract = address(evc);
        items[0].value = 0;
        items[0].data = abi.encodeWithSelector(evc.enableController.selector, borrower, eTST3);

        items[1].onBehalfOfAccount = borrower;
        items[1].targetContract = address(eTST);
        items[1].value = 0;
        items[1].data = abi.encodeWithSelector(EVault.checkLiquidation.selector, liquidator, borrower, address(eTST2));

        vm.expectRevert(Errors.E_TransientState.selector);
        evc.batch(items);
    }

    function setUpBuggyVault() internal returns (address) {
        vm.startPrank(admin);
        address bVaultImpl = address(new VaultWithBug(integrations, modules));
        GenericFactory factory = new GenericFactory(admin);

        factory.setImplementation(address(bVaultImpl));
        IEVault v = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST2), address(oracle), unitOfAccount))
        );
        v.setInterestRateModel(address(new IRMTestDefault()));

        return address(v);
    }
}

// a contract with a function that does not use the callThroughEVC() modifier
contract VaultWithBug is EVault {
    using TypesLib for uint256;

    constructor(Base.Integrations memory _integrations, Dispatch.DeployedModules memory _modules)
        EVault(_integrations, _modules)
    {}

    function borrow100X(uint256 amount, address receiver) public returns (uint256) {
        (VaultCache memory vaultCache, address account) = initOperation(OP_BORROW, CHECKACCOUNT_CALLER);

        Assets assets = amount == type(uint256).max ? vaultCache.cash : amount.toAssets();
        if (assets.isZero()) return 0;

        if (assets > vaultCache.cash) revert E_InsufficientCash();

        increaseBorrow(vaultCache, account, assets);

        pushAssets(vaultCache, receiver, assets);

        return assets.toUint();
    }
}
