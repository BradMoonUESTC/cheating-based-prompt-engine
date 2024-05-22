// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {GovernanceModule} from "../../../../../src/EVault/modules/Governance.sol";

import "../../../../../src/EVault/shared/types/Types.sol";

contract GovernanceTest_InterestFee is EVaultTestBase {
    using TypesLib for uint256;

    address depositor;

    function setUp() public override {
        super.setUp();

        depositor = makeAddr("depositor");

        // Setup
        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 1e18);
        eTST.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);

        // Depositor
        startHoax(depositor);
        assetTST.mint(depositor, type(uint256).max);
        assetTST.approve(address(eTST), type(uint256).max);
        eTST.deposit(1e25, depositor);
    }

    function testFuzz_feesAccrual(uint256 countBorrowers) public {
        countBorrowers = bound(countBorrowers, 1, 15);
        address[] memory borrowers = new address[](countBorrowers);

        assertEq(eTST.totalBorrows(), 0);
        assertEq(eTST.accumulatedFees(), 0);

        borrowMany(borrowers, countBorrowers);

        uint256 amount = eTST.totalBorrows();

        skip(365 days);

        uint256 totalSupplyBefore = eTST.totalSupply();
        uint256 accumFees = eTST.interestFee() * (eTST.totalBorrows() - amount) / (1e4);

        repayMany(borrowers, countBorrowers);

        assertApproxEqAbs(accumFees, eTST.accumulatedFeesAssets(), 1000000);

        eTST.convertFees();

        assertEq(eTST.accumulatedFees(), 0);
        assertEq(eTST.totalSupply(), totalSupplyBefore);
    }

    function testFuzz_setInterestFee_feesAccrual(uint256 countBorrowers) public {
        countBorrowers = bound(countBorrowers, 1, 15);
        address[] memory borrowers = new address[](countBorrowers);

        assertEq(eTST.totalBorrows(), 0);
        assertEq(eTST.accumulatedFees(), 0);

        borrowMany(borrowers, countBorrowers);

        uint16 fee = eTST.interestFee();
        uint256 totalBorrow = eTST.totalBorrows();

        skip(365 days);

        uint256 accumFees1 = fee * (eTST.totalBorrows() - totalBorrow) / (1e4);

        startHoax(address(this));
        eTST.setInterestFee(0.7e4);

        assertApproxEqAbs(eTST.accumulatedFeesAssets(), accumFees1, 1000000);

        fee = eTST.interestFee();
        totalBorrow = eTST.totalBorrows();

        skip(365 days);

        uint256 accumFees2 = fee * (eTST.totalBorrows() - totalBorrow) / (1e4);

        assertApproxEqAbs(eTST.accumulatedFeesAssets(), accumFees1 + accumFees2, 0.01e18);
    }

    function test_convertFees_AnyInvoke() public {
        startHoax(address(this));
        eTST.convertFees();

        startHoax(admin);
        eTST.convertFees();

        startHoax(feeReceiver);
        eTST.convertFees();

        startHoax(depositor);
        eTST.convertFees();
    }

    function test_convertFees_NoGovernorReceiver() public {
        uint256 countBorrowers = 5;
        address[] memory borrowers = new address[](countBorrowers);

        startHoax(address(this));
        eTST.setFeeReceiver(address(0));

        assertEq(eTST.feeReceiver(), address(0));
        assertEq(eTST.accumulatedFees(), 0);
        assertEq(eTST.totalBorrows(), 0);

        borrowMany(borrowers, countBorrowers);
        skip(100 days);
        repayMany(borrowers, countBorrowers);

        uint256 totalSupplyBefore = eTST.totalSupply();
        uint256 accumFees = eTST.accumulatedFees();
        address protocolFeeReceiver = protocolConfig.feeReceiver();

        assertEq(eTST.balanceOf(protocolFeeReceiver), 0);
        assertEq(eTST.balanceOf(address(0)), 0);

        eTST.convertFees();

        assertEq(eTST.balanceOf(protocolFeeReceiver), accumFees);
        assertEq(eTST.balanceOf(address(0)), 0);
        assertEq(eTST.totalSupply(), totalSupplyBefore);
        assertEq(eTST.accumulatedFees(), 0);
    }

    function testFuzz_convertFees_WithGovernorReceiver(uint256 countBorrowers) public {
        countBorrowers = bound(countBorrowers, 1, 15);
        address[] memory borrowers = new address[](countBorrowers);

        assertEq(eTST.totalBorrows(), 0);
        assertEq(eTST.accumulatedFees(), 0);

        borrowMany(borrowers, countBorrowers);
        skip(365 days);
        repayMany(borrowers, countBorrowers);

        uint256 totalSupplyBefore = eTST.totalSupply();
        uint256 accumFees = eTST.accumulatedFees();
        uint256 protocolShare = eTST.protocolFeeShare();
        uint256 partFees = accumFees.toShares().mulDiv(1e4 - protocolShare, 1e4).toUint();

        address governFeeReceiver = eTST.feeReceiver();
        address protocolFeeReceiver = protocolConfig.feeReceiver();

        assertEq(eTST.balanceOf(governFeeReceiver), 0);
        assertEq(eTST.balanceOf(protocolFeeReceiver), 0);

        eTST.convertFees();

        assertEq(eTST.balanceOf(governFeeReceiver), partFees);
        assertEq(eTST.balanceOf(protocolFeeReceiver), accumFees - partFees);
        assertEq(eTST.totalSupply(), totalSupplyBefore);
        assertEq(eTST.accumulatedFees(), 0);
    }

    function test_convertFees_OverMaxProtocolFeeShare() public {
        uint256 countBorrowers = 5;
        address[] memory borrowers = new address[](countBorrowers);

        uint16 newProtocolFeeShare = 0.5e4 + 0.1e4;

        address governFeeReceiver = eTST.feeReceiver();
        address protocolFeeReceiver = protocolConfig.feeReceiver();

        startHoax(admin);
        protocolConfig.setProtocolFeeShare(newProtocolFeeShare);

        assertEq(eTST.totalBorrows(), 0);
        assertEq(eTST.accumulatedFees(), 0);

        borrowMany(borrowers, countBorrowers);
        skip(365 days);
        repayMany(borrowers, countBorrowers);

        uint256 totalSupplyBefore = eTST.totalSupply();
        uint256 accumFees = eTST.accumulatedFees();

        assertEq(eTST.balanceOf(governFeeReceiver), 0);
        assertEq(eTST.balanceOf(protocolFeeReceiver), 0);

        eTST.convertFees();

        uint256 partFees = accumFees.toShares().mulDiv(1e4 - newProtocolFeeShare, 1e4).toUint();
        assertNotEq(eTST.balanceOf(governFeeReceiver), partFees);
        assertNotEq(eTST.balanceOf(protocolFeeReceiver), accumFees - partFees);

        partFees = accumFees.toShares().mulDiv(1e4 - 0.5e4, 1e4).toUint();
        assertEq(eTST.balanceOf(governFeeReceiver), partFees);
        assertEq(eTST.balanceOf(protocolFeeReceiver), accumFees - partFees);
        assertEq(eTST.totalSupply(), totalSupplyBefore);
        assertEq(eTST.accumulatedFees(), 0);
    }

    function testFuzz_setInterestFee_InsideGuaranteedRange(uint16 newInterestFee) public {
        vm.assume(newInterestFee >= 0.1e4 && newInterestFee <= 1e4);

        startHoax(address(this));
        vm.expectEmit();
        emit GovernanceModule.GovSetInterestFee(newInterestFee);
        eTST.setInterestFee(newInterestFee);
        assertEq(eTST.interestFee(), newInterestFee);
    }

    function testFuzz_setInterestFee_OutsideGuaranteedRange(uint16 newInterestFee) public {
        vm.assume(newInterestFee < 0.1e4 || newInterestFee > 1e4);

        startHoax(address(this));
        vm.expectRevert(Errors.E_BadFee.selector);
        eTST.setInterestFee(newInterestFee);
    }

    function testFuzz_setInterestFee_BelowLowerBound(uint16 newInterestFee) public {
        vm.assume(newInterestFee < 0.1e4 - 1);

        startHoax(address(this));
        vm.expectRevert(Errors.E_BadFee.selector);
        eTST.setInterestFee(newInterestFee);

        startHoax(admin);
        protocolConfig.setVaultInterestFeeRange(address(eTST), true, 0.1e4 - 1, 1e4);

        startHoax(address(this));
        vm.expectRevert(Errors.E_BadFee.selector);
        eTST.setInterestFee(newInterestFee);

        startHoax(admin);
        protocolConfig.setVaultInterestFeeRange(address(eTST), true, newInterestFee, 1e4);

        startHoax(address(this));
        vm.expectEmit();
        emit GovernanceModule.GovSetInterestFee(newInterestFee);
        eTST.setInterestFee(newInterestFee);
        assertEq(eTST.interestFee(), newInterestFee);
    }

    function borrowMany(address[] memory borrowers, uint256 count) internal {
        uint256 total;
        for (uint8 i; i < count; ++i) {
            uint256 amount = (i + 1) * 1e18;
            borrowers[i] = vm.addr(i + 200);

            assetTST.mint(borrowers[i], amount);
            assetTST2.mint(borrowers[i], amount * 2);

            startHoax(borrowers[i]);
            assetTST2.approve(address(eTST2), type(uint256).max);
            eTST2.deposit(type(uint256).max, borrowers[i]);
            evc.enableCollateral(borrowers[i], address(eTST2));
            evc.enableController(borrowers[i], address(eTST));

            eTST.borrow(amount, borrowers[i]);
            total += amount;
        }
        assertEq(eTST.totalBorrows(), total);
    }

    function repayMany(address[] memory borrowers, uint256 count) internal {
        for (uint8 i; i < count; ++i) {
            startHoax(borrowers[i]);
            assetTST.approve(address(eTST), type(uint256).max);
            eTST.repay(type(uint256).max, borrowers[i]);
        }
    }
}
