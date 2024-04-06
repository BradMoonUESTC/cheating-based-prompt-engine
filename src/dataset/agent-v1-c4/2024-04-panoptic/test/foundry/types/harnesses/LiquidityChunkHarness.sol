// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {LiquidityChunk, LiquidityChunkLibrary} from "@types/LiquidityChunk.sol";

/// @title LeftRightHarness: A harness to expose the LeftRight library for code coverage analysis.
/// @notice Replicates the interface of the LeftRight library, passing through any function calls
/// @author Axicon Labs Limited
contract LiquidityChunkHarness {
    /**
     * @notice Create a new liquidity chunk given by its bounding ticks and its liquidity.
     * @param _tickLower the lower tick of this chunk
     * @param _tickUpper the upper tick of this chunk
     * @param amount the amount of liquidity to add to this chunk.
     * @return the new liquidity chunk
     */
    function createChunk(
        int24 _tickLower,
        int24 _tickUpper,
        uint128 amount
    ) public pure returns (LiquidityChunk) {
        LiquidityChunk r = LiquidityChunkLibrary.createChunk(_tickLower, _tickUpper, amount);
        return r;
    }

    /**
     * @notice Add liquidity to the chunk.
     * @param self the LiquidityChunk.
     * @param amount the amount of liquidity to add to this chunk.
     * @return the chunk with added liquidity
     */
    function addLiquidity(
        LiquidityChunk self,
        uint128 amount
    ) public pure returns (LiquidityChunk) {
        LiquidityChunk r = LiquidityChunkLibrary.addLiquidity(self, amount);
        return r;
    }

    /**
     * @notice Add the lower tick to this chunk.
     * @param self the LiquidityChunk.
     * @param _tickLower the lower tick to add.
     * @return the chunk with added lower tick
     */
    function addTickLower(
        LiquidityChunk self,
        int24 _tickLower
    ) public pure returns (LiquidityChunk) {
        LiquidityChunk r = LiquidityChunkLibrary.addTickLower(self, _tickLower);
        return r;
    }

    /**
     * @notice Add the upper tick to this chunk.
     * @param self the LiquidityChunk.
     * @param _tickUpper the upper tick to add.
     * @return the chunk with added upper tick
     */
    function addTickUpper(
        LiquidityChunk self,
        int24 _tickUpper
    ) public pure returns (LiquidityChunk) {
        LiquidityChunk r = LiquidityChunkLibrary.addTickUpper(self, _tickUpper);
        return r;
    }

    /// @notice Overwrites the lower tick to this chunk.
    /// @param self the LiquidityChunk
    /// @param _tickLower the lower tick to add
    /// @return the chunk with added lower tick
    function updateTickLower(
        LiquidityChunk self,
        int24 _tickLower
    ) public pure returns (LiquidityChunk) {
        LiquidityChunk r = LiquidityChunkLibrary.updateTickLower(self, _tickLower);
        return r;
    }

    /// @notice Overwrites the upper tick to this chunk.
    /// @param self the LiquidityChunk
    /// @param _tickUpper the upper tick to add
    /// @return the chunk with added upper tick
    function updateTickUpper(
        LiquidityChunk self,
        int24 _tickUpper
    ) public pure returns (LiquidityChunk) {
        LiquidityChunk r = LiquidityChunkLibrary.updateTickUpper(self, _tickUpper);
        return r;
    }

    /*****************************************************************/
    /*
    /* READ FROM A LIQUIDITYCHUNK
    /*
    /*****************************************************************/

    /**
     * @notice Get the lower tick of a chunk.
     * @param self the LiquidityChunk LiquidityChunk.
     * @return the lower tick of this chunk.
     */
    function tickLower(LiquidityChunk self) public pure returns (int24) {
        int24 r = LiquidityChunkLibrary.tickLower(self);
        return r;
    }

    /**
     * @notice Get the upper tick of a chunk.
     * @param self the LiquidityChunk LiquidityChunk.
     * @return the upper tick of this chunk.
     */
    function tickUpper(LiquidityChunk self) public pure returns (int24) {
        int24 r = LiquidityChunkLibrary.tickUpper(self);
        return r;
    }

    /**
     * @notice Get the amount of liquidity/size of a chunk.
     * @param self the LiquidityChunk LiquidityChunk.
     * @return the size of this chunk.
     */
    function liquidity(LiquidityChunk self) public pure returns (uint128) {
        uint128 r = LiquidityChunkLibrary.liquidity(self);
        return r;
    }
}
