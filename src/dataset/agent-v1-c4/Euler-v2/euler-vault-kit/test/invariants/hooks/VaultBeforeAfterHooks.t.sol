// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import "../../../src/EVault/shared/types/Types.sol";
import "../../../src/EVault/shared/types/AmountCap.sol";

// Test Helpers
import {Pretty, Strings} from "../utils/Pretty.sol";

// Test Contracts
import {BaseHooks} from "../base/BaseHooks.t.sol";

import "forge-std/console.sol";

/// @title Vault Before After Hooks
/// @notice Helper contract for before and after hooks
/// @dev This contract is inherited by handlers
abstract contract VaultBeforeAfterHooks is BaseHooks {
    uint32 internal constant INIT_OPERATION_FLAG = 1 << 31;

    using Strings for string;
    using Pretty for uint256;
    using Pretty for int256;
    using Pretty for bool;

    struct VaultVars {
        // Total Supply
        uint256 totalSupplyBefore;
        uint256 totalSupplyAfter;
        // Exchange Rate
        uint256 exchangeRateBefore;
        uint256 exchangeRateAfter;
        // ERC4626
        uint256 totalAssetsBefore;
        uint256 totalAssetsAfter;
        // Supply Cap
        uint256 supplyCapBefore;
        uint256 supplyCapAfter;
        // Fees
        uint256 accumulatedFeesBefore;
        uint256 accumulatedFeesAfter;
        uint256 accumulatedFeesAssetsBefore;
        uint256 accumulatedFeesAssetsAfter;
    }

    VaultVars vaultVars;

    function _vaultHooksBefore() internal {
        // Exchange Rate
        vaultVars.exchangeRateBefore = _calculateExchangeRate();
        // ERC4626
        vaultVars.totalAssetsBefore = eTST.totalAssets();
        // Total Supply
        vaultVars.totalSupplyBefore = eTST.totalSupply();
        // Caps
        (uint16 _supplyCap,) = eTST.caps();
        vaultVars.supplyCapBefore = AmountCap.wrap(_supplyCap).resolve();
        // Fees
        vaultVars.accumulatedFeesBefore = eTST.accumulatedFees();
        vaultVars.accumulatedFeesAssetsBefore = eTST.accumulatedFeesAssets();
    }

    function _vaultHooksAfter() internal {
        // Exchange Rate
        vaultVars.exchangeRateAfter = _calculateExchangeRate();
        // ERC4626
        vaultVars.totalAssetsAfter = eTST.totalAssets();
        // Total Supply
        vaultVars.totalSupplyAfter = eTST.totalSupply();
        // Caps
        (uint16 _supplyCap,) = eTST.caps();
        vaultVars.supplyCapAfter = AmountCap.wrap(_supplyCap).resolve();
        // Fees
        vaultVars.accumulatedFeesAfter = eTST.accumulatedFees();
        vaultVars.accumulatedFeesAssetsAfter = eTST.accumulatedFeesAssets();
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                     POST CONDITIONS                                       //
    /////////////////////////////////////////////////////////////////////////////////////////////*/

    function assert_VM_INVARIANT_B() internal {
        assertTrue(
            (vaultVars.totalSupplyAfter > vaultVars.totalSupplyBefore && vaultVars.supplyCapAfter != 0)
                ? (vaultVars.supplyCapAfter >= vaultVars.totalSupplyAfter)
                : true,
            VM_INVARIANT_B
        );
    }

    function assert_LM_INVARIANT_B() internal {
        if (eTST.isFlagSet(CFG_DONT_SOCIALIZE_DEBT)) {
            assertGe(vaultVars.exchangeRateAfter, vaultVars.exchangeRateBefore, LM_INVARIANT_B);
        }
    }
}
