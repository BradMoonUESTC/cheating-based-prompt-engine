// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase, ProtocolConfig} from "./EVaultTestBase.t.sol";
import {Errors} from "../../../src/EVault/shared/Errors.sol";
import {GovernanceModule} from "../../../src/EVault/modules/Governance.sol";
import "../../../src/EVault/modules/Governance.sol";
import "../../../src/EVault/shared/Constants.sol";
import "../../../src/EVault/shared/types/Types.sol";

uint16 constant DEFAULT_INTEREST_FEE = 0.1e4;

contract ERC4626Test_ProtocolConfig is EVaultTestBase {
    using TypesLib for uint256;

    address user = makeAddr("user");

    function setUp() public override {
        super.setUp();

        assetTST.mint(user, type(uint256).max);
        vm.prank(user);
        assetTST.approve(address(eTST), type(uint256).max);
    }

    function test_contructor_badAdminOrReceiver() public {
        vm.expectRevert(ProtocolConfig.E_InvalidAdmin.selector);
        new ProtocolConfig(address(0), address(1));

        vm.expectRevert(ProtocolConfig.E_InvalidReceiver.selector);
        new ProtocolConfig(address(1), address(0));
    }

    function test_interestFees_normal() public {
        assertEq(eTST.interestFee(), DEFAULT_INTEREST_FEE);

        vm.expectRevert(Errors.E_BadFee.selector);
        eTST.setInterestFee(0.005e4);

        eTST.setInterestFee(1e4);
        assertEq(eTST.interestFee(), 1e4);

        eTST.setInterestFee(0.1e4);
        assertEq(eTST.interestFee(), 0.1e4);

        eTST.setInterestFee(0.9e4);
        assertEq(eTST.interestFee(), 0.9e4);
    }

    function test_interestFees_extended() public {
        vm.prank(admin);
        protocolConfig.setVaultInterestFeeRange(address(eTST), true, 0.05e4, 1e4);

        eTST.setInterestFee(0.08e4);
        assertEq(eTST.interestFee(), 0.08e4);

        vm.expectRevert(Errors.E_BadFee.selector);
        eTST.setInterestFee(0.001e4);

        eTST.setInterestFee(0.55e4);
        assertEq(eTST.interestFee(), 0.55e4);

        eTST.setInterestFee(1e4);
        assertEq(eTST.interestFee(), 1e4);
    }

    function test_interestFees_rogueProtocolConfig() public {
        vm.prank(admin);
        protocolConfig.setVaultInterestFeeRange(address(eTST), true, 0.8e4, 0.9e4);

        // Vault won't call into protocolConfig with reasonable interestFee

        eTST.setInterestFee(0.35e4);
        assertEq(eTST.interestFee(), 0.35e4);

        // But will outside the always-valid range

        vm.expectRevert(Errors.E_BadFee.selector);
        eTST.setInterestFee(0.05e4);
    }

    function test_override_interestFeeRanges() public {
        vm.prank(admin);
        protocolConfig.setVaultInterestFeeRange(address(eTST), true, 0.1e4, 1e4);

        (uint16 vaultMinInterestFee, uint16 vaultMaxInterestFee) = protocolConfig.interestFeeRange(address(eTST));

        assertEq(vaultMinInterestFee, 0.1e4);
        assertEq(vaultMaxInterestFee, 1e4);

        // reset vault to use generic ranges
        vm.prank(admin);
        protocolConfig.setVaultInterestFeeRange(address(eTST), false, 0, 0);

        (uint16 genericMinInterestFee, uint16 genericMaxInterestFee) = protocolConfig.interestFeeRange(address(0));
        (vaultMinInterestFee, vaultMaxInterestFee) = protocolConfig.interestFeeRange(address(eTST));

        assertEq(vaultMinInterestFee, genericMinInterestFee);
        assertEq(vaultMaxInterestFee, genericMaxInterestFee);
    }

    function test_updateProtocolConfig() public {
        address newFeeReceiver = makeAddr("newFeeReceiver");

        vm.expectRevert(ProtocolConfig.E_InvalidReceiver.selector);
        vm.prank(admin);
        protocolConfig.setFeeReceiver(address(0));

        vm.prank(admin);
        protocolConfig.setFeeReceiver(newFeeReceiver);

        (address protocolFeeReceiver,) = protocolConfig.protocolFeeConfig(address(0));
        assertEq(protocolFeeReceiver, newFeeReceiver);

        vm.prank(admin);
        protocolConfig.setProtocolFeeShare(0.2e4);

        (, uint16 feeShare) = protocolConfig.protocolFeeConfig(address(0));
        assertEq(feeShare, 0.2e4);
    }

    function test_override_feeConfig() public {
        address newFeeReceiver = makeAddr("newFeeReceiver");
        uint16 newFeeShare = 0.2e4;

        vm.prank(admin);
        protocolConfig.setVaultFeeConfig(address(eTST), true, newFeeReceiver, newFeeShare);

        (address feeReceiver, uint256 feeShare) = protocolConfig.protocolFeeConfig(address(eTST));

        assertEq(feeReceiver, newFeeReceiver);
        assertEq(feeShare, newFeeShare);

        // reset vault to use generic ranges
        vm.prank(admin);
        protocolConfig.setVaultFeeConfig(address(eTST), false, newFeeReceiver, newFeeShare);

        (address genericFeeReceiver, uint16 genericFeeShare) = protocolConfig.protocolFeeConfig(address(0));
        (feeReceiver, feeShare) = protocolConfig.protocolFeeConfig(address(eTST));

        assertEq(genericFeeReceiver, feeReceiver);
        assertEq(genericFeeShare, feeShare);

        // zero out the config slot
        vm.prank(admin);
        protocolConfig.setVaultFeeConfig(address(eTST), false, address(0), 0);

        (genericFeeReceiver, genericFeeShare) = protocolConfig.protocolFeeConfig(address(0));
        (feeReceiver, feeShare) = protocolConfig.protocolFeeConfig(address(eTST));

        assertEq(genericFeeReceiver, feeReceiver);
        assertEq(genericFeeShare, feeShare);
    }

    function test_setInterestFeeRange() public {
        uint16 newMinInterestFee = 0.6e4;
        uint16 newMaxInterestFee = 1e4;

        vm.prank(admin);
        protocolConfig.setInterestFeeRange(newMinInterestFee, newMaxInterestFee);

        (uint16 minInterestFee, uint16 maxInterestFee) = protocolConfig.interestFeeRange(address(0));

        assertEq(minInterestFee, newMinInterestFee);
        assertEq(maxInterestFee, newMaxInterestFee);
    }

    function test_invalid_configs() public {
        vm.startPrank(admin);

        // Bad config values

        vm.expectRevert(ProtocolConfig.E_InvalidConfigValue.selector);
        protocolConfig.setProtocolFeeShare(1e4 + 1);

        vm.expectRevert(ProtocolConfig.E_InvalidConfigValue.selector);
        protocolConfig.setInterestFeeRange(0, 1e4 + 1);

        vm.expectRevert(ProtocolConfig.E_InvalidConfigValue.selector);
        protocolConfig.setInterestFeeRange(1e4 + 1, 1e4 + 2);

        vm.expectRevert(ProtocolConfig.E_InvalidConfigValue.selector);
        protocolConfig.setInterestFeeRange(0.6e4, 0.4e4);

        vm.expectRevert(ProtocolConfig.E_InvalidConfigValue.selector);
        protocolConfig.setVaultInterestFeeRange(address(eTST), true, 0.1e4, 1e4 + 1);

        vm.expectRevert(ProtocolConfig.E_InvalidConfigValue.selector);
        protocolConfig.setVaultInterestFeeRange(address(eTST), true, 1e4 + 1, 1e4 + 2);

        vm.expectRevert(ProtocolConfig.E_InvalidConfigValue.selector);
        protocolConfig.setVaultInterestFeeRange(address(eTST), true, 0.6e4, 0.4e4);

        vm.expectRevert(ProtocolConfig.E_InvalidConfigValue.selector);
        protocolConfig.setVaultFeeConfig(address(eTST), true, user, 1e4 + 1);

        vm.expectRevert(ProtocolConfig.E_InvalidReceiver.selector);
        protocolConfig.setVaultFeeConfig(address(eTST), true, address(0), 1e4);

        // Bad vaults

        vm.expectRevert(ProtocolConfig.E_InvalidVault.selector);
        protocolConfig.setVaultInterestFeeRange(address(0), true, 0.1e4, 0.2e4);

        vm.expectRevert(ProtocolConfig.E_InvalidVault.selector);
        protocolConfig.setVaultFeeConfig(address(0), true, address(0), 0.1e4);
    }

    function test_setAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.startPrank(admin);

        vm.expectRevert(ProtocolConfig.E_InvalidAdmin.selector);
        protocolConfig.setAdmin(address(0));

        protocolConfig.setAdmin(newAdmin);
        assertEq(protocolConfig.admin(), newAdmin);
    }
}
