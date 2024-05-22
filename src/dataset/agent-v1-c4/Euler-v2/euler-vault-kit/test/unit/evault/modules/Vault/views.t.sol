// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../EVaultTestBase.t.sol";

contract VaultTest_views is EVaultTestBase {
    function test_Vault_basicViews() public {
        assertEq(eTST.asset(), address(assetTST));
        address creator = makeAddr("creator");
        vm.prank(creator);
        address newVault =
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount));
        assertEq(IEVault(newVault).creator(), creator);
    }
}
