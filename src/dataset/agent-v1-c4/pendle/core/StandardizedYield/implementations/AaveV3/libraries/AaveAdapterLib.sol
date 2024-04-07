// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./WadRayMath.sol";

library AaveAdapterLib {
    // Also denote this function as f(share) for a given (constant) index
    function calcSharesToAssetDown(uint256 amountShares, uint256 index) internal pure returns (uint256) {
        return (amountShares * index) / WadRayMath.RAY;
    }

    function calcSharesFromAssetDown(uint256 amountAssets, uint256 index) internal pure returns (uint256) {
        return (amountAssets * WadRayMath.RAY) / index;
    }

    function calcSharesFromAssetUp(uint256 amountAssets, uint256 index) internal pure returns (uint256) {
        return WadRayMath.rayDiv(amountAssets, index);
    }
}
