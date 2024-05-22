// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {EVaultTestBase} from "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";

contract MaliciousController {
    IEVC immutable evc;

    constructor(IEVC _evc) {
        evc = _evc;
    }

    function checkAccountStatus(address, address[] calldata) external pure returns (bytes4) {
        return this.checkAccountStatus.selector;
    }

    function performExploit(address vault, address governor, bytes calldata data) external {
        evc.controlCollateral(vault, governor, 0, data);
    }
}

contract GovernanceTest_GovernorOnly is EVaultTestBase {
    function setUp() public override {
        super.setUp();
    }

    function test_GovernorAdmin() public {
        eTST.setFeeReceiver(address(0));
        eTST.setLTV(address(0), 0, 0, 0);
        eTST.clearLTV(address(0));
        eTST.setMaxLiquidationDiscount(0);
        eTST.setLiquidationCoolOffTime(0);
        eTST.setInterestRateModel(address(0));
        eTST.setHookConfig(address(0), 0);
        eTST.setConfigFlags(0);
        eTST.setCaps(0, 0);
        eTST.setInterestFee(0.1e4);
        eTST.setGovernorAdmin(address(0));

        // restore the governor admin
        vm.prank(address(0));
        eTST.setGovernorAdmin(address(this));

        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setFeeReceiver, address(0)));
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setLTV, (address(0), 0, 0, 0)));
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.clearLTV, address(0)));
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setMaxLiquidationDiscount, 0));
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setLiquidationCoolOffTime, 0));
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setInterestRateModel, address(0)));
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setHookConfig, (address(0), 0)));
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setConfigFlags, 0));
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setCaps, (0, 0)));
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setInterestFee, 0.1e4));
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setGovernorAdmin, address(0)));
    }

    function testFuzz_UnauthorizedRevert_GovernorAdmin(uint8 id) public {
        vm.assume(id != 0);
        address subAccount = getSubAccount(address(this), id);
        eTST.setGovernorAdmin(subAccount);

        // direct calls are unauthorized if msg.sender != governor
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setFeeReceiver(address(0));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setLTV(address(0), 0, 0, 0);
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.clearLTV(address(0));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setMaxLiquidationDiscount(0);
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setLiquidationCoolOffTime(0);
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setInterestRateModel(address(0));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setHookConfig(address(0), 0);
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setConfigFlags(0);
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setCaps(0, 0);
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setInterestFee(0.1e4);
        vm.expectRevert(Errors.E_Unauthorized.selector);
        eTST.setGovernorAdmin(address(0));

        // restore the governor admin
        vm.prank(subAccount);
        eTST.setGovernorAdmin(address(this));

        // calls through the EVC are unauthorized, even if the authenticated account is the governor's sub-account
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), subAccount, 0, abi.encodeCall(eTST.setFeeReceiver, address(0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), subAccount, 0, abi.encodeCall(eTST.setLTV, (address(0), 0, 0, 0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), subAccount, 0, abi.encodeCall(eTST.clearLTV, address(0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), subAccount, 0, abi.encodeCall(eTST.setMaxLiquidationDiscount, 0));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), subAccount, 0, abi.encodeCall(eTST.setLiquidationCoolOffTime, 0));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), subAccount, 0, abi.encodeCall(eTST.setInterestRateModel, address(0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), subAccount, 0, abi.encodeCall(eTST.setHookConfig, (address(0), 0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), subAccount, 0, abi.encodeCall(eTST.setConfigFlags, 0));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), subAccount, 0, abi.encodeCall(eTST.setCaps, (0, 0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), subAccount, 0, abi.encodeCall(eTST.setInterestFee, 0.1e4));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), subAccount, 0, abi.encodeCall(eTST.setGovernorAdmin, address(0)));

        // set address(1) as the operator
        evc.setOperator(evc.getAddressPrefix(address(this)), address(1), type(uint256).max);

        // calls through the EVC are unauthorized, even if the authenticated account is the governor
        // but the operation is executed by the operator
        vm.startPrank(address(1));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setFeeReceiver, address(0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setLTV, (address(0), 0, 0, 0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setInterestRateModel, address(0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setHookConfig, (address(0), 0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setConfigFlags, 0));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setCaps, (0, 0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setInterestFee, 0.1e4));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        evc.call(address(eTST), address(this), 0, abi.encodeCall(eTST.setGovernorAdmin, address(0)));
        vm.stopPrank();

        // enable this vault as collateral for the governor
        evc.enableCollateral(address(this), address(eTST));

        // enable malicious controller for the governor
        MaliciousController controller = new MaliciousController(evc);
        evc.enableController(address(this), address(controller));

        // try to exploit governance system using malicious controller contract
        vm.startPrank(address(controller));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        controller.performExploit(address(eTST), address(this), abi.encodeCall(eTST.setFeeReceiver, address(0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        controller.performExploit(address(eTST), address(this), abi.encodeCall(eTST.setLTV, (address(0), 0, 0, 0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        controller.performExploit(address(eTST), address(this), abi.encodeCall(eTST.setInterestRateModel, address(0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        controller.performExploit(address(eTST), address(this), abi.encodeCall(eTST.setHookConfig, (address(0), 0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        controller.performExploit(address(eTST), address(this), abi.encodeCall(eTST.setConfigFlags, 0));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        controller.performExploit(address(eTST), address(this), abi.encodeCall(eTST.setCaps, (0, 0)));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        controller.performExploit(address(eTST), address(this), abi.encodeCall(eTST.setInterestFee, 0.1e4));
        vm.expectRevert(Errors.E_Unauthorized.selector);
        controller.performExploit(address(eTST), address(this), abi.encodeCall(eTST.setGovernorAdmin, address(0)));
    }
}
