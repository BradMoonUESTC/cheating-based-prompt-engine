// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

// Interfaces
import {CollateralTracker} from "@contracts/CollateralTracker.sol";
import {SemiFungiblePositionManager} from "@contracts/SemiFungiblePositionManager.sol";
import {IUniswapV3Pool} from "univ3-core/interfaces/IUniswapV3Pool.sol";
// Inherited implementations
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Multicall} from "@multicall/Multicall.sol";
// Libraries
import {Constants} from "@libraries/Constants.sol";
import {Errors} from "@libraries/Errors.sol";
import {FeesCalc} from "@libraries/FeesCalc.sol";
import {InteractionHelper} from "@libraries/InteractionHelper.sol";
import {Math} from "@libraries/Math.sol";
import {PanopticMath} from "@libraries/PanopticMath.sol";
// Custom types
import {LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";
import {LiquidityChunk} from "@types/LiquidityChunk.sol";
import {TokenId} from "@types/TokenId.sol";

/// @title The Panoptic Pool: Create permissionless options on top of a concentrated liquidity AMM like Uniswap v3.
/// @author Axicon Labs Limited
/// @notice Manages positions, collateral, liquidations and forced exercises.
/// @dev All liquidity deployed to/from the AMM is owned by this smart contract.
contract PanopticPool is ERC1155Holder, Multicall {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an account is liquidated.
    /// @dev Need to unpack bonusAmounts to get raw numbers, which are always positive.
    /// @param liquidator Address of the caller whom is liquidating the distressed account.
    /// @param liquidatee Address of the distressed/liquidatable account.
    /// @param bonusAmounts LeftRight encoding for the the bonus paid for token 0 (right slot) and 1 (left slot) from the Panoptic Pool to the liquidator.
    /// The token0 bonus is in the right slot, and token1 bonus is in the left slot.
    event AccountLiquidated(
        address indexed liquidator,
        address indexed liquidatee,
        LeftRightSigned bonusAmounts
    );

    /// @notice Emitted when a position is force exercised.
    /// @dev Need to unpack exerciseFee to get raw numbers, represented as a negative value (fee debited).
    /// @param exercisor Address of the account that forces the exercise of the position.
    /// @param user Address of the owner of the liquidated position
    /// @param tokenId TokenId of the liquidated position.
    /// @param exerciseFee LeftRight encoding for the cost paid by the exercisor to force the exercise of the token.
    /// The token0 fee is in the right slot, and token1 fee is in the left slot.
    event ForcedExercised(
        address indexed exercisor,
        address indexed user,
        TokenId indexed tokenId,
        LeftRightSigned exerciseFee
    );

    /// @notice Emitted when premium is settled independent of a mint/burn (e.g. during `settleLongPremium`)
    /// @param user Address of the owner of the settled position.
    /// @param tokenId TokenId of the settled position.
    /// @param settledAmounts LeftRight encoding for the amount of premium settled for token0 (right slot) and token1 (left slot).
    event PremiumSettled(
        address indexed user,
        TokenId indexed tokenId,
        LeftRightSigned settledAmounts
    );

    /// @notice Emitted when an option is burned.
    /// @dev Is not emitted when a position is liquidated or force exercised.
    /// @param recipient User that burnt the option.
    /// @param positionSize The number of contracts burnt, expressed in terms of the asset.
    /// @param tokenId TokenId of the burnt option.
    /// @param premia LeftRight packing for the amount of premia collected for token0 and token1.
    /// The token0 premia is in the right slot, and token1 premia is in the left slot.
    event OptionBurnt(
        address indexed recipient,
        uint128 positionSize,
        TokenId indexed tokenId,
        LeftRightSigned premia
    );

    /// @notice Emitted when an option is minted.
    /// @dev Cannot add liquidity to an existing position
    /// @param recipient User that minted the option.
    /// @param positionSize The number of contracts minted, expressed in terms of the asset.
    /// @param tokenId TokenId of the created option.
    /// @param poolUtilizations Packing of the pool utilization (how much funds are in the Panoptic pool versus the AMM pool at the time of minting),
    /// right 64bits for token0 and left 64bits for token1, defined as (inAMM * 10_000) / totalAssets().
    /// Where totalAssets is the total tracked assets in the AMM and PanopticPool minus fees and donations to the Panoptic pool.
    event OptionMinted(
        address indexed recipient,
        uint128 positionSize,
        TokenId indexed tokenId,
        uint128 poolUtilizations
    );

    /*//////////////////////////////////////////////////////////////
                         IMMUTABLES & CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // specifies what the MIN/MAX slippage ticks are:
    /// @dev has to be one above MIN because of univ3pool.swap's strict "<" check
    int24 internal constant MIN_SWAP_TICK = Constants.MIN_V3POOL_TICK + 1;
    /// @dev has to be one below MAX because of univ3pool.swap's strict "<" check
    int24 internal constant MAX_SWAP_TICK = Constants.MAX_V3POOL_TICK - 1;

    // Flags used as arguments to premia caluculation functions
    /// @dev 'COMPUTE_ALL_PREMIA' calculates premia for all legs of a position
    bool internal constant COMPUTE_ALL_PREMIA = true;
    /// @dev 'COMPUTE_LONG_PREMIA' calculates premia for only the long legs of a position
    bool internal constant COMPUTE_LONG_PREMIA = false;

    /// @dev Only include the share of (settled) premium that is available to collect when calling `_calculateAccumulatedPremia`
    bool internal constant ONLY_AVAILABLE_PREMIUM = false;

    /// @dev Flag on the function `updateSettlementPostBurn`
    /// @dev 'COMMIT_LONG_SETTLED' commits both collected Uniswap fees and settled long premium to `s_settledTokens`
    /// @dev 'DONOT_COMMIT_LONG__SETTLED' only commits collected Uniswap fees to `s_settledTokens`
    bool internal constant COMMIT_LONG_SETTLED = true;
    bool internal constant DONOT_COMMIT_LONG_SETTLED = false;

    /// @dev Boolean flag to determine wether a position is added (true) or not (!ADD = false)
    bool internal constant ADD = true;

    /// @dev The window to calculate the TWAP used for solvency checks
    /// Currently calculated by dividing this value into 20 periods, averaging them together, then taking the median
    /// May be configurable on a pool-by-pool basis in the future, but hardcoded for now
    uint32 internal constant TWAP_WINDOW = 600;

    // If false, an 7-slot internal median array is used to compute the "slow" oracle price
    // This oracle is updated with the last Uniswap observation during `mintOptions` if MEDIAN_PERIOD has elapsed past the last observation
    // If true, the "slow" oracle price is instead computed on-the-fly from 7 Uniswap observations (spaced 5 observations apart) irrespective of the frequency of `mintOptions` calls
    bool internal constant SLOW_ORACLE_UNISWAP_MODE = false;

    // The minimum amount of time, in seconds, permitted between internal TWAP updates.
    uint256 internal constant MEDIAN_PERIOD = 60;

    /// @dev Amount of Uniswap observations to take in computing the "fast" oracle price
    uint256 internal constant FAST_ORACLE_CARDINALITY = 3;

    /// @dev Amount of observation indices to skip in between each observation for the "fast" oracle price
    /// Note that the *minimum* total observation time is determined by the blocktime and may need to be adjusted by chain
    /// Uniswap observations snapshot the last block's closing price at the first interaction with the pool in a block
    /// In this case, if there is an interaction every block, the "fast" oracle can consider 3 consecutive block end prices (min=36 seconds on Ethereum)
    uint256 internal constant FAST_ORACLE_PERIOD = 1;

    /// @dev Amount of Uniswap observations to take in computing the "slow" oracle price (in Uniswap mode)
    uint256 internal constant SLOW_ORACLE_CARDINALITY = 7;

    /// @dev Amount of observation indices to skip in between each observation for the "slow" oracle price
    /// @dev Structured such that the minimum total observation time is 7 minutes on Ethereum (similar to internal median mode)
    uint256 internal constant SLOW_ORACLE_PERIOD = 5;

    // The maximum allowed delta between the currentTick and the Uniswap TWAP tick during a liquidation (~5% down, ~5.26% up)
    // Prevents manipulation of the currentTick to liquidate positions at a less favorable price
    int256 internal constant MAX_TWAP_DELTA_LIQUIDATION = 513;

    /// The maximum allowed delta between the fast and slow oracle ticks
    /// Falls back on the more conservative (less solvent) tick during times of extreme volatility (to ensure the account is always solvent)
    int256 internal constant MAX_SLOW_FAST_DELTA = 1800;

    /// @dev The maximum allowed ratio for a single chunk, defined as: totalLiquidity / netLiquidity
    /// The long premium spread multiplier that corresponds with the MAX_SPREAD value depends on VEGOID,
    /// which can be explored in this calculator: https://www.desmos.com/calculator/mdeqob2m04
    uint64 internal constant MAX_SPREAD = 9 * (2 ** 32);

    /// @dev The maximum allowed number of opened positions
    uint64 internal constant MAX_POSITIONS = 32;

    // multiplier (x10k) for the collateral requirement in the event of a buying power decrease, such as minting or force exercising
    uint256 internal constant BP_DECREASE_BUFFER = 13_333;

    // multiplier (x10k) for the collateral requirement in the general case
    uint256 internal constant NO_BUFFER = 10_000;

    // Panoptic ecosystem contracts - addresses are set in the constructor

    /// @notice The "engine" of Panoptic - manages AMM liquidity and executes all mints/burns/exercises
    SemiFungiblePositionManager internal immutable SFPM;

    /*//////////////////////////////////////////////////////////////
                                STORAGE 
    //////////////////////////////////////////////////////////////*/

    /// @dev The Uniswap v3 pool that this instance of Panoptic is deployed on
    IUniswapV3Pool internal s_univ3pool;

    /// @notice Mini-median storage slot
    /// @dev The data for the last 8 interactions is stored as such:
    /// LAST UPDATED BLOCK TIMESTAMP (40 bits)
    /// [BLOCK.TIMESTAMP]
    // (00000000000000000000000000000000) // dynamic
    //
    /// @dev ORDERING of tick indices least --> greatest (24 bits)
    /// The value of the bit codon ([#]) is a pointer to a tick index in the tick array.
    /// The position of the bit codon from most to least significant is the ordering of the
    /// tick index it points to from least to greatest.
    //
    /// @dev [7] [5] [3] [1] [0] [2] [4] [6]
    /// 111 101 011 001 000 010 100 110
    //
    // [Constants.MIN_V3POOL_TICK] [7]
    // 111100100111011000010111
    //
    // [Constants.MAX_V3POOL_TICK] [0]
    // 000011011000100111101001
    //
    // [Constants.MIN_V3POOL_TICK] [6]
    // 111100100111011000010111
    //
    // [Constants.MAX_V3POOL_TICK] [1]
    // 000011011000100111101001
    //
    // [Constants.MIN_V3POOL_TICK] [5]
    // 111100100111011000010111
    //
    // [Constants.MAX_V3POOL_TICK] [2]
    // 000011011000100111101001
    //
    ///  @dev [CURRENT TICK] [4]
    /// (000000000000000000000000) // dynamic
    //
    ///  @dev [CURRENT TICK] [3]
    /// (000000000000000000000000) // dynamic
    uint256 internal s_miniMedian;

    /// @dev ERC4626 vaults that users collateralize their positions with
    /// Each token has its own vault, listed in the same order as the tokens in the pool
    /// In addition to collateral deposits, these vaults also handle various collateral/bonus/exercise computations
    /// underlying collateral token0
    CollateralTracker internal s_collateralToken0;
    /// @dev underlying collateral token1
    CollateralTracker internal s_collateralToken1;

    /// @dev Nested mapping that tracks the option formation: address => tokenId => leg => premiaGrowth
    // premia growth is taking a snapshot of the chunk premium in SFPM, which is measuring the amount of fees
    // collected for every chunk per unit of liquidity (net or short, depending on the isLong value of the specific leg index)
    mapping(address account => mapping(TokenId tokenId => mapping(uint256 leg => LeftRightUnsigned premiaGrowth)))
        internal s_options;

    /// @dev Per-chunk `last` value that gives the aggregate amount of premium owed to all sellers when multiplied by the total amount of liquidity `totalLiquidity`
    /// totalGrossPremium = totalLiquidity * (grossPremium(perLiquidityX64) - lastGrossPremium(perLiquidityX64)) / 2**64
    /// Used to compute the denominator for the fraction of premium available to sellers to collect
    /// LeftRight - right slot is token0, left slot is token1
    mapping(bytes32 chunkKey => LeftRightUnsigned lastGrossPremium) internal s_grossPremiumLast;

    /// @dev per-chunk accumulator for tokens owed to sellers that have been settled and are now available
    /// This number increases when buyers pay long premium and when tokens are collected from Uniswap
    /// It decreases when sellers close positions and collect the premium they are owed
    /// LeftRight - right slot is token0, left slot is token1
    mapping(bytes32 chunkKey => LeftRightUnsigned settledTokens) internal s_settledTokens;

    /// @dev Tracks the amount of liquidity for a user+tokenId (right slot) and the initial pool utilizations when that position was minted (left slot)
    ///    poolUtilizations when minted (left)    liquidity=ERC1155 balance (right)
    ///        token0          token1
    ///  |<-- 64 bits -->|<-- 64 bits -->|<---------- 128 bits ---------->|
    ///  |<-------------------------- 256 bits -------------------------->|
    mapping(address account => mapping(TokenId tokenId => LeftRightUnsigned balanceAndUtilizations))
        internal s_positionBalance;

    /// @dev numPositions (32 positions max)    user positions hash
    ///  |<-- 8 bits -->|<------------------ 248 bits ------------------->|
    ///  |<---------------------- 256 bits ------------------------------>|
    /// @dev Tracks the position list hash i.e keccak256(XORs of abi.encodePacked(positionIdList)).
    /// The order and content of this list is emitted in an event every time it is changed
    /// If the user has no positions, the hash is not the hash of "[]" but just bytes32(0) for consistency.
    /// The accumulator also tracks the total number of positions (ie. makes sure the length of the provided positionIdList matches);
    /// @dev The purpose of the positionIdList is to reduce storage usage when a user has more than one active position
    /// instead of having to manage an unwieldy storage array and do lots of loads, we just store a hash of the array
    /// this hash can be cheaply verified on every operation with a user provided positionIdList - and we can use that for operations
    /// without having to every load any other data from storage
    mapping(address account => uint256 positionsHash) internal s_positionsHash;

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice During construction: sets the address of the panoptic factory smart contract and the SemiFungiblePositionMananger (SFPM).
    /// @param _sfpm The address of the SemiFungiblePositionManager (SFPM) contract.
    constructor(SemiFungiblePositionManager _sfpm) {
        SFPM = _sfpm;
    }

    /// @notice Creates a method for creating a Panoptic Pool on top of an existing Uniswap v3 pair.
    /// @dev Must be called first before any transaction can occur. Must also deploy collateralReference first.
    /// @param _univ3pool Address of the target Uniswap v3 pool.
    /// @param token0 Address of the pool's token0.
    /// @param token1 Address of the pool's token1.
    /// @param collateralTracker0 Interface for collateral token0.
    /// @param collateralTracker1 Interface for collateral token1.
    function startPool(
        IUniswapV3Pool _univ3pool,
        address token0,
        address token1,
        CollateralTracker collateralTracker0,
        CollateralTracker collateralTracker1
    ) external {
        // reverts if the Uniswap pool has already been initialized
        if (address(s_univ3pool) != address(0)) revert Errors.PoolAlreadyInitialized();

        // Store the univ3Pool variable
        s_univ3pool = IUniswapV3Pool(_univ3pool);

        (, int24 currentTick, , , , , ) = IUniswapV3Pool(_univ3pool).slot0();

        // Store the median data
        unchecked {
            s_miniMedian =
                (uint256(block.timestamp) << 216) +
                // magic number which adds (7,5,3,1,0,2,4,6) order and minTick in positions 7, 5, 3 and maxTick in 6, 4, 2
                // see comment on s_miniMedian initialization for format of this magic number
                (uint256(0xF590A6F276170D89E9F276170D89E9F276170D89E9000000000000)) +
                (uint256(uint24(currentTick)) << 24) + // add to slot 4
                (uint256(uint24(currentTick))); // add to slot 3
        }

        // Store the collateral token0
        s_collateralToken0 = collateralTracker0;
        s_collateralToken1 = collateralTracker1;

        // consolidate all 4 approval calls to one library delegatecall in order to reduce bytecode size
        // approves:
        // SFPM: token0, token1
        // CollateralTracker0 - token0
        // CollateralTracker1 - token1
        InteractionHelper.doApprovals(SFPM, collateralTracker0, collateralTracker1, token0, token1);
    }

    /*//////////////////////////////////////////////////////////////
                             QUERY HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts if current Uniswap price is not within the provided bounds.
    /// @dev Can be used for composable slippage checks with `multicall` (such as for a force exercise or liquidation)
    /// @dev Can also be used for more granular subtick precision on slippage checks
    /// @param sqrtLowerBound The lower bound of the acceptable open interval for `currentSqrtPriceX96`
    /// @param sqrtUpperBound The upper bound of the acceptable open interval for `currentSqrtPriceX96`
    function assertPriceWithinBounds(uint160 sqrtLowerBound, uint160 sqrtUpperBound) external view {
        (uint160 currentSqrtPriceX96, , , , , , ) = s_univ3pool.slot0();

        if (currentSqrtPriceX96 <= sqrtLowerBound || currentSqrtPriceX96 >= sqrtUpperBound) {
            revert Errors.PriceBoundFail();
        }
    }

    /// @notice Returns the total number of contracts owned by user for a specified position.
    /// @param user Address of the account to be checked.
    /// @param tokenId TokenId of the option position to be checked.
    /// @return balance Number of contracts of tokenId owned by the user.
    /// @return poolUtilization0 The utilization of token0 in the Panoptic pool at mint.
    /// @return poolUtilization1 The utilization of token1 in the Panoptic pool at mint.
    function optionPositionBalance(
        address user,
        TokenId tokenId
    ) external view returns (uint128 balance, uint64 poolUtilization0, uint64 poolUtilization1) {
        // Extract the data stored in s_positionBalance for the provided user + tokenId
        LeftRightUnsigned balanceData = s_positionBalance[user][tokenId];

        // Return the unpacked data: balanceOf(user, tokenId) and packed pool utilizations at the time of minting
        balance = balanceData.rightSlot();

        // pool utilizations are packed into a single uint128

        // the 64 least significant bits are the utilization of token0, so we can simply cast to uint64 to extract it
        // (cutting off the 64 most significant bits)
        poolUtilization0 = uint64(balanceData.leftSlot());

        // the 64 most significant bits are the utilization of token1, so we can shift the number to the right by 64 to extract it
        // (shifting away the 64 least significant bits)
        poolUtilization1 = uint64(balanceData.leftSlot() >> 64);
    }

    /// @notice Compute the total amount of premium accumulated for a list of positions.
    /// @dev Can be costly as it reads information from 2 ticks for each leg of each tokenId.
    /// @param user Address of the user that owns the positions.
    /// @param positionIdList List of positions. Written as [tokenId1, tokenId2, ...].
    /// @param includePendingPremium true = include premium that is owed to the user but has not yet settled, false = only include premium that is available to collect.
    /// @return premium0 Premium for token0 (negative = amount is owed).
    /// @return premium1 Premium for token1 (negative = amount is owed).
    /// @return balances A list of balances and pool utilization for each position, of the form [[tokenId0, balances0], [tokenId1, balances1], ...].
    function calculateAccumulatedFeesBatch(
        address user,
        bool includePendingPremium,
        TokenId[] calldata positionIdList
    ) external view returns (int128 premium0, int128 premium1, uint256[2][] memory) {
        // Get the current tick of the Uniswap pool
        (, int24 currentTick, , , , , ) = s_univ3pool.slot0();

        // Compute the accumulated premia for all tokenId in positionIdList (includes short+long premium)
        (LeftRightSigned premia, uint256[2][] memory balances) = _calculateAccumulatedPremia(
            user,
            positionIdList,
            COMPUTE_ALL_PREMIA,
            includePendingPremium,
            currentTick
        );

        // Return the premia as (token0, token1)
        return (premia.rightSlot(), premia.leftSlot(), balances);
    }

    /// @notice Compute the total value of the portfolio defined by the positionIdList at the given tick.
    /// @dev The return values do not include the value of the accumulated fees.
    /// @dev value0 and value1 are related to one another according to: value1 = value0 * price(atTick).
    /// @param user Address of the user that owns the positions.
    /// @param atTick Tick at which the portfolio value is evaluated.
    /// @param positionIdList List of positions. Written as [tokenId1, tokenId2, ...].
    /// @return value0 Portfolio value in terms of token0 (negative = loss, when compared with starting value).
    /// @return value1 Portfolio value in terms of token1 (negative = loss, when compared to starting value).
    function calculatePortfolioValue(
        address user,
        int24 atTick,
        TokenId[] calldata positionIdList
    ) external view returns (int256 value0, int256 value1) {
        (value0, value1) = FeesCalc.getPortfolioValue(
            atTick,
            s_positionBalance[user],
            positionIdList
        );
    }

    /// @notice Calculate the accumulated premia owed from the option buyer to the option seller.
    /// @param user The holder of options.
    /// @param positionIdList The list of all option positions held by user.
    /// @param computeAllPremia Whether to compute accumulated premia for all legs held by the user (true), or just owed premia for long legs (false).
    /// @param includePendingPremium true = include premium that is owed to the user but has not yet settled, false = only include premium that is available to collect.
    /// @return portfolioPremium The computed premia of the user's positions, where premia contains the accumulated premia for token0 in the right slot and for token1 in the left slot.
    /// @return balances A list of balances and pool utilization for each position, of the form [[tokenId0, balances0], [tokenId1, balances1], ...].
    function _calculateAccumulatedPremia(
        address user,
        TokenId[] calldata positionIdList,
        bool computeAllPremia,
        bool includePendingPremium,
        int24 atTick
    ) internal view returns (LeftRightSigned portfolioPremium, uint256[2][] memory balances) {
        uint256 pLength = positionIdList.length;
        balances = new uint256[2][](pLength);

        address c_user = user;
        // loop through each option position/tokenId
        for (uint256 k = 0; k < pLength; ) {
            TokenId tokenId = positionIdList[k];

            balances[k][0] = TokenId.unwrap(tokenId);
            balances[k][1] = LeftRightUnsigned.unwrap(s_positionBalance[c_user][tokenId]);

            (
                LeftRightSigned[4] memory premiaByLeg,
                uint256[2][4] memory premiumAccumulatorsByLeg
            ) = _getPremia(
                    tokenId,
                    LeftRightUnsigned.wrap(balances[k][1]).rightSlot(),
                    c_user,
                    computeAllPremia,
                    atTick
                );

            uint256 numLegs = tokenId.countLegs();
            for (uint256 leg = 0; leg < numLegs; ) {
                if (tokenId.isLong(leg) == 0 && !includePendingPremium) {
                    bytes32 chunkKey = keccak256(
                        abi.encodePacked(
                            tokenId.strike(leg),
                            tokenId.width(leg),
                            tokenId.tokenType(leg)
                        )
                    );

                    LeftRightUnsigned availablePremium = _getAvailablePremium(
                        _getTotalLiquidity(tokenId, leg),
                        s_settledTokens[chunkKey],
                        s_grossPremiumLast[chunkKey],
                        LeftRightUnsigned.wrap(uint256(LeftRightSigned.unwrap(premiaByLeg[leg]))),
                        premiumAccumulatorsByLeg[leg]
                    );
                    portfolioPremium = portfolioPremium.add(
                        LeftRightSigned.wrap(int256(LeftRightUnsigned.unwrap(availablePremium)))
                    );
                } else {
                    portfolioPremium = portfolioPremium.add(premiaByLeg[leg]);
                }
                unchecked {
                    ++leg;
                }
            }

            unchecked {
                ++k;
            }
        }
        return (portfolioPremium, balances);
    }

    /// @notice Disable slippage checks if tickLimitLow == tickLimitHigh and reverses ticks if given in correct order to enable ITM swaps
    /// @param tickLimitLow The lower slippage limit on the tick.
    /// @param tickLimitHigh The upper slippage limit on the tick.
    /// @return tickLimitLow Adjusted value for the lower tick limit.
    /// @return tickLimitHigh Adjusted value for the upper tick limit.
    function _getSlippageLimits(
        int24 tickLimitLow,
        int24 tickLimitHigh
    ) internal pure returns (int24, int24) {
        // disable slippage checks if tickLimitLow == tickLimitHigh
        if (tickLimitLow == tickLimitHigh) {
            // note the reversed order of the ticks
            return (MAX_SWAP_TICK, MIN_SWAP_TICK);
        }

        // ensure tick limits are reversed (the SFPM uses low > high as a flag to do ITM swaps, which we need)
        if (tickLimitLow < tickLimitHigh) {
            return (tickLimitHigh, tickLimitLow);
        }

        return (tickLimitLow, tickLimitHigh);
    }

    /*//////////////////////////////////////////////////////////////
                          ONBOARD MEDIAN TWAP
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the internal median with the last Uniswap observation if the MEDIAN_PERIOD has elapsed.
    function pokeMedian() external {
        (, , uint16 observationIndex, uint16 observationCardinality, , , ) = s_univ3pool.slot0();

        (, uint256 medianData) = PanopticMath.computeInternalMedian(
            observationIndex,
            observationCardinality,
            MEDIAN_PERIOD,
            s_miniMedian,
            s_univ3pool
        );

        if (medianData != 0) s_miniMedian = medianData;
    }

    /*//////////////////////////////////////////////////////////////
                          MINT/BURN INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates the current options of the user, and mints a new position.
    /// @param positionIdList the list of currently held positions by the user, where the newly minted position(token) will be the last element in 'positionIdList'.
    /// @param positionSize The size of the position to be minted, expressed in terms of the asset.
    /// @param effectiveLiquidityLimitX32 Maximum amount of "spread" defined as totalLiquidity/netLiquidity for a new position.
    /// denominated as X32 = (ratioLimit * 2**32). Set to 0 for no limit / only short options.
    /// @param tickLimitLow The lower tick slippagelimit.
    /// @param tickLimitHigh The upper tick slippagelimit.
    function mintOptions(
        TokenId[] calldata positionIdList,
        uint128 positionSize,
        uint64 effectiveLiquidityLimitX32,
        int24 tickLimitLow,
        int24 tickLimitHigh
    ) external {
        _mintOptions(
            positionIdList,
            positionSize,
            effectiveLiquidityLimitX32,
            tickLimitLow,
            tickLimitHigh
        );
    }

    /// @notice Burns the entire balance of tokenId of the caller(msg.sender).
    /// @dev Will exercise if necessary, and will revert if user does not have enough collateral to exercise.
    /// @param tokenId The tokenId of the option position to be burnt.
    /// @param newPositionIdList The new positionIdList without the token being burnt.
    /// @param tickLimitLow Price slippage limit when burning an ITM option.
    /// @param tickLimitHigh Price slippage limit when burning an ITM option.
    function burnOptions(
        TokenId tokenId,
        TokenId[] calldata newPositionIdList,
        int24 tickLimitLow,
        int24 tickLimitHigh
    ) external {
        _burnOptions(COMMIT_LONG_SETTLED, tokenId, msg.sender, tickLimitLow, tickLimitHigh);

        _validateSolvency(msg.sender, newPositionIdList, NO_BUFFER);
    }

    /// @notice Burns the entire balance of all tokenIds provided in positionIdList of the caller(msg.sender).
    /// @dev Will exercise if necessary, and will revert if user does not have enough collateral to exercise.
    /// @param positionIdList The list of tokenIds for the option positions to be burnt.
    /// @param newPositionIdList The new positionIdList without the token(s) being burnt.
    /// @param tickLimitLow Price slippage limit when burning an ITM option.
    /// @param tickLimitHigh Price slippage limit when burning an ITM option.
    function burnOptions(
        TokenId[] calldata positionIdList,
        TokenId[] calldata newPositionIdList,
        int24 tickLimitLow,
        int24 tickLimitHigh
    ) external {
        _burnAllOptionsFrom(
            msg.sender,
            tickLimitLow,
            tickLimitHigh,
            COMMIT_LONG_SETTLED,
            positionIdList
        );

        _validateSolvency(msg.sender, newPositionIdList, NO_BUFFER);
    }

    /*//////////////////////////////////////////////////////////////
                         POSITION MINTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates the current options of the user, and mints a new position.
    /// @param positionIdList the list of currently held positions by the user, where the newly minted position(token) will be the last element in 'positionIdList'.
    /// @param positionSize The size of the position to be minted, expressed in terms of the asset.
    /// @param effectiveLiquidityLimitX32 Maximum amount of "spread" defined as totalLiquidity/netLiquidity for a new position.
    /// denominated as X32 = (ratioLimit * 2**32). Set to 0 for no limit / only short options.
    /// @param tickLimitLow The lower tick slippagelimit.
    /// @param tickLimitHigh The upper tick slippagelimit.
    function _mintOptions(
        TokenId[] calldata positionIdList,
        uint128 positionSize,
        uint64 effectiveLiquidityLimitX32,
        int24 tickLimitLow,
        int24 tickLimitHigh
    ) internal {
        // the new tokenId will be the last element in 'positionIdList'
        TokenId tokenId;
        unchecked {
            tokenId = positionIdList[positionIdList.length - 1];
        }

        // do duplicate checks and the checks related to minting and positions
        _validatePositionList(msg.sender, positionIdList, 1);

        (tickLimitLow, tickLimitHigh) = _getSlippageLimits(tickLimitLow, tickLimitHigh);

        // make sure the tokenId is for this Panoptic pool
        if (tokenId.poolId() != SFPM.getPoolId(address(s_univ3pool)))
            revert Errors.InvalidTokenIdParameter(0);

        // disallow user to mint exact same position
        // in order to do it, user should burn it first and then mint
        if (LeftRightUnsigned.unwrap(s_positionBalance[msg.sender][tokenId]) != 0)
            revert Errors.PositionAlreadyMinted();

        // Mint in the SFPM and update state of collateral
        uint128 poolUtilizations = _mintInSFPMAndUpdateCollateral(
            tokenId,
            positionSize,
            tickLimitLow,
            tickLimitHigh
        );

        // calculate and write position data
        _addUserOption(tokenId, effectiveLiquidityLimitX32);

        // update the users options balance of position 'tokenId'
        // note: user can't mint same position multiple times, so set the positionSize instead of adding
        s_positionBalance[msg.sender][tokenId] = LeftRightUnsigned
            .wrap(0)
            .toLeftSlot(poolUtilizations)
            .toRightSlot(positionSize);

        // Perform solvency check on user's account to ensure they had enough buying power to mint the option
        // Add an initial buffer to the collateral requirement to prevent users from minting their account close to insolvency
        uint256 medianData = _validateSolvency(msg.sender, positionIdList, BP_DECREASE_BUFFER);

        // Update `s_miniMedian` with a new observation if the last observation is old enough (returned medianData is nonzero)
        if (medianData != 0) s_miniMedian = medianData;

        emit OptionMinted(msg.sender, positionSize, tokenId, poolUtilizations);
    }

    /// @notice Check user health (collateral status).
    /// @dev Moves the required liquidity and checks for user health.
    /// @param tokenId The option position to be minted.
    /// @param positionSize The size of the position, expressed in terms of the asset.
    /// @param tickLimitLow The lower slippage limit on the tick.
    /// @param tickLimitHigh The upper slippage limit on the tick.
    /// @return poolUtilizations Packing of the pool utilization (how much funds are in the Panoptic pool versus the AMM pool) at the time of minting,
    /// right 64bits for token0 and left 64bits for token1.
    function _mintInSFPMAndUpdateCollateral(
        TokenId tokenId,
        uint128 positionSize,
        int24 tickLimitLow,
        int24 tickLimitHigh
    ) internal returns (uint128) {
        // Mint position by using the SFPM. totalSwapped will reflect tokens swapped because of minting ITM.
        // Switch order of tickLimits to create "swapAtMint" flag
        (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped) = SFPM
            .mintTokenizedPosition(tokenId, positionSize, tickLimitLow, tickLimitHigh);

        // update premium settlement info
        _updateSettlementPostMint(tokenId, collectedByLeg, positionSize);

        // pay commission based on total moved amount (long + short)
        // write data about inAMM in collateralBase
        uint128 poolUtilizations = _payCommissionAndWriteData(tokenId, positionSize, totalSwapped);

        return poolUtilizations;
    }

    /// @notice Pay the commission fees for creating the options and update internal state.
    /// @dev Computes long+short amounts, extracts pool utilizations.
    /// @param tokenId The option position
    /// @param positionSize The size of the position, expressed in terms of the asset
    /// @param totalSwapped How much was swapped (if in-the-money position).
    /// @return poolUtilizations Packing of the pool utilization (how much funds are in the Panoptic pool versus the AMM pool at the time of minting),
    /// right 64bits for token0 and left 64bits for token1, defined as (inAMM * 10_000) / totalAssets().
    /// Where totalAssets is the total tracked assets in the AMM and PanopticPool minus fees and donations to the Panoptic pool.
    function _payCommissionAndWriteData(
        TokenId tokenId,
        uint128 positionSize,
        LeftRightSigned totalSwapped
    ) internal returns (uint128) {
        // compute how much of tokenId is long and short positions
        (LeftRightSigned longAmounts, LeftRightSigned shortAmounts) = PanopticMath
            .computeExercisedAmounts(tokenId, positionSize);

        int256 utilization0 = s_collateralToken0.takeCommissionAddData(
            msg.sender,
            longAmounts.rightSlot(),
            shortAmounts.rightSlot(),
            totalSwapped.rightSlot()
        );
        int256 utilization1 = s_collateralToken1.takeCommissionAddData(
            msg.sender,
            longAmounts.leftSlot(),
            shortAmounts.leftSlot(),
            totalSwapped.leftSlot()
        );

        // return pool utilizations as a uint128 (pool Utilization is always < 10000)
        unchecked {
            return uint128(uint256(utilization0) + uint128(uint256(utilization1) << 64));
        }
    }

    /// @notice Store user option data. Track fees collected for the options.
    /// @dev Computes and stores the option data for each leg.
    /// @param tokenId The id of the minted option position.
    /// @param effectiveLiquidityLimitX32 Maximum amount of "spread" defined as totalLiquidity/netLiquidity for a new position
    /// denominated as X32 = (ratioLimit * 2**32). Set to 0 for no limit / only short options.
    function _addUserOption(TokenId tokenId, uint64 effectiveLiquidityLimitX32) internal {
        // Update the position list hash (hash = XOR of all keccak256(tokenId)). Remove hash by XOR'ing again
        _updatePositionsHash(msg.sender, tokenId, ADD);

        uint256 numLegs = tokenId.countLegs();
        // compute upper and lower tick and liquidity
        for (uint256 leg = 0; leg < numLegs; ) {
            // Extract base fee (AMM swap/trading fees) for the position and add it to s_options
            // (ie. the (feeGrowth * liquidity) / 2**128 for each token)
            (int24 tickLower, int24 tickUpper) = tokenId.asTicks(leg);
            uint256 isLong = tokenId.isLong(leg);
            {
                (uint128 premiumAccumulator0, uint128 premiumAccumulator1) = SFPM.getAccountPremium(
                    address(s_univ3pool),
                    address(this),
                    tokenId.tokenType(leg),
                    tickLower,
                    tickUpper,
                    type(int24).max,
                    isLong
                );

                // update the premium accumulators
                s_options[msg.sender][tokenId][leg] = LeftRightUnsigned
                    .wrap(0)
                    .toRightSlot(premiumAccumulator0)
                    .toLeftSlot(premiumAccumulator1);
            }
            // verify base Liquidity limit only if new position is long
            if (isLong == 1) {
                // Move this into a new function
                _checkLiquiditySpread(
                    tokenId,
                    leg,
                    tickLower,
                    tickUpper,
                    uint64(Math.min(effectiveLiquidityLimitX32, MAX_SPREAD))
                );
            }
            unchecked {
                ++leg;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                         POSITION BURNING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Helper to burn option during a liquidation from an account _owner.
    /// @param owner the owner of the option position to be liquidated.
    /// @param tickLimitLow Price slippage limit when burning an ITM option
    /// @param tickLimitHigh Price slippage limit when burning an ITM option
    /// @param commitLongSettled Whether to commit the long premium that will be settled to storage
    /// @param positionIdList the option position to liquidate.
    function _burnAllOptionsFrom(
        address owner,
        int24 tickLimitLow,
        int24 tickLimitHigh,
        bool commitLongSettled,
        TokenId[] calldata positionIdList
    ) internal returns (LeftRightSigned netPaid, LeftRightSigned[4][] memory premiasByLeg) {
        premiasByLeg = new LeftRightSigned[4][](positionIdList.length);
        for (uint256 i = 0; i < positionIdList.length; ) {
            LeftRightSigned paidAmounts;
            (paidAmounts, premiasByLeg[i]) = _burnOptions(
                commitLongSettled,
                positionIdList[i],
                owner,
                tickLimitLow,
                tickLimitHigh
            );
            netPaid = netPaid.add(paidAmounts);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Helper to burn an option position held by '_owner'.
    /// @param tokenId the option position to burn.
    /// @param owner the owner of the option position to be burned.
    /// @param tickLimitLow Price slippage limit when burning an ITM option
    /// @param tickLimitHigh Price slippage limit when burning an ITM option
    /// @param commitLongSettled Whether to commit the long premium that will be settled to storage
    /// @return paidAmounts The amount of tokens paid when closing the option
    /// @return premiaByLeg The amount of premia owed to the user for each leg of the position
    function _burnOptions(
        bool commitLongSettled,
        TokenId tokenId,
        address owner,
        int24 tickLimitLow,
        int24 tickLimitHigh
    ) internal returns (LeftRightSigned paidAmounts, LeftRightSigned[4] memory premiaByLeg) {
        // Ensure that the current price is within the tick limits
        (tickLimitLow, tickLimitHigh) = _getSlippageLimits(tickLimitLow, tickLimitHigh);

        uint128 positionSize = s_positionBalance[owner][tokenId].rightSlot();

        LeftRightSigned premiaOwed;
        // burn position and do exercise checks
        (premiaOwed, premiaByLeg, paidAmounts) = _burnAndHandleExercise(
            commitLongSettled,
            tickLimitLow,
            tickLimitHigh,
            tokenId,
            positionSize,
            owner
        );

        // erase position data
        _updatePositionDataBurn(owner, tokenId);

        // emit event
        emit OptionBurnt(owner, positionSize, tokenId, premiaOwed);
    }

    /// @notice Update the internal tracking of the owner's position data upon burning a position.
    /// @param owner The owner of the option position.
    /// @param tokenId The option position to burn.
    function _updatePositionDataBurn(address owner, TokenId tokenId) internal {
        // reset balances and delete stored option data
        s_positionBalance[owner][tokenId] = LeftRightUnsigned.wrap(0);

        uint256 numLegs = tokenId.countLegs();
        for (uint256 leg = 0; leg < numLegs; ) {
            if (tokenId.isLong(leg) == 0) {
                // Check the liquidity spread, make sure that closing the option does not exceed the MAX_SPREAD allowed
                (int24 tickLower, int24 tickUpper) = tokenId.asTicks(leg);
                _checkLiquiditySpread(tokenId, leg, tickLower, tickUpper, MAX_SPREAD);
            }
            s_options[owner][tokenId][leg] = LeftRightUnsigned.wrap(0);
            unchecked {
                ++leg;
            }
        }

        // Update the position list hash (hash = XOR of all keccak256(tokenId)). Remove hash by XOR'ing again
        _updatePositionsHash(owner, tokenId, !ADD);
    }

    /// @notice Validates the solvency of `user` at the fast oracle tick.
    /// @notice Falls back to the more conservative tick if the delta between the fast and slow oracle exceeds `MAX_SLOW_FAST_DELTA`.
    /// @dev Effectively, this means that the users must be solvent at both the fast and slow oracle ticks if one of them is stale to mint or burn options.
    /// @param user The account to validate.
    /// @param positionIdList The new positionIdList without the token(s) being burnt.
    /// @param buffer The buffer to apply to the collateral requirement for `user`
    /// @return medianData If nonzero (enough time has passed since last observation), the updated value for `s_miniMedian` with a new observation
    function _validateSolvency(
        address user,
        TokenId[] calldata positionIdList,
        uint256 buffer
    ) internal view returns (uint256 medianData) {
        // check that the provided positionIdList matches the positions in memory
        _validatePositionList(user, positionIdList, 0);

        IUniswapV3Pool _univ3pool = s_univ3pool;
        (
            ,
            int24 currentTick,
            uint16 observationIndex,
            uint16 observationCardinality,
            ,
            ,

        ) = _univ3pool.slot0();
        int24 fastOracleTick = PanopticMath.computeMedianObservedPrice(
            _univ3pool,
            observationIndex,
            observationCardinality,
            FAST_ORACLE_CARDINALITY,
            FAST_ORACLE_PERIOD
        );

        int24 slowOracleTick;
        if (SLOW_ORACLE_UNISWAP_MODE) {
            slowOracleTick = PanopticMath.computeMedianObservedPrice(
                _univ3pool,
                observationIndex,
                observationCardinality,
                SLOW_ORACLE_CARDINALITY,
                SLOW_ORACLE_PERIOD
            );
        } else {
            (slowOracleTick, medianData) = PanopticMath.computeInternalMedian(
                observationIndex,
                observationCardinality,
                MEDIAN_PERIOD,
                s_miniMedian,
                _univ3pool
            );
        }

        // Check the user's solvency at the fast tick; revert if not solvent
        bool solventAtFast = _checkSolvencyAtTick(
            user,
            positionIdList,
            currentTick,
            fastOracleTick,
            buffer
        );
        if (!solventAtFast) revert Errors.NotEnoughCollateral();

        // If one of the ticks is too stale, we fall back to the more conservative tick, i.e, the user must be solvent at both the fast and slow oracle ticks.
        if (Math.abs(int256(fastOracleTick) - slowOracleTick) > MAX_SLOW_FAST_DELTA)
            if (!_checkSolvencyAtTick(user, positionIdList, currentTick, slowOracleTick, buffer))
                revert Errors.NotEnoughCollateral();
    }

    /// @notice Burns and handles the exercise of options.
    /// @param commitLongSettled Whether to commit the long premium that will be settled to storage
    /// @param tickLimitLow The lower slippage limit on the tick.
    /// @param tickLimitHigh The upper slippage limit on the tick.
    /// @param tokenId The option position to burn.
    /// @param positionSize The size of the option position, expressed in terms of the asset.
    /// @param owner The owner of the option position.
    function _burnAndHandleExercise(
        bool commitLongSettled,
        int24 tickLimitLow,
        int24 tickLimitHigh,
        TokenId tokenId,
        uint128 positionSize,
        address owner
    )
        internal
        returns (
            LeftRightSigned realizedPremia,
            LeftRightSigned[4] memory premiaByLeg,
            LeftRightSigned paidAmounts
        )
    {
        (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped) = SFPM
            .burnTokenizedPosition(tokenId, positionSize, tickLimitLow, tickLimitHigh);

        (realizedPremia, premiaByLeg) = _updateSettlementPostBurn(
            owner,
            tokenId,
            collectedByLeg,
            positionSize,
            commitLongSettled
        );

        (LeftRightSigned longAmounts, LeftRightSigned shortAmounts) = PanopticMath
            .computeExercisedAmounts(tokenId, positionSize);

        {
            int128 paid0 = s_collateralToken0.exercise(
                owner,
                longAmounts.rightSlot(),
                shortAmounts.rightSlot(),
                totalSwapped.rightSlot(),
                realizedPremia.rightSlot()
            );
            paidAmounts = paidAmounts.toRightSlot(paid0);
        }

        {
            int128 paid1 = s_collateralToken1.exercise(
                owner,
                longAmounts.leftSlot(),
                shortAmounts.leftSlot(),
                totalSwapped.leftSlot(),
                realizedPremia.leftSlot()
            );
            paidAmounts = paidAmounts.toLeftSlot(paid1);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    LIQUIDATIONS & FORCED EXERCISES
    //////////////////////////////////////////////////////////////*/

    /// @notice Liquidates a distressed account. Will burn all positions and will issue a bonus to the liquidator.
    /// @dev Will revert if liquidated account is solvent at the TWAP tick or if TWAP tick is too far away from the current tick.
    /// @param positionIdListLiquidator List of positions owned by the liquidator.
    /// @param liquidatee Address of the distressed account.
    /// @param delegations LeftRight amounts of token0 and token1 (token0:token1 right:left) delegated to the liquidatee by the liquidator so the option can be smoothly exercised.
    /// @param positionIdList List of positions owned by the user. Written as [tokenId1, tokenId2, ...].
    function liquidate(
        TokenId[] calldata positionIdListLiquidator,
        address liquidatee,
        LeftRightUnsigned delegations,
        TokenId[] calldata positionIdList
    ) external {
        _validatePositionList(liquidatee, positionIdList, 0);

        // Assert the account we are liquidating is actually insolvent
        int24 twapTick = getUniV3TWAP();

        LeftRightUnsigned tokenData0;
        LeftRightUnsigned tokenData1;
        LeftRightSigned premia;
        {
            (, int24 currentTick, , , , , ) = s_univ3pool.slot0();

            // Enforce maximum delta between TWAP and currentTick to prevent extreme price manipulation
            if (Math.abs(currentTick - twapTick) > MAX_TWAP_DELTA_LIQUIDATION)
                revert Errors.StaleTWAP();

            uint256[2][] memory positionBalanceArray = new uint256[2][](positionIdList.length);
            (premia, positionBalanceArray) = _calculateAccumulatedPremia(
                liquidatee,
                positionIdList,
                COMPUTE_ALL_PREMIA,
                ONLY_AVAILABLE_PREMIUM,
                currentTick
            );
            tokenData0 = s_collateralToken0.getAccountMarginDetails(
                liquidatee,
                twapTick,
                positionBalanceArray,
                premia.rightSlot()
            );

            tokenData1 = s_collateralToken1.getAccountMarginDetails(
                liquidatee,
                twapTick,
                positionBalanceArray,
                premia.leftSlot()
            );

            (uint256 balanceCross, uint256 thresholdCross) = _getSolvencyBalances(
                tokenData0,
                tokenData1,
                Math.getSqrtRatioAtTick(twapTick)
            );

            if (balanceCross >= thresholdCross) revert Errors.NotMarginCalled();
        }

        // Perform the specified delegation from `msg.sender` to `liquidatee`
        // Works like a transfer, so the liquidator must possess all the tokens they are delegating, resulting in no net supply change
        // If not enough tokens are delegated for the positions of `liquidatee` to be closed, the liquidation will fail
        s_collateralToken0.delegate(msg.sender, liquidatee, delegations.rightSlot());
        s_collateralToken1.delegate(msg.sender, liquidatee, delegations.leftSlot());

        int256 liquidationBonus0;
        int256 liquidationBonus1;
        int24 finalTick;
        {
            LeftRightSigned netExchanged;
            LeftRightSigned[4][] memory premiasByLeg;
            // burn all options from the liquidatee

            // Do not commit any settled long premium to storage - we will do this after we determine if any long premium must be revoked
            // This is to prevent any short positions the liquidatee has being settled with tokens that will later be revoked
            // Note: tick limits are not applied here since it is not the liquidator's position being liquidated
            (netExchanged, premiasByLeg) = _burnAllOptionsFrom(
                liquidatee,
                Constants.MIN_V3POOL_TICK,
                Constants.MAX_V3POOL_TICK,
                DONOT_COMMIT_LONG_SETTLED,
                positionIdList
            );

            (, finalTick, , , , , ) = s_univ3pool.slot0();

            LeftRightSigned collateralRemaining;
            // compute bonus amounts using latest tick data
            (liquidationBonus0, liquidationBonus1, collateralRemaining) = PanopticMath
                .getLiquidationBonus(
                    tokenData0,
                    tokenData1,
                    Math.getSqrtRatioAtTick(twapTick),
                    Math.getSqrtRatioAtTick(finalTick),
                    netExchanged,
                    premia
                );

            // premia cannot be paid if there is protocol loss associated with the liquidatee
            // otherwise, an economic exploit could occur if the liquidator and liquidatee collude to
            // manipulate the fees in a liquidity area they control past the protocol loss threshold
            // such that the PLPs are forced to pay out premia to the liquidator
            // thus, we haircut any premium paid by the liquidatee (converting tokens as necessary) until the protocol loss is covered or the premium is exhausted
            // note that the haircutPremia function also commits the settled amounts (adjusted for the haircut) to storage, so it will be called even if there is no haircut

            // if premium is haircut from a token that is not in protocol loss, some of the liquidation bonus will be converted into that token
            // reusing variables to save stack space; netExchanged = deltaBonus0, premia = deltaBonus1
            address _liquidatee = liquidatee;
            TokenId[] memory _positionIdList = positionIdList;
            int24 _finalTick = finalTick;
            int256 deltaBonus0;
            int256 deltaBonus1;
            (deltaBonus0, deltaBonus1) = PanopticMath.haircutPremia(
                _liquidatee,
                _positionIdList,
                premiasByLeg,
                collateralRemaining,
                s_collateralToken0,
                s_collateralToken1,
                Math.getSqrtRatioAtTick(_finalTick),
                s_settledTokens
            );

            unchecked {
                liquidationBonus0 += deltaBonus0;
                liquidationBonus1 += deltaBonus1;
            }
        }

        LeftRightUnsigned _delegations = delegations;
        // revoke the delegated amount plus the bonus amount.
        s_collateralToken0.revoke(
            msg.sender,
            liquidatee,
            uint256(int256(uint256(_delegations.rightSlot())) + liquidationBonus0)
        );
        s_collateralToken1.revoke(
            msg.sender,
            liquidatee,
            uint256(int256(uint256(_delegations.leftSlot())) + liquidationBonus1)
        );

        // check that the provided positionIdList matches the positions in memory
        _validatePositionList(msg.sender, positionIdListLiquidator, 0);

        if (
            !_checkSolvencyAtTick(
                msg.sender,
                positionIdListLiquidator,
                finalTick,
                finalTick,
                BP_DECREASE_BUFFER
            )
        ) revert Errors.NotEnoughCollateral();

        LeftRightSigned bonusAmounts = LeftRightSigned
            .wrap(0)
            .toRightSlot(int128(liquidationBonus0))
            .toLeftSlot(int128(liquidationBonus1));

        emit AccountLiquidated(msg.sender, liquidatee, bonusAmounts);
    }

    /// @notice Force the exercise of a single position. Exercisor will have to pay a fee to the force exercisee.
    /// @dev Will revert if: number of touchedId is larger than 1 or if user force exercises their own position
    /// @param account Address of the distressed account
    /// @param touchedId List of position to be force exercised. Can only contain one tokenId, written as [tokenId]
    /// @param positionIdListExercisee Post-burn list of open positions in the exercisee's (account) account
    /// @param positionIdListExercisor List of open positions in the exercisor's (msg.sender) account
    function forceExercise(
        address account,
        TokenId[] calldata touchedId,
        TokenId[] calldata positionIdListExercisee,
        TokenId[] calldata positionIdListExercisor
    ) external {
        // revert if multiple positions are specified
        // the reason why the singular touchedId is an array is so it composes well with the rest of the system
        // '_calculateAccumulatedPremia' expects a list of positions to be touched, and this is the only way to pass a single position
        if (touchedId.length != 1) revert Errors.InputListFail();

        // validate the exercisor's position list (the exercisee's list will be evaluated after their position is force exercised)
        _validatePositionList(msg.sender, positionIdListExercisor, 0);

        uint128 positionBalance = s_positionBalance[account][touchedId[0]].rightSlot();

        // compute the notional value of the short legs (the maximum amount of tokens required to exercise - premia)
        // and the long legs (from which the exercise cost is computed)
        (LeftRightSigned longAmounts, LeftRightSigned delegatedAmounts) = PanopticMath
            .computeExercisedAmounts(touchedId[0], positionBalance);

        int24 twapTick = getUniV3TWAP();

        (, int24 currentTick, , , , , ) = s_univ3pool.slot0();

        {
            // add the premia to the delegated amounts to ensure the user has enough collateral to exercise
            (LeftRightSigned positionPremia, ) = _calculateAccumulatedPremia(
                account,
                touchedId,
                COMPUTE_LONG_PREMIA,
                ONLY_AVAILABLE_PREMIUM,
                currentTick
            );

            // long premia is represented as negative so subtract it to increase it for the delegated amounts
            delegatedAmounts = delegatedAmounts.sub(positionPremia);
        }

        // on forced exercise, the price *must* be outside the position's range for at least 1 leg
        touchedId[0].validateIsExercisable(twapTick);

        // The protocol delegates some virtual shares to ensure the burn can be settled.
        s_collateralToken0.delegate(account, uint128(delegatedAmounts.rightSlot()));
        s_collateralToken1.delegate(account, uint128(delegatedAmounts.leftSlot()));

        // Exercise the option
        // Note: tick limits are not applied here since it is not the exercisor's position being closed
        _burnAllOptionsFrom(account, 0, 0, COMMIT_LONG_SETTLED, touchedId);

        // Compute the exerciseFee, this will decrease the further away the price is from the forcedExercised position
        /// @dev use the medianTick to prevent price manipulations based on swaps.
        LeftRightSigned exerciseFees = s_collateralToken0.exerciseCost(
            currentTick,
            twapTick,
            touchedId[0],
            positionBalance,
            longAmounts
        );

        LeftRightSigned refundAmounts = delegatedAmounts.add(exerciseFees);

        // redistribute token composition of refund amounts if user doesn't have enough of one token to pay
        refundAmounts = PanopticMath.getRefundAmounts(
            account,
            refundAmounts,
            twapTick,
            s_collateralToken0,
            s_collateralToken1
        );

        unchecked {
            // settle difference between delegated amounts (from the protocol) and exercise fees/substituted tokens
            s_collateralToken0.refund(
                account,
                msg.sender,
                refundAmounts.rightSlot() - delegatedAmounts.rightSlot()
            );
            s_collateralToken1.refund(
                account,
                msg.sender,
                refundAmounts.leftSlot() - delegatedAmounts.leftSlot()
            );
        }

        // refund the protocol any virtual shares after settling the difference with the exercisor
        s_collateralToken0.refund(account, uint128(delegatedAmounts.rightSlot()));
        s_collateralToken1.refund(account, uint128(delegatedAmounts.leftSlot()));

        _validateSolvency(account, positionIdListExercisee, NO_BUFFER);

        // the exercisor's position list is validated above
        // we need to assert their solvency against their collateral requirement plus a buffer
        // force exercises involve a collateral decrease with open positions, so there is a higher standard for solvency
        // a similar buffer is also invoked when minting options, which also decreases the available collateral
        if (positionIdListExercisor.length > 0)
            _validateSolvency(msg.sender, positionIdListExercisor, BP_DECREASE_BUFFER);

        emit ForcedExercised(msg.sender, account, touchedId[0], exerciseFees);
    }

    /*//////////////////////////////////////////////////////////////
                            SOLVENCY CHECKS
    //////////////////////////////////////////////////////////////*/

    /// @notice check whether an account is solvent at a given `atTick` with a collateral requirement of `buffer`/10_000 multiplied by the requirement of `positionIdList`.
    /// @param account The account to check solvency for.
    /// @param positionIdList The list of positions to check solvency for.
    /// @param currentTick The current tick of the Uniswap pool (needed for fee calculations).
    /// @param atTick The tick to check solvency at.
    /// @param buffer The buffer to apply to the collateral requirement.
    function _checkSolvencyAtTick(
        address account,
        TokenId[] calldata positionIdList,
        int24 currentTick,
        int24 atTick,
        uint256 buffer
    ) internal view returns (bool) {
        (
            LeftRightSigned portfolioPremium,
            uint256[2][] memory positionBalanceArray
        ) = _calculateAccumulatedPremia(
                account,
                positionIdList,
                COMPUTE_ALL_PREMIA,
                ONLY_AVAILABLE_PREMIUM,
                currentTick
            );

        LeftRightUnsigned tokenData0 = s_collateralToken0.getAccountMarginDetails(
            account,
            atTick,
            positionBalanceArray,
            portfolioPremium.rightSlot()
        );
        LeftRightUnsigned tokenData1 = s_collateralToken1.getAccountMarginDetails(
            account,
            atTick,
            positionBalanceArray,
            portfolioPremium.leftSlot()
        );

        (uint256 balanceCross, uint256 thresholdCross) = _getSolvencyBalances(
            tokenData0,
            tokenData1,
            Math.getSqrtRatioAtTick(atTick)
        );

        // compare balance and required tokens, can use unsafe div because denominator is always nonzero
        unchecked {
            return balanceCross >= Math.unsafeDivRoundingUp(thresholdCross * buffer, 10_000);
        }
    }

    /// @notice Get parameters related to the solvency state of the account associated with the incoming tokenData.
    /// @param tokenData0 Leftright encoded word with balance of token0 in the right slot, and required balance in left slot.
    /// @param tokenData1 Leftright encoded word with balance of token1 in the right slot, and required balance in left slot.
    /// @param sqrtPriceX96 The current sqrt(price) of the AMM.
    /// @return balanceCross The current cross-collateral balance of the option positions.
    /// @return thresholdCross The cross-collateral threshold balance under which the account is insolvent.
    function _getSolvencyBalances(
        LeftRightUnsigned tokenData0,
        LeftRightUnsigned tokenData1,
        uint160 sqrtPriceX96
    ) internal pure returns (uint256 balanceCross, uint256 thresholdCross) {
        unchecked {
            // the cross-collateral balance, computed in terms of liquidity X*√P + Y/√P
            // We use mulDiv to compute Y/√P + X*√P while correctly handling overflows, round down
            balanceCross =
                Math.mulDiv(uint256(tokenData1.rightSlot()), 2 ** 96, sqrtPriceX96) +
                Math.mulDiv96(tokenData0.rightSlot(), sqrtPriceX96);
            // the amount of cross-collateral balance needed for the account to be solvent, computed in terms of liquidity
            // overstimate by rounding up
            thresholdCross =
                Math.mulDivRoundingUp(uint256(tokenData1.leftSlot()), 2 ** 96, sqrtPriceX96) +
                Math.mulDiv96RoundingUp(tokenData0.leftSlot(), sqrtPriceX96);
        }
    }

    /*//////////////////////////////////////////////////////////////
                 POSITIONS HASH GENERATION & VALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Makes sure that the positions in the incoming user's list match the existing active option positions.
    /// @dev Check whether the list of positionId 1) has duplicates and 2) matches the length stored in the positionsHash.
    /// @param account The owner of the incoming list of positions.
    /// @param positionIdList The existing list of active options for the owner.
    /// @param offset Changes depending on whether this is a new mint or a liquidation (=1 if new mint, 0 if liquidation).
    function _validatePositionList(
        address account,
        TokenId[] calldata positionIdList,
        uint256 offset
    ) internal view {
        uint256 pLength;
        uint256 currentHash = s_positionsHash[account];

        unchecked {
            pLength = positionIdList.length - offset;
        }
        // note that if pLength == 0 even if a user has existing position(s) the below will fail b/c the fingerprints will mismatch
        // Check that position hash (the fingerprint of option positions) matches the one stored for the '_account'
        uint256 fingerprintIncomingList;

        for (uint256 i = 0; i < pLength; ) {
            fingerprintIncomingList = PanopticMath.updatePositionsHash(
                fingerprintIncomingList,
                positionIdList[i],
                ADD
            );
            unchecked {
                ++i;
            }
        }

        // revert if fingerprint for provided '_positionIdList' does not match the one stored for the '_account'
        if (fingerprintIncomingList != currentHash) revert Errors.InputListFail();
    }

    /// @notice Updates the hash for all positions owned by an account. This fingerprints the list of all incoming options with a single hash.
    /// @dev The outcome of this function will be to update the hash of positions.
    /// This is done as a duplicate/validation check of the incoming list O(N).
    /// @dev The positions hash is stored as the XOR of the keccak256 of each tokenId. Updating will XOR the existing hash with the new tokenId.
    /// The same update can either add a new tokenId (when minting an option), or remove an existing one (when burning it) - this happens through the XOR.
    /// @param account The owner of the options.
    /// @param tokenId The option position.
    /// @param addFlag Pass addFlag=true when this is adding a position, needed to ensure the number of positions increases or decreases.
    function _updatePositionsHash(address account, TokenId tokenId, bool addFlag) internal {
        // Get the current position hash value (fingerprint of all pre-existing positions created by '_account')
        // Add the current tokenId to the positionsHash as XOR'd
        // since 0 ^ x = x, no problem on first mint
        // Store values back into the user option details with the updated hash (leaves the other parameters unchanged)
        uint256 newHash = PanopticMath.updatePositionsHash(
            s_positionsHash[account],
            tokenId,
            addFlag
        );
        if ((newHash >> 248) > MAX_POSITIONS) revert Errors.TooManyPositionsOpen();
        s_positionsHash[account] = newHash;
    }

    /*//////////////////////////////////////////////////////////////
                                QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the address of the AMM pool connected to this Panoptic pool.
    /// @return univ3pool AMM pool corresponding to this Panoptic pool.
    function univ3pool() external view returns (IUniswapV3Pool) {
        return s_univ3pool;
    }

    /// @notice Get the collateral token corresponding to token0 of the AMM pool.
    /// @return collateralToken Collateral token corresponding to token0 in the AMM.
    function collateralToken0() external view returns (CollateralTracker collateralToken) {
        return s_collateralToken0;
    }

    /// @notice Get the collateral token corresponding to token1 of the AMM pool.
    /// @return collateralToken collateral token corresponding to token1 in the AMM.
    function collateralToken1() external view returns (CollateralTracker) {
        return s_collateralToken1;
    }

    /// @notice get the number of positions for an account
    /// @param user the account to get the positions hash of
    /// @return _numberOfPositions number of positions in the account
    function numberOfPositions(address user) public view returns (uint256 _numberOfPositions) {
        _numberOfPositions = (s_positionsHash[user] >> 248);
    }

    /// @notice Compute the TWAP price from the last 600s = 10mins.
    /// @return twapTick The TWAP price in ticks.
    function getUniV3TWAP() internal view returns (int24 twapTick) {
        twapTick = PanopticMath.twapFilter(s_univ3pool, TWAP_WINDOW);
    }

    /*//////////////////////////////////////////////////////////////
                  PREMIA & PREMIA SPREAD CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Ensure the effective liquidity in a given chunk is above a certain threshold.
    /// @param tokenId The id of the option position.
    /// @param leg The leg of the option position (used to check if long or short).
    /// @param tickLower The lower tick of the chunk.
    /// @param tickUpper The upper tick of the chunk.
    /// @param effectiveLiquidityLimitX32 Maximum amount of "spread" defined as totalLiquidity/netLiquidity for a new position
    /// denominated as X32 = (ratioLimit * 2**32). Set to 0 for no limit / only short options.
    function _checkLiquiditySpread(
        TokenId tokenId,
        uint256 leg,
        int24 tickLower,
        int24 tickUpper,
        uint64 effectiveLiquidityLimitX32
    ) internal view {
        LeftRightUnsigned accountLiquidities = SFPM.getAccountLiquidity(
            address(s_univ3pool),
            address(this),
            tokenId.tokenType(leg),
            tickLower,
            tickUpper
        );

        uint128 netLiquidity = accountLiquidities.rightSlot();
        uint128 totalLiquidity = accountLiquidities.leftSlot();
        // compute and return effective liquidity. Return if short=net=0, which is closing short position
        if (netLiquidity == 0) return;

        uint256 effectiveLiquidityFactorX32;
        unchecked {
            effectiveLiquidityFactorX32 = (uint256(totalLiquidity) * 2 ** 32) / netLiquidity;
        }

        // put a limit on how much new liquidity in one transaction can be deployed into this leg
        // the effective liquidity measures how many times more the newly added liquidity is compared to the existing/base liquidity
        if (effectiveLiquidityFactorX32 > uint256(effectiveLiquidityLimitX32))
            revert Errors.EffectiveLiquidityAboveThreshold();
    }

    /// @notice Compute the premia collected for a single option position 'tokenId'.
    /// @param tokenId The option position.
    /// @param positionSize The number of contracts (size) of the option position.
    /// @param owner The holder of the tokenId option.
    /// @param computeAllPremia Whether to compute accumulated premia for all legs held by the user (true), or just owed premia for long legs (false).
    /// @param atTick The tick at which the premia is calculated -> use (atTick < type(int24).max) to compute it
    /// up to current block. atTick = type(int24).max will only consider fees as of the last on-chain transaction.
    function _getPremia(
        TokenId tokenId,
        uint128 positionSize,
        address owner,
        bool computeAllPremia,
        int24 atTick
    )
        internal
        view
        returns (
            LeftRightSigned[4] memory premiaByLeg,
            uint256[2][4] memory premiumAccumulatorsByLeg
        )
    {
        uint256 numLegs = tokenId.countLegs();
        for (uint256 leg = 0; leg < numLegs; ) {
            uint256 isLong = tokenId.isLong(leg);
            if ((isLong == 1) || computeAllPremia) {
                LiquidityChunk liquidityChunk = PanopticMath.getLiquidityChunk(
                    tokenId,
                    leg,
                    positionSize
                );
                uint256 tokenType = tokenId.tokenType(leg);

                (premiumAccumulatorsByLeg[leg][0], premiumAccumulatorsByLeg[leg][1]) = SFPM
                    .getAccountPremium(
                        address(s_univ3pool),
                        address(this),
                        tokenType,
                        liquidityChunk.tickLower(),
                        liquidityChunk.tickUpper(),
                        atTick,
                        isLong
                    );

                unchecked {
                    LeftRightUnsigned premiumAccumulatorLast = s_options[owner][tokenId][leg];

                    // if the premium accumulatorLast is higher than current, it means the premium accumulator has overflowed and rolled over at least once
                    // we can account for one rollover by doing (acc_cur + (acc_max - acc_last))
                    // if there are multiple rollovers or the rollover goes past the last accumulator, rolled over fees will just remain unclaimed
                    premiaByLeg[leg] = LeftRightSigned
                        .wrap(0)
                        .toRightSlot(
                            int128(
                                int256(
                                    ((premiumAccumulatorsByLeg[leg][0] -
                                        premiumAccumulatorLast.rightSlot()) *
                                        (liquidityChunk.liquidity())) / 2 ** 64
                                )
                            )
                        )
                        .toLeftSlot(
                            int128(
                                int256(
                                    ((premiumAccumulatorsByLeg[leg][1] -
                                        premiumAccumulatorLast.leftSlot()) *
                                        (liquidityChunk.liquidity())) / 2 ** 64
                                )
                            )
                        );

                    if (isLong == 1) {
                        premiaByLeg[leg] = LeftRightSigned.wrap(0).sub(premiaByLeg[leg]);
                    }
                }
            }
            unchecked {
                ++leg;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        AVAILABLE PREMIUM LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Settle all unpaid premium for long legs of chunk `chunkIdentity` on `tokenIds` of `owners`.
    /// @dev Called by sellers on buyers of their chunk to increase the available premium for withdrawal (before closing their position).
    /// @dev This feature is only available when all `owners` is solvent at the current tick
    /// @param positionIdList Exhaustive list of open positions for the `owners` used for solvency checks where the tokenId to be settled is the last element.
    /// @param owner The owner of the option position to make premium payments on.
    /// @param legIndex the index of the leg in tokenId that is to be collected on (must be isLong=1).
    function settleLongPremium(
        TokenId[] calldata positionIdList,
        address owner,
        uint256 legIndex
    ) external {
        _validatePositionList(owner, positionIdList, 0);

        TokenId tokenId = positionIdList[positionIdList.length - 1];

        if (tokenId.isLong(legIndex) == 0 || legIndex > 3) revert Errors.NotALongLeg();

        (, int24 currentTick, , , , , ) = s_univ3pool.slot0();

        LeftRightUnsigned accumulatedPremium;
        {
            (int24 tickLower, int24 tickUpper) = tokenId.asTicks(legIndex);

            uint256 tokenType = tokenId.tokenType(legIndex);
            (uint128 premiumAccumulator0, uint128 premiumAccumulator1) = SFPM.getAccountPremium(
                address(s_univ3pool),
                address(this),
                tokenType,
                tickLower,
                tickUpper,
                currentTick,
                1
            );
            accumulatedPremium = LeftRightUnsigned
                .wrap(0)
                .toRightSlot(premiumAccumulator0)
                .toLeftSlot(premiumAccumulator1);

            // update the premium accumulator for the long position to the latest value
            // (the entire premia delta will be settled)
            LeftRightUnsigned premiumAccumulatorsLast = s_options[owner][tokenId][legIndex];
            s_options[owner][tokenId][legIndex] = accumulatedPremium;

            accumulatedPremium = accumulatedPremium.sub(premiumAccumulatorsLast);
        }

        uint256 liquidity = PanopticMath
            .getLiquidityChunk(tokenId, legIndex, s_positionBalance[owner][tokenId].rightSlot())
            .liquidity();

        unchecked {
            // update the realized premia
            LeftRightSigned realizedPremia = LeftRightSigned
                .wrap(0)
                .toRightSlot(int128(int256((accumulatedPremium.rightSlot() * liquidity) / 2 ** 64)))
                .toLeftSlot(int128(int256((accumulatedPremium.leftSlot() * liquidity) / 2 ** 64)));

            // deduct the paid premium tokens from the owner's balance and add them to the cumulative settled token delta
            s_collateralToken0.exercise(owner, 0, 0, 0, realizedPremia.rightSlot());
            s_collateralToken1.exercise(owner, 0, 0, 0, realizedPremia.leftSlot());

            bytes32 chunkKey = keccak256(
                abi.encodePacked(
                    tokenId.strike(legIndex),
                    tokenId.width(legIndex),
                    tokenId.tokenType(legIndex)
                )
            );
            // commit the delta in settled tokens (all of the premium paid by long chunks in the tokenIds list) to storage
            s_settledTokens[chunkKey] = s_settledTokens[chunkKey].add(
                LeftRightUnsigned.wrap(uint256(LeftRightSigned.unwrap(realizedPremia)))
            );

            emit PremiumSettled(owner, tokenId, realizedPremia);
        }

        // ensure the owner is solvent (insolvent accounts are not permitted to pay premium unless they are being liquidated)
        _validateSolvency(owner, positionIdList, NO_BUFFER);
    }

    /// @notice Adds collected tokens to settled accumulator and adjusts grossPremiumLast for any liquidity added
    /// @dev Always called after `mintTokenizedPosition`
    /// @param tokenId The option position that was minted.
    /// @param collectedByLeg The amount of tokens collected in the corresponding chunk for each leg of the position.
    /// @param positionSize The size of the position, expressed in terms of the asset.
    function _updateSettlementPostMint(
        TokenId tokenId,
        LeftRightUnsigned[4] memory collectedByLeg,
        uint128 positionSize
    ) internal {
        uint256 numLegs = tokenId.countLegs();
        for (uint256 leg = 0; leg < numLegs; ++leg) {
            bytes32 chunkKey = keccak256(
                abi.encodePacked(tokenId.strike(leg), tokenId.width(leg), tokenId.tokenType(leg))
            );
            // add any tokens collected from Uniswap in a given chunk to the settled tokens available for withdrawal by sellers
            s_settledTokens[chunkKey] = s_settledTokens[chunkKey].add(collectedByLeg[leg]);

            if (tokenId.isLong(leg) == 0) {
                LiquidityChunk liquidityChunk = PanopticMath.getLiquidityChunk(
                    tokenId,
                    leg,
                    positionSize
                );

                // new totalLiquidity (total sold) = removedLiquidity + netLiquidity (R + N)
                uint256 totalLiquidity = _getTotalLiquidity(tokenId, leg);

                // We need to adjust the grossPremiumLast value such that the result of
                // (grossPremium - adjustedGrossPremiumLast)*updatedTotalLiquidityPostMint/2**64 is equal to (grossPremium - grossPremiumLast)*totalLiquidityBeforeMint/2**64
                // G: total gross premium
                // T: totalLiquidityBeforeMint
                // R: positionLiquidity
                // C: current grossPremium value
                // L: current grossPremiumLast value
                // Ln: updated grossPremiumLast value
                // T * (C - L) = G
                // (T + R) * (C - Ln) = G
                //
                // T * (C - L) = (T + R) * (C - Ln)
                // (TC - TL) / (T + R) = C - Ln
                // Ln = C - (TC - TL)/(T + R)
                // Ln = (CT + CR - TC + TL)/(T+R)
                // Ln = (CR + TL)/(T+R)

                uint256[2] memory grossCurrent;
                (grossCurrent[0], grossCurrent[1]) = SFPM.getAccountPremium(
                    address(s_univ3pool),
                    address(this),
                    tokenId.tokenType(leg),
                    liquidityChunk.tickLower(),
                    liquidityChunk.tickUpper(),
                    type(int24).max,
                    0
                );

                unchecked {
                    // L
                    LeftRightUnsigned grossPremiumLast = s_grossPremiumLast[chunkKey];
                    // R
                    uint256 positionLiquidity = liquidityChunk.liquidity();
                    // T (totalLiquidity is (T + R) after minting)
                    uint256 totalLiquidityBefore = totalLiquidity - positionLiquidity;

                    s_grossPremiumLast[chunkKey] = LeftRightUnsigned
                        .wrap(0)
                        .toRightSlot(
                            uint128(
                                (grossCurrent[0] *
                                    positionLiquidity +
                                    grossPremiumLast.rightSlot() *
                                    totalLiquidityBefore) / (totalLiquidity)
                            )
                        )
                        .toLeftSlot(
                            uint128(
                                (grossCurrent[1] *
                                    positionLiquidity +
                                    grossPremiumLast.leftSlot() *
                                    totalLiquidityBefore) / (totalLiquidity)
                            )
                        );
                }
            }
        }
    }

    /// @notice Query the amount of premium available for withdrawal given a certain `premiumOwed` for a chunk
    /// @dev Based on the ratio between `settledTokens` and the total premium owed to sellers in a chunk
    /// @dev The ratio is capped at 1 (it can be greater than one if some seller forfeits enough premium)
    /// @param totalLiquidity The updated total liquidity amount for the chunk
    /// @param settledTokens LeftRight accumulator for the amount of tokens that have been settled (collected or paid)
    /// @param grossPremiumLast The `last` values used with `premiumAccumulators` to compute the total premium owed to sellers
    /// @param premiumOwed The amount of premium owed to sellers in the chunk
    /// @param premiumAccumulators The current values of the premium accumulators for the chunk
    /// @return availablePremium The amount of premium available for withdrawal
    function _getAvailablePremium(
        uint256 totalLiquidity,
        LeftRightUnsigned settledTokens,
        LeftRightUnsigned grossPremiumLast,
        LeftRightUnsigned premiumOwed,
        uint256[2] memory premiumAccumulators
    ) internal pure returns (LeftRightUnsigned) {
        unchecked {
            // long premium only accumulates as it is settled, so compute the ratio
            // of total settled tokens in a chunk to total premium owed to sellers and multiply
            // cap the ratio at 1 (it can be greater than one if some seller forfeits enough premium)
            uint256 accumulated0 = ((premiumAccumulators[0] - grossPremiumLast.rightSlot()) *
                totalLiquidity) / 2 ** 64;
            uint256 accumulated1 = ((premiumAccumulators[1] - grossPremiumLast.leftSlot()) *
                totalLiquidity) / 2 ** 64;

            return (
                LeftRightUnsigned
                    .wrap(0)
                    .toRightSlot(
                        uint128(
                            Math.min(
                                (uint256(premiumOwed.rightSlot()) * settledTokens.rightSlot()) /
                                    (accumulated0 == 0 ? type(uint256).max : accumulated0),
                                premiumOwed.rightSlot()
                            )
                        )
                    )
                    .toLeftSlot(
                        uint128(
                            Math.min(
                                (uint256(premiumOwed.leftSlot()) * settledTokens.leftSlot()) /
                                    (accumulated1 == 0 ? type(uint256).max : accumulated1),
                                premiumOwed.leftSlot()
                            )
                        )
                    )
            );
        }
    }

    /// @notice Query the total amount of liquidity sold in the corresponding chunk for a position leg
    /// @dev totalLiquidity (total sold) = removedLiquidity + netLiquidity (in AMM)
    /// @param tokenId The option position
    /// @param leg The leg of the option position to get `totalLiquidity for
    function _getTotalLiquidity(
        TokenId tokenId,
        uint256 leg
    ) internal view returns (uint256 totalLiquidity) {
        unchecked {
            // totalLiquidity (total sold) = removedLiquidity + netLiquidity

            (int24 tickLower, int24 tickUpper) = tokenId.asTicks(leg);
            uint256 tokenType = tokenId.tokenType(leg);
            LeftRightUnsigned accountLiquidities = SFPM.getAccountLiquidity(
                address(s_univ3pool),
                address(this),
                tokenType,
                tickLower,
                tickUpper
            );

            // removed + net
            totalLiquidity = accountLiquidities.rightSlot() + accountLiquidities.leftSlot();
        }
    }

    /// @notice Updates settled tokens and grossPremiumLast for a chunk after a burn and returns premium info
    /// @dev Always called after `burnTokenizedPosition`
    /// @param owner The owner of the option position that was burnt
    /// @param tokenId The option position that was burnt
    /// @param collectedByLeg The amount of tokens collected in the corresponding chunk for each leg of the position
    /// @param positionSize The size of the position, expressed in terms of the asset
    /// @param commitLongSettled Whether to commit the long premium that will be settled to storage
    /// @return realizedPremia The amount of premia owed to the user
    /// @return premiaByLeg The amount of premia owed to the user for each leg of the position
    function _updateSettlementPostBurn(
        address owner,
        TokenId tokenId,
        LeftRightUnsigned[4] memory collectedByLeg,
        uint128 positionSize,
        bool commitLongSettled
    ) internal returns (LeftRightSigned realizedPremia, LeftRightSigned[4] memory premiaByLeg) {
        uint256 numLegs = tokenId.countLegs();
        uint256[2][4] memory premiumAccumulatorsByLeg;

        // compute accumulated fees
        (premiaByLeg, premiumAccumulatorsByLeg) = _getPremia(
            tokenId,
            positionSize,
            owner,
            COMPUTE_ALL_PREMIA,
            type(int24).max
        );

        for (uint256 leg = 0; leg < numLegs; ) {
            LeftRightSigned legPremia = premiaByLeg[leg];

            bytes32 chunkKey = keccak256(
                abi.encodePacked(tokenId.strike(leg), tokenId.width(leg), tokenId.tokenType(leg))
            );

            // collected from Uniswap
            LeftRightUnsigned settledTokens = s_settledTokens[chunkKey].add(collectedByLeg[leg]);

            if (LeftRightSigned.unwrap(legPremia) != 0) {
                // (will be) paid by long legs
                if (tokenId.isLong(leg) == 1) {
                    if (commitLongSettled)
                        settledTokens = LeftRightUnsigned.wrap(
                            uint256(
                                LeftRightSigned.unwrap(
                                    LeftRightSigned
                                        .wrap(int256(LeftRightUnsigned.unwrap(settledTokens)))
                                        .sub(legPremia)
                                )
                            )
                        );
                    realizedPremia = realizedPremia.add(legPremia);
                } else {
                    uint256 positionLiquidity = PanopticMath
                        .getLiquidityChunk(tokenId, leg, positionSize)
                        .liquidity();

                    // new totalLiquidity (total sold) = removedLiquidity + netLiquidity (T - R)
                    uint256 totalLiquidity = _getTotalLiquidity(tokenId, leg);
                    // T (totalLiquidity is (T - R) after burning)
                    uint256 totalLiquidityBefore = totalLiquidity + positionLiquidity;

                    LeftRightUnsigned grossPremiumLast = s_grossPremiumLast[chunkKey];

                    LeftRightUnsigned availablePremium = _getAvailablePremium(
                        totalLiquidity + positionLiquidity,
                        settledTokens,
                        grossPremiumLast,
                        LeftRightUnsigned.wrap(uint256(LeftRightSigned.unwrap(legPremia))),
                        premiumAccumulatorsByLeg[leg]
                    );

                    // subtract settled tokens sent to seller
                    settledTokens = settledTokens.sub(availablePremium);

                    // add available premium to amount that should be settled
                    realizedPremia = realizedPremia.add(
                        LeftRightSigned.wrap(int256(LeftRightUnsigned.unwrap(availablePremium)))
                    );

                    // We need to adjust the grossPremiumLast value such that the result of
                    // (grossPremium - adjustedGrossPremiumLast)*updatedTotalLiquidityPostBurn/2**64 is equal to
                    // (grossPremium - grossPremiumLast)*totalLiquidityBeforeBurn/2**64 - premiumOwedToPosition
                    // G: total gross premium (- premiumOwedToPosition)
                    // T: totalLiquidityBeforeMint
                    // R: positionLiquidity
                    // C: current grossPremium value
                    // L: current grossPremiumLast value
                    // Ln: updated grossPremiumLast value
                    // T * (C - L) = G
                    // (T - R) * (C - Ln) = G - P
                    //
                    // T * (C - L) = (T - R) * (C - Ln) + P
                    // (TC - TL - P) / (T - R) = C - Ln
                    // Ln = C - (TC - TL - P) / (T - R)
                    // Ln = (TC - CR - TC + LT + P) / (T-R)
                    // Ln = (LT - CR + P) / (T-R)

                    unchecked {
                        uint256[2][4] memory _premiumAccumulatorsByLeg = premiumAccumulatorsByLeg;
                        uint256 _leg = leg;

                        // if there's still liquidity, compute the new grossPremiumLast
                        // otherwise, we just reset grossPremiumLast to the current grossPremium
                        s_grossPremiumLast[chunkKey] = totalLiquidity != 0
                            ? LeftRightUnsigned
                                .wrap(0)
                                .toRightSlot(
                                    uint128(
                                        uint256(
                                            Math.max(
                                                (int256(
                                                    grossPremiumLast.rightSlot() *
                                                        totalLiquidityBefore
                                                ) -
                                                    int256(
                                                        _premiumAccumulatorsByLeg[_leg][0] *
                                                            positionLiquidity
                                                    )) + int256(legPremia.rightSlot() * 2 ** 64),
                                                0
                                            )
                                        ) / totalLiquidity
                                    )
                                )
                                .toLeftSlot(
                                    uint128(
                                        uint256(
                                            Math.max(
                                                (int256(
                                                    grossPremiumLast.leftSlot() *
                                                        totalLiquidityBefore
                                                ) -
                                                    int256(
                                                        _premiumAccumulatorsByLeg[_leg][1] *
                                                            positionLiquidity
                                                    )) + int256(legPremia.leftSlot()) * 2 ** 64,
                                                0
                                            )
                                        ) / totalLiquidity
                                    )
                                )
                            : LeftRightUnsigned
                                .wrap(0)
                                .toRightSlot(uint128(premiumAccumulatorsByLeg[_leg][0]))
                                .toLeftSlot(uint128(premiumAccumulatorsByLeg[_leg][1]));
                    }
                }
            }

            // update settled tokens in storage with all local deltas
            s_settledTokens[chunkKey] = settledTokens;

            unchecked {
                ++leg;
            }
        }
    }
}
