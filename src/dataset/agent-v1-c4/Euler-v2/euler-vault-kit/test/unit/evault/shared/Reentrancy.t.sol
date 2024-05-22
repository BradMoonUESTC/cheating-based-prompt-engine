// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVault} from "../../../../src/EVault/EVault.sol";
import {Errors} from "../../../../src/EVault/shared/Errors.sol";
import {IHookTarget} from "../../../../src/interfaces/IHookTarget.sol";

import "../EVaultTestBase.t.sol";

contract EVaultTest is EVault {
    constructor(Integrations memory integrations, DeployedModules memory modules) EVault(integrations, modules) {}

    function setReentrancyLock() external {
        vaultStorage.reentrancyLocked = true;
    }
}

contract MockHookTarget is Test, IHookTarget {
    EVault eTST;

    function setEVault(address vault) public {
        eTST = EVault(vault);
    }

    function isHookTarget() external pure override returns (bytes4) {
        return this.isHookTarget.selector;
    }

    fallback(bytes calldata data) external returns (bytes memory) {
        address account1 = address(uint160(uint256(keccak256(abi.encodePacked(data, "account1")))));
        address account2 = address(uint160(uint256(keccak256(abi.encodePacked(data, "account2")))));
        uint256 amount1 = uint256(keccak256(abi.encodePacked(data, "amount1")));
        uint256 amount2 = uint256(keccak256(abi.encodePacked(data, "amount2")));

        eTST.name();
        eTST.symbol();
        eTST.decimals();
        eTST.totalSupply();
        eTST.balanceOf(account1);
        eTST.allowance(account1, account2);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.transfer(account1, amount1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.transferFrom(account1, account2, amount1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.approve(account1, amount1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.transferFromMax(account1, account2);

        eTST.asset();
        eTST.totalAssets();
        eTST.convertToAssets(uint112(bound(amount1, 0, type(uint112).max)));
        eTST.convertToShares(uint112(bound(amount1, 0, type(uint112).max)));
        eTST.maxDeposit(account1);
        eTST.previewDeposit(uint112(bound(amount1, 0, type(uint112).max)));
        eTST.maxMint(account1);
        eTST.previewMint(uint112(bound(amount1, 0, type(uint112).max)));
        eTST.maxWithdraw(account1);
        eTST.previewWithdraw(uint112(bound(amount1, 0, type(uint112).max)));
        eTST.maxRedeem(account1);
        eTST.previewRedeem(uint112(bound(amount1, 0, type(uint112).max)));
        eTST.accumulatedFees();
        eTST.accumulatedFeesAssets();
        eTST.creator();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.deposit(amount1, account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.mint(amount1, account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.withdraw(amount1, account1, account2);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.redeem(amount1, account1, account2);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.skim(amount1, account1);

        eTST.totalBorrows();
        eTST.totalBorrowsExact();
        eTST.cash();
        eTST.debtOf(account1);
        eTST.debtOfExact(account1);
        eTST.interestRate();
        eTST.interestAccumulator();
        eTST.dToken();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.borrow(amount1, account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.repay(amount1, account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.repayWithShares(amount1, account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.pullDebt(amount1, account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.flashLoan(amount1, "");

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.touch();

        vm.expectRevert(Errors.E_BadCollateral.selector);
        eTST.checkLiquidation(account1, account2, account2);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.liquidate(account1, account2, amount1, amount2);

        vm.expectRevert(Errors.E_NoLiability.selector);
        eTST.accountLiquidity(account1, true);

        vm.expectRevert(Errors.E_NoLiability.selector);
        eTST.accountLiquidityFull(account1, false);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.disableController();

        eTST.balanceTrackerAddress();
        eTST.balanceForwarderEnabled(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.enableBalanceForwarder();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.disableBalanceForwarder();

        eTST.governorAdmin();
        eTST.feeReceiver();
        eTST.interestFee();
        eTST.interestRateModel();
        eTST.protocolConfigAddress();
        eTST.protocolFeeShare();
        eTST.protocolFeeReceiver();
        eTST.caps();
        eTST.LTVBorrow(account1);
        eTST.LTVLiquidation(account1);
        eTST.LTVFull(account1);
        eTST.LTVList();
        eTST.hookConfig();
        eTST.configFlags();
        eTST.EVC();
        eTST.unitOfAccount();
        eTST.oracle();
        eTST.permit2Address();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.convertFees();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setGovernorAdmin(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setFeeReceiver(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setLTV(
            account1,
            uint16(bound(amount1, 0, type(uint16).max)),
            uint16(bound(amount1, 0, type(uint16).max)),
            uint32(bound(amount2, 0, type(uint32).max))
        );

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.clearLTV(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setInterestRateModel(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setHookConfig(account1, uint32(bound(amount2, 0, OP_MAX_VALUE - 1)));

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setConfigFlags(uint32(bound(amount2, 0, CFG_MAX_VALUE - 1)));

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setCaps(uint16(bound(amount1, 0, type(uint16).max)), uint16(bound(amount2, 0, type(uint16).max)));

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setInterestFee(uint16(bound(amount1, 0, type(uint16).max)));

        return "";
    }
}

contract ReentrancyTest is EVaultTestBase {
    function setUp() public override {
        super.setUp();
    }

    function testFuzz_nonReentrant_nonReentrantView(
        address sender,
        uint256 amount1,
        uint256 amount2,
        address account1,
        address account2
    ) public {
        address evaultImpl = address(new EVaultTest(integrations, modules));

        vm.prank(admin);
        factory.setImplementation(evaultImpl);

        eTST = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );

        vm.assume(sender != address(0) && sender != address(eTST));

        (bool success,) = address(eTST).call(abi.encodeWithSignature("setReentrancyLock()"));
        require(success, "setReentrancyLock failed");

        vm.startPrank(sender);

        eTST.name();
        eTST.symbol();
        eTST.decimals();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.totalSupply();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.balanceOf(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.allowance(account1, account2);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.transfer(account1, amount1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.transferFrom(account1, account2, amount1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.approve(account1, amount1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.transferFromMax(account1, account2);

        eTST.asset();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.totalAssets();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.convertToAssets(uint112(bound(amount1, 0, type(uint112).max)));

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.convertToShares(uint112(bound(amount1, 0, type(uint112).max)));

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.maxDeposit(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.previewDeposit(uint112(bound(amount1, 0, type(uint112).max)));

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.maxMint(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.previewMint(uint112(bound(amount1, 0, type(uint112).max)));

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.maxWithdraw(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.previewWithdraw(uint112(bound(amount1, 0, type(uint112).max)));

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.maxRedeem(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.previewRedeem(uint112(bound(amount1, 0, type(uint112).max)));

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.accumulatedFees();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.accumulatedFeesAssets();

        eTST.creator();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.deposit(amount1, account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.mint(amount1, account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.withdraw(amount1, account1, account2);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.redeem(amount1, account1, account2);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.skim(amount1, account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.totalBorrows();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.totalBorrowsExact();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.cash();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.debtOf(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.debtOfExact(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.interestRate();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.interestAccumulator();

        eTST.dToken();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.borrow(amount1, account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.repay(amount1, account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.repayWithShares(amount1, account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.pullDebt(amount1, account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.flashLoan(amount1, "");

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.touch();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.checkLiquidation(account1, account2, account2);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.liquidate(account1, account2, amount1, amount2);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.accountLiquidity(account1, true);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.accountLiquidityFull(account1, false);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.disableController();

        eTST.balanceTrackerAddress();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.balanceForwarderEnabled(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.enableBalanceForwarder();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.disableBalanceForwarder();

        eTST.governorAdmin();
        eTST.feeReceiver();
        eTST.interestFee();
        eTST.interestRateModel();
        eTST.protocolConfigAddress();
        eTST.protocolFeeShare();
        eTST.protocolFeeReceiver();
        eTST.caps();
        eTST.LTVBorrow(account1);
        eTST.LTVLiquidation(account1);
        eTST.LTVFull(account1);
        eTST.LTVList();
        eTST.hookConfig();
        eTST.configFlags();
        eTST.EVC();
        eTST.unitOfAccount();
        eTST.oracle();
        eTST.permit2Address();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.convertFees();

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setGovernorAdmin(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setFeeReceiver(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setLTV(
            account1,
            uint16(bound(amount1, 0, type(uint16).max)),
            uint16(bound(amount1, 0, type(uint16).max)),
            uint32(bound(amount2, 0, type(uint32).max))
        );

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.clearLTV(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setInterestRateModel(account1);

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setHookConfig(account1, uint32(bound(amount2, 0, OP_MAX_VALUE - 1)));

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setConfigFlags(uint32(bound(amount2, 0, CFG_MAX_VALUE - 1)));

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setCaps(uint16(bound(amount1, 0, type(uint16).max)), uint16(bound(amount2, 0, type(uint16).max)));

        vm.expectRevert(Errors.E_Reentrancy.selector);
        eTST.setInterestFee(uint16(bound(amount1, 0, type(uint16).max)));
    }

    function test_hookTargetAllowed_nonReentrantView() public {
        address hookTarget = address(new MockHookTarget());

        eTST.setHookConfig(hookTarget, OP_TRANSFER);
        MockHookTarget(hookTarget).setEVault(address(eTST));

        eTST.transfer(address(2), 0);
    }
}
