// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase, EthereumVaultConnector, IEVault} from "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {IHookTarget} from "../../../../../src/interfaces/IHookTarget.sol";
import "../../../../../src/EVault/shared/Constants.sol";

contract MockHookTarget is IHookTarget {
    bytes32 internal expectedDataHash;

    error UnexpectedError();
    error ExpectedData();
    error EVC_ChecksReentrancy();

    function setExpectedDataHash(bytes32 _expectedDataHash) public {
        expectedDataHash = _expectedDataHash;
    }

    function isHookTarget() external pure override returns (bytes4) {
        return this.isHookTarget.selector;
    }

    fallback() external {
        // test reentrancy protection
        if (bytes4(msg.data) == IEVault(msg.sender).checkVaultStatus.selector) {
            try IEVault(msg.sender).touch() {
                revert UnexpectedError();
            } catch (bytes memory reason) {
                if (bytes4(reason) != EVC_ChecksReentrancy.selector) revert UnexpectedError();
            }

            try IEVault(msg.sender).approve(address(0), 0) {
                revert UnexpectedError();
            } catch (bytes memory reason) {
                if (bytes4(reason) != Errors.E_Reentrancy.selector) revert UnexpectedError();
            }

            // view functions are still reentrant for the hook target
            IEVault(msg.sender).totalSupply();
            IEVault(msg.sender).balanceOf(address(0));
        }

        if (expectedDataHash == keccak256(msg.data)) revert ExpectedData();
    }
}

contract MockHookTargetReturnVoid {
    function isHookTarget() external pure {}
}

contract MockHookTargetReturnWrongSelector {
    function isHookTarget() external pure returns (bytes4) {
        return bytes4("123");
    }
}

contract Governance_HookedOps is EVaultTestBase {
    address notGovernor;
    address borrower;
    address depositor;
    address liquidator1;
    address liquidator2;
    uint256 constant MINT_AMOUNT = 100e18;

    function setUp() public override {
        super.setUp();
    }

    function getHookCalldata(bytes memory data, address sender) internal view returns (bytes memory) {
        data = abi.encodePacked(data, eTST.asset(), eTST.oracle(), eTST.unitOfAccount());

        if (sender != address(0)) data = abi.encodePacked(data, sender);

        return data;
    }

    function test_revertWhen_wrongHookTarget() public {
        // isHookTarget not implemented
        address hookTarget = address(evc);
        vm.expectRevert();
        eTST.setHookConfig(hookTarget, OP_DEPOSIT);

        // isHookTarget returns nothing
        hookTarget = address(new MockHookTargetReturnVoid());
        vm.expectRevert();
        eTST.setHookConfig(hookTarget, OP_DEPOSIT);

        // isHookTarget returns wrong selector
        hookTarget = address(new MockHookTargetReturnWrongSelector());
        vm.expectRevert(Errors.E_NotHookTarget.selector);
        eTST.setHookConfig(hookTarget, OP_DEPOSIT);
    }

    function testFuzz_hookedDepositMintWithdrawRedeem(
        uint32 hookedOps,
        address sender,
        uint256 amount,
        address receiver,
        bool deposit,
        bool withdraw
    ) public {
        hookedOps = uint32(bound(hookedOps, 0, OP_MAX_VALUE - 1));
        vm.assume(hookedOps & OP_VAULT_STATUS_CHECK == 0);
        vm.assume(
            sender.code.length == 0 && receiver.code.length == 0 && !evc.haveCommonOwner(sender, address(0))
                && !evc.haveCommonOwner(receiver, address(0)) && !evc.haveCommonOwner(sender, receiver)
        );
        amount = bound(amount, 1, type(uint112).max);

        // set the hooked ops
        eTST.setHookConfig(
            address(0),
            hookedOps | (deposit ? OP_DEPOSIT : OP_MINT) | (withdraw ? OP_WITHDRAW : OP_REDEEM) | OP_TRANSFER
        );

        // mint some tokens to the sender
        vm.startPrank(sender);
        assetTST.mint(sender, amount);
        assetTST.approve(address(eTST), type(uint256).max);

        // if the hook taget is zero address, the operation is considered disabled
        assertEq(deposit ? eTST.maxDeposit(receiver) : eTST.maxMint(receiver), 0);
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        deposit ? eTST.deposit(amount, receiver) : eTST.mint(amount, receiver);

        // deploy the hook target
        address hookTarget1 = address(new MockHookTarget());

        vm.startPrank(address(this));
        eTST.setHookConfig(
            hookTarget1,
            hookedOps | (deposit ? OP_DEPOSIT : OP_MINT) | (withdraw ? OP_WITHDRAW : OP_REDEEM) | OP_TRANSFER
        );

        vm.startPrank(sender);
        // now the operation succeeds which proves that it's not affected if the hook target call succeeds
        assertEq(deposit ? eTST.maxDeposit(receiver) : eTST.maxMint(receiver), MAX_SANE_AMOUNT);
        deposit ? eTST.deposit(amount, receiver) : eTST.mint(amount, receiver);
        assertEq(eTST.balanceOf(receiver), amount);

        // now the hook target call reverts, but proves that the expected calldata was passed
        bytes memory data = getHookCalldata(
            abi.encodeCall(deposit ? IEVault(eTST).deposit : IEVault(eTST).mint, (amount, receiver)), sender
        );
        MockHookTarget(hookTarget1).setExpectedDataHash(keccak256(data));
        vm.expectRevert(MockHookTarget.ExpectedData.selector);
        deposit ? eTST.deposit(amount, receiver) : eTST.mint(amount, receiver);

        // if the hook target is a contract, it's not considered disabled from the max* functions perspective
        if (deposit) assertEq(eTST.maxDeposit(receiver), MAX_SANE_AMOUNT - eTST.cash());
        else assertEq(eTST.maxMint(receiver), MAX_SANE_AMOUNT - eTST.totalSupply());

        // the operation succeeds which proves that it's not affected if the hook target call succeeds
        vm.startPrank(receiver);
        eTST.transfer(sender, amount);
        assertEq(eTST.balanceOf(sender), amount);

        // now the hook target call reverts, but proves that the expected calldata was passed
        data = getHookCalldata(abi.encodeCall(IEVault(eTST).transfer, (sender, amount)), receiver);
        MockHookTarget(hookTarget1).setExpectedDataHash(keccak256(data));
        vm.expectRevert(MockHookTarget.ExpectedData.selector);
        eTST.transfer(sender, amount);

        // change the hook target
        vm.startPrank(address(this));
        (, uint32 ops) = eTST.hookConfig();
        address hookTarget2 = address(new MockHookTarget());
        eTST.setHookConfig(hookTarget2, ops);

        // the operation succeeds which proves that it's not affected if the hook target call succeeds
        vm.startPrank(sender);
        assertEq(withdraw ? eTST.maxWithdraw(sender) : eTST.maxRedeem(sender), eTST.balanceOf(sender));
        withdraw ? eTST.withdraw(amount / 2, sender, sender) : eTST.redeem(amount / 2, sender, sender);
        assertEq(assetTST.balanceOf(sender), amount / 2);

        // now the hook target call reverts, but proves that the expected calldata was passed
        data = getHookCalldata(
            abi.encodeCall(withdraw ? IEVault(eTST).withdraw : IEVault(eTST).redeem, (amount / 2, sender, sender)),
            sender
        );
        MockHookTarget(hookTarget2).setExpectedDataHash(keccak256(data));
        vm.expectRevert(MockHookTarget.ExpectedData.selector);
        withdraw ? eTST.withdraw(amount / 2, sender, sender) : eTST.redeem(amount / 2, sender, sender);

        // if the hook target is a contract, it's not considered disabled from the max* functions perspective
        MockHookTarget(hookTarget2).setExpectedDataHash(keccak256(data));
        if (withdraw) assertEq(eTST.maxWithdraw(sender), eTST.convertToAssets(eTST.balanceOf(sender)));
        else assertEq(eTST.maxRedeem(sender), eTST.balanceOf(sender));
    }

    function testFuzz_vaultStatusCheckHook(address sender, uint256 amount, address receiver) public {
        vm.assume(
            sender.code.length == 0 && receiver.code.length == 0 && !evc.haveCommonOwner(sender, address(0))
                && !evc.haveCommonOwner(receiver, address(0)) && !evc.haveCommonOwner(sender, receiver)
        );
        amount = bound(amount, 1, type(uint64).max);

        // set the hooked ops
        eTST.setHookConfig(address(0), OP_VAULT_STATUS_CHECK);

        // mint some tokens to the sender
        vm.startPrank(sender);
        assetTST.mint(sender, 2 * amount);
        assetTST.approve(address(eTST), type(uint256).max);

        // if the hook taget is zero address, any operation requesting a vault status check is considered disabled
        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.deposit(amount, receiver);

        vm.expectRevert(Errors.E_OperationDisabled.selector);
        eTST.touch();

        // deploy the hook target
        address hookTarget = address(new MockHookTarget());

        vm.startPrank(address(this));
        eTST.setHookConfig(hookTarget, OP_VAULT_STATUS_CHECK);

        vm.startPrank(sender);
        // now the operations succeed which proves that they're not affected if the hook target call succeeds
        eTST.deposit(amount, receiver);
        assertEq(eTST.balanceOf(receiver), amount);

        eTST.touch();

        // now the hook target call reverts, but proves that the expected calldata was passed
        bytes memory data = getHookCalldata(abi.encodeCall(IEVault(eTST).checkVaultStatus, ()), address(evc));
        MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
        vm.expectRevert(MockHookTarget.ExpectedData.selector);
        eTST.deposit(amount, receiver);

        vm.expectRevert(MockHookTarget.ExpectedData.selector);
        eTST.touch();
    }

    function testFuzz_hookedAllOps(uint32 hookedOps, address sender, address address1, address address2, uint256 amount)
        public
    {
        hookedOps = uint32(bound(hookedOps, 0, OP_MAX_VALUE - 1));
        vm.assume(sender.code.length == 0 && !evc.haveCommonOwner(sender, address(0)));

        // deploy the hook target
        address hookTarget = address(new MockHookTarget());

        // set the hooked ops
        eTST.setHookConfig(hookTarget, hookedOps);

        vm.startPrank(sender);

        if (hookedOps & OP_DEPOSIT != 0) {
            bytes memory data = getHookCalldata(abi.encodeCall(IEVault(eTST).deposit, (amount, address1)), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.deposit(amount, address1);

            data = getHookCalldata(abi.encodeCall(IEVault(eTST).maxDeposit, (address1)), address(0));
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            assertEq(eTST.maxDeposit(address1), MAX_SANE_AMOUNT);
        }

        if (hookedOps & OP_MINT != 0) {
            bytes memory data = getHookCalldata(abi.encodeCall(IEVault(eTST).mint, (amount, address1)), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.mint(amount, address1);

            data = getHookCalldata(abi.encodeCall(IEVault(eTST).maxMint, (address1)), address(0));
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            assertEq(eTST.maxMint(address1), MAX_SANE_AMOUNT);
        }

        if (hookedOps & OP_WITHDRAW != 0) {
            bytes memory data =
                getHookCalldata(abi.encodeCall(IEVault(eTST).withdraw, (amount, address1, address2)), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.withdraw(amount, address1, address2);

            data = getHookCalldata(abi.encodeCall(IEVault(eTST).maxWithdraw, (address1)), address(0));
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            assertEq(eTST.maxWithdraw(address1), 0);
        }

        if (hookedOps & OP_REDEEM != 0) {
            bytes memory data =
                getHookCalldata(abi.encodeCall(IEVault(eTST).redeem, (amount, address1, address2)), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.redeem(amount, address1, address2);

            data = getHookCalldata(abi.encodeCall(IEVault(eTST).maxRedeem, (address1)), address(0));
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            assertEq(eTST.maxRedeem(address1), 0);
        }

        if (hookedOps & OP_TRANSFER != 0) {
            vm.assume(address1 != address(0));

            bytes memory data = getHookCalldata(abi.encodeCall(IEVault(eTST).transfer, (address1, amount)), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.transfer(address1, amount);

            vm.assume(address1 != CHECKACCOUNT_CALLER && address2 != address(0));

            data = getHookCalldata(abi.encodeCall(IEVault(eTST).transferFrom, (address1, address2, amount)), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.transferFrom(address1, address2, amount);

            data = getHookCalldata(abi.encodeCall(IEVault(eTST).transferFromMax, (address1, address2)), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.transferFromMax(address1, address2);
        }

        if (hookedOps & OP_SKIM != 0) {
            bytes memory data = getHookCalldata(abi.encodeCall(IEVault(eTST).skim, (amount, address1)), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.skim(amount, address1);
        }

        if (hookedOps & OP_BORROW != 0) {
            evc.enableController(sender, address(eTST));
            bytes memory data = getHookCalldata(abi.encodeCall(IEVault(eTST).borrow, (amount, address1)), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.borrow(amount, address1);
        }

        if (hookedOps & OP_REPAY != 0) {
            bytes memory data = getHookCalldata(abi.encodeCall(IEVault(eTST).repay, (amount, address1)), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.repay(amount, address1);
        }

        if (hookedOps & OP_REPAY_WITH_SHARES != 0) {
            bytes memory data =
                getHookCalldata(abi.encodeCall(IEVault(eTST).repayWithShares, (amount, address1)), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.repayWithShares(amount, address1);
        }

        if (hookedOps & OP_PULL_DEBT != 0) {
            evc.enableController(sender, address(eTST));
            bytes memory data = getHookCalldata(abi.encodeCall(IEVault(eTST).pullDebt, (amount, address1)), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.pullDebt(amount, address1);
        }

        if (hookedOps & OP_CONVERT_FEES != 0) {
            bytes memory data = getHookCalldata(abi.encodeCall(IEVault(eTST).convertFees, ()), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.convertFees();
        }

        if (hookedOps & OP_LIQUIDATE != 0) {
            evc.enableController(sender, address(eTST));
            bytes memory data =
                getHookCalldata(abi.encodeCall(IEVault(eTST).liquidate, (address1, address2, amount, amount)), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.liquidate(address1, address2, amount, amount);
        }

        if (hookedOps & OP_FLASHLOAN != 0) {
            bytes memory data =
                getHookCalldata(abi.encodeCall(IEVault(eTST).flashLoan, (amount, abi.encode(address1, amount))), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.flashLoan(amount, abi.encode(address1, amount));
        }

        if (hookedOps & OP_TOUCH != 0) {
            bytes memory data = getHookCalldata(abi.encodeCall(IEVault(eTST).touch, ()), sender);
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.touch();
        }

        if (hookedOps & OP_VAULT_STATUS_CHECK != 0) {
            // disable the touch operation hook so it doesn't interfere with the vault status check
            vm.stopPrank();
            eTST.setHookConfig(hookTarget, hookedOps & ~OP_TOUCH);

            vm.startPrank(sender);
            bytes memory data = getHookCalldata(abi.encodeCall(IEVault(eTST).checkVaultStatus, ()), address(evc));
            MockHookTarget(hookTarget).setExpectedDataHash(keccak256(data));
            vm.expectRevert(MockHookTarget.ExpectedData.selector);
            eTST.touch();
        }
    }
}
