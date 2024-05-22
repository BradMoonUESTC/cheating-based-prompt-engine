// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../EVaultTestBase.t.sol";
import {Errors} from "../../../../../src/EVault/shared/Errors.sol";
import {Events} from "../../../../../src/EVault/shared/Events.sol";
import {IComponent} from "../../../../../src/GenericFactory/GenericFactory.sol";
import {MetaProxyDeployer} from "../../../../../src/GenericFactory/MetaProxyDeployer.sol";

contract InitializeTests is EVaultTestBase, MetaProxyDeployer {
    function test_cant_reinitialize() public {
        // On vault
        vm.expectRevert(Errors.E_Initialized.selector);
        eTST.initialize(msg.sender);

        // Direct on implementation module
        vm.expectRevert(Errors.E_Initialized.selector);
        IEVault(initializeModule).initialize(msg.sender);
    }

    function test_trailing_metadata_check(bytes memory input) public {
        vm.assume(input.length != PROXY_METADATA_LENGTH);
        bytes memory trailingData = bytes(input);

        address proxy = deployMetaProxy(address(new Initialize(integrations)), trailingData);
        vm.expectRevert(Errors.E_ProxyMetadata.selector);
        IComponent(proxy).initialize(msg.sender);
    }

    function test_asset_is_a_contract() public {
        bytes memory trailingData = abi.encodePacked(address(0), address(1), address(2));

        address proxy = deployMetaProxy(address(new Initialize(integrations)), trailingData);
        vm.expectRevert(Errors.E_BadAddress.selector);
        IComponent(proxy).initialize(msg.sender);
    }
}
