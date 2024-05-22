// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {IEVault} from "../../../../../src/EVault/IEVault.sol";
import {TestERC20} from "../../../../mocks/TestERC20.sol";
import {IRMTestFixed} from "../../../../mocks/IRMTestFixed.sol";
import {IRMTestZero} from "../../../../mocks/IRMTestZero.sol";
import {IRMTestLinear} from "../../../../mocks/IRMTestLinear.sol";
import {DToken} from "../../../../../src/EVault/DToken.sol";
import "../../../../../src/EVault/shared/types/Types.sol";

contract VaultTest_Decimals is EVaultTestBase {
    address user1;
    address user2;
    address user3;

    TestERC20 assetTST3;
    IEVault public eTST3;

    TestERC20 assetTST4;
    IEVault public eTST4;

    function setUp() public override {
        super.setUp();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        assetTST3 = new TestERC20("Test TST 3", "TST3", 6, false);
        eTST3 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST3), address(oracle), unitOfAccount))
        );

        assetTST4 = new TestERC20("Test TST 4", "TST4", 0, false);
        eTST4 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST4), address(oracle), unitOfAccount))
        );

        startHoax(address(this));
        eTST.setInterestRateModel(address(new IRMTestZero()));

        assetTST3.mint(user1, 100e6);
        startHoax(user1);
        assetTST3.approve(address(eTST3), type(uint256).max);

        assetTST3.mint(user2, 100e6);
        startHoax(user2);
        assetTST3.approve(address(eTST3), type(uint256).max);

        assetTST2.mint(user3, 100e18);
        startHoax(user3);
        assetTST2.approve(address(eTST2), type(uint256).max);
        evc.enableCollateral(user3, address(eTST2));
        eTST2.deposit(50e18, user3);

        // approve TST3 token for repay() to avoid ERC20: transfer amount exceeds allowance error
        assetTST3.approve(address(eTST3), type(uint256).max);

        oracle.setPrice(address(eTST3), unitOfAccount, 0.5e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 0.2e18);

        startHoax(address(this));
        eTST3.setLTV(address(eTST2), 0.21e4, 0.21e4, 0);
        eTST4.setLTV(address(eTST2), 0.21e4, 0.21e4, 0);
    }

    function test_basicFlow() public {
        startHoax(address(this));
        eTST3.setInterestFee(0.23e4);

        startHoax(user3);
        evc.enableController(user3, address(eTST3));
        skip(31 * 60);
        startHoax(address(this));
        eTST3.setInterestRateModel(address(new IRMTestLinear()));

        startHoax(user1);
        eTST3.deposit(1e6, user1);
        assertEq(eTST3.maxWithdraw(user1), 1e6);
        assertEq(eTST3.balanceOf(user1), 1e6);
        assertEq(assetTST3.balanceOf(user1), 99e6);
        assertEq(assetTST3.balanceOf(address(eTST3)), 1e6);

        eTST3.withdraw(0.2e6, user1, user1);
        assertEq(eTST3.maxWithdraw(user1), 0.8e6);
        assertEq(eTST3.balanceOf(user1), 0.8e6);
        assertEq(assetTST3.balanceOf(user1), 99.2e6);
        assertEq(assetTST3.balanceOf(address(eTST3)), 0.8e6);

        startHoax(user3);
        eTST3.borrow(0.3e6, user3);
        assertEq(eTST3.debtOf(user3), 0.3e6);
        assertEq(eTST3.debtOfExact(user3), debtExact(0.3e6));
        assertEq(eTST3.totalBorrows(), 0.3e6);
        assertEq(assetTST3.balanceOf(user3), 0.3e6);
        assertEq(assetTST3.balanceOf(address(eTST3)), 0.5e6);

        // Make sure the TST3 market borrow is recorded
        assertEq(evc.getCollaterals(user3).length, 1);
        assertEq(evc.getCollaterals(user3)[0], address(eTST2));
        assertEq(evc.getControllers(user3).length, 1);
        assertEq(evc.getControllers(user3)[0], address(eTST3));

        assertEq(eTST3.interestAccumulator(), 1e27);

        startHoax(address(this));
        eTST3.setInterestRateModel(address(new IRMTestFixed()));
        skip(1);
        assertEq(eTST3.interestAccumulator(), 1.00000000317097919837645865e27);

        // Mint some extra so we can pay interest
        assetTST3.mint(user3, 0.1e6);

        // 1 month later
        skip(2628000); // 1 month in seconds
        // 1 block later
        assertApproxEqAbs(eTST3.debtOfExact(user3), debtExact(0.30251e6), 0.000000001e18);
        // Rounds up to 6th decimal place:
        assertEq(eTST3.debtOf(user3), 0.302511e6);
        // Does round up:
        assertEq(eTST3.totalBorrows(), 0.302511e6);

        // Conversion methods
        assertApproxEqAbs(eTST3.balanceOf(user1), 0.8e6, 1e6);
        assertEq(eTST3.convertToAssets(0.8e6), 0.80086e6);
        assertEq(eTST3.convertToAssets(0.8e6) * 1000, 0.80086e6 * 1000);
        assertEq(eTST3.convertToShares(0.800861e6), 0.8e6); //js value = 0.800860e6

        // Try to pay off full amount:
        startHoax(user3);
        eTST3.repay(0.302511e6, user3);
        assertEq(eTST3.debtOf(user3), 0);
        assertEq(eTST3.debtOfExact(user3), 0);

        // Check if any more interest is accrued after mined block:
        skip(1);
        assertEq(eTST3.debtOf(user3), 0);
        assertEq(eTST3.debtOfExact(user3), 0);
        assertEq(eTST3.totalBorrows(), 0);
        assertEq(eTST3.totalBorrowsExact(), 0);
    }

    //decimals() on e vaults should return same value as underlying
    function test_decimals_sameValueAsUnderlying() public view {
        assertEq(assetTST3.decimals(), 6);
        assertEq(eTST3.decimals(), 6);
    }

    function test_decimals_zeroDecimals() public {
        // TST4 has 0 decimals
        assetTST4.mint(user1, 100);
        startHoax(user1);
        assetTST4.approve(address(eTST4), type(uint256).max);
        evc.enableCollateral(user1, address(eTST4));
        eTST4.deposit(50, user1);

        assertEq(assetTST4.decimals(), 0);
        assertEq(eTST4.decimals(), 0);
    }

    //decimals() on d tokens should always return underlying decimals
    function test_decimals_dToken() public {
        assertEq(assetTST3.decimals(), 6);
        assertEq(DToken(eTST3.dToken()).decimals(), 6);

        assetTST4.mint(user1, 100);
        startHoax(user1);
        assetTST4.approve(address(eTST4), type(uint256).max);
        eTST4.deposit(50, user1);

        startHoax(user3);
        evc.enableController(user3, address(eTST4));
        eTST4.borrow(1, user3);

        assertEq(assetTST4.decimals(), 0);
        assertEq(DToken(eTST4.dToken()).decimals(), 0);
    }

    //no dust left over after max uint redeem
    function test_redeem_noDustLeft() public {
        startHoax(user1);
        eTST3.deposit(1e6, user1);
        eTST3.withdraw(0.2e6, user1, user1);
        assertEq(eTST3.totalSupply(), 0.8e6);

        startHoax(user3);
        evc.enableController(user3, address(eTST3));
        eTST3.borrow(0.3e6, user3);

        startHoax(address(this));
        eTST3.setInterestRateModel(address(new IRMTestFixed()));
        assetTST3.mint(user3, 0.1e6);

        skip(2628000); // 1 month in seconds

        startHoax(user3);
        eTST3.repay(0.302511e6, user3);

        startHoax(user1);
        eTST3.redeem(type(uint256).max, user1, user1);
        assertEq(eTST3.balanceOf(user1), 0);
    }

    //total supply of underlying
    function test_totalSupply() public {
        startHoax(user1);
        eTST3.deposit(1.5e6, user1);

        assertEq(eTST3.totalSupply(), 1.5e6);
        assertEq(eTST3.totalAssets(), 1.5e6);
    }

    function debtExact(uint256 value) internal pure returns (uint256) {
        return value * (1 << INTERNAL_DEBT_PRECISION_SHIFT);
    }
}
