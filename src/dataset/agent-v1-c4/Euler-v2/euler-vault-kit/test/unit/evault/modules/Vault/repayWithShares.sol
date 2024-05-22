// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {IEVault} from "../../../../../src/EVault/IEVault.sol";
import {TestERC20} from "../../../../mocks/TestERC20.sol";
import {IRMTestZero} from "../../../../mocks/IRMTestZero.sol";
import "../../../../../src/EVault/shared/types/Types.sol";

contract VaultTest_RepayWithShares is EVaultTestBase {
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
        evc.enableCollateral(user2, address(eTST2));

        startHoax(user3);
        assetTST.approve(address(eTST), type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        evc.enableCollateral(user3, address(eTST));
        evc.enableCollateral(user3, address(eTST2));

        assetTST.mint(user1, 100e18);
        assetTST.mint(user2, 100e18);
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

    //repayWithShares for 0 is a no-op
    function test_repayWithShares_forZero() public {
        startHoax(user2);
        eTST2.deposit(40e18, user2);

        assertEq(evc.getCollaterals(user2)[0], address(eTST2));

        assertEq(assetTST.balanceOf(user2), 100e18);
        assertEq(eTST.balanceOf(user2), 0);
        assertEq(eTST.debtOf(user2), 0);

        startHoax(user2);
        evc.enableController(user2, address(eTST));
        eTST.borrow(0.5e18, user2);

        assertEq(assetTST.balanceOf(user2), 100.5e18);
        assertEq(eTST.balanceOf(user2), 0);
        assertEq(eTST.debtOf(user2), 0.5e18);

        // repayWithShares 0 is a no-op
        eTST.repayWithShares(0, user2);
    }

    //repayWithShares when owed amount is 0 is a no-op
    function test_repayWithShares_whenOwedAmountZero() public {
        assertEq(evc.getCollaterals(user2)[0], address(eTST2));

        startHoax(user2);
        eTST.deposit(1e18, user2);

        assertEq(assetTST.balanceOf(user2), 99e18);
        assertEq(eTST.balanceOf(user2), 1e18);
        assertEq(eTST.debtOf(user2), 0);

        evc.enableController(user2, address(eTST));
        eTST.repayWithShares(type(uint256).max, user2);

        assertEq(assetTST.balanceOf(user2), 99e18);
        assertEq(eTST.balanceOf(user2), 1e18);
        assertEq(eTST.debtOf(user2), 0);
    }

    //repayWithShares with max_uint256 repays the debt in full or up to the available underlying balance
    function test_repayWithShares_withMaxRepays() public {
        startHoax(user2);
        eTST2.deposit(40e18, user2);

        assertEq(evc.getCollaterals(user2)[0], address(eTST2));

        assertEq(assetTST.balanceOf(user2), 100e18);
        assertEq(eTST.balanceOf(user2), 0);
        assertEq(eTST.debtOf(user2), 0);

        // Two separate borrows, .4 and .1:
        startHoax(user2);
        evc.enableController(user2, address(eTST));

        vm.expectEmit();
        emit Events.Transfer(address(0), user2, 0.4e18);
        eTST.borrow(0.4e18, user2);
        eTST.borrow(0.1e18, user2);

        // Make sure the borrow market is recorded
        assertEq(evc.getCollaterals(user2)[0], address(eTST2));
        assertEq(evc.getControllers(user2)[0], address(eTST));

        assertEq(assetTST.balanceOf(user2), 100.5e18);
        assertEq(eTST.balanceOf(user2), 0);
        assertEq(eTST.debtOf(user2), 0.5e18);

        // Wait 1 day
        skip(1 days);

        // No interest was charged
        assertEq(eTST.debtOf(user2), 0.5e18);

        // nothing to repay
        eTST.repayWithShares(type(uint256).max, user2);

        assertEq(assetTST.balanceOf(user2), 100.5e18);
        assertEq(eTST.balanceOf(user2), 0);
        assertEq(eTST.debtOf(user2), 0.5e18);

        // eVault balance is less than debt
        eTST.deposit(0.1e18, user2);
        eTST.repayWithShares(type(uint256).max, user2);

        assertEq(assetTST.balanceOf(user2), 100.4e18);
        assertEq(eTST.balanceOf(user2), 0);
        assertEq(eTST.maxWithdraw(user2), 0);
        assertEq(eTST.debtOf(user2), 0.4e18);

        // eVault balance is greater than debt
        eTST.deposit(1e18, user2);
        eTST.repayWithShares(type(uint256).max, user2);

        assertEq(assetTST.balanceOf(user2), 99.4e18);
        assertEq(eTST.balanceOf(user2), 0.6e18);
        assertEq(eTST.maxWithdraw(user2), 0);
        assertEq(eTST.debtOf(user2), 0);

        eTST.disableController();
        assertEq(eTST.maxWithdraw(user2), 0.6e18);
    }
}
