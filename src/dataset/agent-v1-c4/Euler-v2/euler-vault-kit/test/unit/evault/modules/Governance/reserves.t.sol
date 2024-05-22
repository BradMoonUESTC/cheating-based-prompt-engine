// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {IRMTestFixed} from "../../../../mocks/IRMTestFixed.sol";

contract Governance_Reserves is EVaultTestBase {
    address user1;
    address user2;
    address user3;
    address user4;
    address user5;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        user4 = makeAddr("user4");
        user5 = makeAddr("user5");

        assetTST.mint(user1, 100e18);
        startHoax(user1);
        assetTST.approve(address(eTST), type(uint256).max);

        assetTST.mint(user2, 100e18);
        startHoax(user2);
        assetTST.approve(address(eTST), type(uint256).max);

        assetTST2.mint(user3, 100e18);
        startHoax(user3);
        assetTST2.approve(address(eTST2), type(uint256).max);
        evc.enableCollateral(user3, address(eTST2));
        eTST2.deposit(50e18, user3);

        assetTST2.mint(user4, 100e18);
        startHoax(user4);
        assetTST2.approve(address(eTST2), type(uint256).max);
        evc.enableCollateral(user4, address(eTST2));
        eTST2.deposit(50e18, user4);

        startHoax(address(this));
        eTST.setLTV(address(eTST2), 0.3e4, 0.3e4, 0);

        oracle.setPrice(address(eTST), unitOfAccount, 0.1e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 0.2e18);

        skip(31 * 60);
    }

    function test_reserves() public {
        startHoax(admin);
        protocolConfig.setVaultInterestFeeRange(address(eTST), true, 0.075e4, 1e4);

        startHoax(address(this));
        eTST.setInterestFee(0.075e4);
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        startHoax(user1);
        eTST.deposit(50e18, user1);
        startHoax(user2);
        eTST.deposit(10e18, user2);

        assertEq(eTST.totalAssets(), 60e18);
        assertEq(eTST.accumulatedFees(), 0);

        startHoax(user3);
        evc.enableController(user3, address(eTST));
        eTST.borrow(5e18, user3);

        skip(30.5 days);

        assertApproxEqAbs(eTST.debtOf(user3), 5.041955e18, 0.000001e18);
        assertApproxEqAbs(eTST.accumulatedFeesAssets(), 0.003146e18, 0.000001e18);

        assertApproxEqAbs(eTST.maxWithdraw(user1), 50.03234e18, 0.000001e18);
        assertApproxEqAbs(eTST.maxWithdraw(user2), 10.0064681e18, 0.000001e18);

        // Some more interest earned:
        skip(90 days);

        assertApproxEqAbs(eTST.debtOf(user3), 5.167823e18, 0.000001e18);
        assertApproxEqAbs(eTST.accumulatedFeesAssets(), 0.012586e18, 0.000001e18);
        assertApproxEqAbs(eTST.accumulatedFees(), 0.012554e18, 0.000001e18);

        // Now let's try to withdraw some reserves:
        startHoax(address(this));
        eTST.setFeeReceiver(user4);
        startHoax(admin);
        protocolConfig.setFeeReceiver(user5);

        eTST.convertFees();

        assertApproxEqAbs(eTST.balanceOf(user5), protocolShare(0.012554e18), 0.000001e18);
        assertApproxEqAbs(eTST.balanceOf(user4), riskManagerShare(0.012554e18), 0.000001e18);
        assertEq(eTST.accumulatedFees(), 0);

        // More starts to accrue now:
        skip(15);

        assertApproxEqAbs(eTST.accumulatedFees(), 0.000000018e18, 0.000000001e18);
    }

    function test_convertFees_withoutAnyDeposit() public {
        startHoax(admin);
        protocolConfig.setVaultInterestFeeRange(address(eTST), true, 0.075e4, 1e4);

        startHoax(address(this));
        eTST.setInterestFee(0.075e4);
        eTST.setInterestRateModel(address(new IRMTestFixed()));

        assertEq(eTST.accumulatedFees(), 0);
        assertEq(eTST.accumulatedFeesAssets(), 0);
        assertEq(eTST.totalSupply(), 0);
        assertEq(eTST.totalAssets(), 0);

        skip(30.5 days);

        startHoax(address(this));
        eTST.setFeeReceiver(user4);
        startHoax(admin);
        protocolConfig.setFeeReceiver(user5);

        vm.expectEmit();
        emit Events.VaultStatus(0, 0, 0, 0, eTST.interestAccumulator(), eTST.interestRate(), block.timestamp);
        eTST.convertFees();

        assertEq(eTST.balanceOf(user5), 0);
        assertEq(eTST.accumulatedFees(), 0);
    }

    function test_setInterestFee_outOfBounds() public {
        startHoax(address(this));
        vm.expectRevert(Errors.E_BadFee.selector);
        eTST.setInterestFee(1.01e4);
    }

    function protocolShare(uint256 fees) internal pure returns (uint256) {
        return fees * 0.1e18 / 1e18;
    }

    function riskManagerShare(uint256 fees) internal pure returns (uint256) {
        return fees * (1e18 - 0.1e18) / 1e18;
    }
}
