// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {SafeERC20Lib} from "../../../../../src/EVault/shared/lib/SafeERC20Lib.sol";
import {Permit2ECDSASigner} from "../../../../mocks/Permit2ECDSASigner.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";

import "../../../../../src/EVault/shared/types/Types.sol";

contract VaultTest_Deposit is EVaultTestBase {
    using TypesLib for uint256;

    error InvalidNonce();
    error InsufficientAllowance(uint256 amount);

    uint256 userPK;
    address user;
    address user1;

    Permit2ECDSASigner permit2Signer;

    function setUp() public override {
        super.setUp();

        permit2Signer = new Permit2ECDSASigner(address(permit2));

        userPK = 0x123400;
        user = vm.addr(userPK);
        user1 = makeAddr("user1");

        assetTST.mint(user1, type(uint256).max);
        hoax(user1);
        assetTST.approve(address(eTST), type(uint256).max);

        assetTST.mint(user, type(uint256).max);
        startHoax(user);
        assetTST.approve(address(eTST), type(uint256).max);
    }

    function test_maxSaneAmount() public {
        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST.deposit(MAX_SANE_AMOUNT + 1, user);

        eTST.deposit(MAX_SANE_AMOUNT, user);

        assertEq(assetTST.balanceOf(address(eTST)), MAX_SANE_AMOUNT);

        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        eTST.deposit(1, user);
    }

    function test_deposit_zeroAmountIsNoop() public {
        assertEq(assetTST.balanceOf(address(eTST)), 0);
        assertEq(eTST.balanceOf(user), 0);

        eTST.deposit(0, user);

        assertEq(assetTST.balanceOf(address(eTST)), 0);
        assertEq(eTST.balanceOf(user), 0);
    }

    function test_skim_zeroAmountIsNoop() public {
        assertEq(assetTST.balanceOf(address(eTST)), 0);
        assertEq(eTST.balanceOf(user), 0);

        assetTST.mint(address(eTST), 1e18);

        eTST.skim(0, user);

        assertEq(assetTST.balanceOf(address(eTST)), 1e18);
        assertEq(eTST.balanceOf(user), 0);
        assertEq(eTST.cash(), 0);
        assertEq(eTST.totalSupply(), 0);
    }

    function test_deposit_skim_zeroShares() public {
        startHoax(address(this));

        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 1e18);

        eTST.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);

        // user

        startHoax(user);

        eTST.deposit(100e18, user);

        // borrower

        startHoax(user1);

        assetTST2.mint(user1, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, user1);

        evc.enableController(user1, address(eTST));
        evc.enableCollateral(user1, address(eTST2));

        eTST.borrow(5e18, user1);

        skip(100);

        vm.expectRevert(Errors.E_ZeroShares.selector);
        eTST.deposit(1, user1);

        assetTST.mint(address(eTST), 1e18);

        vm.expectRevert(Errors.E_ZeroShares.selector);
        eTST.skim(1, user1);
    }

    function test_mint_zeroShares_isNoop() public {
        uint256 balanceBefore = eTST.balanceOf(user);
        eTST.mint(0, user);
        assertEq(balanceBefore, eTST.balanceOf(user));
    }

    function test_withdraw_zeroAssets_isNoop() public {
        eTST.deposit(1e18, user);

        uint256 balanceBefore = eTST.balanceOf(user);
        eTST.withdraw(0, user, user);
        assertEq(balanceBefore, eTST.balanceOf(user));
    }

    function test_redeem_zeroShares_isNoop() public {
        eTST.deposit(1e18, user);

        uint256 balanceBefore = eTST.balanceOf(user);
        eTST.redeem(0, user, user);
        assertEq(balanceBefore, eTST.balanceOf(user));
    }

    function test_redeem_zeroAssets() public {
        startHoax(address(this));

        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 1e18);

        eTST.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);

        // user

        startHoax(user);

        eTST.deposit(100e18, user);

        // borrower

        startHoax(user1);

        assetTST2.mint(user1, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(10e18, user1);

        evc.enableController(user1, address(eTST));
        evc.enableCollateral(user1, address(eTST2));

        eTST.borrow(5e18, user1);

        // socialize debt in liquidation to push exchange rate < 1

        oracle.setPrice(address(assetTST), unitOfAccount, 2e18);

        startHoax(user);

        assetTST2.mint(user, type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        eTST2.deposit(100e18, user);
        evc.enableController(user, address(eTST));
        evc.enableCollateral(user, address(eTST2));

        eTST.liquidate(user1, address(eTST2), type(uint256).max, 0);

        assertEq(eTST.convertToAssets(1), 0);

        vm.expectRevert(Errors.E_ZeroAssets.selector);
        eTST.redeem(1, user, user);
    }

    function test_zeroReceiver() public {
        vm.expectRevert(Errors.E_BadSharesReceiver.selector);
        eTST.deposit(1e18, address(0));

        vm.expectRevert(Errors.E_BadSharesReceiver.selector);
        eTST.mint(1e18, address(0));
    }

    function test_maxUintAmount() public {
        address user2 = makeAddr("user2");
        startHoax(user2);

        eTST.deposit(type(uint256).max, user2);

        assertEq(eTST.totalAssets(), 0);
        assertEq(eTST.balanceOf(user2), 0);
        assertEq(eTST.totalSupply(), 0);

        uint256 walletBalance = 2e18;

        assetTST.mint(user2, walletBalance);
        assetTST.approve(address(eTST), type(uint256).max);

        eTST.deposit(type(uint256).max, user2);

        assertEq(eTST.totalAssets(), walletBalance);
        assertEq(eTST.balanceOf(user2), walletBalance);
        assertEq(eTST.totalSupply(), walletBalance);
    }

    function test_directTransfer() public {
        uint256 amount = 1e18;

        vm.startPrank(user);
        assetTST.transfer(address(eTST), amount);

        assertEq(assetTST.balanceOf(address(eTST)), amount);
        assertEq(eTST.balanceOf(user), 0);
        assertEq(eTST.totalSupply(), 0);
        assertEq(eTST.totalAssets(), 0);

        eTST.deposit(amount, user);

        assertEq(assetTST.balanceOf(address(eTST)), amount * 2);
        assertEq(eTST.balanceOf(user), amount);
        assertEq(eTST.totalSupply(), amount);
        assertEq(eTST.totalAssets(), amount);
    }

    function test_depositWithPermit2() public {
        uint256 amount = 1e18;

        // cancel the approval to the vault
        assetTST.approve(address(eTST), 0);

        // deposit won't succeed without any approval
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Lib.E_TransferFromFailed.selector,
                abi.encodeWithSignature("Error(string)", "ERC20: transfer amount exceeds allowance"),
                abi.encodeWithSelector(IAllowanceTransfer.AllowanceExpired.selector, 0)
            )
        );
        eTST.deposit(amount, user);

        // approve permit2 contract to spend the tokens
        assetTST.approve(permit2, type(uint160).max);

        // approve the vault to spend the tokens via permit2
        IAllowanceTransfer(permit2).approve(address(assetTST), address(eTST), type(uint160).max, type(uint48).max);

        // deposit succeeds now
        eTST.deposit(amount, user);

        assertEq(assetTST.balanceOf(address(eTST)), amount);
        assertEq(eTST.balanceOf(user), amount);
        assertEq(eTST.totalSupply(), amount);
        assertEq(eTST.totalAssets(), amount);
    }

    function test_depositWithPermit2InBatch() public {
        uint256 amount = 1e18;
        vm.warp(100);

        // cancel the approval to the vault
        assetTST.approve(address(eTST), 0);

        // deposit won't succeed without any approval
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Lib.E_TransferFromFailed.selector,
                abi.encodeWithSignature("Error(string)", "ERC20: transfer amount exceeds allowance"),
                abi.encodeWithSelector(IAllowanceTransfer.AllowanceExpired.selector, 0)
            )
        );
        eTST.deposit(amount, user);

        // approve permit2 contract to spend the tokens
        assetTST.approve(permit2, type(uint160).max);

        // build permit2 object
        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: address(assetTST),
                amount: type(uint160).max,
                expiration: type(uint48).max,
                nonce: 0
            }),
            spender: address(eTST),
            sigDeadline: type(uint256).max
        });

        // build a deposit batch with permit2
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);
        items[0].onBehalfOfAccount = user;
        items[0].targetContract = permit2;
        items[0].value = 0;
        items[0].data = abi.encodeWithSignature(
            "permit(address,((address,uint160,uint48,uint48),address,uint256),bytes)",
            user,
            permitSingle,
            permit2Signer.signPermitSingle(userPK, permitSingle)
        );

        items[1].onBehalfOfAccount = user;
        items[1].targetContract = address(eTST);
        items[1].value = 0;
        items[1].data = abi.encodeCall(eTST.deposit, (amount, user));

        evc.batch(items);
        assertEq(assetTST.balanceOf(address(eTST)), amount);
        assertEq(eTST.balanceOf(user), amount);
        assertEq(eTST.totalSupply(), amount);
        assertEq(eTST.totalAssets(), amount);

        // cannot replay the same batch
        vm.expectRevert(InvalidNonce.selector);
        evc.batch(items);

        // modify permit
        permitSingle.details.amount = uint160(amount - 1);
        permitSingle.details.nonce = 1;

        // modify batch item
        items[0].data = abi.encodeWithSignature(
            "permit(address,((address,uint160,uint48,uint48),address,uint256),bytes)",
            user,
            permitSingle,
            permit2Signer.signPermitSingle(userPK, permitSingle)
        );

        // not enough permitted
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Lib.E_TransferFromFailed.selector,
                abi.encodeWithSignature("Error(string)", "ERC20: transfer amount exceeds allowance"),
                abi.encodeWithSelector(InsufficientAllowance.selector, amount - 1)
            )
        );
        evc.batch(items);

        // cancel the approval to the vault via permit2
        IAllowanceTransfer(permit2).approve(address(assetTST), address(eTST), type(uint160).max, 1);

        // permit2 approval is expired
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Lib.E_TransferFromFailed.selector,
                abi.encodeWithSignature("Error(string)", "ERC20: transfer amount exceeds allowance"),
                abi.encodeWithSelector(IAllowanceTransfer.AllowanceExpired.selector, 1)
            )
        );
        eTST.deposit(amount, user);

        // once again approve the vault
        assetTST.approve(address(eTST), amount);

        // deposit succeeds now
        eTST.deposit(amount, user);
        assertEq(assetTST.balanceOf(address(eTST)), 2 * amount);
        assertEq(eTST.balanceOf(user), 2 * amount);
        assertEq(eTST.totalSupply(), 2 * amount);
        assertEq(eTST.totalAssets(), 2 * amount);
    }
}
