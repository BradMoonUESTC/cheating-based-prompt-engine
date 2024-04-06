// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// Libraries
import {Constants} from "@libraries/Constants.sol";
import {Errors} from "@libraries/Errors.sol";
import {PanopticMath} from "@libraries/PanopticMath.sol";

type TokenId is uint256;
using TokenIdLibrary for TokenId global;

/// @title Panoptic's tokenId: the fundamental options position.
/// @author Axicon Labs Limited
/// @notice This is the token ID used in the ERC1155 representation of the option position in the SFPM.
/// @notice The SFPM "overloads" the ERC1155 `id` by storing all option information in said `id`.
/// @notice Contains methods for packing and unpacking a Panoptic options position into a uint256 bit pattern.
// PACKING RULES FOR A TOKENID:
// this is how the token Id is packed into its bit-constituents containing position information.
// the following is a diagram to be read top-down in a little endian format
// (so (1) below occupies the first 64 least significant bits, e.g.):
// From the LSB to the MSB:
// ===== 1 time (same for all legs) ==============================================================
//      Property         Size      Offset      Comment
// (0) univ3pool        48bits     0bits      : first 6 bytes of the Uniswap v3 pool address (first 48 bits; little-endian), plus a pseudorandom number in the event of a collision
// (1) tickSpacing      16bits     48bits     : tickSpacing for the univ3pool. Up to 16 bits
// ===== 4 times (one for each leg) ==============================================================
// (2) asset             1bit      0bits      : Specifies the asset (0: token0, 1: token1)
// (3) optionRatio       7bits     1bits      : number of contracts per leg
// (4) isLong            1bit      8bits      : long==1 means liquidity is removed, long==0 -> liquidity is added
// (5) tokenType         1bit      9bits      : put/call: which token is moved when deployed (0 -> token0, 1 -> token1)
// (6) riskPartner       2bits     10bits     : normally its own index. Partner in defined risk position otherwise
// (7) strike           24bits     12bits     : strike price; defined as (tickUpper + tickLower) / 2
// (8) width            12bits     36bits     : width; defined as (tickUpper - tickLower) / tickSpacing
// Total                48bits                : Each leg takes up this many bits
// ===============================================================================================
//
// The bit pattern is therefore, in general:
//
//                        (strike price tick of the 3rd leg)
//                            |             (width of the 2nd leg)
//                            |                   |
// (8)(7)(6)(5)(4)(3)(2)  (8)(7)(6)(5)(4)(3)(2)  (8)(7)(6)(5)(4)(3)(2)   (8)(7)(6)(5)(4)(3)(2)        (1)           (0)
//  <---- 48 bits ---->    <---- 48 bits ---->    <---- 48 bits ---->     <---- 48 bits ---->   <- 16 bits ->   <- 48 bits ->
//         Leg 4                  Leg 3                  Leg 2                   Leg 1          tickSpacing    Univ3 Pool Address
//
//  <--- most significant bit                                                                             least significant bit --->
//
// Some rules of how legs behave (we enforce these in a `validate()` function):
//   - a leg is inactive if it's not part of the position. Technically it means that all bits are zero.
//   - a leg is active if it has an optionRatio > 0 since this must always be set for an active leg.
//   - if a leg is active (e.g. leg 1) there can be no gaps in other legs meaning: if leg 1 is active then leg 3 cannot be active if leg 2 is inactive.
//
// Examples:
//  We can think of the bit pattern as an array starting at bit index 0 going to bit index 255 (so 256 total bits)
//  We also refer to the legs via their index, so leg number 2 has leg index 1 (legIndex) (counting from zero), and in general leg number N has leg index N-1.
//  - the underlying strike price of the 2nd leg (leg index = 1) in this option position starts at bit index  (64 + 12 + 48 * (leg index=1))=123
//  - the tokenType of the 4th leg in this option position starts at bit index 64+9+48*3=217
//  - the Uniswap v3 pool id starts at bit index 0 and ends at bit index 63 (and thus takes up 64 bits).
//  - the width of the 3rd leg in this option position starts at bit index 64+36+48*2=196
library TokenIdLibrary {
    /// @notice AND mask to extract all `isLong` bits for each leg from a TokenId
    uint256 internal constant LONG_MASK =
        0x100_000000000100_000000000100_000000000100_0000000000000000;

    /// @notice AND mask to clear `poolId` from a TokenId
    uint256 internal constant CLEAR_POOLID_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF_0000000000000000;

    /// @notice AND mask to clear all bits except for the option ratios of the legs
    uint256 internal constant OPTION_RATIO_MASK =
        0x0000000000FE_0000000000FE_0000000000FE_0000000000FE_0000000000000000;

    /// @notice AND mask to clear all bits except for the components of the chunk key (strike, width, tokenType) for each leg
    uint256 internal constant CHUNK_MASK =
        0xFFFFFFFFF200_FFFFFFFFF200_FFFFFFFFF200_FFFFFFFFF200_0000000000000000;

    /// @notice AND mask to cut a sign-extended int256 back to an int24
    int256 internal constant BITMASK_INT24 = 0xFFFFFF;

    /*//////////////////////////////////////////////////////////////
                                DECODING
    //////////////////////////////////////////////////////////////*/

    /// @notice The full poolId (Uniswap pool identifier + pool pattern) of this option position.
    /// @param self The TokenId to extract `poolId` from
    /// @return The `poolId` (Panoptic's pool fingerprint, contains the whole 64 bit sequence with the tickSpacing) of the Uniswap V3 pool
    function poolId(TokenId self) internal pure returns (uint64) {
        unchecked {
            return uint64(TokenId.unwrap(self));
        }
    }

    /// @notice The tickSpacing of this option position.
    /// @param self The TokenId to extract `tickSpacing` from
    /// @return The `tickSpacing` of the Uniswap v3 pool
    function tickSpacing(TokenId self) internal pure returns (int24) {
        unchecked {
            return int24(uint24((TokenId.unwrap(self) >> 48) % 2 ** 16));
        }
    }

    /// @notice Get the asset basis for this TokenId.
    /// @dev Which token is the asset - can be token0 (return 0) or token1 (return 1).
    /// @param self The TokenId to extract `asset` from
    /// @param legIndex The leg index of this position (in {0,1,2,3}) to extract `asset` from
    /// @dev Occupies the leftmost bit of the optionRatio 4 bits slot.
    /// @return 0 if asset is token0, 1 if asset is token1
    function asset(TokenId self, uint256 legIndex) internal pure returns (uint256) {
        unchecked {
            return uint256((TokenId.unwrap(self) >> (64 + legIndex * 48)) % 2);
        }
    }

    /// @notice Get the number of contracts multiplier for leg `legIndex`.
    /// @param self The TokenId to extract `optionRatio` at `legIndex` from
    /// @param legIndex The leg index of this position (in {0,1,2,3})
    /// @return The number of contracts multiplier for leg `legIndex`
    function optionRatio(TokenId self, uint256 legIndex) internal pure returns (uint256) {
        unchecked {
            return uint256((TokenId.unwrap(self) >> (64 + legIndex * 48 + 1)) % 128);
        }
    }

    /// @notice Return 1 if the nth leg (leg index `legIndex`) is a long position.
    /// @param self The TokenId to extract `isLong` at `legIndex` from
    /// @param legIndex The leg index of this position (in {0,1,2,3})
    /// @return 1 if long; 0 if not long
    function isLong(TokenId self, uint256 legIndex) internal pure returns (uint256) {
        unchecked {
            return uint256((TokenId.unwrap(self) >> (64 + legIndex * 48 + 8)) % 2);
        }
    }

    /// @notice Get the type of token moved for a given leg (implies a call or put). Either Token0 or Token1.
    /// @param self The TokenId to extract `tokenType` at `legIndex` from
    /// @param legIndex The leg index of this position (in {0,1,2,3})
    /// @return 1 if the token moved is token1 or 0 if the token moved is token0
    function tokenType(TokenId self, uint256 legIndex) internal pure returns (uint256) {
        unchecked {
            return uint256((TokenId.unwrap(self) >> (64 + legIndex * 48 + 9)) % 2);
        }
    }

    /// @notice Get the associated risk partner of the leg index (generally another leg index in the position if enabled or the same leg index if no partner).
    /// @param self The TokenId to extract `riskPartner` at `legIndex` from
    /// @param legIndex The leg index of this position (in {0,1,2,3})
    /// @return The leg index of `legIndex`'s risk partner
    function riskPartner(TokenId self, uint256 legIndex) internal pure returns (uint256) {
        unchecked {
            return uint256((TokenId.unwrap(self) >> (64 + legIndex * 48 + 10)) % 4);
        }
    }

    /// @notice Get the strike price tick of the nth leg (with index `legIndex`).
    /// @param self The TokenId to extract `strike` at `legIndex` from
    /// @param legIndex the leg index of this position (in {0,1,2,3})
    /// @return The strike price (the underlying price of the leg)
    function strike(TokenId self, uint256 legIndex) internal pure returns (int24) {
        unchecked {
            return int24(int256(TokenId.unwrap(self) >> (64 + legIndex * 48 + 12)));
        }
    }

    /// @notice Get the width of the nth leg (index `legIndex`). This is half the tick-range covered by the leg (tickUpper - tickLower)/2.
    /// @dev Return as int24 to be compatible with the strike tick format (they naturally go together).
    /// @param self The TokenId to extract `width` at `legIndex` from
    /// @param legIndex the leg index of this position (in {0,1,2,3})
    /// @return The width of the position
    function width(TokenId self, uint256 legIndex) internal pure returns (int24) {
        unchecked {
            return int24(int256((TokenId.unwrap(self) >> (64 + legIndex * 48 + 36)) % 4096));
        } // "% 4096" = take last (2 ** 12 = 4096) 12 bits
    }

    /*//////////////////////////////////////////////////////////////
                                ENCODING
    //////////////////////////////////////////////////////////////*/

    /// @notice Add the Uniswap V3 Pool pointed to by this option position (contains the entropy and tickSpacing).
    /// @param self The TokenId to add `_poolId` to
    /// @param _poolId The PoolID to add to `self`
    /// @return `self` with `_poolId` added to the PoolID slot
    function addPoolId(TokenId self, uint64 _poolId) internal pure returns (TokenId) {
        unchecked {
            return TokenId.wrap(TokenId.unwrap(self) + _poolId);
        }
    }

    /// @notice Add the `tickSpacing` to the PoolID for `self`.
    /// @param self The TokenId to add `_tickSpacing` to
    /// @param _tickSpacing The tickSpacing to add to `self`
    /// @return `self` with `_tickSpacing` added to the TickSpacing slot in the PoolID.
    function addTickSpacing(TokenId self, int24 _tickSpacing) internal pure returns (TokenId) {
        unchecked {
            return TokenId.wrap(TokenId.unwrap(self) + (uint256(uint24(_tickSpacing)) << 48));
        }
    }

    /// @notice Add the asset basis for this position.
    /// @param self The TokenId to add `_asset` to
    /// @param _asset The asset to add to the Asset slot in `self` for `legIndex`
    /// @param legIndex The leg index of this position (in {0,1,2,3})
    /// @dev Occupies the leftmost bit of the optionRatio 4 bits slot
    /// @return `self` with `_asset` added to the Asset slot
    function addAsset(
        TokenId self,
        uint256 _asset,
        uint256 legIndex
    ) internal pure returns (TokenId) {
        unchecked {
            return
                TokenId.wrap(TokenId.unwrap(self) + (uint256(_asset % 2) << (64 + legIndex * 48)));
        }
    }

    /// @notice Add the number of contracts multiplier to leg index `legIndex`.
    /// @param self The TokenId to add `_optionRatio` to
    /// @param _optionRatio The number of contracts multiplier to add to the OptionRatio slot in `self` for LegIndex
    /// @param legIndex The leg index of the position (in {0,1,2,3})
    /// @return `self` with `_optionRatio` added to the OptionRatio slot for `legIndex`
    function addOptionRatio(
        TokenId self,
        uint256 _optionRatio,
        uint256 legIndex
    ) internal pure returns (TokenId) {
        unchecked {
            return
                TokenId.wrap(
                    TokenId.unwrap(self) + (uint256(_optionRatio % 128) << (64 + legIndex * 48 + 1))
                );
        }
    }

    /// @notice Add "isLong" parameter indicating whether a leg is long (isLong=1) or short (isLong=0).
    /// @notice returns 1 if the nth leg (leg index n-1) is a long position.
    /// @param self The TokenId to add `_isLong` to
    /// @param _isLong The isLong parameter to add to the IsLong slot in `self` for `legIndex`
    /// @param legIndex the leg index of this position (in {0,1,2,3})
    /// @return `self` with `_isLong` added to the IsLong slot for `legIndex`
    function addIsLong(
        TokenId self,
        uint256 _isLong,
        uint256 legIndex
    ) internal pure returns (TokenId) {
        unchecked {
            return TokenId.wrap(TokenId.unwrap(self) + ((_isLong % 2) << (64 + legIndex * 48 + 8)));
        }
    }

    /// @notice Add the type of token moved for a given leg (implies a call or put). Either Token0 or Token1.
    /// @param self The TokenId to add `_tokenType` to
    /// @param _tokenType The tokenType to add to the TokenType slot in `self` for `legIndex`
    /// @param legIndex the leg index of this position (in {0,1,2,3})
    /// @return `self` with `_tokenType` added to the TokenType slot for `legIndex`
    function addTokenType(
        TokenId self,
        uint256 _tokenType,
        uint256 legIndex
    ) internal pure returns (TokenId) {
        unchecked {
            return
                TokenId.wrap(
                    TokenId.unwrap(self) + (uint256(_tokenType % 2) << (64 + legIndex * 48 + 9))
                );
        }
    }

    /// @notice Add the associated risk partner of the leg index (generally another leg in the overall position).
    /// @param self The TokenId to add `_riskPartner` to
    /// @param _riskPartner The riskPartner to add to the RiskPartner slot in `self` for `legIndex`
    /// @param legIndex the leg index of this position (in {0,1,2,3})
    /// @return `self` with `_riskPartner` added to the RiskPartner slot for `legIndex`
    function addRiskPartner(
        TokenId self,
        uint256 _riskPartner,
        uint256 legIndex
    ) internal pure returns (TokenId) {
        unchecked {
            return
                TokenId.wrap(
                    TokenId.unwrap(self) + (uint256(_riskPartner % 4) << (64 + legIndex * 48 + 10))
                );
        }
    }

    /// @notice Add the strike price tick of the nth leg (index `legIndex`).
    /// @param self The TokenId to add `_strike` to
    /// @param _strike The strike price tick to add to the Strike slot in `self` for `legIndex`
    /// @param legIndex the leg index of this position (in {0,1,2,3})
    /// @return `self` with `_strike` added to the Strike slot for `legIndex`
    function addStrike(
        TokenId self,
        int24 _strike,
        uint256 legIndex
    ) internal pure returns (TokenId) {
        unchecked {
            return
                TokenId.wrap(
                    TokenId.unwrap(self) +
                        uint256((int256(_strike) & BITMASK_INT24) << (64 + legIndex * 48 + 12))
                );
        }
    }

    /// @notice Add the width of the nth leg (index `legIndex`).
    /// @param self The TokenId to add `_width` to
    /// @param _width The width to add to the Width slot in `self` for `legIndex`
    /// @param legIndex the leg index of this position (in {0,1,2,3})
    /// @return `self` with `_width` added to the Width slot for `legIndex`
    function addWidth(
        TokenId self,
        int24 _width,
        uint256 legIndex
    ) internal pure returns (TokenId) {
        // % 4096 -> take 12 bits from the incoming 24 bits (there's no uint12)
        unchecked {
            return
                TokenId.wrap(
                    TokenId.unwrap(self) +
                        (uint256(uint24(_width) % 4096) << (64 + legIndex * 48 + 36))
                );
        }
    }

    /// @notice Add a leg to a TokenId.
    /// @param self The tokenId in the SFPM representing an option position.
    /// @param legIndex The leg index of this position (in {0,1,2,3}) to add
    /// @param _optionRatio The relative size of the leg
    /// @param _asset The asset of the leg
    /// @param _isLong Whether the leg is long
    /// @param _tokenType The type of token moved for the leg
    /// @param _riskPartner The associated risk partner of the leg
    /// @param _strike The strike price tick of the leg
    /// @param _width The width of the leg
    /// @return tokenId The tokenId with the leg added
    function addLeg(
        TokenId self,
        uint256 legIndex,
        uint256 _optionRatio,
        uint256 _asset,
        uint256 _isLong,
        uint256 _tokenType,
        uint256 _riskPartner,
        int24 _strike,
        int24 _width
    ) internal pure returns (TokenId tokenId) {
        tokenId = addOptionRatio(self, _optionRatio, legIndex);
        tokenId = addAsset(tokenId, _asset, legIndex);
        tokenId = addIsLong(tokenId, _isLong, legIndex);
        tokenId = addTokenType(tokenId, _tokenType, legIndex);
        tokenId = addRiskPartner(tokenId, _riskPartner, legIndex);
        tokenId = addStrike(tokenId, _strike, legIndex);
        tokenId = addWidth(tokenId, _width, legIndex);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Flip all the `isLong` positions in the legs in the `tokenId` option position.
    /// @dev Uses XOR on existing isLong bits.
    /// @dev Useful when we need to take an existing tokenId but now burn it.
    /// @dev The way to do this is to simply flip it to a short instead.
    /// @param self The TokenId to flip isLong for on all active legs
    /// @return tokenId with all `isLong` bits flipped
    function flipToBurnToken(TokenId self) internal pure returns (TokenId) {
        unchecked {
            // NOTE: This is a hack to avoid blowing up the contract size.
            // We copy the logic from the countLegs function, using it here adds 5K to the contract size with IR for some reason
            // Strip all bits except for the option ratios
            uint256 optionRatios = TokenId.unwrap(self) & OPTION_RATIO_MASK;

            // The legs are filled in from least to most significant
            // Each comparison here is to the start of the next leg's option ratio
            // Since only the option ratios remain, we can be sure that no bits above the start of the inactive legs will be 1
            if (optionRatios < 2 ** 64) {
                optionRatios = 0;
            } else if (optionRatios < 2 ** 112) {
                optionRatios = 1;
            } else if (optionRatios < 2 ** 160) {
                optionRatios = 2;
            } else if (optionRatios < 2 ** 208) {
                optionRatios = 3;
            } else {
                optionRatios = 4;
            }

            // We need to ensure that only active legs are flipped
            // In order to achieve this, we shift our long bit mask to the right by (4-# active legs)
            // i.e the whole mask is used to flip all legs with 4 legs, but only the first leg is flipped with 1 leg so we shift by 3 legs
            // We also clear the poolId area of the mask to ensure the bits that are shifted right into the area don't flip and cause issues
            return
                TokenId.wrap(
                    TokenId.unwrap(self) ^
                        ((LONG_MASK >> (48 * (4 - optionRatios))) & CLEAR_POOLID_MASK)
                );
        }
    }

    /// @notice Get the number of longs in this option position.
    /// @notice Count the number of legs (out of a maximum of 4) that are long positions.
    /// @param self The TokenId to count longs for
    /// @return The number of long positions in `self` (in the range {0,...,4}).
    function countLongs(TokenId self) internal pure returns (uint256) {
        unchecked {
            return self.isLong(0) + self.isLong(1) + self.isLong(2) + self.isLong(3);
        }
    }

    /// @notice Get the option position's nth leg's (index `legIndex`) tick ranges (lower, upper).
    /// @dev NOTE: Does not extract liquidity which is the third piece of information in a LiquidityChunk.
    /// @param self The TokenId to extract the tick range from
    /// @param legIndex The leg index of the position (in {0,1,2,3})
    /// @return legLowerTick The lower tick of the leg/liquidity chunk
    /// @return legUpperTick The upper tick of the leg/liquidity chunk
    function asTicks(
        TokenId self,
        uint256 legIndex
    ) internal pure returns (int24 legLowerTick, int24 legUpperTick) {
        (legLowerTick, legUpperTick) = PanopticMath.getTicks(
            self.strike(legIndex),
            self.width(legIndex),
            self.tickSpacing()
        );
    }

    /// @notice Return the number of active legs in the option position.
    /// @param self The TokenId to count active legs for
    /// @dev ASSUMPTION: There is at least 1 leg in this option position.
    /// @dev ASSUMPTION: For any leg, the option ratio is always > 0 (the leg always has a number of contracts associated with it).
    /// @return The number of active legs in `self` (in the range {0,...,4})
    function countLegs(TokenId self) internal pure returns (uint256) {
        // Strip all bits except for the option ratios
        uint256 optionRatios = TokenId.unwrap(self) & OPTION_RATIO_MASK;

        // The legs are filled in from least to most significant
        // Each comparison here is to the start of the next leg's option ratio section
        // Since only the option ratios remain, we can be sure that no bits above the start of the inactive legs will be 1
        if (optionRatios < 2 ** 64) {
            return 0;
        } else if (optionRatios < 2 ** 112) {
            return 1;
        } else if (optionRatios < 2 ** 160) {
            return 2;
        } else if (optionRatios < 2 ** 208) {
            return 3;
        }
        return 4;
    }

    /// @notice Clear a leg in an option position with index `i`.
    /// @dev set bits of the leg to zero. Also sets the optionRatio and asset to zero of that leg.
    /// @dev NOTE it's important that the caller fills in the leg details after.
    //  - optionRatio is zeroed
    //  - asset is zeroed
    //  - width is zeroed
    // - strike is zeroed
    //  - tokenType is zeroed
    //  - isLong is zeroed
    //  - riskPartner is zeroed
    /// @param self The TokenId to clear the leg from
    /// @param i The leg index to reset, in {0,1,2,3}
    /// @return `self` with the `i`th leg zeroed including optionRatio and asset
    function clearLeg(TokenId self, uint256 i) internal pure returns (TokenId) {
        if (i == 0)
            return
                TokenId.wrap(
                    TokenId.unwrap(self) &
                        0xFFFFFFFFFFFF_FFFFFFFFFFFF_FFFFFFFFFFFF_000000000000_FFFFFFFFFFFFFFFF
                );
        if (i == 1)
            return
                TokenId.wrap(
                    TokenId.unwrap(self) &
                        0xFFFFFFFFFFFF_FFFFFFFFFFFF_000000000000_FFFFFFFFFFFF_FFFFFFFFFFFFFFFF
                );
        if (i == 2)
            return
                TokenId.wrap(
                    TokenId.unwrap(self) &
                        0xFFFFFFFFFFFF_000000000000_FFFFFFFFFFFF_FFFFFFFFFFFF_FFFFFFFFFFFFFFFF
                );
        if (i == 3)
            return
                TokenId.wrap(
                    TokenId.unwrap(self) &
                        0x000000000000_FFFFFFFFFFFF_FFFFFFFFFFFF_FFFFFFFFFFFF_FFFFFFFFFFFFFFFF
                );

        return self;
    }

    /*//////////////////////////////////////////////////////////////
                               VALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Validate an option position and all its active legs; return the underlying AMM address.
    /// @dev Used to validate a position tokenId and its legs.
    /// @param self The TokenId to validate
    function validate(TokenId self) internal pure {
        if (self.optionRatio(0) == 0) revert Errors.InvalidTokenIdParameter(1);

        // loop through the 4 (possible) legs in the tokenId `self`
        unchecked {
            // extract strike, width, and tokenType
            uint256 chunkData = (TokenId.unwrap(self) & CHUNK_MASK) >> 64;
            for (uint256 i = 0; i < 4; ++i) {
                if (self.optionRatio(i) == 0) {
                    // final leg in this position identified;
                    // make sure any leg above this are zero as well
                    // (we don't allow gaps eg having legs 1 and 4 active without 2 and 3 is not allowed)
                    if ((TokenId.unwrap(self) >> (64 + 48 * i)) != 0)
                        revert Errors.InvalidTokenIdParameter(1);

                    break; // we are done iterating over potential legs
                }

                // prevent legs touching the same chunks - all chunks in the position must be discrete
                uint256 numLegs = self.countLegs();
                for (uint256 j = i + 1; j < numLegs; ++j) {
                    if (uint48(chunkData >> (48 * i)) == uint48(chunkData >> (48 * j))) {
                        revert Errors.InvalidTokenIdParameter(6);
                    }
                }
                // now validate this ith leg in the position:

                // The width cannot be 0; the minimum is 1
                if ((self.width(i) == 0)) revert Errors.InvalidTokenIdParameter(5);
                // Strike cannot be MIN_TICK or MAX_TICK
                if (
                    (self.strike(i) == Constants.MIN_V3POOL_TICK) ||
                    (self.strike(i) == Constants.MAX_V3POOL_TICK)
                ) revert Errors.InvalidTokenIdParameter(4);

                // In the following, we check whether the risk partner of this leg is itself
                // or another leg in this position.
                // Handles case where riskPartner(i) != i ==> leg i has a risk partner that is another leg
                uint256 riskPartnerIndex = self.riskPartner(i);
                if (riskPartnerIndex != i) {
                    // Ensures that risk partners are mutual
                    if (self.riskPartner(riskPartnerIndex) != i)
                        revert Errors.InvalidTokenIdParameter(3);

                    // Ensures that risk partners have 1) the same asset, and 2) the same ratio
                    if (
                        (self.asset(riskPartnerIndex) != self.asset(i)) ||
                        (self.optionRatio(riskPartnerIndex) != self.optionRatio(i))
                    ) revert Errors.InvalidTokenIdParameter(3);

                    // long/short status of associated legs
                    uint256 _isLong = self.isLong(i);
                    uint256 isLongP = self.isLong(riskPartnerIndex);

                    // token type status of associated legs (call/put)
                    uint256 _tokenType = self.tokenType(i);
                    uint256 tokenTypeP = self.tokenType(riskPartnerIndex);

                    // if the position is the same i.e both long calls, short put's etc.
                    // then this is a regular position, not a defined risk position
                    if ((_isLong == isLongP) && (_tokenType == tokenTypeP))
                        revert Errors.InvalidTokenIdParameter(4);

                    // if the two token long-types and the tokenTypes are both different (one is a short call, the other a long put, e.g.), this is a synthetic position
                    // A synthetic long or short is more capital efficient than each leg separated because the long+short premia accumulate proportionally
                    // unlike short stranlges, long strangles also cannot be partnered, because there is no reduction in risk (both legs can earn premia simultaneously)
                    if (((_isLong != isLongP) || _isLong == 1) && (_tokenType != tokenTypeP))
                        revert Errors.InvalidTokenIdParameter(5);
                }
            } // end for loop over legs
        }
    }

    /// @notice Validate that a position `self` and its legs/chunks are exercisable.
    /// @dev At least one long leg must be far-out-of-the-money (i.e. price is outside its range).
    /// @dev Reverts if the position is not exercisable.
    /// @param self The TokenId to validate for exercisability
    /// @param currentTick The current tick corresponding to the current price in the Univ3 pool
    function validateIsExercisable(TokenId self, int24 currentTick) internal pure {
        unchecked {
            uint256 numLegs = self.countLegs();
            for (uint256 i = 0; i < numLegs; ++i) {
                (int24 rangeDown, int24 rangeUp) = PanopticMath.getRangesFromStrike(
                    self.width(i),
                    self.tickSpacing()
                );

                int24 _strike = self.strike(i);
                // check if the price is outside this chunk
                if ((currentTick >= _strike + rangeUp) || (currentTick < _strike - rangeDown)) {
                    // if this leg is long and the price beyond the leg's range:
                    // this exercised ID, `self`, appears valid
                    if (self.isLong(i) == 1) return; // validated
                }
            }
        }

        // Fail if position has no legs that is far-out-of-the-money
        revert Errors.NoLegsExercisable();
    }
}
