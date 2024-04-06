// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

// Interfaces
import {PanopticPool} from "@contracts/PanopticPool.sol";
import {SemiFungiblePositionManager} from "@contracts/SemiFungiblePositionManager.sol";
// Libraries
import {Constants} from "@libraries/Constants.sol";
import {PanopticMath} from "@libraries/PanopticMath.sol";
// Custom types
import {LeftRightUnsigned} from "@types/LeftRight.sol";
import {TokenId, TokenIdLibrary} from "@types/TokenId.sol";

/// @title Utility contract for token ID construction and advanced queries.
/// @author Axicon Labs Limited
contract PanopticHelper {
    SemiFungiblePositionManager internal immutable SFPM;

    struct Leg {
        uint64 poolId;
        address UniswapV3Pool;
        uint256 asset;
        uint256 optionRatio;
        uint256 tokenType;
        uint256 isLong;
        uint256 riskPartner;
        int24 strike;
        int24 width;
    }

    /// @notice Construct the PanopticHelper contract
    /// @param _SFPM address of the SemiFungiblePositionManager
    /// @dev the SFPM is used to get the pool ID for a given address
    constructor(SemiFungiblePositionManager _SFPM) payable {
        SFPM = _SFPM;
    }

    /// @notice Compute the total amount of collateral needed to cover the existing list of active positions in positionIdList.
    /// @param pool The PanopticPool instance to check collateral on
    /// @param account Address of the user that owns the positions
    /// @param atTick At what price is the collateral requirement evaluated at
    /// @param tokenType whether to return the values in term of token0 or token1
    /// @param positionIdList List of positions. Written as [tokenId1, tokenId2, ...]
    /// @return collateralBalance the total combined balance of token0 and token1 for a user in terms of tokenType
    /// @return requiredCollateral The combined collateral requirement for a user in terms of tokenType
    function checkCollateral(
        PanopticPool pool,
        address account,
        int24 atTick,
        uint256 tokenType,
        TokenId[] calldata positionIdList
    ) public view returns (uint256, uint256) {
        // Compute premia for all options (includes short+long premium)
        (int128 premium0, int128 premium1, uint256[2][] memory positionBalanceArray) = pool
            .calculateAccumulatedFeesBatch(account, false, positionIdList);

        // Query the current and required collateral amounts for the two tokens
        LeftRightUnsigned tokenData0 = pool.collateralToken0().getAccountMarginDetails(
            account,
            atTick,
            positionBalanceArray,
            premium0
        );
        LeftRightUnsigned tokenData1 = pool.collateralToken1().getAccountMarginDetails(
            account,
            atTick,
            positionBalanceArray,
            premium1
        );

        // convert (using atTick) and return the total collateral balance and required balance in terms of tokenType
        return PanopticMath.convertCollateralData(tokenData0, tokenData1, tokenType, atTick);
    }

    /// @notice Returns the net assets (balance - maintenance margin) of a given account on a given pool.
    /// @dev does not work for very large tick gradients.
    /// @param pool address of the pool
    /// @param account address of the account
    /// @param tick tick to consider
    /// @param positionIdList list of position IDs to consider
    /// @return netEquity the net assets of `account` on `pool`
    function netEquity(
        address pool,
        address account,
        int24 tick,
        TokenId[] calldata positionIdList
    ) internal view returns (int256) {
        (uint256 balanceCross, uint256 requiredCross) = checkCollateral(
            PanopticPool(pool),
            account,
            tick,
            0,
            positionIdList
        );

        return int256(balanceCross) - int256(requiredCross);
    }

    /// @notice Unwraps the contents of the tokenId into its legs.
    /// @param tokenId the input tokenId
    /// @return legs an array of leg structs
    function unwrapTokenId(TokenId tokenId) public view returns (Leg[] memory) {
        uint256 numLegs = tokenId.countLegs();
        Leg[] memory legs = new Leg[](numLegs);

        uint64 poolId = tokenId.poolId();
        address UniswapV3Pool = address(SFPM.getUniswapV3PoolFromId(tokenId.poolId()));
        for (uint256 i = 0; i < numLegs; ++i) {
            legs[i].poolId = poolId;
            legs[i].UniswapV3Pool = UniswapV3Pool;
            legs[i].asset = tokenId.asset(i);
            legs[i].optionRatio = tokenId.optionRatio(i);
            legs[i].tokenType = tokenId.tokenType(i);
            legs[i].isLong = tokenId.isLong(i);
            legs[i].riskPartner = tokenId.riskPartner(i);
            legs[i].strike = tokenId.strike(i);
            legs[i].width = tokenId.width(i);
        }
        return legs;
    }

    /// @notice Returns an estimate of the downside liquidation price for a given account on a given pool.
    /// @dev returns MIN_TICK if the LP is more than 100000 ticks below the current tick.
    /// @param pool address of the pool
    /// @param account address of the account
    /// @param positionIdList list of position IDs to consider
    /// @return liquidationTick the downward liquidation price of `account` on `pool`, if any
    function findLiquidationPriceDown(
        address pool,
        address account,
        TokenId[] calldata positionIdList
    ) public view returns (int24 liquidationTick) {
        // initialize right and left bounds from current tick
        (, int24 currentTick, , , , , ) = PanopticPool(pool).univ3pool().slot0();
        int24 x0 = currentTick - 10000;
        int24 x1 = currentTick;
        int24 tol = 100000;
        // use the secant method to find the root of the function netEquity(tick)
        // stopping criterion are netEquity(tick+1) > 0 and netEquity(tick-1) < 0
        // and tick is below currentTick - tol
        // (we have limited ability to calculate collateral for very large tick gradients)
        // in that case, we return the min tick
        while (true) {
            // perform an iteration of the secant method
            (x0, x1) = (
                x1,
                int24(
                    x1 -
                        (int256(netEquity(pool, account, x1, positionIdList)) * (x1 - x0)) /
                        int256(
                            netEquity(pool, account, x1, positionIdList) -
                                netEquity(pool, account, x0, positionIdList)
                        )
                )
            );
            // if price is not within a 100000 tick range of current price, return MIN_TICK
            if (x1 > currentTick + tol || x1 < currentTick - tol) {
                return Constants.MIN_V3POOL_TICK;
            }
            // stop if price is within 0.01% (1 tick) of LP
            if (
                netEquity(pool, account, x1 + 1, positionIdList) >= 0 ==
                netEquity(pool, account, x1 - 1, positionIdList) <= 0
            ) {
                return x1;
            }
        }
    }

    /// @notice Returns an estimate of the upside liquidation price for a given account on a given pool.
    /// @dev returns MAX_TICK if the LP is more than 100000 ticks above current tick.
    /// @param pool address of the pool
    /// @param account address of the account
    /// @param positionIdList list of position IDs to consider
    /// @return liquidationTick the upward liquidation price of `account` on `pool`, if any
    function findLiquidationPriceUp(
        address pool,
        address account,
        TokenId[] calldata positionIdList
    ) public view returns (int24 liquidationTick) {
        // initialize right and left bounds from current tick
        (, int24 currentTick, , , , , ) = PanopticPool(pool).univ3pool().slot0();
        int24 x0 = currentTick;
        int24 x1 = currentTick + 10000;
        int24 tol = 100000;
        // use the secant method to find the root of the function netEquity(tick)
        // stopping criterion are netEquity(tick+1) > 0 and netEquity(tick-1) < 0
        // and tick is within the range of currentTick +- tol
        // (we have limited ability to calculate collateral for very large tick gradients)
        // in that case, we return the corresponding max/min tick
        while (true) {
            // perform an iteration of the secant method
            (x0, x1) = (
                x1,
                int24(
                    x1 -
                        (int256(netEquity(pool, account, x1, positionIdList)) * (x1 - x0)) /
                        int256(
                            netEquity(pool, account, x1, positionIdList) -
                                netEquity(pool, account, x0, positionIdList)
                        )
                )
            );
            // if price is not within a 100000 tick range of current price, stop + return MAX_TICK
            if (x1 > currentTick + tol || x1 < currentTick - tol) {
                return Constants.MAX_V3POOL_TICK;
            }
            // stop if price is within 0.01% (1 tick) of LP
            if (
                netEquity(pool, account, x1 + 1, positionIdList) >= 0 ==
                netEquity(pool, account, x1 - 1, positionIdList) <= 0
            ) {
                return x1;
            }
        }
    }

    /// @notice initializes a given leg in a tokenId as a call.
    /// @param tokenId tokenId to edit
    /// @param legIndex index of the leg to edit
    /// @param optionRatio relative size of the leg
    /// @param asset asset of the leg
    /// @param isLong whether the leg is long or short
    /// @param riskPartner defined risk partner of the leg
    /// @param strike strike of the leg
    /// @param width width of the leg
    /// @return tokenId with the leg initialized
    function addCallLeg(
        TokenId tokenId,
        uint256 legIndex,
        uint256 optionRatio,
        uint256 asset,
        uint256 isLong,
        uint256 riskPartner,
        int24 strike,
        int24 width
    ) internal pure returns (TokenId) {
        return
            TokenIdLibrary.addLeg(
                tokenId,
                legIndex,
                optionRatio,
                asset,
                isLong,
                0,
                riskPartner,
                strike,
                width
            );
    }

    /// @notice initializes a given leg in a tokenId as a put.
    /// @param tokenId tokenId to edit
    /// @param legIndex index of the leg to edit
    /// @param optionRatio relative size of the leg
    /// @param asset asset of the leg
    /// @param isLong whether the leg is long or short
    /// @param riskPartner defined risk partner of the leg
    /// @param strike strike of the leg
    /// @param width width of the leg
    /// @return tokenId with the leg initialized
    function addPutLeg(
        TokenId tokenId,
        uint256 legIndex,
        uint256 optionRatio,
        uint256 asset,
        uint256 isLong,
        uint256 riskPartner,
        int24 strike,
        int24 width
    ) internal pure returns (TokenId) {
        return
            TokenIdLibrary.addLeg(
                tokenId,
                legIndex,
                optionRatio,
                asset,
                isLong,
                1,
                riskPartner,
                strike,
                width
            );
    }

    /// @notice creates "Classic" strangle using a call and a put, with asymmetric upward risk.
    /// @dev example: createStrangle(uniPoolAddress, 4, 50, -50, 0, 1, 1, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the strangle
    /// @param callStrike strike of the call
    /// @param putStrike strike of the put
    /// @param asset asset of the strangle
    /// @param isLong is the strangle long or short
    /// @param optionRatio relative size of the strangle
    /// @param start leg index where the (2 legs) of the strangle begin (usually 0)
    /// @return tokenId the position id with the strategy configured
    function createStrangle(
        address univ3pool,
        int24 width,
        int24 callStrike,
        int24 putStrike,
        uint256 asset,
        uint256 isLong,
        uint256 optionRatio,
        uint256 start
    ) public view returns (TokenId tokenId) {
        // Pool
        tokenId = tokenId.addPoolId(SFPM.getPoolId(univ3pool));

        // A strangle is composed of
        // 1. a call with a higher strike price
        // 2. a put with a lower strike price

        // Call w/ higher strike
        tokenId = addCallLeg(
            tokenId,
            start,
            optionRatio,
            asset,
            isLong,
            start + 1,
            callStrike,
            width
        );

        // Put w/ lower strike
        tokenId = addPutLeg(
            tokenId,
            start + 1,
            optionRatio,
            asset,
            isLong,
            start,
            putStrike,
            width
        );
    }

    /// @notice creates "Classic" straddle using a call and a put, with asymmetric upward risk.
    /// @dev createStraddle(uniPoolAddress, 4, 0, 0, 1, 1, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the strangle
    /// @param strike strike of the call and put
    /// @param asset asset of the strangle
    /// @param isLong is the strangle long or short
    /// @param optionRatio relative size of the strangle
    /// @param start leg index where the (2 legs) of the straddle begin (usually 0)
    /// @return tokenId the position id with the strategy configured
    function createStraddle(
        address univ3pool,
        int24 width,
        int24 strike,
        uint256 asset,
        uint256 isLong,
        uint256 optionRatio,
        uint256 start
    ) public view returns (TokenId tokenId) {
        // Pool
        tokenId = tokenId.addPoolId(SFPM.getPoolId(univ3pool));

        // A straddle is composed of
        // 1. a call with an identical strike price
        // 2. a put with an identical strike price

        // call
        tokenId = addCallLeg(tokenId, start, optionRatio, asset, isLong, start + 1, strike, width);

        // put
        tokenId = addPutLeg(tokenId, start + 1, optionRatio, asset, isLong, start, strike, width);
    }

    /// @notice creates a call spread with 1 long leg and 1 short leg.
    /// @dev example: createCallSpread(uniPoolAddress, 4, -50, 50, 0, 1, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param strikeLong strike of the long leg
    /// @param strikeShort strike of the short leg
    /// @param asset asset of the spread
    /// @param optionRatio relative size of the spread
    /// @param start leg index where the (2 legs) of the spread begin (usually 0)
    /// @return tokenId the position id with the strategy configured
    function createCallSpread(
        address univ3pool,
        int24 width,
        int24 strikeLong,
        int24 strikeShort,
        uint256 asset,
        uint256 optionRatio,
        uint256 start
    ) public view returns (TokenId tokenId) {
        // Pool
        tokenId = tokenId.addPoolId(SFPM.getPoolId(univ3pool));

        // A call spread is composed of
        // 1. a long call with a lower strike price
        // 2. a short call with a higher strike price

        // Long call
        tokenId = addCallLeg(tokenId, start, optionRatio, asset, 1, start + 1, strikeLong, width);

        // Short call
        tokenId = addCallLeg(tokenId, start + 1, optionRatio, asset, 0, start, strikeShort, width);
    }

    /// @notice creates a put spread with 1 long leg and 1 short leg.
    /// @dev example: createPutSpread(uniPoolAddress, 4, -50, 50, 0, 1, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param strikeLong strike of the long leg
    /// @param strikeShort strike of the short leg
    /// @param asset asset of the spread
    /// @param optionRatio relative size of the spread
    /// @param start leg index where the (2 legs) of the spread begin (usually 0)
    /// @return tokenId the position id with the strategy configured
    function createPutSpread(
        address univ3pool,
        int24 width,
        int24 strikeLong,
        int24 strikeShort,
        uint256 asset,
        uint256 optionRatio,
        uint256 start
    ) public view returns (TokenId tokenId) {
        // Pool
        tokenId = tokenId.addPoolId(SFPM.getPoolId(univ3pool));

        // A put spread is composed of
        // 1. a long put with a higher strike price
        // 2. a short put with a lower strike price

        // Long put
        tokenId = addPutLeg(tokenId, start, optionRatio, asset, 1, start + 1, strikeLong, width);

        // Short put
        tokenId = addPutLeg(tokenId, start + 1, optionRatio, asset, 0, start, strikeShort, width);
    }

    /// @notice creates a diagonal spread with 1 long leg and 1 short leg.abi.
    /// @dev example: createCallDiagonalSpread(uniPoolAddress, 4, 8, -50, 50, 0, 1, 0).
    /// @param univ3pool address of the pool
    /// @param widthLong width of the long leg
    /// @param widthShort width of the short leg
    /// @param strikeLong strike of the long leg
    /// @param strikeShort strike of the short leg
    /// @param asset asset of the spread
    /// @param optionRatio relative size of the spread
    /// @param start leg index where the (2 legs) of the spread begin (usually 0)
    /// @return tokenId the position id with the strategy configured
    function createCallDiagonalSpread(
        address univ3pool,
        int24 widthLong,
        int24 widthShort,
        int24 strikeLong,
        int24 strikeShort,
        uint256 asset,
        uint256 optionRatio,
        uint256 start
    ) public view returns (TokenId tokenId) {
        // Pool
        tokenId = tokenId.addPoolId(SFPM.getPoolId(univ3pool));

        // A call diagonal spread is composed of
        // 1. a long call with a (lower/higher) strike price and (lower/higher) width(expiry)
        // 2. a short call with a (higher/lower) strike price and (higher/lower) width(expiry)

        // Long call
        tokenId = addCallLeg(
            tokenId,
            start,
            optionRatio,
            asset,
            1,
            start + 1,
            strikeLong,
            widthLong
        );

        // Short call
        tokenId = addCallLeg(
            tokenId,
            start + 1,
            optionRatio,
            asset,
            0,
            start,
            strikeShort,
            widthShort
        );
    }

    /// @notice creates a diagonal spread with 1 long leg and 1 short leg.
    /// @dev example: createPutDiagonalSpread(uniPoolAddress, 4, 8, -50, 50, 0, 1, 0).
    /// @param univ3pool address of the pool
    /// @param widthLong width of the long leg
    /// @param widthShort width of the short leg
    /// @param strikeLong strike of the long leg
    /// @param strikeShort strike of the short leg
    /// @param asset asset of the spread
    /// @param optionRatio relative size of the spread
    /// @param start leg index where the (2 legs) of the spread begin (usually 0)
    /// @return tokenId the position id with the strategy configured
    function createPutDiagonalSpread(
        address univ3pool,
        int24 widthLong,
        int24 widthShort,
        int24 strikeLong,
        int24 strikeShort,
        uint256 asset,
        uint256 optionRatio,
        uint256 start
    ) public view returns (TokenId tokenId) {
        // Pool
        tokenId = tokenId.addPoolId(SFPM.getPoolId(univ3pool));

        // A bearish diagonal spread is composed of
        // 1. a long put with a (higher/lower) strike price and (lower/higher) width(expiry)
        // 2. a short put with a (lower/higher) strike price and (higher/lower) width(expiry)

        // Long put
        tokenId = addPutLeg(
            tokenId,
            start,
            optionRatio,
            asset,
            1,
            start + 1,
            strikeLong,
            widthLong
        );

        // Short put
        tokenId = addPutLeg(
            tokenId,
            start + 1,
            optionRatio,
            asset,
            0,
            start,
            strikeShort,
            widthShort
        );
    }

    /// @notice creates a calendar spread with 1 long leg and 1 short leg.
    /// @dev example: createCallCalendarSpread(uniPoolAddress, 4, 8, 0, 0, 1, 0).
    /// @param univ3pool address of the pool
    /// @param widthLong width of the long leg
    /// @param widthShort width of the short leg
    /// @param strike strike of the long and short legs
    /// @param asset asset of the spread
    /// @param optionRatio relative size of the spread
    /// @param start leg index where the (2 legs) of the spread begin (usually 0)
    /// @return tokenId the position id with the strategy configured
    function createCallCalendarSpread(
        address univ3pool,
        int24 widthLong,
        int24 widthShort,
        int24 strike,
        uint256 asset,
        uint256 optionRatio,
        uint256 start
    ) public view returns (TokenId tokenId) {
        // calendar spread is a diagonal spread where the legs have identical strike prices
        // so we can create one using the diagonal spread function
        tokenId = createCallDiagonalSpread(
            univ3pool,
            widthLong,
            widthShort,
            strike,
            strike,
            asset,
            optionRatio,
            start
        );
    }

    /// @notice creates a calendar spread with 1 long leg and 1 short leg.
    /// @dev example: createPutCalendarSpread(uniPoolAddress, 4, 8, 0, 0, 1, 0).
    /// @param univ3pool address of the pool
    /// @param widthLong width of the long leg
    /// @param widthShort width of the short leg
    /// @param strike strike of the long and short legs
    /// @param asset asset of the spread
    /// @param optionRatio relative size of the spread
    /// @param start leg index where the (2 legs) of the spread begin (usually 0)
    /// @return tokenId the position id with the strategy configured
    function createPutCalendarSpread(
        address univ3pool,
        int24 widthLong,
        int24 widthShort,
        int24 strike,
        uint256 asset,
        uint256 optionRatio,
        uint256 start
    ) public view returns (TokenId tokenId) {
        // calendar spread is a diagonal spread where the legs have identical strike prices
        // so we can create one using the diagonal spread function
        tokenId = createPutDiagonalSpread(
            univ3pool,
            widthLong,
            widthShort,
            strike,
            strike,
            asset,
            optionRatio,
            start
        );
    }

    /// @notice creates iron condor w/ call and put spread.
    /// @dev example: createIronCondor(uniPoolAddress, 4, 50, -50, 50, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param callStrike strike of the call spread
    /// @param putStrike strike of the put spread
    /// @param wingWidth width of the wings
    /// @param asset asset of the strategy
    /// @return tokenId the position id with the strategy configured
    function createIronCondor(
        address univ3pool,
        int24 width,
        int24 callStrike,
        int24 putStrike,
        int24 wingWidth,
        uint256 asset
    ) public view returns (TokenId tokenId) {
        // an iron condor is composed of
        // 1. a call spread
        // 2. a put spread
        // the "wings" represent how much more OTM the long sides of the spreads are

        // call spread
        tokenId = createCallSpread(
            univ3pool,
            width,
            callStrike + wingWidth,
            callStrike,
            asset,
            1,
            0
        );

        // put spread
        tokenId = TokenId.wrap(
            TokenId.unwrap(tokenId) +
                TokenId.unwrap(
                    createPutSpread(
                        address(0),
                        width,
                        putStrike - wingWidth,
                        putStrike,
                        asset,
                        1,
                        2
                    )
                )
        );
    }

    /// @notice creates a jade lizard w/ long call and short asymmetric (traditional) strangle.
    /// @dev example: createJadeLizard(uniPoolAddress, 4, 100, 50, -50, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param longCallStrike strike of the long call
    /// @param shortCallStrike strike of the short call
    /// @param shortPutStrike strike of the short put
    /// @param asset asset of the strategy
    /// @return tokenId the position id with the strategy configured
    function createJadeLizard(
        address univ3pool,
        int24 width,
        int24 longCallStrike,
        int24 shortCallStrike,
        int24 shortPutStrike,
        uint256 asset
    ) public view returns (TokenId tokenId) {
        // a jade lizard is composed of
        // 1. a short strangle
        // 2. a long call

        // short strangle
        tokenId = createStrangle(univ3pool, width, shortCallStrike, shortPutStrike, asset, 0, 1, 1);

        // long call
        tokenId = addCallLeg(tokenId, 0, 1, asset, 1, 0, longCallStrike, width);
    }

    /// @notice creates a big lizard w/ long call and short asymmetric (traditional) straddle.
    /// @dev example: createBigLizard(uniPoolAddress, 4, 100, 50, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param longCallStrike strike of the long call
    /// @param straddleStrike strike of the short straddle
    /// @param asset asset of the strategy
    /// @return tokenId the position id with the strategy configured
    function createBigLizard(
        address univ3pool,
        int24 width,
        int24 longCallStrike,
        int24 straddleStrike,
        uint256 asset
    ) public view returns (TokenId tokenId) {
        // a big lizard is composed of
        // 1. a short straddle
        // 2. a long call

        // short straddle
        tokenId = createStraddle(univ3pool, width, straddleStrike, asset, 0, 1, 1);

        // long call
        tokenId = addCallLeg(tokenId, 0, 1, asset, 1, 0, longCallStrike, width);
    }

    /// @notice creates a super bull w/ long call spread and short put.
    /// @dev example: createSuperBull(uniPoolAddress, 4, -50, 50, 50, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param longCallStrike strike of the long call
    /// @param shortCallStrike strike of the short call
    /// @param shortPutStrike strike of the short put
    /// @param asset asset of the strategy
    /// @return tokenId the position id with the strategy configured
    function createSuperBull(
        address univ3pool,
        int24 width,
        int24 longCallStrike,
        int24 shortCallStrike,
        int24 shortPutStrike,
        uint256 asset
    ) public view returns (TokenId tokenId) {
        // a super bull is composed of
        // 1. a long call spread
        // 2. a short put

        // long call spread
        tokenId = createCallSpread(univ3pool, width, longCallStrike, shortCallStrike, asset, 1, 1);

        // short put
        tokenId = addPutLeg(tokenId, 0, 1, asset, 0, 0, shortPutStrike, width);
    }

    /// @notice creates a super bear w/ long put spread and short call.
    /// @dev example: createSuperBear(uniPoolAddress, 4, 50, -50, -50, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param longPutStrike strike of the long put
    /// @param shortPutStrike strike of the short put
    /// @param shortCallStrike strike of the short call
    /// @param asset asset of the strategy
    /// @return tokenId the position id with the strategy configured
    function createSuperBear(
        address univ3pool,
        int24 width,
        int24 longPutStrike,
        int24 shortPutStrike,
        int24 shortCallStrike,
        uint256 asset
    ) public view returns (TokenId tokenId) {
        // a super bear is composed of
        // 1. a long put spread
        // 2. a short call

        // long put spread
        tokenId = createPutSpread(univ3pool, width, longPutStrike, shortPutStrike, asset, 1, 1);

        // short call
        tokenId = addCallLeg(tokenId, 0, 1, asset, 0, 0, shortCallStrike, width);
    }

    /// @notice creates a butterfly w/ long call spread and short put spread.
    /// @dev example: createIronButterfly(uniPoolAddress, 4, 0, 50, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param strike strike of the long and short legs
    /// @param wingWidth width of the wings
    /// @param asset asset of the strategy
    /// @return tokenId the position id with the strategy configured
    function createIronButterfly(
        address univ3pool,
        int24 width,
        int24 strike,
        int24 wingWidth,
        uint256 asset
    ) public view returns (TokenId tokenId) {
        // an iron butterfly is composed of
        // 1. a long call spread
        // 2. a short put spread

        // long call spread
        tokenId = createCallSpread(univ3pool, width, strike, strike + wingWidth, asset, 1, 0);

        // short put spread
        tokenId = TokenId.wrap(
            TokenId.unwrap(tokenId) +
                TokenId.unwrap(
                    createPutSpread(address(0), width, strike, strike - wingWidth, asset, 1, 2)
                )
        );
    }

    /// @notice creates a ratio spread w/ long call and multiple short calls.
    /// @dev example: createCallRatioSpread(uniPoolAddress, 4, -50, 50, 0, 2, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param longStrike strike of the long call
    /// @param shortStrike strike of the short calls
    /// @param asset asset of the strategy
    /// @param ratio ratio of the short calls to the long call
    /// @param start leg index where the (2 legs) of the spread begin (usually 0)
    /// @return tokenId the position id with the strategy configured

    function createCallRatioSpread(
        address univ3pool,
        int24 width,
        int24 longStrike,
        int24 shortStrike,
        uint256 asset,
        uint256 ratio,
        uint256 start
    ) public view returns (TokenId tokenId) {
        // Pool
        tokenId = tokenId.addPoolId(SFPM.getPoolId(univ3pool));

        // a call ratio spread is composed of
        // 1. a long call
        // 2. multiple short calls

        // long call
        tokenId = addCallLeg(tokenId, start, 1, asset, 1, start + 1, longStrike, width);

        // short calls
        tokenId = addCallLeg(tokenId, start + 1, ratio, asset, 0, start, shortStrike, width);
    }

    /// @notice creates a ratio spread w/ long put and multiple short puts.
    /// @dev example: createPutRatioSpread(uniPoolAddress, 4, -50, 50, 0, 2, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param longStrike strike of the long put
    /// @param shortStrike strike of the short puts
    /// @param asset asset of the strategy
    /// @param ratio ratio of the short puts to the long put
    /// @param start leg index where the (2 legs) of the spread begin (usually 0)
    /// @return tokenId the position id with the strategy configured
    function createPutRatioSpread(
        address univ3pool,
        int24 width,
        int24 longStrike,
        int24 shortStrike,
        uint256 asset,
        uint256 ratio,
        uint256 start
    ) public view returns (TokenId tokenId) {
        // Pool
        tokenId = tokenId.addPoolId(SFPM.getPoolId(univ3pool));

        // a put ratio spread is composed of
        // 1. a long put
        // 2. multiple short puts

        // long put
        tokenId = addPutLeg(tokenId, start, 1, asset, 1, start + 1, longStrike, width);

        // short puts
        tokenId = addPutLeg(tokenId, start + 1, ratio, asset, 0, start, shortStrike, width);
    }

    /// @notice creates a ZEBRA spread w/ short call and multiple long calls.
    /// @dev example: createCallZEBRASpread(uniPoolAddress, 4, -50, 50, 0, 2, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param longStrike strike of the long calls
    /// @param shortStrike strike of the short call
    /// @param asset asset of the strategy
    /// @param ratio ratio of the short call to the long calls
    /// @param start leg index where the (2 legs) of the spread begin (usually 0)
    /// @return tokenId the position id with the strategy configured
    function createCallZEBRASpread(
        address univ3pool,
        int24 width,
        int24 longStrike,
        int24 shortStrike,
        uint256 asset,
        uint256 ratio,
        uint256 start
    ) public view returns (TokenId tokenId) {
        // Pool
        tokenId = tokenId.addPoolId(SFPM.getPoolId(univ3pool));

        // a call ZEBRA(zero extrinsic value back ratio spread) spread is composed of
        // 1. a short call
        // 2. multiple long calls

        // long put
        tokenId = addCallLeg(tokenId, start, ratio, asset, 1, start + 1, longStrike, width);

        // short puts
        tokenId = addCallLeg(tokenId, start + 1, 1, asset, 0, start, shortStrike, width);
    }

    /// @notice creates a ZEBRA spread w/ short put and multiple long puts.
    /// @dev example: createPutZEBRASpread(uniPoolAddress, 4, -50, 50, 0, 2, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param longStrike strike of the long puts
    /// @param shortStrike strike of the short put
    /// @param asset asset of the strategy
    /// @param ratio ratio of the short put to the long puts
    /// @param start leg index where the (2 legs) of the spread begin (usually 0)
    /// @return tokenId the position id with the strategy configured
    function createPutZEBRASpread(
        address univ3pool,
        int24 width,
        int24 longStrike,
        int24 shortStrike,
        uint256 asset,
        uint256 ratio,
        uint256 start
    ) public view returns (TokenId tokenId) {
        // Pool
        tokenId = tokenId.addPoolId(SFPM.getPoolId(univ3pool));

        // a put ZEBRA(zero extrinsic value back ratio spread) spread is composed of
        // 1. a short put
        // 2. multiple long puts

        // long puts
        tokenId = addPutLeg(tokenId, start, ratio, asset, 1, start + 1, longStrike, width);

        // short put
        tokenId = addPutLeg(tokenId, start + 1, 1, asset, 0, start, shortStrike, width);
    }

    /// @notice creates a ZEEHBS w/ call and put ZEBRA spreads.
    /// @dev example: createPutZEBRASpread(uniPoolAddress, 4, -50, 50, 0, 2, 0).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param longStrike strike of the long legs
    /// @param shortStrike strike of the short legs
    /// @param asset asset of the strategy
    /// @param ratio ratio of the short legs to the long legs
    /// @return tokenId the position id with the strategy configured
    function createZEEHBS(
        address univ3pool,
        int24 width,
        int24 longStrike,
        int24 shortStrike,
        uint256 asset,
        uint256 ratio
    ) public view returns (TokenId tokenId) {
        // a ZEEHBS(Zero extrinsic hedged back spread) is composed of
        // 1. a call ZEBRA spread
        // 2. a put ZEBRA spread

        // call ZEBRA
        tokenId = createCallZEBRASpread(univ3pool, width, longStrike, shortStrike, asset, ratio, 0);

        // put ZEBRA
        tokenId = TokenId.wrap(
            TokenId.unwrap(tokenId) +
                TokenId.unwrap(
                    createPutZEBRASpread(
                        address(0),
                        width,
                        longStrike,
                        shortStrike,
                        asset,
                        ratio,
                        2
                    )
                )
        );
    }

    /// @notice creates a BATS (AKA double ratio spread) w/ call and put ratio spreads.
    /// @dev example: createBATS(uniPoolAddress, 4, -50, 50, 0, 2).
    /// @param univ3pool address of the pool
    /// @param width width of the spread
    /// @param longStrike strike of the long legs
    /// @param shortStrike strike of the short legs
    /// @param asset asset of the strategy
    /// @param ratio ratio of the short legs to the long legs
    /// @return tokenId the position id with the strategy configured
    function createBATS(
        address univ3pool,
        int24 width,
        int24 longStrike,
        int24 shortStrike,
        uint256 asset,
        uint256 ratio
    ) public view returns (TokenId tokenId) {
        // a BATS(double ratio spread) is composed of
        // 1. a call ratio spread
        // 2. a put ratio spread

        // call ratio spread
        tokenId = createCallRatioSpread(univ3pool, width, longStrike, shortStrike, asset, ratio, 0);

        // put ratio spread
        tokenId = TokenId.wrap(
            TokenId.unwrap(tokenId) +
                TokenId.unwrap(
                    createPutRatioSpread(
                        address(0),
                        width,
                        longStrike,
                        shortStrike,
                        asset,
                        ratio,
                        2
                    )
                )
        );
    }
}
