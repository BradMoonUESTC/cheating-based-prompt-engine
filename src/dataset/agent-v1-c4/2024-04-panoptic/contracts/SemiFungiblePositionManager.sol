// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

// Interfaces
import {IUniswapV3Factory} from "univ3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "univ3-core/interfaces/IUniswapV3Pool.sol";
// Inherited implementations
import {ERC1155} from "@tokens/ERC1155Minimal.sol";
import {Multicall} from "@multicall/Multicall.sol";
// Libraries
import {CallbackLib} from "@libraries/CallbackLib.sol";
import {Constants} from "@libraries/Constants.sol";
import {Errors} from "@libraries/Errors.sol";
import {FeesCalc} from "@libraries/FeesCalc.sol";
import {Math} from "@libraries/Math.sol";
import {PanopticMath} from "@libraries/PanopticMath.sol";
import {SafeTransferLib} from "@libraries/SafeTransferLib.sol";
// Custom types
import {LeftRightUnsigned, LeftRightSigned, LeftRightLibrary} from "@types/LeftRight.sol";
import {LiquidityChunk} from "@types/LiquidityChunk.sol";
import {TokenId} from "@types/TokenId.sol";

//                                                                        ..........
//                       ,.                                   .,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,.                                    ,,
//                    ,,,,,,,                           ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,                            ,,,,,,
//                  .,,,,,,,,,,.                   ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,                     ,,,,,,,,,,,
//                .,,,,,,,,,,,,,,,             ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,.              ,,,,,,,,,,,,,,,
//               ,,,,,,,,,,,,,,.            ,,,,,,,,,,,,,,,,,,,,,,,,,,,                ,,,,,,,,,,,,,,,,,,,,,,,,,,.             ,,,,,,,,,,,,,,,
//             ,,,,,,,,,,,,,,,           ,,,,,,,,,,,,,,,,,,,,,,                                ,,,,,,,,,,,,,,,,,,,,,,            ,,,,,,,,,,,,,,,
//            ,,,,,,,,,,,,,.           ,,,,,,,,,,,,,,,,,,                                           .,,,,,,,,,,,,,,,,,,            ,,,,,,,,,,,,,,
//          ,,,,,,,,,,,,,,          ,,,,,,,,,,,,,,,,,.                                                  ,,,,,,,,,,,,,,,,,           .,,,,,,,,,,,,,
//         ,,,,,,,,,,,,,.         .,,,,,,,,,,,,,,,.                                                        ,,,,,,,,,,,,,,,,           ,,,,,,,,,,,,,.
//        ,,,,,,,,,,,,,          ,,,,,,,,,,,,,,,                                                              ,,,,,,,,,,,,,,,           ,,,,,,,,,,,,,
//       ,,,,,,,,,,,,,         ,,,,,,,,,,,,,,.                                                                  ,,,,,,,,,,,,,,           ,,,,,,,,,,,,,
//      ,,,,,,,,,,,,,         ,,,,,,,,,,,,,,                                                                      ,,,,,,,,,,,,,,          ,,,,,,,,,,,,,
//     ,,,,,,,,,,,,,         ,,,,,,,,,,,,,                                                                         ,,,,,,,,,,,,,,          ,,,,,,,,,,,,.
//    .,,,,,,,,,,,,        .,,,,,,,,,,,,,                                                                            ,,,,,,,,,,,,,          ,,,,,,,,,,,,
//    ,,,,,,,,,,,,         ,,,,,,,,,,,,                                                                               ,,,,,,,,,,,,,         .,,,,,,,,,,,,
//   ,,,,,,,,,,,,         ,,,,,,,,,,,,                                                                                 ,,,,,,,,,,,,.         ,,,,,,,,,,,,
//   ,,,,,,,,,,,,        ,,,,,,,,,,,,.                █████████  ███████████ ███████████  ██████   ██████               ,,,,,,,,,,,,          ,,,,,,,,,,,,
//  .,,,,,,,,,,,,        ,,,,,,,,,,,,                ███░░░░░███░░███░░░░░░█░░███░░░░░███░░██████ ██████                .,,,,,,,,,,,,         ,,,,,,,,,,,,
//  ,,,,,,,,,,,,        ,,,,,,,,,,,,                ░███    ░░░  ░███   █ ░  ░███    ░███ ░███░█████░███                 ,,,,,,,,,,,,         ,,,,,,,,,,,,.
//  ,,,,,,,,,,,,        ,,,,,,,,,,,,                ░░█████████  ░███████    ░██████████  ░███░░███ ░███                 .,,,,,,,,,,,          ,,,,,,,,,,,.
//  ,,,,,,,,,,,,        ,,,,,,,,,,,,                 ░░░░░░░░███ ░███░░░█    ░███░░░░░░   ░███ ░░░  ░███                  ,,,,,,,,,,,.         ,,,,,,,,,,,,
//  ,,,,,,,,,,,,        ,,,,,,,,,,,,                 ███    ░███ ░███  ░     ░███         ░███      ░███                  ,,,,,,,,,,,,         ,,,,,,,,,,,,
//  ,,,,,,,,,,,,        ,,,,,,,,,,,,                ░░█████████  █████       █████        █████     █████                 ,,,,,,,,,,,          ,,,,,,,,,,,,
//  ,,,,,,,,,,,,        ,,,,,,,,,,,,                 ░░░░░░░░░  ░░░░░       ░░░░░        ░░░░░     ░░░░░                 ,,,,,,,,,,,,          ,,,,,,,,,,,.
//  ,,,,,,,,,,,,        .,,,,,,,,,,,.                                                                                    ,,,,,,,,,,,,         ,,,,,,,,,,,,
//  .,,,,,,,,,,,,        ,,,,,,,,,,,,                                                                                   .,,,,,,,,,,,,         ,,,,,,,,,,,,
//   ,,,,,,,,,,,,        ,,,,,,,,,,,,,                                                                                  ,,,,,,,,,,,,          ,,,,,,,,,,,,
//   ,,,,,,,,,,,,.        ,,,,,,,,,,,,.                                                                                ,,,,,,,,,,,,.         ,,,,,,,,,,,,
//    ,,,,,,,,,,,,         ,,,,,,,,,,,,,                                                                              ,,,,,,,,,,,,,         .,,,,,,,,,,,,
//     ,,,,,,,,,,,,         ,,,,,,,,,,,,,                                                                            ,,,,,,,,,,,,,         .,,,,,,,,,,,,
//     .,,,,,,,,,,,,         ,,,,,,,,,,,,,                                                                         ,,,,,,,,,,,,,.          ,,,,,,,,,,,,
//      ,,,,,,,,,,,,,         ,,,,,,,,,,,,,,                                                                     .,,,,,,,,,,,,,.          ,,,,,,,,,,,,
//       ,,,,,,,,,,,,,         .,,,,,,,,,,,,,,                                                                 .,,,,,,,,,,,,,,          .,,,,,,,,,,,,
//        ,,,,,,,,,,,,,          ,,,,,,,,,,,,,,,                                                             ,,,,,,,,,,,,,,,.          ,,,,,,,,,,,,,.
//         ,,,,,,,,,,,,,,          ,,,,,,,,,,,,,,,,                                                       .,,,,,,,,,,,,,,,,           ,,,,,,,,,,,,,
//          .,,,,,,,,,,,,,           ,,,,,,,,,,,,,,,,,                                                 .,,,,,,,,,,,,,,,,,           ,,,,,,,,,,,,,,
//            ,,,,,,,,,,,,,,           ,,,,,,,,,,,,,,,,,,,.                                        ,,,,,,,,,,,,,,,,,,,.            ,,,,,,,,,,,,,,
//             ,,,,,,,,,,,,,,,            ,,,,,,,,,,,,,,,,,,,,,,                             .,,,,,,,,,,,,,,,,,,,,,,             ,,,,,,,,,,,,,,
//               ,,,,,,,,,,,,,,,            .,,,,,,,,,,,,,,,,,,,,,,,,,,,,,.        ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,             .,,,,,,,,,,,,,,.
//                 ,,,,,,,,,,,,,,.              ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,               ,,,,,,,,,,,,,,,
//                   ,,,,,,,,,,                     ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,                     .,,,,,,,,,,
//                     ,,,,,.                            ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,                             ,,,,,,
//                       ,                                     ..,,,,,,,,,,,,,,,,,,,,,,,,,,,,.

/// @author Axicon Labs Limited
/// @title Semi-Fungible Position Manager (ERC1155) - a gas-efficient Uniswap V3 position manager.
/// @notice Wraps Uniswap V3 positions with up to 4 legs behind an ERC1155 token.
/// @dev Replaces the NonfungiblePositionManager.sol (ERC721) from Uniswap Labs
contract SemiFungiblePositionManager is ERC1155, Multicall {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a UniswapV3Pool is initialized.
    /// @param uniswapPool Address of the underlying Uniswap v3 pool
    /// @param poolId The SFPM's pool identifier for the pool, including the 16-bit tick spacing and 48-bit pool pattern
    event PoolInitialized(address indexed uniswapPool, uint64 poolId);

    /// @notice Emitted when a position is destroyed/burned
    /// @dev Recipient is used to track whether it was burned directly by the user or through an option contract
    /// @param recipient The address of the user who burned the position
    /// @param tokenId The tokenId of the burned position
    /// @param positionSize The number of contracts burnt, expressed in terms of the asset
    event TokenizedPositionBurnt(
        address indexed recipient,
        TokenId indexed tokenId,
        uint128 positionSize
    );

    /// @notice Emitted when a position is created/minted
    /// @dev Recipient is used to track whether it was minted directly by the user or through an option contract
    /// @param caller the caller who created the position. In 99% of cases `caller` == `recipient`.
    /// @param tokenId The tokenId of the minted position
    /// @param positionSize The number of contracts minted, expressed in terms of the asset
    event TokenizedPositionMinted(
        address indexed caller,
        TokenId indexed tokenId,
        uint128 positionSize
    );

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    // Used for safecasting
    using Math for uint256;
    using Math for int256;

    // Packs the pool address and reentrancy lock into a single slot
    // `locked` can be initialized to false because the pool address makes the slot nonzero
    // false = unlocked, true = locked
    struct PoolAddressAndLock {
        IUniswapV3Pool pool;
        bool locked;
    }

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLES 
    //////////////////////////////////////////////////////////////*/

    /// @dev flag for mint/burn
    bool internal constant MINT = false;
    bool internal constant BURN = true;

    // ν = 1/2**VEGOID = multiplicative factor for long premium (Eqns 1-5)
    // Similar to vega in options because the liquidity utilization is somewhat reflective of the implied volatility (IV),
    // and vegoid modifies the sensitivity of the streamia to changes in that utilization,
    // much like vega measures the sensitivity of traditional option prices to IV.
    // The effect of vegoid on the long premium multiplier can be explored here: https://www.desmos.com/calculator/mdeqob2m04
    uint128 private constant VEGOID = 2;

    /// @dev Uniswap V3 Factory address. Initialized in the constructor.
    /// @dev used to verify callbacks and to query for the pool address
    IUniswapV3Factory internal immutable FACTORY;

    /*//////////////////////////////////////////////////////////////
                            STORAGE 
    //////////////////////////////////////////////////////////////*/

    /// Store the mapping between the poolId and the Uniswap v3 pool - intent is to be 1:1 for all pools
    /// @dev pool address => pool id + 2 ** 255 (initialization bit for `poolId == 0`, set if the pool exists)
    mapping(address univ3pool => uint256 poolIdData) internal s_AddrToPoolIdData;

    /// @dev also contains a boolean which is used for the reentrancy lock - saves gas since this slot is often warmed
    // pool ids are used instead of addresses to save bits in the token id
    // (there will never be a collision because it's infeasible to mine an address with 8 consecutive bytes)
    mapping(uint64 poolId => PoolAddressAndLock contextData) internal s_poolContext;

    /** 
        We're tracking the amount of net and removed liquidity for the specific region:

             net amount    
           received minted  
          ▲ for isLong=0     amount           
          │                 moved out      actual amount 
          │  ┌────┐-T      due isLong=1   in the UniswapV3Pool 
          │  │    │          mints      
          │  │    │                        ┌────┐-(T-R)  
          │  │    │         ┌────┐-R       │    │          
          │  │    │         │    │         │    │     
          └──┴────┴─────────┴────┴─────────┴────┴──────►                     
             total=T       removed=R      net=(T-R)


     *       removed liquidity r          net liquidity N=(T-R)
     * |<------- 128 bits ------->|<------- 128 bits ------->|
     * |<---------------------- 256 bits ------------------->|
     */
    ///
    /// @dev mapping that stores the liquidity data of keccak256(abi.encodePacked(address poolAddress, address owner, int24 tickLower, int24 tickUpper))
    // liquidityData is a LeftRight. The right slot represents the liquidity currently sold (added) in the AMM owned by the user
    // the left slot represents the amount of liquidity currently bought (removed) that has been removed from the AMM - the user owes it to a seller
    // the reason why it is called "removedLiquidity" is because long options are created by removed liquidity -ie. short selling LP positions
    mapping(bytes32 positionKey => LeftRightUnsigned removedAndNetLiquidity)
        internal s_accountLiquidity;

    /**
        Any liquidity that has been deposited in the AMM using the SFPM will collect fees over 
        time, we call this the gross premia. If that liquidity has been removed, we also need to
        keep track of the amount of fees that *would have been collected*, we call this the owed
        premia. The gross and owed premia are tracked per unit of liquidity by the 
        s_accountPremiumGross and s_accountPremiumOwed accumulators.
        
        Here is how we can use the accumulators to compute the Gross, Net, and Owed fees collected
        by any position.

        Let`s say Charlie the smart contract deposited T into the AMM and later removed R from that
        same tick using a tokenId with a isLong=1 parameter. Because the netLiquidity is only (T-R),
        the AMM will collect fees equal to:

              net_feesCollectedX128 = feeGrowthX128 * (T - R)
                                    = feeGrowthX128 * N                                     
        
        where N = netLiquidity = T-R. Had that liquidity never been removed, we want the gross
        premia to be given by:

              gross_feesCollectedX128 = feeGrowthX128 * T

        So we must keep track of fees for the removed liquidity R so that the long premia exactly
        compensates for the fees that would have been collected from the initial liquidity.

        In addition to tracking, we also want to track those fees plus a small spread. Specifically,
        we want:

              gross_feesCollectedX128 = net_feesCollectedX128 + owed_feesCollectedX128

       where 

              owed_feesCollectedX128 = feeGrowthX128 * R * (1 + spread)                      (Eqn 1)

        A very opinionated definition for the spread is: 
              
              spread = ν*(liquidity removed from that strike)/(netLiquidity remaining at that strike)
                     = ν*R/N

        For an arbitrary parameter 0 <= ν <= 1 (ν = 1/2^VEGOID). This way, the gross_feesCollectedX128 will be given by: 

              gross_feesCollectedX128 = feeGrowthX128 * N + feeGrowthX128*R*(1 + ν*R/N) 
                                      = feeGrowthX128 * T + feesGrowthX128*ν*R^2/N         
                                      = feeGrowthX128 * T * (1 + ν*R^2/(N*T))                (Eqn 2)
        
        The s_accountPremiumOwed accumulator tracks the feeGrowthX128 * R * (1 + spread) term
        per unit of removed liquidity R every time the position touched:

              s_accountPremiumOwed += feeGrowthX128 * R * (1 + ν*R/N) / R
                                   += feeGrowthX128 * (T - R + ν*R)/N
                                   += feeGrowthX128 * T/N * (1 - R/T + ν*R/T)
         
        Note that the value of feeGrowthX128 can be extracted from the amount of fees collected by
        the smart contract since the amount of feesCollected is related to feeGrowthX128 according
        to:

             feesCollected = feesGrowthX128 * (T-R)

        So that we get:
             
             feesGrowthX128 = feesCollected/N

        And the accumulator is computed from the amount of collected fees according to:
             
             s_accountPremiumOwed += feesCollected * T/N^2 * (1 - R/T + ν*R/T)          (Eqn 3)     

        So, the amount of owed premia for a position of size r minted at time t1 and burnt at 
        time t2 is:

             owedPremia(t1, t2) = (s_accountPremiumOwed_t2-s_accountPremiumOwed_t1) * r
                                = ∆feesGrowthX128 * r * T/N * (1 - R/T + ν*R/T)
                                = ∆feesGrowthX128 * r * (T - R + ν*R)/N
                                = ∆feesGrowthX128 * r * (N + ν*R)/N
                                = ∆feesGrowthX128 * r * (1 + ν*R/N)             (same as Eqn 1)

        This way, the amount of premia owed for a position will match Eqn 1 exactly.

        Similarly, the amount of gross fees for the total liquidity is tracked in a similar manner
        by the s_accountPremiumGross accumulator. 

        However, since we require that Eqn 2 holds up-- ie. the gross fees collected should be equal
        to the net fees collected plus the ower fees plus the small spread, the expression for the
        s_accountPremiumGross accumulator has to be given by (you`ll see why in a minute): 

            s_accountPremiumGross += feesCollected * T/N^2 * (1 - R/T + ν*R^2/T^2)       (Eqn 4) 

        This expression can be used to calculate the fees collected by a position of size t between times
        t1 and t2 according to:
             
            grossPremia(t1, t2) = ∆(s_accountPremiumGross) * t
                                = ∆feeGrowthX128 * t * T/N * (1 - R/T + ν*R^2/T^2) 
                                = ∆feeGrowthX128 * t * (T - R + ν*R^2/T) / N 
                                = ∆feeGrowthX128 * t * (N + ν*R^2/T) / N
                                = ∆feeGrowthX128 * t * (1  + ν*R^2/(N*T))   (same as Eqn 2)
            
        where the last expression matches Eqn 2 exactly.

        In summary, the s_accountPremium accumulators allow smart contracts that need to handle 
        long+short liquidity to guarantee that liquidity deposited always receives the correct
        premia, whether that liquidity has been removed from the AMM or not.

        Note that the expression for the spread is extremely opinionated, and may not fit the
        specific risk management profile of every smart contract. And simply setting the ν parameter
        to zero would get rid of the "spread logic".
    */

    // tracking account premia for the added liquidity (isLong=0 legs) and removed liquidity (isLong=1 legs) separately
    mapping(bytes32 positionKey => LeftRightUnsigned accountPremium) private s_accountPremiumOwed;

    mapping(bytes32 positionKey => LeftRightUnsigned accountPremium) private s_accountPremiumGross;

    /// @dev mapping that stores a LeftRight packing of feesBase of  keccak256(abi.encodePacked(address poolAddress, address owner, int24 tickLower, int24 tickUpper))
    /// @dev Base fees is stored as int128((feeGrowthInside0LastX128 * liquidity) / 2**128), which allows us to store the accumulated fees as int128 instead of uint256
    /// @dev Right slot: int128 token0 base fees, Left slot: int128 token1 base fees.
    /// feesBase represents the baseline fees collected by the position last time it was updated - this is recalculated every time the position is collected from with the new value
    mapping(bytes32 positionKey => LeftRightSigned baseFees0And1) internal s_accountFeesBase;

    /*//////////////////////////////////////////////////////////////
                           REENTRANCY LOCK
    //////////////////////////////////////////////////////////////*/

    /// @notice Modifier that prohibits reentrant calls for a specific pool
    /// @dev We piggyback the reentrancy lock on the (pool id => pool) mapping to save gas
    /// @dev (there's an extra 96 bits of storage available in the mapping slot and it's almost always warm)
    /// @param poolId The poolId of the pool to activate the reentrancy lock on
    modifier ReentrancyLock(uint64 poolId) {
        // check if the pool is already locked
        // init lock if not
        beginReentrancyLock(poolId);

        // execute function
        _;

        // remove lock
        endReentrancyLock(poolId);
    }

    /// @notice Add reentrancy lock on pool
    /// @dev reverts if the pool is already locked
    /// @param poolId The poolId of the pool to add the reentrancy lock to
    function beginReentrancyLock(uint64 poolId) internal {
        // check if the pool is already locked, if so, revert
        if (s_poolContext[poolId].locked) revert Errors.ReentrantCall();

        // activate lock
        s_poolContext[poolId].locked = true;
    }

    /// @notice Remove reentrancy lock on pool
    /// @param poolId The poolId of the pool to remove the reentrancy lock from
    function endReentrancyLock(uint64 poolId) internal {
        // gas refund is triggered here by returning the slot to its original value
        s_poolContext[poolId].locked = false;
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Construct the Semi-Fungible Position Manager (SFPM)
    /// @param _factory the Uniswap v3 Factory used to retrieve registered Uniswap pools
    constructor(IUniswapV3Factory _factory) {
        FACTORY = _factory;
    }

    /// @notice Initialize a Uniswap v3 pool in the SemifungiblePositionManager contract
    /// @dev Revert if already initialized.
    /// @param token0 The contract address of token0 of the pool
    /// @param token1 The contract address of token1 of the pool
    /// @param fee The fee level of the of the underlying Uniswap v3 pool, denominated in hundredths of bips
    function initializeAMMPool(address token0, address token1, uint24 fee) external {
        // compute the address of the Uniswap v3 pool for the given token0, token1, and fee tier
        address univ3pool = FACTORY.getPool(token0, token1, fee);

        // reverts if the Uni v3 pool has not been initialized
        if (univ3pool == address(0)) revert Errors.UniswapPoolNotInitialized();

        // return if the pool has already been initialized in SFPM
        // @dev pools can be initialized from a Panoptic pool or by calling initializeAMMPool directly, reverting
        // would prevent any PanopticPool from being deployed
        // @dev some pools may not be deployable if the poolId has a collision (since we take only 8 bytes)
        // if poolId == 0, we have a bit on the left set if it was initialized, so this will still return properly
        if (s_AddrToPoolIdData[univ3pool] != 0) return;

        // The base poolId is composed as follows:
        // [tickSpacing][pool pattern]
        // [16 bit tickSpacing][most significant 48 bits of the pool address]
        uint64 poolId = PanopticMath.getPoolId(univ3pool);

        // There are 281,474,976,710,655 possible pool patterns.
        // A modern GPU can generate a collision such a space relatively quickly,
        // so if a collision is detected increment the pool pattern until a unique poolId is found
        while (address(s_poolContext[poolId].pool) != address(0)) {
            poolId = PanopticMath.incrementPoolPattern(poolId);
        }

        // store the poolId => UniswapV3Pool information in a mapping
        // `locked` being initialized to false is gas-efficient because the pool address makes the slot nonzero
        // note: we preserve the state of `locked` to prevent reentering a pool by initializing it during the reentrant call
        s_poolContext[poolId] = PoolAddressAndLock({
            pool: IUniswapV3Pool(univ3pool),
            locked: s_poolContext[poolId].locked
        });

        // store the UniswapV3Pool => poolId information in a mapping
        // add a bit on the end to indicate that the pool is initialized
        // (this is for the case that poolId == 0, so we can make a distinction between zero and uninitialized)
        unchecked {
            s_AddrToPoolIdData[univ3pool] = uint256(poolId) + 2 ** 255;
        }
        emit PoolInitialized(univ3pool, poolId);
    }

    /*//////////////////////////////////////////////////////////////
                           CALLBACK HANDLERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Called after minting liquidity to a position
    /// @dev Pays the pool tokens owed for the minted liquidity from the payer (always the caller)
    /// @param amount0Owed The amount of token0 due to the pool for the minted liquidity
    /// @param amount1Owed The amount of token1 due to the pool for the minted liquidity
    /// @param data Contains the payer address and the pool features required to validate the callback
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        // Decode the mint callback data
        CallbackLib.CallbackData memory decoded = abi.decode(data, (CallbackLib.CallbackData));
        // Validate caller to ensure we got called from the AMM pool
        CallbackLib.validateCallback(msg.sender, FACTORY, decoded.poolFeatures);
        // Sends the amount0Owed and amount1Owed quantities provided
        if (amount0Owed > 0)
            SafeTransferLib.safeTransferFrom(
                decoded.poolFeatures.token0,
                decoded.payer,
                msg.sender,
                amount0Owed
            );
        if (amount1Owed > 0)
            SafeTransferLib.safeTransferFrom(
                decoded.poolFeatures.token1,
                decoded.payer,
                msg.sender,
                amount1Owed
            );
    }

    /// @notice Called by the pool after executing a swap during an ITM option mint/burn.
    /// @dev Pays the pool tokens owed for the swap from the payer (always the caller)
    /// @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token0 to the pool.
    /// @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token1 to the pool.
    /// @param data Contains the payer address and the pool features required to validate the callback
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        // Decode the swap callback data, checks that the UniswapV3Pool has the correct address.
        CallbackLib.CallbackData memory decoded = abi.decode(data, (CallbackLib.CallbackData));
        // Validate caller to ensure we got called from the AMM pool
        CallbackLib.validateCallback(msg.sender, FACTORY, decoded.poolFeatures);

        // Extract the address of the token to be sent (amount0 -> token0, amount1 -> token1)
        address token = amount0Delta > 0
            ? address(decoded.poolFeatures.token0)
            : address(decoded.poolFeatures.token1);

        // Transform the amount to pay to uint256 (take positive one from amount0 and amount1)
        // the pool will always pass one delta with a positive sign and one with a negative sign or zero,
        // so this logic always picks the correct delta to pay
        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);

        // Pay the required token from the payer to the caller of this contract
        SafeTransferLib.safeTransferFrom(token, decoded.payer, msg.sender, amountToPay);
    }

    /*//////////////////////////////////////////////////////////////
                       PUBLIC MINT/BURN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Burn a new position containing up to 4 legs wrapped in a ERC1155 token.
    /// @dev Auto-collect all accumulated fees.
    /// @param tokenId The tokenId of the minted position, which encodes information about up to 4 legs
    /// @param positionSize The number of contracts minted, expressed in terms of the asset
    /// @param slippageTickLimitLow The lower price slippage limit when minting an ITM position (set to larger than slippageTickLimitHigh for swapping when minting)
    /// @param slippageTickLimitHigh The higher slippage limit when minting an ITM position (set to lower than slippageTickLimitLow for swapping when minting)
    /// @return collectedByLeg An array of LeftRight encoded words containing the amount of token0 and token1 collected as fees for each leg
    /// @return totalSwapped A LeftRight encoded word containing the total amount of token0 and token1 swapped if minting ITM
    function burnTokenizedPosition(
        TokenId tokenId,
        uint128 positionSize,
        int24 slippageTickLimitLow,
        int24 slippageTickLimitHigh
    )
        external
        ReentrancyLock(tokenId.poolId())
        returns (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped)
    {
        // burn this ERC1155 token id
        _burn(msg.sender, TokenId.unwrap(tokenId), positionSize);

        // emit event
        emit TokenizedPositionBurnt(msg.sender, tokenId, positionSize);

        // Call a function that contains other functions to mint/burn position, collect amounts, swap if necessary
        (collectedByLeg, totalSwapped) = _validateAndForwardToAMM(
            tokenId,
            positionSize,
            slippageTickLimitLow,
            slippageTickLimitHigh,
            BURN
        );
    }

    /// @notice Create a new position `tokenId` containing up to 4 legs.
    /// @param tokenId The tokenId of the minted position, which encodes information for up to 4 legs
    /// @param positionSize The number of contracts minted, expressed in terms of the asset
    /// @param slippageTickLimitLow The lower price slippage limit when minting an ITM position (set to larger than slippageTickLimitHigh for swapping when minting)
    /// @param slippageTickLimitHigh The higher slippage limit when minting an ITM position (set to lower than slippageTickLimitLow for swapping when minting)
    /// @return collectedByLeg An array of LeftRight encoded words containing the amount of token0 and token1 collected as fees for each leg
    /// @return totalSwapped A LeftRight encoded word containing the total amount of token0 and token1 swapped if minting ITM
    function mintTokenizedPosition(
        TokenId tokenId,
        uint128 positionSize,
        int24 slippageTickLimitLow,
        int24 slippageTickLimitHigh
    )
        external
        ReentrancyLock(tokenId.poolId())
        returns (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped)
    {
        // create the option position via its ID in this erc1155
        _mint(msg.sender, TokenId.unwrap(tokenId), positionSize);

        emit TokenizedPositionMinted(msg.sender, tokenId, positionSize);

        // validate the incoming option position, then forward to the AMM for minting/burning required liquidity chunks
        (collectedByLeg, totalSwapped) = _validateAndForwardToAMM(
            tokenId,
            positionSize,
            slippageTickLimitLow,
            slippageTickLimitHigh,
            MINT
        );
    }

    /*//////////////////////////////////////////////////////////////
                     TRANSFER HOOK IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfer a single token from one user to another
    /// @dev supports token approvals
    /// @param from the user to transfer tokens from
    /// @param to the user to transfer tokens to
    /// @param id the ERC1155 token id to transfer
    /// @param amount the amount of tokens to transfer
    /// @param data optional data to include in the receive hook
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) public override {
        // we don't need to reentrancy lock on transfers, but we can't allow transfers for a pool during mint/burn with a reentrant call
        // so just check if there is an active reentrancy lock for the relevant pool on the token we're transferring
        if (s_poolContext[TokenId.wrap(id).poolId()].locked) revert Errors.ReentrantCall();

        // update the position data
        registerTokenTransfer(from, to, TokenId.wrap(id), amount);

        // transfer the token (note that all state updates are completed before reentrancy is possible through onReceived callbacks)
        super.safeTransferFrom(from, to, id, amount, data);
    }

    /// @notice Transfer multiple tokens from one user to another
    /// @dev supports token approvals
    /// @dev ids and amounts must be of equal length
    /// @param from the user to transfer tokens from
    /// @param to the user to transfer tokens to
    /// @param ids the ERC1155 token ids to transfer
    /// @param amounts the amounts of tokens to transfer
    /// @param data optional data to include in the receive hook
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) public override {
        // we don't need to reentrancy lock on transfers, but we can't allow transfers for a pool during mint/burn with a reentrant call
        // so just check if there is an active reentrancy lock for the relevant pool on each token
        for (uint256 i = 0; i < ids.length; ) {
            if (s_poolContext[TokenId.wrap(ids[i]).poolId()].locked) revert Errors.ReentrantCall();
            registerTokenTransfer(from, to, TokenId.wrap(ids[i]), amounts[i]);
            unchecked {
                ++i;
            }
        }

        // transfer the token (note that all state updates are completed before reentrancy is possible)
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    /// @notice update user position data following a token transfer
    /// @dev token transfers are only allowed if you transfer your entire liquidity of a given chunk and the recipient has none
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param id The tokenId being transferred'
    /// @param amount The amount of the token being transferred
    function registerTokenTransfer(address from, address to, TokenId id, uint256 amount) internal {
        // Validate tokenId
        id.validate();

        // Extract univ3pool from the poolId map to Uniswap Pool
        IUniswapV3Pool univ3pool = s_poolContext[id.poolId()].pool;

        uint256 numLegs = id.countLegs();
        for (uint256 leg = 0; leg < numLegs; ) {
            // for this leg index: extract the liquidity chunk: a 256bit word containing the liquidity amount and upper/lower tick
            // @dev see `contracts/types/LiquidityChunk.sol`
            LiquidityChunk liquidityChunk = PanopticMath.getLiquidityChunk(
                id,
                leg,
                uint128(amount)
            );

            //construct the positionKey for the from and to addresses
            bytes32 positionKey_from = keccak256(
                abi.encodePacked(
                    address(univ3pool),
                    from,
                    id.tokenType(leg),
                    liquidityChunk.tickLower(),
                    liquidityChunk.tickUpper()
                )
            );
            bytes32 positionKey_to = keccak256(
                abi.encodePacked(
                    address(univ3pool),
                    to,
                    id.tokenType(leg),
                    liquidityChunk.tickLower(),
                    liquidityChunk.tickUpper()
                )
            );

            // Revert if recipient already has that position
            if (
                (LeftRightUnsigned.unwrap(s_accountLiquidity[positionKey_to]) != 0) ||
                (LeftRightSigned.unwrap(s_accountFeesBase[positionKey_to]) != 0)
            ) revert Errors.TransferFailed();

            // Revert if sender has long positions in that chunk or the entire liquidity is not being transferred
            LeftRightUnsigned fromLiq = s_accountLiquidity[positionKey_from];
            if (LeftRightUnsigned.unwrap(fromLiq) != liquidityChunk.liquidity())
                revert Errors.TransferFailed();

            LeftRightSigned fromBase = s_accountFeesBase[positionKey_from];

            //update+store liquidity and fee values between accounts
            s_accountLiquidity[positionKey_to] = fromLiq;
            s_accountLiquidity[positionKey_from] = LeftRightUnsigned.wrap(0);

            s_accountFeesBase[positionKey_to] = fromBase;
            s_accountFeesBase[positionKey_from] = LeftRightSigned.wrap(0);
            unchecked {
                ++leg;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
              AMM INTERACTION AND POSITION UPDATE HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Helper that checks the proposed option position and size and forwards the minting and potential swapping tasks.
    /// @notice This helper function checks:
    /// @notice  - that the `tokenId` is valid
    /// @notice  - confirms that the Uniswap pool exists
    /// @notice  - retrieves Uniswap pool info
    /// @notice and then forwards the minting/burning/swapping to another internal helper functions which perform the AMM pool actions.
    ///   ┌───────────────────────┐
    ///   │mintTokenizedPosition()├───┐
    ///   └───────────────────────┘   │
    ///                               │
    ///   ┌───────────────────────┐   │   ┌───────────────────────────────┐
    ///   │burnTokenizedPosition()├───────► _validateAndForwardToAMM(...) ├─ (...) --> (mint/burn in AMM)
    ///   └───────────────────────┘       └───────────────────────────────┘

    /// @param tokenId the option position
    /// @param positionSize the size of the position to create
    /// @param tickLimitLow lower limits on potential slippage
    /// @param tickLimitHigh upper limits on potential slippage
    /// @param isBurn is equal to false for mints and true for burns
    /// @return collectedByLeg An array of LeftRight encoded words containing the amount of token0 and token1 collected as fees for each leg
    /// @return totalMoved the total amount of funds swapped in Uniswap as part of building potential ITM positions
    function _validateAndForwardToAMM(
        TokenId tokenId,
        uint128 positionSize,
        int24 tickLimitLow,
        int24 tickLimitHigh,
        bool isBurn
    ) internal returns (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalMoved) {
        // Reverts if positionSize is 0 and user did not own the position before minting/burning
        if (positionSize == 0) revert Errors.OptionsBalanceZero();

        /// @dev the flipToBurnToken() function flips the isLong bits
        if (isBurn) {
            tokenId = tokenId.flipToBurnToken();
        }

        // Validate tokenId
        tokenId.validate();

        // Extract univ3pool from the poolId map to Uniswap Pool
        IUniswapV3Pool univ3pool = s_poolContext[tokenId.poolId()].pool;

        // Revert if the pool not been previously initialized
        if (univ3pool == IUniswapV3Pool(address(0))) revert Errors.UniswapPoolNotInitialized();

        // initialize some variables returned by the _createPositionInAMM function
        LeftRightSigned itmAmounts;

        // calls a function that loops through each leg of tokenId and mints/burns liquidity in Uni v3 pool
        (totalMoved, collectedByLeg, itmAmounts) = _createPositionInAMM(
            univ3pool,
            tokenId,
            positionSize,
            isBurn
        );

        if (tickLimitLow > tickLimitHigh) {
            // if the in-the-money amount is not zero (i.e. positions were minted ITM) and the user did provide tick limits LOW > HIGH, then swap necessary amounts
            if ((LeftRightSigned.unwrap(itmAmounts) != 0)) {
                totalMoved = swapInAMM(univ3pool, itmAmounts).add(totalMoved);
            }

            (tickLimitLow, tickLimitHigh) = (tickLimitHigh, tickLimitLow);
        }

        // Get the current tick of the Uniswap pool, check slippage
        (, int24 currentTick, , , , , ) = univ3pool.slot0();

        if ((currentTick >= tickLimitHigh) || (currentTick <= tickLimitLow))
            revert Errors.PriceBoundFail();
    }

    /// @notice When a position is minted or burnt in-the-money (ITM) we are *not* 100% token0 or 100% token1: we have a mix of both tokens.
    /// @notice The swapping for ITM options is needed because only one of the tokens are "borrowed" by a user to create the position.
    /// @notice This is an ITM situation below (price within the range of the chunk):
    ///
    ///        AMM       strike
    ///     liquidity   price tick
    ///        ▲           │
    ///        │       ┌───▼───┐
    ///        │       │       │liquidity chunk
    ///        │ ┌─────┴─▲─────┴─────┐
    ///        │ │       │           │
    ///        │ │       :           │
    ///        │ │       :           │
    ///        │ │       :           │
    ///        └─┴───────▲───────────┴─► price
    ///                  │
    ///             current price
    ///             in-the-money: mix of tokens 0 and 1 within the chunk
    ///
    ///   If we take token0 as an example, we deploy it to the AMM pool and *then* swap to get the right mix of token0 and token1
    ///   to be correctly in the money at that strike.
    ///   It that position is burnt, then we remove a mix of the two tokens and swap one of them so that the user receives only one.
    /// @param univ3pool the uniswap pool in which to swap.
    /// @param itmAmounts how much to swap - how much is ITM
    /// @return totalSwapped the amount swapped in the AMM
    function swapInAMM(
        IUniswapV3Pool univ3pool,
        LeftRightSigned itmAmounts
    ) internal returns (LeftRightSigned totalSwapped) {
        // Initialize variables
        bool zeroForOne; // The direction of the swap, true for token0 to token1, false for token1 to token0
        int256 swapAmount; // The amount of token0 or token1 to swap
        bytes memory data;

        IUniswapV3Pool _univ3pool = univ3pool;

        unchecked {
            // unpack the in-the-money amounts
            int128 itm0 = itmAmounts.rightSlot();
            int128 itm1 = itmAmounts.leftSlot();

            // construct the swap callback struct
            data = abi.encode(
                CallbackLib.CallbackData({
                    poolFeatures: CallbackLib.PoolFeatures({
                        token0: _univ3pool.token0(),
                        token1: _univ3pool.token1(),
                        fee: _univ3pool.fee()
                    }),
                    payer: msg.sender
                })
            );

            // note: upstream users of this function such as the Panoptic Pool should ensure users always compensate for the ITM amount delta
            // the netting swap is not perfectly accurate, and it is possible for swaps to run out of liquidity, so we do not want to rely on it
            // this is simply a convenience feature, and should be treated as such
            if ((itm0 != 0) && (itm1 != 0)) {
                (uint160 sqrtPriceX96, , , , , , ) = _univ3pool.slot0();

                // implement a single "netting" swap. Thank you @danrobinson for this puzzle/idea
                // note: negative ITM amounts denote a surplus of tokens (burning liquidity), while positive amounts denote a shortage of tokens (minting liquidity)
                // compute the approximate delta of token0 that should be resolved in the swap at the current tick
                // we do this by flipping the signs on the token1 ITM amount converting+deducting it against the token0 ITM amount
                // couple examples (price = 2 1/0):
                //  - 100 surplus 0, 100 surplus 1 (itm0 = -100, itm1 = -100)
                //    normal swap 0: 100 0 => 200 1
                //    normal swap 1: 100 1 => 50 0
                //    final swap amounts: 50 0 => 100 1
                //    netting swap: net0 = -100 - (-100/2) = -50, ZF1 = true, 50 0 => 100 1
                // - 100 surplus 0, 100 shortage 1 (itm0 = -100, itm1 = 100)
                //    normal swap 0: 100 0 => 200 1
                //    normal swap 1: 50 0 => 100 1
                //    final swap amounts: 150 0 => 300 1
                //    netting swap: net0 = -100 - (100/2) = -150, ZF1 = true, 150 0 => 300 1
                // - 100 shortage 0, 100 surplus 1 (itm0 = 100, itm1 = -100)
                //    normal swap 0: 200 1 => 100 0
                //    normal swap 1: 100 1 => 50 0
                //    final swap amounts: 300 1 => 150 0
                //    netting swap: net0 = 100 - (-100/2) = 150, ZF1 = false, 300 1 => 150 0
                // - 100 shortage 0, 100 shortage 1 (itm0 = 100, itm1 = 100)
                //    normal swap 0: 200 1 => 100 0
                //    normal swap 1: 50 0 => 100 1
                //    final swap amounts: 100 1 => 50 0
                //    netting swap: net0 = 100 - (100/2) = 50, ZF1 = false, 100 1 => 50 0
                // - = Net surplus of token0
                // + = Net shortage of token0
                int256 net0 = itm0 - PanopticMath.convert1to0(itm1, sqrtPriceX96);

                zeroForOne = net0 < 0;

                //compute the swap amount, set as positive (exact input)
                swapAmount = -net0;
            } else if (itm0 != 0) {
                zeroForOne = itm0 < 0;
                swapAmount = -itm0;
            } else {
                zeroForOne = itm1 > 0;
                swapAmount = -itm1;
            }

            // note - can occur if itm0 and itm1 have the same value
            // in that case, swapping would be pointless so skip
            if (swapAmount == 0) return LeftRightSigned.wrap(0);

            // swap tokens in the Uniswap pool
            // @dev note this triggers our swap callback function
            (int256 swap0, int256 swap1) = _univ3pool.swap(
                msg.sender,
                zeroForOne,
                swapAmount,
                zeroForOne
                    ? Constants.MIN_V3POOL_SQRT_RATIO + 1
                    : Constants.MAX_V3POOL_SQRT_RATIO - 1,
                data
            );

            // Add amounts swapped to totalSwapped variable
            totalSwapped = LeftRightSigned.wrap(0).toRightSlot(swap0.toInt128()).toLeftSlot(
                swap1.toInt128()
            );
        }
    }

    /// @notice Create the position in the AMM given in the tokenId.
    /// @dev Loops over each leg in the tokenId and calls _createLegInAMM for each, which does the mint/burn in the AMM.
    /// @param univ3pool the Uniswap pool.
    /// @param tokenId the option position
    /// @param positionSize the size of the option position
    /// @param isBurn is true if the position is burnt
    /// @return totalMoved the total amount of liquidity moved from the msg.sender to Uniswap
    /// @return collectedByLeg An array of LeftRight encoded words containing the amount of token0 and token1 collected as fees for each leg
    /// @return itmAmounts the amount of tokens swapped due to legs being in-the-money
    function _createPositionInAMM(
        IUniswapV3Pool univ3pool,
        TokenId tokenId,
        uint128 positionSize,
        bool isBurn
    )
        internal
        returns (
            LeftRightSigned totalMoved,
            LeftRightUnsigned[4] memory collectedByLeg,
            LeftRightSigned itmAmounts
        )
    {
        // upper bound on amount of tokens contained across all legs of the position at any given tick
        uint256 amount0;
        uint256 amount1;

        uint256 numLegs = tokenId.countLegs();
        // loop through up to the 4 potential legs in the tokenId
        for (uint256 leg = 0; leg < numLegs; ) {
            LeftRightSigned _moved;
            LeftRightSigned _itmAmounts;
            LeftRightUnsigned _collectedSingleLeg;

            {
                // cache the univ3pool, tokenId, isBurn, and _positionSize variables to get rid of stack too deep error
                IUniswapV3Pool _univ3pool = univ3pool;
                TokenId _tokenId = tokenId;
                bool _isBurn = isBurn;
                uint128 _positionSize = positionSize;
                uint256 _leg;

                unchecked {
                    // Reverse the order of the legs if this call is burning a position (LIFO)
                    // We loop in reverse order if burning a position so that any dependent long liquidity is returned to the pool first,
                    // allowing the corresponding short liquidity to be removed
                    _leg = _isBurn ? numLegs - leg - 1 : leg;
                }

                // for this _leg index: extract the liquidity chunk: a 256bit word containing the liquidity amount and upper/lower tick
                // @dev see `contracts/types/LiquidityChunk.sol`
                LiquidityChunk liquidityChunk = PanopticMath.getLiquidityChunk(
                    _tokenId,
                    _leg,
                    _positionSize
                );

                (_moved, _itmAmounts, _collectedSingleLeg) = _createLegInAMM(
                    _univ3pool,
                    _tokenId,
                    _leg,
                    liquidityChunk,
                    _isBurn
                );

                collectedByLeg[_leg] = _collectedSingleLeg;

                unchecked {
                    // increment accumulators of the upper bound on tokens contained across all legs of the position at any given tick
                    amount0 += Math.getAmount0ForLiquidity(liquidityChunk);

                    amount1 += Math.getAmount1ForLiquidity(liquidityChunk);
                }
            }

            totalMoved = totalMoved.add(_moved);
            itmAmounts = itmAmounts.add(_itmAmounts);

            unchecked {
                ++leg;
            }
        }

        // Ensure upper bound on amount of tokens contained across all legs of the position on any given tick does not exceed a maximum of (2**127-1).
        // This is the maximum value of the `int128` type we frequently use to hold token amounts, so a given position's size should be guaranteed to
        // fit within that limit at all times.
        if (amount0 > uint128(type(int128).max) || amount1 > uint128(type(int128).max))
            revert Errors.PositionTooLarge();
    }

    /// @notice Create the position in the AMM for a specific leg in the tokenId.
    /// @dev For the leg specified by the _leg input:
    /// @dev  - mints any new liquidity in the AMM needed (via _mintLiquidity)
    /// @dev  - burns any new liquidity in the AMM needed (via _burnLiquidity)
    /// @dev  - tracks all amounts minted and burned
    /// @dev to burn a position, the opposing position is "created" through this function
    /// but we need to pass in a flag to indicate that so the removedLiquidity is updated.
    /// @param univ3pool the Uniswap pool.
    /// @param tokenId the option position
    /// @param leg the leg index that needs to be modified
    /// @param liquidityChunk has lower tick, upper tick, and liquidity amount to mint
    /// @param isBurn is true if the position is burnt
    /// @return moved the total amount of liquidity moved from the msg.sender to Uniswap
    /// @return itmAmounts the amount of tokens swapped due to legs being in-the-money
    /// @return collectedSingleLeg LeftRight encoded words containing the amount of token0 and token1 collected as fees
    function _createLegInAMM(
        IUniswapV3Pool univ3pool,
        TokenId tokenId,
        uint256 leg,
        LiquidityChunk liquidityChunk,
        bool isBurn
    )
        internal
        returns (
            LeftRightSigned moved,
            LeftRightSigned itmAmounts,
            LeftRightUnsigned collectedSingleLeg
        )
    {
        uint256 tokenType = tokenId.tokenType(leg);
        // unique key to identify the liquidity chunk in this uniswap pool
        bytes32 positionKey = keccak256(
            abi.encodePacked(
                address(univ3pool),
                msg.sender,
                tokenType,
                liquidityChunk.tickLower(),
                liquidityChunk.tickUpper()
            )
        );

        // update our internal bookkeeping of how much liquidity we have deployed in the AMM
        // for example: if this _leg is short, we add liquidity to the amm, make sure to add that to our tracking
        uint128 updatedLiquidity;
        uint256 isLong = tokenId.isLong(leg);
        LeftRightUnsigned currentLiquidity = s_accountLiquidity[positionKey]; //cache
        {
            // did we have liquidity already deployed in Uniswap for this chunk range from some past mint?

            // s_accountLiquidity is a LeftRight. The right slot represents the liquidity currently sold (added) in the AMM owned by the user
            // the left slot represents the amount of liquidity currently bought (removed) that has been removed from the AMM - the user owes it to a seller
            // the reason why it is called "removedLiquidity" is because long options are created by removing -ie.short selling LP positions
            uint128 startingLiquidity = currentLiquidity.rightSlot();
            uint128 removedLiquidity = currentLiquidity.leftSlot();
            uint128 chunkLiquidity = liquidityChunk.liquidity();

            if (isLong == 0) {
                // selling/short: so move from msg.sender *to* uniswap
                // we're minting more liquidity in uniswap: so add the incoming liquidity chunk to the existing liquidity chunk
                updatedLiquidity = startingLiquidity + chunkLiquidity;

                /// @dev If the isLong flag is 0=short but the position was burnt, then this is closing a long position
                /// @dev so the amount of removed liquidity should decrease.
                if (isBurn) {
                    removedLiquidity -= chunkLiquidity;
                }
            } else {
                // the _leg is long (buying: moving *from* uniswap to msg.sender)
                // so we seek to move the incoming liquidity chunk *out* of uniswap - but was there sufficient liquidity sitting in uniswap
                // in the first place?
                if (startingLiquidity < chunkLiquidity) {
                    // the amount we want to move (liquidityChunk.legLiquidity()) out of uniswap is greater than
                    // what the account that owns the liquidity in uniswap has (startingLiquidity)
                    // we must ensure that an account can only move its own liquidity out of uniswap
                    // so we revert in this case
                    revert Errors.NotEnoughLiquidity();
                } else {
                    // startingLiquidity is >= chunkLiquidity, so no possible underflow
                    unchecked {
                        // we want to move less than what already sits in uniswap, no problem:
                        updatedLiquidity = startingLiquidity - chunkLiquidity;
                    }
                }

                /// @dev If the isLong flag is 1=long and the position is minted, then this is opening a long position
                /// @dev so the amount of removed liquidity should increase.
                if (!isBurn) {
                    // we can't remove more liquidity than we add in the first place, so this can't overflow
                    unchecked {
                        removedLiquidity += chunkLiquidity;
                    }
                }
            }

            // update the starting liquidity for this position for next time around
            s_accountLiquidity[positionKey] = LeftRightUnsigned
                .wrap(0)
                .toLeftSlot(removedLiquidity)
                .toRightSlot(updatedLiquidity);
        }

        // track how much liquidity we need to collect from uniswap
        // add the fees that accumulated in uniswap within the liquidityChunk:
        {
            /** if the position is NOT long (selling a put or a call), then _mintLiquidity to move liquidity
                from the msg.sender to the uniswap v3 pool:
                Selling(isLong=0): Mint chunk of liquidity in Uniswap (defined by upper tick, lower tick, and amount)
                       ┌─────────────────────────────────┐
                ▲     ┌▼┐ liquidityChunk                 │
                │  ┌──┴─┴──┐                         ┌───┴──┐
                │  │       │                         │      │
                └──┴───────┴──►                      └──────┘
                   Uniswap v3                      msg.sender
            
             else: the position is long (buying a put or a call), then _burnLiquidity to remove liquidity from univ3
                Buying(isLong=1): Burn in Uniswap
                       ┌─────────────────┐
                ▲     ┌┼┐                │
                │  ┌──┴─┴──┐         ┌───▼──┐
                │  │       │         │      │
                └──┴───────┴──►      └──────┘
                    Uniswap v3      msg.sender 
            */
            moved = isLong == 0
                ? _mintLiquidity(liquidityChunk, univ3pool)
                : _burnLiquidity(liquidityChunk, univ3pool); // from msg.sender to Uniswap
            // add the moved liquidity chunk to amount we need to collect from uniswap:

            // Is this _leg ITM?
            // if tokenType is 1, and we transacted some token0: then this leg is ITM!
            if (tokenType == 1) {
                // extract amount moved out of UniswapV3 pool
                itmAmounts = itmAmounts.toRightSlot(moved.rightSlot());
            }
            // if tokenType is 0, and we transacted some token1: then this leg is ITM
            if (tokenType == 0) {
                // Add this in-the-money amount transacted.
                itmAmounts = itmAmounts.toLeftSlot(moved.leftSlot());
            }
        }

        // if there was liquidity at that tick before the transaction, collect any accumulated fees
        if (currentLiquidity.rightSlot() > 0) {
            collectedSingleLeg = _collectAndWritePositionData(
                liquidityChunk,
                univ3pool,
                currentLiquidity,
                positionKey,
                moved,
                isLong
            );
        }

        // position has been touched, update s_accountFeesBase with the latest values from the pool.positions
        // round up the stored feesbase to minimize Δfeesbase when we next calculate it
        s_accountFeesBase[positionKey] = _getFeesBase(
            univ3pool,
            updatedLiquidity,
            liquidityChunk,
            true
        );
    }

    /// @notice caches/stores the accumulated premia values for the specified postion.
    /// @param positionKey the hashed data which represents the underlying position in the Uniswap pool
    /// @param currentLiquidity the total amount of liquidity in the AMM for the specific position
    /// @param collectedAmounts amount of tokens (token0 and token1) collected from Uniswap
    function _updateStoredPremia(
        bytes32 positionKey,
        LeftRightUnsigned currentLiquidity,
        LeftRightUnsigned collectedAmounts
    ) private {
        (
            LeftRightUnsigned deltaPremiumOwed,
            LeftRightUnsigned deltaPremiumGross
        ) = _getPremiaDeltas(currentLiquidity, collectedAmounts);

        // add deltas to accumulators and freeze both accumulators (for a token) if one of them overflows
        // (i.e if only token0 (right slot) of the owed premium overflows, then stop accumulating  both token0 owed premium and token0 gross premium for the chunk)
        // this prevents situations where the owed premium gets out of sync with the gross premium due to one of them overflowing
        (s_accountPremiumOwed[positionKey], s_accountPremiumGross[positionKey]) = LeftRightLibrary
            .addCapped(
                s_accountPremiumOwed[positionKey],
                deltaPremiumOwed,
                s_accountPremiumGross[positionKey],
                deltaPremiumGross
            );
    }

    /// @notice Compute the feesGrowth * liquidity / 2**128 by reading feeGrowthInside0LastX128 and feeGrowthInside1LastX128 from univ3pool.positions.
    /// @param univ3pool the Uniswap pool.
    /// @param liquidity the total amount of liquidity in the AMM for the specific position
    /// @param liquidityChunk has lower tick, upper tick, and liquidity amount to mint
    /// @param roundUp if true, round up the feesBase, otherwise round down
    /// @dev stored fees base is rounded up and the current fees base is rounded down to minimize the amount of fees collected (Δfeesbase) in favor of the protocol
    function _getFeesBase(
        IUniswapV3Pool univ3pool,
        uint128 liquidity,
        LiquidityChunk liquidityChunk,
        bool roundUp
    ) private view returns (LeftRightSigned feesBase) {
        // now collect fee growth within the liquidity chunk in `liquidityChunk`
        // this is the fee accumulated in Uniswap for this chunk of liquidity

        // read the latest feeGrowth directly from the Uniswap pool
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = univ3pool
            .positions(
                keccak256(
                    abi.encodePacked(
                        address(this),
                        liquidityChunk.tickLower(),
                        liquidityChunk.tickUpper()
                    )
                )
            );

        // (feegrowth * liquidity) / 2 ** 128
        /// @dev here we're converting the value to an int128 even though all values (feeGrowth, liquidity, Q128) are strictly positive.
        /// That's because of the way feeGrowthInside works in Uniswap v3, where it can underflow when stored for the first time.
        /// This is not a problem in Uniswap v3 because the fees are always calculated by taking the difference of the feeGrowths,
        /// so that the net different is always positive.
        /// So by using int128 instead of uint128, we remove the need to handle extremely large underflows and simply allow it to be negative
        feesBase = roundUp
            ? LeftRightSigned
                .wrap(0)
                .toRightSlot(
                    int128(int256(Math.mulDiv128RoundingUp(feeGrowthInside0LastX128, liquidity)))
                )
                .toLeftSlot(
                    int128(int256(Math.mulDiv128RoundingUp(feeGrowthInside1LastX128, liquidity)))
                )
            : LeftRightSigned
                .wrap(0)
                .toRightSlot(int128(int256(Math.mulDiv128(feeGrowthInside0LastX128, liquidity))))
                .toLeftSlot(int128(int256(Math.mulDiv128(feeGrowthInside1LastX128, liquidity))));
    }

    /// @notice Mint a chunk of liquidity (`liquidityChunk`) in the Uniswap v3 pool; return the amount moved.
    /// @dev note that "moved" means: mint in Uniswap and move tokens from msg.sender.
    /// @param liquidityChunk the chunk of liquidity to mint given by tick upper, tick lower, and its size
    /// @param univ3pool the Uniswap v3 pool to mint liquidity in/to
    /// @return movedAmounts how many tokens were moved from msg.sender to Uniswap
    function _mintLiquidity(
        LiquidityChunk liquidityChunk,
        IUniswapV3Pool univ3pool
    ) internal returns (LeftRightSigned movedAmounts) {
        // build callback data
        bytes memory mintdata = abi.encode(
            CallbackLib.CallbackData({ // compute by reading values from univ3pool every time
                    poolFeatures: CallbackLib.PoolFeatures({
                        token0: univ3pool.token0(),
                        token1: univ3pool.token1(),
                        fee: univ3pool.fee()
                    }),
                    payer: msg.sender
                })
        );

        /// mint the required amount in the Uniswap pool
        /// @dev this triggers the uniswap mint callback function
        (uint256 amount0, uint256 amount1) = univ3pool.mint(
            address(this),
            liquidityChunk.tickLower(),
            liquidityChunk.tickUpper(),
            liquidityChunk.liquidity(),
            mintdata
        );

        // amount0 The amount of token0 that was paid to mint the given amount of liquidity
        // amount1 The amount of token1 that was paid to mint the given amount of liquidity
        // no need to safecast to int from uint here as the max position size is int128
        movedAmounts = LeftRightSigned.wrap(0).toRightSlot(int128(int256(amount0))).toLeftSlot(
            int128(int256(amount1))
        );
    }

    /// @notice Burn a chunk of liquidity (`liquidityChunk`) in the Uniswap v3 pool and send to msg.sender; return the amount moved.
    /// @dev note that "moved" means: burn position in Uniswap and send tokens to msg.sender.
    /// @param liquidityChunk the chunk of liquidity to burn given by tick upper, tick lower, and its size
    /// @param univ3pool the Uniswap v3 pool to burn liquidity in/from
    /// @return movedAmounts how many tokens were moved from Uniswap to msg.sender
    function _burnLiquidity(
        LiquidityChunk liquidityChunk,
        IUniswapV3Pool univ3pool
    ) internal returns (LeftRightSigned movedAmounts) {
        // burn that option's liquidity in the Uniswap Pool.
        // This will send the underlying tokens back to the Panoptic Pool (msg.sender)
        (uint256 amount0, uint256 amount1) = univ3pool.burn(
            liquidityChunk.tickLower(),
            liquidityChunk.tickUpper(),
            liquidityChunk.liquidity()
        );

        // amount0 The amount of token0 that was sent back to the Panoptic Pool
        // amount1 The amount of token1 that was sent back to the Panoptic Pool
        // no need to safecast to int from uint here as the max position size is int128
        // decrement the amountsOut with burnt amounts. amountsOut = notional value of tokens moved
        unchecked {
            movedAmounts = LeftRightSigned.wrap(0).toRightSlot(-int128(int256(amount0))).toLeftSlot(
                -int128(int256(amount1))
            );
        }
    }

    /// @notice Helper to collect amounts between msg.sender and Uniswap and also to update the Uniswap fees collected to date from the AMM.
    /// @param liquidityChunk the liquidity chunk representing the option position/leg
    /// @param univ3pool the Uniswap pool where the position is deployed
    /// @param currentLiquidity the existing liquidity msg.sender owns in the AMM for this chunk before the SFPM was called
    /// @param positionKey the unique key to identify the liquidity chunk/tokenType pairing in this uniswap pool
    /// @param movedInLeg how much liquidity has been moved between msg.sender and Uniswap before this function call
    /// @param isLong whether the leg in question is long (=1) or short (=0)
    /// @return collectedChunk the incoming amount collected with potentially whatever is collected in this function added to it
    function _collectAndWritePositionData(
        LiquidityChunk liquidityChunk,
        IUniswapV3Pool univ3pool,
        LeftRightUnsigned currentLiquidity,
        bytes32 positionKey,
        LeftRightSigned movedInLeg,
        uint256 isLong
    ) internal returns (LeftRightUnsigned collectedChunk) {
        uint128 startingLiquidity = currentLiquidity.rightSlot();
        // round down current fees base to minimize Δfeesbase
        // If the current feesBase is close or identical to the stored one, the amountToCollect can be negative.
        // This is because the stored feesBase is rounded up, and the current feesBase is rounded down.
        // When this is the case, we want to behave as if there are 0 fees, so we just rectify the values.
        LeftRightSigned amountToCollect = _getFeesBase(
            univ3pool,
            startingLiquidity,
            liquidityChunk,
            false
        ).subRect(s_accountFeesBase[positionKey]);

        if (isLong == 1) {
            amountToCollect = amountToCollect.sub(movedInLeg);
        }

        if (LeftRightSigned.unwrap(amountToCollect) != 0) {
            // first collect amounts from Uniswap corresponding to this position
            // Collect only if there was existing startingLiquidity=liquidities.rightSlot() at that position: collect all fees

            // Collects tokens owed to a liquidity chunk
            (uint128 receivedAmount0, uint128 receivedAmount1) = univ3pool.collect(
                msg.sender,
                liquidityChunk.tickLower(),
                liquidityChunk.tickUpper(),
                uint128(amountToCollect.rightSlot()),
                uint128(amountToCollect.leftSlot())
            );

            // moved will be negative if the leg was long (funds left the caller, don't count it in collected fees)
            uint128 collected0;
            uint128 collected1;
            unchecked {
                collected0 = movedInLeg.rightSlot() < 0
                    ? receivedAmount0 - uint128(-movedInLeg.rightSlot())
                    : receivedAmount0;
                collected1 = movedInLeg.leftSlot() < 0
                    ? receivedAmount1 - uint128(-movedInLeg.leftSlot())
                    : receivedAmount1;
            }

            // CollectedOut is the amount of fees accumulated+collected (received - burnt)
            // That's because receivedAmount contains the burnt tokens and whatever amount of fees collected
            collectedChunk = LeftRightUnsigned.wrap(0).toRightSlot(collected0).toLeftSlot(
                collected1
            );

            // record the collected amounts in the s_accountPremiumOwed and s_accountPremiumGross accumulators
            _updateStoredPremia(positionKey, currentLiquidity, collectedChunk);
        }
    }

    /// @notice Function that updates the Owed and Gross account liquidities.
    /// @dev Returned accumulators are capped at the max value (2**128 - 1) for each token if they overflow.
    /// @param currentLiquidity netLiquidity (right) and removedLiquidity (left) at the start of the transaction
    /// @param collectedAmounts total amount of tokens (token0 and token1) collected from Uniswap.
    /// @return deltaPremiumOwed The extra premium (per liquidity X64) to be added to the owed accumulator for token0 (right) and token1 (left)
    /// @return deltaPremiumGross The extra premium (per liquidity X64) to be added to the gross accumulator for token0 (right) and token1 (left)
    function _getPremiaDeltas(
        LeftRightUnsigned currentLiquidity,
        LeftRightUnsigned collectedAmounts
    )
        private
        pure
        returns (LeftRightUnsigned deltaPremiumOwed, LeftRightUnsigned deltaPremiumGross)
    {
        // extract liquidity values
        uint256 removedLiquidity = currentLiquidity.leftSlot();
        uint256 netLiquidity = currentLiquidity.rightSlot();

        // premia spread equations are graphed and documented here: https://www.desmos.com/calculator/mdeqob2m04
        // explains how we get from the premium per liquidity (calculated here) to the total premia collected and the multiplier
        // as well as how the value of VEGOID affects the premia
        // note that the "base" premium is just a common factor shared between the owed (long) and gross (short)
        // premia, and is only seperated to simplify the calculation
        // (the graphed equations include this factor without separating it)
        unchecked {
            uint256 totalLiquidity = netLiquidity + removedLiquidity;

            uint256 premium0X64_base;
            uint256 premium1X64_base;

            {
                uint128 collected0 = collectedAmounts.rightSlot();
                uint128 collected1 = collectedAmounts.leftSlot();

                // compute the base premium as collected * total / net^2 (from Eqn 3)
                premium0X64_base = Math.mulDiv(
                    collected0,
                    totalLiquidity * 2 ** 64,
                    netLiquidity ** 2
                );
                premium1X64_base = Math.mulDiv(
                    collected1,
                    totalLiquidity * 2 ** 64,
                    netLiquidity ** 2
                );
            }

            {
                uint128 premium0X64_owed;
                uint128 premium1X64_owed;
                {
                    // compute the owed premium (from Eqn 3)
                    uint256 numerator = netLiquidity + (removedLiquidity / 2 ** VEGOID);

                    premium0X64_owed = Math
                        .mulDiv(premium0X64_base, numerator, totalLiquidity)
                        .toUint128Capped();
                    premium1X64_owed = Math
                        .mulDiv(premium1X64_base, numerator, totalLiquidity)
                        .toUint128Capped();

                    deltaPremiumOwed = LeftRightUnsigned
                        .wrap(0)
                        .toRightSlot(premium0X64_owed)
                        .toLeftSlot(premium1X64_owed);
                }
            }

            {
                uint128 premium0X64_gross;
                uint128 premium1X64_gross;
                {
                    // compute the gross premium (from Eqn 4)
                    uint256 numerator = totalLiquidity ** 2 -
                        totalLiquidity *
                        removedLiquidity +
                        ((removedLiquidity ** 2) / 2 ** (VEGOID));

                    premium0X64_gross = Math
                        .mulDiv(premium0X64_base, numerator, totalLiquidity ** 2)
                        .toUint128Capped();
                    premium1X64_gross = Math
                        .mulDiv(premium1X64_base, numerator, totalLiquidity ** 2)
                        .toUint128Capped();

                    deltaPremiumGross = LeftRightUnsigned
                        .wrap(0)
                        .toRightSlot(premium0X64_gross)
                        .toLeftSlot(premium1X64_gross);
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            SFPM PROPERTIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Return the liquidity associated with a given position.
    /// @dev Computes accountLiquidity[keccak256(abi.encodePacked(univ3pool, owner, tokenType, tickLower, tickUpper))]
    /// @param univ3pool The address of the Uniswap v3 Pool
    /// @param owner The address of the account that is queried
    /// @param tokenType The tokenType of the position (the token it started as)
    /// @param tickLower The lower end of the tick range for the position (int24)
    /// @param tickUpper The upper end of the tick range for the position (int24)
    /// @return accountLiquidities The amount of liquidity that has been shorted/added to the Uniswap contract (netLiquidity:removedLiquidity -> rightSlot:leftSlot)
    function getAccountLiquidity(
        address univ3pool,
        address owner,
        uint256 tokenType,
        int24 tickLower,
        int24 tickUpper
    ) external view returns (LeftRightUnsigned accountLiquidities) {
        /// Extract the account liquidity for a given uniswap pool, owner, token type, and ticks
        /// @dev tokenType input here is the asset of the positions minted, this avoids put liquidity to be used for call, and vice-versa
        accountLiquidities = s_accountLiquidity[
            keccak256(abi.encodePacked(univ3pool, owner, tokenType, tickLower, tickUpper))
        ];
    }

    /// @notice Return the premium associated with a given position, where Premium is an accumulator of feeGrowth for the touched position.
    /// @dev Computes s_accountPremium{isLong ? Owed : Gross}[keccak256(abi.encodePacked(univ3pool, owner, tokenType, tickLower, tickUpper))]
    /// @dev if an atTick parameter is provided that is different from type(int24).max, then it will update the premium up to the current
    /// @dev block at the provided atTick value. We do this because this may be called immediately after the Uni v3 pool has been touched
    /// @dev so no need to read the feeGrowths from the Uni v3 pool.
    /// @param univ3pool The address of the Uniswap v3 Pool
    /// @param owner The address of the account that is queried
    /// @param tokenType The tokenType of the position (the token it started as)
    /// @param tickLower The lower end of the tick range for the position (int24)
    /// @param tickUpper The upper end of the tick range for the position (int24)
    /// @param atTick The current tick. Set atTick < type(int24).max = 8388608 to get latest premium up to the current block
    /// @param isLong whether the position is long (=1) or short (=0)
    /// @return premiumToken0 The amount of premium (per liquidity X64) for token0 = sum (feeGrowthLast0X128) over every block where the position has been touched
    /// @return premiumToken1 The amount of premium (per liquidity X64) for token1 = sum (feeGrowthLast0X128) over every block where the position has been touched
    function getAccountPremium(
        address univ3pool,
        address owner,
        uint256 tokenType,
        int24 tickLower,
        int24 tickUpper,
        int24 atTick,
        uint256 isLong
    ) external view returns (uint128, uint128) {
        bytes32 positionKey = keccak256(
            abi.encodePacked(univ3pool, owner, tokenType, tickLower, tickUpper)
        );

        LeftRightUnsigned acctPremia;

        // Compute the premium up to the current block (ie. after last touch until now). Do not proceed if atTick == type(int24).max = 8388608
        if (atTick < type(int24).max) {
            // unique key to identify the liquidity chunk in this uniswap pool
            LeftRightUnsigned accountLiquidities = s_accountLiquidity[positionKey];
            uint128 netLiquidity = accountLiquidities.rightSlot();
            if (netLiquidity != 0) {
                LeftRightUnsigned amountToCollect;
                {
                    IUniswapV3Pool _univ3pool = IUniswapV3Pool(univ3pool);
                    int24 _tickLower = tickLower;
                    int24 _tickUpper = tickUpper;

                    // how much fees have been accumulated within the liquidity chunk since last time we updated this chunk?
                    // Compute (currentFeesGrowth - oldFeesGrowth), the amount to collect
                    // currentFeesGrowth (calculated from FeesCalc.calculateAMMSwapFeesLiquidityChunk) is (ammFeesCollectedPerLiquidity * liquidityChunk.liquidity())
                    // oldFeesGrowth is the last stored update of fee growth within the position range in the past (feeGrowthRange*liquidityChunk.liquidity()) (s_accountFeesBase[positionKey])
                    LeftRightSigned feesBase = FeesCalc.calculateAMMSwapFees(
                        _univ3pool,
                        atTick,
                        _tickLower,
                        _tickUpper,
                        netLiquidity
                    );

                    // If the current feesBase is close or identical to the stored one, the amountToCollect can be negative.
                    // This is because the stored feesBase is rounded up, and the current feesBase is rounded down.
                    // When this is the case, we want to behave as if there are 0 fees, so we just rectify the values.
                    // Guaranteed to be positive, so swap to unsigned type
                    amountToCollect = LeftRightUnsigned.wrap(
                        uint256(
                            LeftRightSigned.unwrap(feesBase.subRect(s_accountFeesBase[positionKey]))
                        )
                    );
                }

                (LeftRightUnsigned premiumOwed, LeftRightUnsigned premiumGross) = _getPremiaDeltas(
                    accountLiquidities,
                    amountToCollect
                );

                // add deltas to accumulators and freeze both accumulators (for a token) if one of them overflows
                // (i.e if only token0 (right slot) of the owed premium overflows, then stop accumulating  both token0 owed premium and token0 gross premium for the chunk)
                // this prevents situations where the owed premium gets out of sync with the gross premium due to one of them overflowing
                (premiumOwed, premiumGross) = LeftRightLibrary.addCapped(
                    s_accountPremiumOwed[positionKey],
                    premiumOwed,
                    s_accountPremiumGross[positionKey],
                    premiumGross
                );

                acctPremia = isLong == 1 ? premiumOwed : premiumGross;
            }
        } else {
            // Extract the account liquidity for a given uniswap pool, owner, token type, and ticks
            acctPremia = isLong == 1
                ? s_accountPremiumOwed[positionKey]
                : s_accountPremiumGross[positionKey];
        }
        return (acctPremia.rightSlot(), acctPremia.leftSlot());
    }

    /// @notice Return the feesBase associated with a given position.
    /// @dev Computes accountFeesBase[keccak256(abi.encodePacked(univ3pool, owner, tickLower, tickUpper))]
    /// @dev feesBase0 is computed as Math.mulDiv128(feeGrowthInside0X128, legLiquidity)
    /// @param univ3pool The address of the Uniswap v3 Pool
    /// @param owner The address of the account that is queried
    /// @param tokenType The tokenType of the position (the token it started as)
    /// @param tickLower The lower end of the tick range for the position (int24)
    /// @param tickUpper The upper end of the tick range for the position (int24)
    /// @return feesBase0 The feesBase of the position for token0
    /// @return feesBase1 The feesBase of the position for token1
    function getAccountFeesBase(
        address univ3pool,
        address owner,
        uint256 tokenType,
        int24 tickLower,
        int24 tickUpper
    ) external view returns (int128 feesBase0, int128 feesBase1) {
        // Get accumulated fees for token0 (rightSlot) and token1 (leftSlot)
        LeftRightSigned feesBase = s_accountFeesBase[
            keccak256(abi.encodePacked(univ3pool, owner, tokenType, tickLower, tickUpper))
        ];
        feesBase0 = feesBase.rightSlot();
        feesBase1 = feesBase.leftSlot();
    }

    /// @notice Returns the Uniswap v3 pool for a given poolId.
    /// @dev poolId is typically the first 8 bytes of the uni v3 pool address
    /// @dev But poolId can be different for first 8 bytes if there is a collision between Uni v3 pool addresses
    /// @param poolId The poolId for a Uni v3 pool
    /// @return UniswapV3Pool The unique poolId for that Uni v3 pool
    function getUniswapV3PoolFromId(
        uint64 poolId
    ) external view returns (IUniswapV3Pool UniswapV3Pool) {
        return s_poolContext[poolId].pool;
    }

    /// @notice Returns the poolId for a given Uniswap v3 pool.
    /// @dev poolId is typically the first 8 bytes of the uni v3 pool address
    /// @dev But poolId can be different for first 8 bytes if there is a collision between Uni v3 pool addresses
    /// @param univ3pool The address of the Uniswap v3 Pool
    /// @return poolId The unique poolId for that Uni v3 pool
    function getPoolId(address univ3pool) external view returns (uint64 poolId) {
        poolId = uint64(s_AddrToPoolIdData[univ3pool]);
    }
}
