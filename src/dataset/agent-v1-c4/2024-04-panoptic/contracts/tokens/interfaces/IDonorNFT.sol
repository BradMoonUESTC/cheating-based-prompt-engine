// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {PanopticPool} from "@contracts/PanopticPool.sol";

interface IDonorNFT {
    /// @notice Called to issue reward NFT to the deployer of a new `PanopticPool` through `PanopticFactory`.
    /// @param deployer The address that deployed `newPoolContract` and donated funds for full-range liquidity
    /// @param newPoolContract The address of the `PanopticPool` that was deployed
    /// @param token0 Token0 of the Uniswap pool `newPoolContract` was deployed on
    /// @param token1 Token1 of the Uniswap pool `newPoolContract` was deployed on
    /// @param fee The fee tier, in hundredths of bips, of the Uniswap pool `newPoolContract` was deployed on
    function issueNFT(
        address deployer,
        PanopticPool newPoolContract,
        address token0,
        address token1,
        uint24 fee
    ) external;
}
