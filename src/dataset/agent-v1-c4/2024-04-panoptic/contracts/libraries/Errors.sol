// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Custom Errors library.
/// @author Axicon Labs Limited
/// @notice Contains all custom error messages used in Panoptic.
library Errors {
    /// @notice Casting error
    /// @dev e.g. uint128(uint256(a)) fails
    error CastingError();

    /// @notice CollateralTracker: collateral token has already been initialized
    error CollateralTokenAlreadyInitialized();

    /// @notice CollateralTracker: the amount of shares (or assets) deposited is larger than the maximum permitted
    error DepositTooLarge();

    /// @notice PanopticPool: the effective liquidity (X32) is greater than min(`MAX_SPREAD`, `USER_PROVIDED_THRESHOLD`) during a long mint or short burn
    /// Effective liquidity measures how much new liquidity is minted relative to how much is already in the pool
    error EffectiveLiquidityAboveThreshold();

    /// @notice CollateralTracker: attempted to withdraw/redeem more than available liquidity, owned shares, or open positions would allow for
    error ExceedsMaximumRedemption();

    /// @notice PanopticPool: force exercisee is insolvent - liquidatable accounts are not permitted to open or close positions outside of a liquidation
    error ExerciseeNotSolvent();

    /// @notice PanopticPool: the provided list of option positions is incorrect or invalid
    error InputListFail();

    /// @notice PanopticFactory: irst 20 bytes of provided salt does not match caller address
    error InvalidSalt();

    /// @notice Tick is not between `MIN_TICK` and `MAX_TICK`
    error InvalidTick();

    /// @notice The result of a notional value conversion is too small (=0) or too large (>2^128-1)
    error InvalidNotionalValue();

    /// @notice Invalid TokenId parameter detected
    /// @param parameterType poolId=0, ratio=1, tokenType=2, risk_partner=3 , strike=4, width=5, two identical strike/width/tokenType chunks=6
    error InvalidTokenIdParameter(uint256 parameterType);

    /// @notice A mint or swap callback was attempted from an address that did not match the canonical Uniswap V3 pool with the claimed features
    error InvalidUniswapCallback();

    /// @notice Invalid input in LeftRight library.
    error LeftRightInputError();

    /// @notice PanopticPool: one of the legs in a position are force-exercisable (they are all either short or ITM long)
    error NoLegsExercisable();

    /// @notice PanopticPool: the account is not solvent enough to perform the desired action
    error NotEnoughCollateral();

    /// @notice SFPM: maximum token amounts for a position exceed 128 bits
    error PositionTooLarge();

    /// @notice PanopticPool: the leg is not long, so the premium cannot be settled through `settleLongPremium`
    error NotALongLeg();

    /// @notice PanopticPool: there is not enough avaiable liquidity to buy an option
    error NotEnoughLiquidity();

    /// @notice PanopticPool: position is still solvent and cannot be liquidated
    error NotMarginCalled();

    /// @notice Caller needs to be the owner
    /// @dev unauthorized access attempted
    error NotOwner();

    /// @notice CollateralTracker: the caller for a permissioned function is not the Panoptic Pool
    error NotPanopticPool();

    /// @notice Minting and burning in the SFPM must operate on >0 contracts
    error OptionsBalanceZero();

    /// @notice Uniswap pool has already been initialized in the SFPM or created in the factory
    error PoolAlreadyInitialized();

    /// @notice PanopticPool: Option position already minted
    error PositionAlreadyMinted();

    /// @notice CollateralTracker: The user has open/active option positions, so they cannot transfer collateral shares
    error PositionCountNotZero();

    /// @notice The current tick in the pool falls outside a user-defined open interval slippage range
    error PriceBoundFail();

    /// @notice SFPM: function has been called while reentrancy lock is active
    error ReentrantCall();

    /// @notice An oracle price is too far away from another oracle price or the current tick
    /// This is a safeguard against price manipulation during option mints, burns, and liquidations
    error StaleTWAP();

    /// @notice PanopticPool: too many positions open (above limit per account)
    error TooManyPositionsOpen();

    /// @notice ERC20 or SFPM token transfer did not complete successfully
    error TransferFailed();

    /// @notice The tick range given by the strike price and width is invalid
    /// because the upper and lower ticks are not multiples of `tickSpacing`
    error TicksNotInitializable();

    /// @notice An operation in a library has failed due to an underflow or overflow
    error UnderOverFlow();

    /// @notice The Uniswap Pool has not been created, so it cannot be used in the SFPM or factory
    error UniswapPoolNotInitialized();
}
