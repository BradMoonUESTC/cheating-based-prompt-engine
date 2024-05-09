// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

/************
@title INFTOracleGetter interface
@notice Interface for getting NFT price oracle.*/
interface INFTOracleGetter {
    /* CAUTION: Price uint is ETH based (WEI, 18 decimals) */
    /***********
    @dev returns the asset price in ETH
     */
    function getAssetPrice(address asset) external view returns (uint256);
}
