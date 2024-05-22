// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../EVaultTestBase.t.sol";

contract ERC20Test_views is EVaultTestBase {
    function test_basicViews() public view {
        assertEq(eTST.name(), "EVK Vault eTST-1");
        assertEq(eTST.symbol(), "eTST-1");
        assertEq(eTST.decimals(), assetTST.decimals());

        assertEq(eTST2.name(), "EVK Vault eTST2-1");
        assertEq(eTST2.symbol(), "eTST2-1");
        assertEq(eTST2.decimals(), assetTST2.decimals());
    }

    function test_vaultSymbolsInSequence() public {
        // Numbers are incremented correctly

        for (uint256 i = 2; i < 120; i++) {
            IEVault v = IEVault(
                factory.createProxy(
                    address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount)
                )
            );
            if (i == 8) assertEq(v.symbol(), "eTST-8");
            else if (i == 34) assertEq(v.symbol(), "eTST-34");
            else if (i == 106) assertEq(v.symbol(), "eTST-106");
        }

        // Each asset has its own counter

        {
            IEVault v = IEVault(
                factory.createProxy(
                    address(0), true, abi.encodePacked(address(assetTST2), address(oracle), unitOfAccount)
                )
            );
            assertEq(v.symbol(), "eTST2-2");
        }
    }
}
