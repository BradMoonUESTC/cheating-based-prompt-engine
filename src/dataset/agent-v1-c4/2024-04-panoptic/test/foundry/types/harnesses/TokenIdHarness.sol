// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@types/TokenId.sol";

/// @title TokenIdHarness: A harness to expose the TokenId library for code coverage analysis.
/// @notice Replicates the interface of the TokenId library, passing through any function calls
/// @author Axicon Labs Limited
contract TokenIdHarness {
    // this mask in hex has a 1 bit in each location of the "isLong" of the tokenId:
    uint256 public constant LONG_MASK =
        0x100_000000000100_000000000100_000000000100_0000000000000000;
    // This mask contains zero bits where the poolId is. It is used via & to strip the poolId section from a number, leaving the rest.
    uint256 public constant CLEAR_POOLID_MASK =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF_0000000000000000;
    // This mask is used to clear all bits except for the option ratios
    uint256 public constant OPTION_RATIO_MASK =
        0x0000000000FE_0000000000FE_0000000000FE_0000000000FE_0000000000000000;
    int256 public constant BITMASK_INT24 = 0xFFFFFF;
    // Setting the width to its max possible value (2**12-1) indicates a full-range liquidity chunk and not a width of 4095 ticks
    int24 public constant MAX_LEG_WIDTH = 4095; // int24 because that's the strike and width formats
    // this mask in hex has a 1 bit in each location except in the riskPartner of the 48bits on a position's tokenId:
    // this RISK_PARTNER_MASK will make sure that two tokens will have the exact same parameters
    uint256 public constant RISK_PARTNER_MASK = 0xFFFFFFFFF3FF;

    /*****************************************************************/
    /*
    /* READ: GLOBAL OPTION POSITION ID (tokenID) UNPACKING METHODS
    /*
    /*****************************************************************/

    /**
     * @notice The Uniswap v3 Pool pointed to by this option position.
     * @param self the option position Id.
     * @return the poolId (Panoptic's uni v3 pool fingerprint) of the Uniswap v3 pool
     */
    function poolId(TokenId self) public pure returns (uint64) {
        uint64 r = TokenIdLibrary.poolId(self);
        return r;
    }

    /**
     * @notice The tickSpacing of the Uniswap v3 Pool for this position
     * @param self the option position Id.
     * @return the tickSpacing of the Uniswap v3 pool
     */
    function tickSpacing(TokenId self) public pure returns (int24) {
        int24 r = TokenIdLibrary.tickSpacing(self);
        return r;
    }

    /// NOW WE MOVE THROUGH THE BIT PATTERN BEYOND THE FIRST 96 BITS INTO EACH LEG (EACH OF SIZE 48)
    /// @notice our terminology: "leg n" or "nth leg" (in {1,2,3,4}) corresponds to "leg index n-1" or `legIndex` (in {0,1,2,3})

    /**
     * @notice Get the asset basis for this position.
     * @dev which token is the asset - can be token0 (return 0) or token1 (return 1)
     * @param self the option position Id.
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @dev occupies the leftmost bit of the optionRatio 4 bits slot.
     * @dev The final mod: "% 2" = takes the leftmost bit of the pattern.
     * @return 0 if asset is token0, 1 if asset is token1
     */
    function asset(TokenId self, uint256 legIndex) public pure returns (uint256) {
        uint256 r = TokenIdLibrary.asset(self, legIndex);
        return r;
    }

    /**
     * @notice Get the number of contracts per leg.
     * @param self the option position Id.
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @dev The final mod: "% 2**7" = takes the rightmost (2 ** 7 = 128) 7 bits of the pattern.
     */
    function optionRatio(TokenId self, uint256 legIndex) public pure returns (uint256) {
        uint256 r = TokenIdLibrary.optionRatio(self, legIndex);
        return r;
    }

    /**
     * @notice Return 1 if the nth leg (leg index `legIndex`) is a long position.
     * @param self the option position Id.
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @return 1 if long; 0 if not long.
     */
    function isLong(TokenId self, uint256 legIndex) public pure returns (uint256) {
        uint256 r = TokenIdLibrary.isLong(self, legIndex);
        return r;
    }

    /**
     * @notice Get the type of token moved for a given leg (implies a call or put). Either Token0 or Token1.
     * @param self the tokenId in the SFPM representing an option position.
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @return 1 if the token moved is token1 or 0 if the token moved is token0
     */
    function tokenType(TokenId self, uint256 legIndex) public pure returns (uint256) {
        uint256 r = TokenIdLibrary.tokenType(self, legIndex);
        return r;
    }

    /**
     * @notice Get the associated risk partner of the leg index (generally another leg index in the position).
     * @notice that returning the riskPartner for any leg is 0 by default, this does not necessarily imply that token 1 (index 0)
     * @notice is the risk partner of that leg. We are assuming here that the position has been validated before this and that
     * @notice the risk partner of any leg always makes sense in this way. A leg btw. does not need to have a risk partner.
     * @notice the point here is that this function is very low level and must be used with utmost care because it comes down
     * @notice to the caller to interpret whether 00 means "no risk partner" or "risk partner leg index 0".
     * @notice But in general we can return 00, 01, 10, and 11 meaning the partner is leg 0, 1, 2, or 3.
     * @param self the tokenId in the SFPM representing an option position.
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @return the leg index of `legIndex`'s risk partner.
     */
    function riskPartner(TokenId self, uint256 legIndex) public pure returns (uint256) {
        uint256 r = TokenIdLibrary.riskPartner(self, legIndex);
        return r;
    }

    /**
     * @notice Get the strike price tick of the nth leg (with index `legIndex`).
     * @param self the tokenId in the SFPM representing an option position.
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @return the strike price (the underlying price of the leg).
     */
    function strike(TokenId self, uint256 legIndex) public pure returns (int24) {
        int24 r = TokenIdLibrary.strike(self, legIndex);
        return r;
    }

    /**
     * @notice Get the width of the nth leg (index `legIndex`). This is half the tick-range covered by the leg (tickUpper - tickLower)/2.
     * @dev return as int24 to be compatible with the strike tick format (they naturally go together)
     * @param self the tokenId in the SFPM representing an option position.
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @return the width of the position.
     */
    function width(TokenId self, uint256 legIndex) public pure returns (int24) {
        int24 r = TokenIdLibrary.width(self, legIndex);
        return r;
    }

    /**
     *
     */
    /*
    /* WRITE: GLOBAL OPTION POSITION ID (tokenID) PACKING METHODS
    /*
    /*****************************************************************/

    /**
     * @notice Add the Uniswap v3 Pool pointed to by this option position.
     * @param self the option position Id.
     * @return the tokenId with the Uniswap V3 pool added to it.
     */
    function addPoolId(TokenId self, uint64 _poolId) public pure returns (TokenId) {
        TokenId r = TokenIdLibrary.addPoolId(self, _poolId);
        return r;
    }

    /**
     * @notice Add the Uniswap v3 Pool pointed to by this option position.
     * @param self the option position Id.
     * @return the tokenId with the Uniswap V3 pool added to it.
     */
    function addTickSpacing(TokenId self, int24 _tickSpacing) public pure returns (TokenId) {
        TokenId r = TokenIdLibrary.addTickSpacing(self, _tickSpacing);
        return r;
    }

    /// NOW WE MOVE THROUGH THE BIT PATTERN BEYOND THE FIRST 96 BITS INTO EACH LEG (EACH OF SIZE 40)
    /// @notice our terminology: "leg n" or "nth leg" (in {1,2,3,4}) corresponds to "leg index n-1" (in {0,1,2,3})

    /**
     * @notice Add the asset basis for this position.
     * @param self the option position Id.
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @dev occupies the leftmost bit of the optionRatio 4 bits slot.
     * @dev The final mod: "% 2" = takes the rightmost bit of the pattern.
     * @return the tokenId with numerarire added to the incoming leg index
     */
    function addAsset(
        TokenId self,
        uint256 _asset,
        uint256 legIndex
    ) public pure returns (TokenId) {
        TokenId r = TokenIdLibrary.addAsset(self, _asset, legIndex);
        return r;
    }

    /**
     * @notice Add the number of contracts to leg index `legIndex`.
     * @param self the option position Id.
     * @param legIndex the leg index of the position (in {0,1,2,3}).
     * @dev The final mod: "% 128" = takes the rightmost (2 ** 7 = 128) 7 bits of the pattern.
     * @return the tokenId with optionRatio added to the incoming leg index
     */
    function addOptionRatio(
        TokenId self,
        uint256 _optionRatio,
        uint256 legIndex
    ) public pure returns (TokenId) {
        TokenId r = TokenIdLibrary.addOptionRatio(self, _optionRatio, legIndex);
        return r;
    }

    /**
     * @notice Add "isLong" parameter indicating whether a leg is long (isLong=1) or short (isLong=0)
     * @notice returns 1 if the nth leg (leg index n-1) is a long position.
     * @param self the option position Id.
     * @param _isLong whether the leg is long
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @return the tokenId with isLong added to its relevant leg
     */
    function addIsLong(
        TokenId self,
        uint256 _isLong,
        uint256 legIndex
    ) public pure returns (TokenId) {
        TokenId r = TokenIdLibrary.addIsLong(self, _isLong, legIndex);
        return r;
    }

    /**
     * @notice Add the type of token moved for a given leg (implies a call or put). Either Token0 or Token1.
     * @param self the tokenId in the SFPM representing an option position.
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @return the tokenId with tokenType added to its relevant leg.
     */
    function addTokenType(
        TokenId self,
        uint256 _tokenType,
        uint256 legIndex
    ) public pure returns (TokenId) {
        TokenId r = TokenIdLibrary.addTokenType(self, _tokenType, legIndex);
        return r;
    }

    /**
     * @notice Add the associated risk partner of the leg index (generally another leg in the overall position).
     * @param self the tokenId in the SFPM representing an option position.
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @return the tokenId with riskPartner added to its relevant leg.
     */
    function addRiskPartner(
        TokenId self,
        uint256 _riskPartner,
        uint256 legIndex
    ) public pure returns (TokenId) {
        TokenId r = TokenIdLibrary.addRiskPartner(self, _riskPartner, legIndex);
        return r;
    }

    /**
     * @notice Add the strike price tick of the nth leg (index `legIndex`).
     * @param self the tokenId in the SFPM representing an option position.
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @return the tokenId with strike price tick added to its relevant leg
     */
    function addStrike(
        TokenId self,
        int24 _strike,
        uint256 legIndex
    ) public pure returns (TokenId) {
        TokenId r = TokenIdLibrary.addStrike(self, _strike, legIndex);
        return r;
    }

    /**
     * @notice Add the width of the nth leg (index `legIndex`). This is half the tick-range covered by the leg (tickUpper - tickLower)/2.
     * @param self the tokenId in the SFPM representing an option position.
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @return the tokenId with width added to its relevant leg
     */
    function addWidth(TokenId self, int24 _width, uint256 legIndex) public pure returns (TokenId) {
        // % 4096 -> take 12 bits from the incoming 16 bits (there's no uint12)
        TokenId r = TokenIdLibrary.addWidth(self, _width, legIndex);
        return r;
    }

    /**
     * @notice Add a leg to the TokenIdLibrary.
     * @param self the tokenId in the SFPM representing an option position.
     * @param legIndex the leg index of this position (in {0,1,2,3}).
     * @param _optionRatio the relative size of the leg.
     * @param _asset the asset of the leg.
     * @param _isLong whether the leg is long.
     * @param _tokenType the type of token moved for the leg.
     * @param _riskPartner the associated risk partner of the leg.
     * @param _strike the strike price tick of the leg.
     * @param _width the width of the leg.
     * @return tokenId the tokenId with the leg added
     */
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
    ) public pure returns (TokenId tokenId) {
        TokenId r = TokenIdLibrary.addLeg(
            self,
            legIndex,
            _optionRatio,
            _asset,
            _isLong,
            _tokenType,
            _riskPartner,
            _strike,
            _width
        );
        return r;
    }

    /**
     *
     */
    /*
    /* HELPER METHODS TO INTERACT WITH LEGS IN THE OPTION POSITION
    /*
    /*****************************************************************/

    /**
     * @notice Flip all the `isLong` positions in the legs in the `tokenId` option position.
     * @dev uses XOR on existing isLong bits.
     * /// @dev useful when we need to take an existing tokenId but now burn it.
     * an existing tokenId but now burn it. The way to do this is to simply flip it to a short instead.
     * @param self the tokenId in the SFPM representing an option position.
     */
    function flipToBurnToken(TokenId self) public pure returns (TokenId) {
        TokenId r = TokenIdLibrary.flipToBurnToken(self);
        return r;
    }

    /**
     * @notice Get the number of longs in this option position.
     * @notice count the number of legs (out of a maximum of 4) that are long positions.
     * @param self the tokenId in the SFPM representing an option position.
     * @return the number of long positions (in the range {0,...,4}).
     */
    function countLongs(TokenId self) public pure returns (uint256) {
        uint256 r = TokenIdLibrary.countLongs(self);
        return r;
    }

    /**
     * @notice Get the option position's nth leg's (index `legIndex`) tick ranges (lower, upper).
     * @dev NOTE does not extract liquidity which is the third piece of information in a LiquidityChunk.
     * @param self the option position id.
     * @param legIndex the leg index of the position (in {0,1,2,3}).
     * @return legLowerTick the lower tick of the leg/liquidity chunk.
     * @return legUpperTick the upper tick of the leg/liquidity chunk.
     */
    function asTicks(
        TokenId self,
        uint256 legIndex
    ) public pure returns (int24 legLowerTick, int24 legUpperTick) {
        (legLowerTick, legUpperTick) = TokenIdLibrary.asTicks(self, legIndex);
    }

    /**
     * @notice Return the number of active legs in the option position.
     * @param self the option position Id (tokenId).
     * @dev ASSUMPTION: There is at least 1 leg in this option position.
     * @dev ASSUMPTION: For any leg, the option ratio is always > 0 (the leg always has a number of contracts associated with it).
     * @return the number of legs in the option position.
     */
    function countLegs(TokenId self) public pure returns (uint256) {
        uint256 r = TokenIdLibrary.countLegs(self);
        return r;
    }

    /**
     * @notice Clear a leg in an option position with index `i`.
     * @dev set bits of the leg to zero. Also sets the optionRatio and asset to zero of that leg.
     * @dev NOTE it's important that the caller fills in the leg details after.
     * @dev  - optionRatio is zeroed
     * @dev  - asset is zeroed
     * @dev  - width is zeroed
     * @dev  - strike is zeroed
     * @dev  - tokenType is zeroed
     * @dev  - isLong is zeroed
     * @dev  - riskPartner is zeroed
     * @param self the tokenId to reset the leg of
     * @param i the leg index to reset, in {0,1,2,3}
     * @return `self` with the `i`th leg zeroed including optionRatio and asset.
     */
    function clearLeg(TokenId self, uint256 i) public pure returns (TokenId) {
        TokenId r = TokenIdLibrary.clearLeg(self, i);
        return r;
    }

    /**
     * @notice Validate an option position and all its active legs; return the underlying AMM address.
     * @dev used to validate a position tokenId and its legs.
     * @param self the option position id.
     */
    function validate(TokenId self) public pure {
        TokenIdLibrary.validate(self);
    }

    /**
     * @notice Validate that a position `self` and its legs/chunks are exercisable.
     * @dev At least one long leg must be far-out-of-the-money (i.e. price is outside its range).
     * @param self the option position Id (tokenId)
     * @param currentTick the current tick corresponding to the current price in the Univ3 pool.
     */
    function validateIsExercisable(TokenId self, int24 currentTick) public pure {
        TokenIdLibrary.validateIsExercisable(self, currentTick);
    }
}
