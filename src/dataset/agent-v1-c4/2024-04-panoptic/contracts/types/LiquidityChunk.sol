// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// Custom types
import {TokenId} from "@types/TokenId.sol";

type LiquidityChunk is uint256;
using LiquidityChunkLibrary for LiquidityChunk global;

/// @title A Panoptic Liquidity Chunk. Tracks Tick Range and Liquidity Information for a "chunk." Used to track movement of chunks.
/// @author Axicon Labs Limited
///
/// @notice A liquidity chunk is an amount of `liquidity` (an amount of WETH, e.g.) deployed between two ticks: `tickLower` and `tickUpper`
/// into a concentrated liquidity AMM .
//
//                liquidity
//                    ▲      liquidity chunk
//                    │        │
//                    │    ┌───▼────┐   ▲
//                    │    │        │   │ liquidity/size
//      Other AMM     │  ┌─┴────────┴─┐ ▼ of chunk
//      liquidity  ───┼──┼─►          │
//                    │  │            │
//                    └──┴─▲────────▲─┴──► price ticks
//                         │        │
//                         │        │
//                    tickLower     │
//                              tickUpper
//
/// @notice Track Tick Range Information. Lower and Upper ticks including the liquidity deployed within that range.
/// @notice This is used to track information about a leg in the Option Position identified by `TokenId.sol`.
/// @notice We pack this tick range info into a uint256.
//
// PACKING RULES FOR A LIQUIDITYCHUNK:
// =================================================================================================
//  From the LSB to the MSB:
// (1) Liquidity        128bits  : The liquidity within the chunk (uint128).
// ( ) (Zero-bits)       80bits  : Zero-bits to match a total uint256.
// (2) tick Upper        24bits  : The upper tick of the chunk (int24).
// (3) tick Lower        24bits  : The lower tick of the chunk (int24).
// Total                256bits  : Total bits used by a chunk.
// ===============================================================================================
//
// The bit pattern is therefore:
//
//           (3)             (2)             ( )                (1)
//    <-- 24 bits -->  <-- 24 bits -->  <-- 80 bits -->   <-- 128 bits -->
//        tickLower       tickUpper         Zeros             Liquidity
//
//        <--- most significant bit        least significant bit --->
//
library LiquidityChunkLibrary {
    /// @notice AND mask to strip the `tickLower` value from a packed LiquidityChunk
    uint256 internal constant CLEAR_TL_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    /// @notice AND mask to strip the `tickUpper` value from a packed LiquidityChunk
    uint256 internal constant CLEAR_TU_MASK =
        0xFFFFFF000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    /*//////////////////////////////////////////////////////////////
                                ENCODING
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new `LiquidityChunk` given by its bounding ticks and its liquidity.
    /// @param _tickLower The lower tick of the chunk
    /// @param _tickUpper The upper tick of the chunk
    /// @param amount The amount of liquidity to add to the chunk
    /// @return The new chunk with the given liquidity and tick range
    function createChunk(
        int24 _tickLower,
        int24 _tickUpper,
        uint128 amount
    ) internal pure returns (LiquidityChunk) {
        unchecked {
            return
                LiquidityChunk.wrap(
                    (uint256(uint24(_tickLower)) << 232) +
                        (uint256(uint24(_tickUpper)) << 208) +
                        uint256(amount)
                );
        }
    }

    /// @notice Add liquidity to `self`.
    /// @param self The LiquidityChunk to add liquidity to
    /// @param amount The amount of liquidity to add to `self`
    /// @return `self` with added liquidity `amount`
    function addLiquidity(
        LiquidityChunk self,
        uint128 amount
    ) internal pure returns (LiquidityChunk) {
        unchecked {
            return LiquidityChunk.wrap(LiquidityChunk.unwrap(self) + amount);
        }
    }

    /// @notice Add the lower tick to `self`.
    /// @param self The LiquidityChunk to add the lower tick to
    /// @param _tickLower The lower tick to add to `self`
    /// @return `self` with added lower tick `_tickLower`
    function addTickLower(
        LiquidityChunk self,
        int24 _tickLower
    ) internal pure returns (LiquidityChunk) {
        unchecked {
            return
                LiquidityChunk.wrap(
                    LiquidityChunk.unwrap(self) + (uint256(uint24(_tickLower)) << 232)
                );
        }
    }

    /// @notice Add the upper tick to `self`.
    /// @param self The LiquidityChunk to add the upper tick to
    /// @param _tickUpper The upper tick to add to `self`
    /// @return `self` with added upper tick `_tickUpper`
    function addTickUpper(
        LiquidityChunk self,
        int24 _tickUpper
    ) internal pure returns (LiquidityChunk) {
        unchecked {
            // convert tick upper to uint24 as explicit conversion from int24 to uint256 is not allowed
            return
                LiquidityChunk.wrap(
                    LiquidityChunk.unwrap(self) + ((uint256(uint24(_tickUpper))) << 208)
                );
        }
    }

    /// @notice Overwrites the lower tick on `self`.
    /// @param self The LiquidityChunk to overwrite the lower tick on
    /// @param _tickLower The lower tick to overwrite `self` with
    /// @return `self` with `_tickLower` as the new lower tick
    function updateTickLower(
        LiquidityChunk self,
        int24 _tickLower
    ) internal pure returns (LiquidityChunk) {
        unchecked {
            return
                LiquidityChunk.wrap(LiquidityChunk.unwrap(self) & CLEAR_TL_MASK).addTickLower(
                    _tickLower
                );
        }
    }

    /// @notice Overwrites the upper tick on `self`.
    /// @param self The LiquidityChunk to overwrite the upper tick on
    /// @param _tickUpper The upper tick to overwrite `self` with
    /// @return `self` with `_tickUpper` as the new upper tick
    function updateTickUpper(
        LiquidityChunk self,
        int24 _tickUpper
    ) internal pure returns (LiquidityChunk) {
        unchecked {
            // convert tick upper to uint24 as explicit conversion from int24 to uint256 is not allowed
            return
                LiquidityChunk.wrap(LiquidityChunk.unwrap(self) & CLEAR_TU_MASK).addTickUpper(
                    _tickUpper
                );
        }
    }

    /*//////////////////////////////////////////////////////////////
                                DECODING
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the lower tick of `self`.
    /// @param self The LiquidityChunk to get the lower tick from
    /// @return The lower tick of `self`
    function tickLower(LiquidityChunk self) internal pure returns (int24) {
        unchecked {
            return int24(int256(LiquidityChunk.unwrap(self) >> 232));
        }
    }

    /// @notice Get the upper tick of `self`.
    /// @param self The LiquidityChunk to get the upper tick from
    /// @return The upper tick of `self`
    function tickUpper(LiquidityChunk self) internal pure returns (int24) {
        unchecked {
            return int24(int256(LiquidityChunk.unwrap(self) >> 208));
        }
    }

    /// @notice Get the amount of liquidity/size of `self`.
    /// @param self The LiquidityChunk to get the liquidity from
    /// @return The liquidity of `self`
    function liquidity(LiquidityChunk self) internal pure returns (uint128) {
        unchecked {
            return uint128(LiquidityChunk.unwrap(self));
        }
    }
}
