// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {IEVault} from "../../../../../src/EVault/IEVault.sol";
import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {TestERC20} from "../../../../mocks/TestERC20.sol";
import {IRMTestZero} from "../../../../mocks/IRMTestZero.sol";
import "../../../../../src/EVault/shared/types/Types.sol";

contract VaultTest_Batch is EVaultTestBase {
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

        startHoax(user3);
        assetTST.approve(address(eTST), type(uint256).max);
        assetTST2.approve(address(eTST2), type(uint256).max);
        evc.enableCollateral(user3, address(eTST));
        evc.enableCollateral(user3, address(eTST2));

        assetTST.mint(user1, 100e18);
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

    function test_subAccountTransfers() public {
        assertEq(eTST.balanceOf(getSubAccount(user1, 1)), 0);
        assertEq(eTST.balanceOf(getSubAccount(user2, 1)), 0);

        assertEq(evc.getCollaterals(getSubAccount(user1, 1)).length, 0);

        // Do a dry-run
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](9);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.transfer.selector, getSubAccount(user1, 1), 1e18)
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.transfer.selector, getSubAccount(user1, 3), 1e18)
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: getSubAccount(user1, 1),
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.transfer.selector, getSubAccount(user1, 2), 0.6e18)
        });
        items[3] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableCollateral.selector, getSubAccount(user1, 1), address(eTST))
        });
        items[4] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, getSubAccount(user1, 1), address(eTST2))
        });
        items[5] = IEVC.BatchItem({
            onBehalfOfAccount: getSubAccount(user1, 1),
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 1e18, user1)
        });
        items[6] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.accountLiquidityFull.selector, getSubAccount(user1, 1), false)
        });
        items[7] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.balanceOf.selector, getSubAccount(user1, 2))
        });
        items[8] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.balanceOf.selector, getSubAccount(user1, 3))
        });

        startHoax(user1);
        (IEVC.BatchItemResult[] memory batchItemsResult,,) = evc.batchSimulation(items);

        (address[] memory collaterals, uint256[] memory collateralValues, uint256 liabilityValue) =
            abi.decode(batchItemsResult[6].result, (address[], uint256[], uint256));

        assertEq(collaterals.length, 1);
        assertEq(collaterals[0], address(eTST));
        assertApproxEqAbs(collateralValues[0], 0.24e18, 0.001e18);
        assertApproxEqAbs(liabilityValue, 0.083e18, 0.001e18);

        uint256 balance2 = abi.decode(batchItemsResult[7].result, (uint256));
        uint256 balance3 = abi.decode(batchItemsResult[8].result, (uint256));

        assertEq(balance2, 0.6e18);
        assertEq(balance3, 1e18);

        // Do a real one
        items = new IEVC.BatchItem[](8);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.transfer.selector, getSubAccount(user1, 1), 1e18)
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: getSubAccount(user1, 1),
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.approve.selector, user1, type(uint256).max)
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(
                eTST.transferFrom.selector, getSubAccount(user1, 1), getSubAccount(user1, 2), 0.6e18
            )
        });
        items[3] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableCollateral.selector, getSubAccount(user1, 1), address(eTST))
        });
        items[4] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, getSubAccount(user1, 1), address(eTST2))
        });
        items[5] = IEVC.BatchItem({
            onBehalfOfAccount: getSubAccount(user1, 1),
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 1e18, user1)
        });
        items[6] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user1, address(eTST2))
        });
        items[7] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 1e18, user1)
        });

        evc.batch(items);

        assertEq(eTST.balanceOf(getSubAccount(user1, 1)), 0.4e18);
        assertEq(eTST2.debtOf(getSubAccount(user1, 1)), 1e18);
        assertEq(eTST.balanceOf(getSubAccount(user1, 2)), 0.6e18);
        assertEq(evc.getCollaterals(getSubAccount(user1, 1))[0], address(eTST));
    }

    //call to unknown contract is permitted
    function test_callUnknownContract() public {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(assetTST),
            value: 0,
            data: abi.encodeWithSelector(assetTST.name.selector)
        });
        startHoax(user1);
        (IEVC.BatchItemResult[] memory batchItemsResult,,) = evc.batchSimulation(items);

        assertEq(batchItemsResult[0].success, true);
        string memory name = abi.decode(batchItemsResult[0].result, (string));
        assertEq(name, "Test Token");
    }

    //batch reentrancy is allowed
    function test_batchReentrancyAllowed() public {
        assertEq(eTST.balanceOf(getSubAccount(user1, 1)), 0);

        IEVC.BatchItem[] memory items1 = new IEVC.BatchItem[](1);
        items1[0] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.transfer.selector, getSubAccount(user1, 1), 1e18)
        });

        IEVC.BatchItem[] memory items2 = new IEVC.BatchItem[](2);
        items2[0] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST),
            value: 0,
            data: abi.encodeWithSelector(eTST.transfer.selector, getSubAccount(user1, 1), 1e18)
        });
        items2[1] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.batch.selector, items1)
        });

        startHoax(user1);
        evc.batch(items2);

        assertEq(eTST.balanceOf(getSubAccount(user1, 1)), 2e18);
    }

    //simulate a batch execution without liquidity checks
    function test_batchSimulation_withoutLiquidityChecks() public {
        oracle.setPrice(address(eTST), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 0.4e18);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](3);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeWithSelector(evc.enableController.selector, user1, address(eTST2))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 10e18, user1)
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.accountLiquidity.selector, user1, false)
        });

        startHoax(user1);
        (IEVC.BatchItemResult[] memory batchItemsResult, IEVC.StatusCheckResult[] memory accountsStatusCheckResult,) =
            evc.batchSimulation(items);

        assertEq(accountsStatusCheckResult[0].result, abi.encodeWithSignature("E_AccountLiquidity()"));
        (uint256 collateralValue, uint256 liabilityValue) = abi.decode(batchItemsResult[2].result, (uint256, uint256));

        // health score < 1
        assertEq(collateralValue * 1e18 / liabilityValue, 0.75e18);
    }

    //batch simulation executes all items
    function test_batchSimulation_executesAllItems() public {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](3);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 0.1e18, user1)
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(assetTST),
            value: 0,
            data: abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                address(0),
                address(0),
                type(uint256).max,
                0,
                0,
                bytes32("0"),
                bytes32("0")
            )
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: user1,
            targetContract: address(eTST2),
            value: 0,
            data: abi.encodeWithSelector(eTST2.borrow.selector, 10e18, user1)
        });

        startHoax(user1);
        (IEVC.BatchItemResult[] memory batchItemsResult,,) = evc.batchSimulation(items);

        assertEq(batchItemsResult[1].success, false);
        bytes memory err = abi.encodeWithSignature("Error(string)", "permit: invalid signature");
        assertEq(batchItemsResult[1].result, err);
    }
}
