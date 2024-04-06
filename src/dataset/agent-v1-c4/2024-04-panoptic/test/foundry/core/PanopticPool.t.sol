// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Errors} from "@libraries/Errors.sol";
import {Math} from "@libraries/Math.sol";
import {PanopticMath} from "@libraries/PanopticMath.sol";
import {FeesCalc} from "@libraries/FeesCalc.sol";
import {TokenId} from "@types/TokenId.sol";
import {LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";
import {LiquidityChunk, LiquidityChunkLibrary} from "@types/LiquidityChunk.sol";
import {IDonorNFT} from "@tokens/interfaces/IDonorNFT.sol";
import {DonorNFT} from "@periphery/DonorNFT.sol";
import {IERC20Partial} from "@tokens/interfaces/IERC20Partial.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {SqrtPriceMath} from "v3-core/libraries/SqrtPriceMath.sol";
import {PositionKey} from "v3-periphery/libraries/PositionKey.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {SemiFungiblePositionManager} from "@contracts/SemiFungiblePositionManager.sol";
import {PanopticPool} from "@contracts/PanopticPool.sol";
import {CollateralTracker} from "@contracts/CollateralTracker.sol";
import {PanopticFactory} from "@contracts/PanopticFactory.sol";
import {PanopticHelper} from "@periphery/PanopticHelper.sol";
import {PositionUtils} from "../testUtils/PositionUtils.sol";
import {UniPoolPriceMock} from "../testUtils/PriceMocks.sol";
import {Constants} from "@libraries/Constants.sol";

contract SemiFungiblePositionManagerHarness is SemiFungiblePositionManager {
    constructor(IUniswapV3Factory _factory) SemiFungiblePositionManager(_factory) {}

    function poolContext(uint64 poolId) public view returns (PoolAddressAndLock memory) {
        return s_poolContext[poolId];
    }

    function addrToPoolId(address pool) public view returns (uint256) {
        return s_AddrToPoolIdData[pool];
    }
}

contract PanopticPoolHarness is PanopticPool {
    /// @notice get the positions hash of an account
    /// @param user the account to get the positions hash of
    /// @return _positionsHash positions hash of the account
    function positionsHash(address user) external view returns (uint248 _positionsHash) {
        _positionsHash = uint248(s_positionsHash[user]);
    }

    function miniMedian() external view returns (uint256) {
        return s_miniMedian;
    }

    /**
     * @notice compute the TWAP price from the last 600s = 10mins
     * @return twapTick the TWAP price in ticks
     */
    function getUniV3TWAP_() external view returns (int24 twapTick) {
        twapTick = PanopticMath.twapFilter(s_univ3pool, TWAP_WINDOW);
    }

    function settledTokens(bytes32 chunk) external view returns (LeftRightUnsigned) {
        return s_settledTokens[chunk];
    }

    function calculateAccumulatedPremia(
        address user,
        bool computeAllPremia,
        bool includePendingPremium,
        TokenId[] calldata positionIdList
    ) external view returns (int128 premium0, int128 premium1, uint256[2][] memory) {
        // Get the current tick of the Uniswap pool
        (, int24 currentTick, , , , , ) = s_univ3pool.slot0();

        // Compute the accumulated premia for all tokenId in positionIdList (includes short+long premium)
        (LeftRightSigned premia, uint256[2][] memory balances) = _calculateAccumulatedPremia(
            user,
            positionIdList,
            computeAllPremia,
            includePendingPremium,
            currentTick
        );

        // Return the premia as (token0, token1)
        return (premia.rightSlot(), premia.leftSlot(), balances);
    }

    // return premiaByLeg
    function burnAllOptionsFrom(
        TokenId[] calldata positionIdList,
        int24 tickLimitLow,
        int24 tickLimitHigh
    ) external returns (LeftRightSigned[4][] memory, LeftRightSigned) {
        (
            LeftRightSigned netExchanged,
            LeftRightSigned[4][] memory premiasByLeg
        ) = _burnAllOptionsFrom(
                msg.sender,
                tickLimitLow,
                tickLimitHigh,
                COMMIT_LONG_SETTLED,
                positionIdList
            );

        return (premiasByLeg, netExchanged);
    }

    constructor(SemiFungiblePositionManager _sfpm) PanopticPool(_sfpm) {}
}

contract PanopticPoolTest is PositionUtils {
    /*//////////////////////////////////////////////////////////////
                           MAINNET CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // the instance of SFPM we are testing
    SemiFungiblePositionManagerHarness sfpm;

    // reference implemenatations used by the factory
    address poolReference;

    address collateralReference;

    // Mainnet factory address - SFPM is dependent on this for several checks and callbacks
    IUniswapV3Factory V3FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    // Mainnet router address - used for swaps to test fees/premia
    ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // used as example of price parity
    IUniswapV3Pool constant USDC_USDT_5 =
        IUniswapV3Pool(0x7858E59e0C01EA06Df3aF3D20aC7B0003275D4Bf);

    // store a few different mainnet pairs - the pool used is part of the fuzz
    IUniswapV3Pool constant USDC_WETH_5 =
        IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    IUniswapV3Pool constant WBTC_ETH_30 =
        IUniswapV3Pool(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD);
    IUniswapV3Pool constant USDC_WETH_30 =
        IUniswapV3Pool(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8);
    IUniswapV3Pool constant WSTETH_ETH_1 =
        IUniswapV3Pool(0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa);
    IUniswapV3Pool[4] public pools = [USDC_WETH_5, USDC_WETH_5, USDC_WETH_5, WSTETH_ETH_1];

    /*//////////////////////////////////////////////////////////////
                              WORLD STATE
    //////////////////////////////////////////////////////////////*/

    // store some data about the pool we are testing
    IUniswapV3Pool pool;
    uint64 poolId;
    address token0;
    address token1;
    // We range position size in terms of WETH, so need to figure out which token is WETH
    uint256 isWETH;
    uint24 fee;
    int24 tickSpacing;
    uint160 currentSqrtPriceX96;
    int24 currentTick;
    uint256 feeGrowthGlobal0X128;
    uint256 feeGrowthGlobal1X128;
    uint256 poolBalance0;
    uint256 poolBalance1;

    TokenId[] emptyList;

    uint16 observationIndex;
    uint16 observationCardinality;
    int24 fastOracleTick;

    int24 slowOracleTick;
    uint160 medianSqrtPriceX96;
    int24 TWAPtick;

    int256 rangesFromStrike;
    int256[2] exerciseFeeAmounts;

    PanopticFactory factory;
    PanopticPoolHarness pp;
    CollateralTracker ct0;
    CollateralTracker ct1;

    PanopticHelper ph;

    address Deployer = address(0x1234);
    address Alice = address(0x123456);
    address Bob = address(0x12345678);
    address Swapper = address(0x123456789);
    address Charlie = address(0x1234567891);
    address Seller = address(0x12345678912);

    /*//////////////////////////////////////////////////////////////
                               TEST DATA
    //////////////////////////////////////////////////////////////*/

    // used to pass into libraries
    mapping(TokenId tokenId => LeftRightUnsigned balance) userBalance;

    mapping(address actor => uint256 lastBalance0) lastCollateralBalance0;
    mapping(address actor => uint256 lastBalance1) lastCollateralBalance1;

    int24 tickLower;
    int24 tickUpper;
    uint160 sqrtLower;
    uint160 sqrtUpper;

    TokenId[] $posIdList;
    TokenId[][1000] $posIdLists;

    uint128 positionSize;
    uint128 positionSizeBurn;

    uint128 expectedLiq;
    uint128 expectedLiqMint;
    uint128 expectedLiqBurn;

    int256 $amount0Moved;
    int256 $amount1Moved;
    int256 $amount0MovedMint;
    int256 $amount1MovedMint;
    int256 $amount0MovedBurn;
    int256 $amount1MovedBurn;

    int128 $expectedPremia0;
    int128 $expectedPremia1;

    int24[] tickLowers;
    int24[] tickUppers;
    uint160[] sqrtLowers;
    uint160[] sqrtUppers;

    uint128[] positionSizes;
    uint128[] positionSizesBurn;

    uint128[] expectedLiqs;
    uint128[] expectedLiqsMint;
    uint128[] expectedLiqsBurn;

    int24 $width;
    int24 $strike;
    int24 $width2;
    int24 $strike2;

    TokenId[] tokenIds;

    int256[] $amount0Moveds;
    int256[] $amount1Moveds;
    int256[] $amount0MovedsMint;
    int256[] $amount1MovedsMint;
    int256[] $amount0MovedsBurn;
    int256[] $amount1MovedsBurn;

    int128[] $expectedPremias0;
    int128[] $expectedPremias1;

    int256 $swap0;
    int256 $swap1;
    int256 $itm0;
    int256 $itm1;
    int256 $intrinsicValue0;
    int256 $intrinsicValue1;
    int256 $ITMSpread0;
    int256 $ITMSpread1;

    int256 $shareDelta0;
    int256 $shareDelta1;

    int256 $shareDelta0Bob;
    int256 $shareDelta1Bob;

    LeftRightUnsigned $tokenData0;
    LeftRightUnsigned $tokenData1;

    uint256 $accValueBefore0;

    uint256[2][] $positionBalanceArray;

    int256 $balanceDelta0;
    int256 $balanceDelta1;

    int256 $bonus0;
    int256 $bonus1;

    int256 $combinedBalance0;
    int256 $combinedBalance0Premium;
    int256 $combinedBalance0NoPremium;
    int256 $bonusCombined0;
    int256 $burnDelta0Combined;
    int256 $burnDelta0;
    int256 $burnDelta1;
    int256 $balance0CombinedPostBurn;
    int256 $protocolLoss0Actual;
    uint256 $delegated0;
    uint256 $delegated1;
    int256 $protocolLoss0BaseExpected;
    uint256 $totalSupply0;
    uint256 $totalSupply1;
    uint256 $totalAssets0;
    uint256 $totalAssets1;

    uint256 currentValue0;
    uint256 currentValue1;
    uint256 medianValue0;
    uint256 medianValue1;

    int24 atTick;

    mapping(bytes32 chunk => LeftRightUnsigned settledTokens) $settledTokens;
    uint256[] settledTokens0;
    int256 longPremium0;
    LeftRightSigned $premia;
    LeftRightSigned $netExchanged;

    /*//////////////////////////////////////////////////////////////
                               ENV SETUP
    //////////////////////////////////////////////////////////////*/

    function _initPool(uint256 seed) internal {
        _initWorld(seed);
    }

    function _initWorldAtTick(uint256 seed, int24 tick) internal {
        _initWorldAtPrice(seed, tick, TickMath.getSqrtRatioAtTick(tick));
    }

    function _initWorldAtPrice(uint256 seed, int24 tick, uint160 sqrtPriceX96) internal {
        // Pick a pool from the seed and cache initial state
        _cacheWorldState(pools[bound(seed, 0, pools.length - 1)]);

        _deployPanopticPool();

        // replace pool with a mock and set the tick
        vm.etch(address(pool), address(new UniPoolPriceMock()).code);

        UniPoolPriceMock(address(pool)).construct(
            UniPoolPriceMock.Slot0(sqrtPriceX96, tick, 0, 0, 0, 0, true),
            address(token0),
            address(token1),
            fee,
            tickSpacing
        );

        _initAccounts();
    }

    function _initWorld(uint256 seed) internal {
        // Pick a pool from the seed and cache initial state
        _cacheWorldState(pools[bound(seed, 0, pools.length - 1)]);

        _deployPanopticPool();

        _initAccounts();
    }

    function _cacheWorldState(IUniswapV3Pool _pool) internal {
        pool = _pool;
        poolId = PanopticMath.getPoolId(address(_pool));
        token0 = _pool.token0();
        token1 = _pool.token1();
        isWETH = token0 == address(WETH) ? 0 : 1;
        fee = _pool.fee();
        tickSpacing = _pool.tickSpacing();
        (currentSqrtPriceX96, currentTick, , , , , ) = _pool.slot0();
        feeGrowthGlobal0X128 = _pool.feeGrowthGlobal0X128();
        feeGrowthGlobal1X128 = _pool.feeGrowthGlobal1X128();
        poolBalance0 = IERC20Partial(token0).balanceOf(address(_pool));
        poolBalance1 = IERC20Partial(token1).balanceOf(address(_pool));
    }

    function _deployPanopticPool() internal {
        vm.startPrank(Deployer);

        IDonorNFT dNFT = IDonorNFT(address(new DonorNFT()));

        factory = new PanopticFactory(
            WETH,
            sfpm,
            V3FACTORY,
            dNFT,
            poolReference,
            collateralReference
        );

        factory.initialize(Deployer);

        DonorNFT(address(dNFT)).changeFactory(address(factory));

        deal(token0, Deployer, type(uint104).max);
        deal(token1, Deployer, type(uint104).max);
        IERC20Partial(token0).approve(address(factory), type(uint104).max);
        IERC20Partial(token1).approve(address(factory), type(uint104).max);

        pp = PanopticPoolHarness(
            address(
                factory.deployNewPool(
                    token0,
                    token1,
                    fee,
                    bytes32(uint256(uint160(Deployer)) << 96)
                )
            )
        );

        ct0 = pp.collateralToken0();
        ct1 = pp.collateralToken1();
    }

    function _initAccounts() internal {
        vm.startPrank(Swapper);

        IERC20Partial(token0).approve(address(router), type(uint256).max);
        IERC20Partial(token1).approve(address(router), type(uint256).max);

        deal(token0, Swapper, type(uint104).max);
        deal(token1, Swapper, type(uint104).max);

        vm.startPrank(Charlie);

        deal(token0, Charlie, type(uint104).max);
        deal(token1, Charlie, type(uint104).max);

        IERC20Partial(token0).approve(address(router), type(uint256).max);
        IERC20Partial(token1).approve(address(router), type(uint256).max);
        IERC20Partial(token0).approve(address(pp), type(uint256).max);
        IERC20Partial(token1).approve(address(pp), type(uint256).max);
        IERC20Partial(token0).approve(address(ct0), type(uint256).max);
        IERC20Partial(token1).approve(address(ct1), type(uint256).max);

        vm.startPrank(Seller);

        deal(token0, Seller, type(uint104).max);
        deal(token1, Seller, type(uint104).max);

        IERC20Partial(token0).approve(address(router), type(uint256).max);
        IERC20Partial(token1).approve(address(router), type(uint256).max);
        IERC20Partial(token0).approve(address(pp), type(uint256).max);
        IERC20Partial(token1).approve(address(pp), type(uint256).max);
        IERC20Partial(token0).approve(address(ct0), type(uint256).max);
        IERC20Partial(token1).approve(address(ct1), type(uint256).max);

        ct0.deposit(type(uint104).max, Seller);
        ct1.deposit(type(uint104).max, Seller);

        // cancel out MEV tax and push exchange rate back to 1
        deal(address(ct0), Seller, type(uint104).max, true);
        deal(address(ct1), Seller, type(uint104).max, true);

        vm.startPrank(Bob);
        // account for MEV tax
        deal(token0, Bob, (type(uint104).max * uint256(1010)) / 1000);
        deal(token1, Bob, (type(uint104).max * uint256(1010)) / 1000);

        IERC20Partial(token0).approve(address(router), type(uint256).max);
        IERC20Partial(token1).approve(address(router), type(uint256).max);
        IERC20Partial(token0).approve(address(pp), type(uint256).max);
        IERC20Partial(token1).approve(address(pp), type(uint256).max);
        IERC20Partial(token0).approve(address(ct0), type(uint256).max);
        IERC20Partial(token1).approve(address(ct1), type(uint256).max);

        ct0.deposit(type(uint104).max, Bob);
        ct1.deposit(type(uint104).max, Bob);

        // cancel out MEV tax and push exchange rate back to 1
        deal(address(ct0), Bob, type(uint104).max, true);
        deal(address(ct1), Bob, type(uint104).max, true);

        vm.startPrank(Alice);

        deal(token0, Alice, type(uint104).max);
        deal(token1, Alice, type(uint104).max);

        IERC20Partial(token0).approve(address(router), type(uint256).max);
        IERC20Partial(token1).approve(address(router), type(uint256).max);
        IERC20Partial(token0).approve(address(pp), type(uint256).max);
        IERC20Partial(token1).approve(address(pp), type(uint256).max);
        IERC20Partial(token0).approve(address(ct0), type(uint256).max);
        IERC20Partial(token1).approve(address(ct1), type(uint256).max);

        ct0.deposit(type(uint104).max, Alice);
        ct1.deposit(type(uint104).max, Alice);

        // cancel out MEV tax and push exchange rate back to 1
        deal(address(ct0), Alice, type(uint104).max, true);
        deal(address(ct1), Alice, type(uint104).max, true);
    }

    function setUp() public {
        sfpm = new SemiFungiblePositionManagerHarness(V3FACTORY);

        ph = new PanopticHelper(sfpm);

        // deploy reference pool and collateral token
        poolReference = address(new PanopticPoolHarness(sfpm));
        collateralReference = address(
            new CollateralTracker(10, 2_000, 1_000, -1_024, 5_000, 9_000, 20_000)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          TEST DATA POPULATION
    //////////////////////////////////////////////////////////////*/

    function populatePositionData(int24 width, int24 strike, uint256 positionSizeSeed) internal {
        (int24 rangeDown, int24 rangeUp) = PanopticMath.getRangesFromStrike(width, tickSpacing);

        tickLower = int24(strike - rangeDown);
        tickLowers.push(tickLower);
        tickUpper = int24(strike + rangeUp);
        tickUppers.push(tickUpper);

        sqrtLower = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtLowers.push(sqrtLower);
        sqrtUpper = TickMath.getSqrtRatioAtTick(tickUpper);
        sqrtUppers.push(sqrtUpper);

        // 0.0001 -> 10_000 WETH
        positionSizeSeed = bound(positionSizeSeed, 10 ** 15, 10 ** 20);

        // calculate the amount of ETH contracts needed to create a position with above attributes and value in ETH
        positionSize = uint128(
            getContractsForAmountAtTick(currentTick, tickLower, tickUpper, isWETH, positionSizeSeed)
        );

        // `getContractsForAmountAtTick` calculates liquidity under the hood, but SFPM does this conversion
        // as well and using the original value could result in discrepancies due to rounding

        expectedLiq = isWETH == 0
            ? Math.getLiquidityForAmount0(tickLower, tickUpper, positionSize).liquidity()
            : Math.getLiquidityForAmount1(tickLower, tickUpper, positionSize).liquidity();
        expectedLiqs.push(expectedLiq);

        $amount0Moveds.push(
            sqrtUpper < currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount0Delta(
                    sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
                    sqrtUpper,
                    int128(expectedLiq)
                )
        );

        $amount1Moveds.push(
            sqrtLower > currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount1Delta(
                    sqrtLower,
                    sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
                    int128(expectedLiq)
                )
        );
    }

    // intended to be combined with a min-width position so that most of the pool's liquidity is consumed by the position
    function populatePositionDataLarge(
        int24 width,
        int24 strike,
        uint256 positionSizeSeed
    ) internal {
        (int24 rangeDown, int24 rangeUp) = PanopticMath.getRangesFromStrike(width, tickSpacing);

        tickLower = int24(strike - rangeDown);
        tickUpper = int24(strike + rangeUp);
        sqrtLower = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        // 0.0001 -> 10_000 WETH
        positionSizeSeed = bound(positionSizeSeed, 10 ** 22, 10 ** 24);

        // calculate the amount of ETH contracts needed to create a position with above attributes and value in ETH
        positionSize = uint128(
            getContractsForAmountAtTick(currentTick, tickLower, tickUpper, isWETH, positionSizeSeed)
        );

        // `getContractsForAmountAtTick` calculates liquidity under the hood, but SFPM does this conversion
        // as well and using the original value could result in discrepancies due to rounding

        expectedLiq = isWETH == 0
            ? Math.getLiquidityForAmount0(tickLower, tickUpper, positionSize).liquidity()
            : Math.getLiquidityForAmount1(tickLower, tickUpper, positionSize).liquidity();
    }

    function populatePositionData(
        int24 width,
        int24 strike,
        uint256[2] memory positionSizeSeeds
    ) internal {
        (int24 rangeDown, int24 rangeUp) = PanopticMath.getRangesFromStrike(width, tickSpacing);

        tickLower = int24(strike - rangeDown);
        tickUpper = int24(strike + rangeUp);
        sqrtLower = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        positionSizeSeeds[0] = bound(positionSizeSeeds[0], 10 ** 15, 10 ** 20);
        positionSizeSeeds[1] = bound(positionSizeSeeds[1], 10 ** 15, 10 ** 20);

        // calculate the amount of ETH contracts needed to create a position with above attributes and value in ETH
        positionSizes.push(
            uint128(
                getContractsForAmountAtTick(
                    currentTick,
                    tickLower,
                    tickUpper,
                    isWETH,
                    positionSizeSeeds[0]
                )
            )
        );

        positionSizes.push(
            uint128(
                getContractsForAmountAtTick(
                    currentTick,
                    tickLower,
                    tickUpper,
                    isWETH,
                    positionSizeSeeds[1]
                )
            )
        );

        // `getContractsForAmountAtTick` calculates liquidity under the hood, but SFPM does this conversion
        // as well and using the original value could result in discrepancies due to rounding

        expectedLiqs.push(
            isWETH == 0
                ? Math.getLiquidityForAmount0(tickLower, tickUpper, positionSizes[0]).liquidity()
                : Math.getLiquidityForAmount1(tickLower, tickUpper, positionSizes[0]).liquidity()
        );

        expectedLiqs.push(
            isWETH == 0
                ? Math.getLiquidityForAmount0(tickLower, tickUpper, positionSizes[1]).liquidity()
                : Math.getLiquidityForAmount1(tickLower, tickUpper, positionSizes[1]).liquidity()
        );
    }

    function populatePositionData(
        int24[2] memory width,
        int24[2] memory strike,
        uint256 positionSizeSeed
    ) internal {
        (int24 rangeDown0, int24 rangeUp0) = PanopticMath.getRangesFromStrike(
            width[0],
            tickSpacing
        );
        tickLowers.push(int24(strike[0] - rangeDown0));
        tickUppers.push(int24(strike[0] + rangeUp0));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[0]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[0]));

        (int24 rangeDown1, int24 rangeUp1) = PanopticMath.getRangesFromStrike(
            width[1],
            tickSpacing
        );
        tickLowers.push(int24(strike[1] - rangeDown1));
        tickUppers.push(int24(strike[1] + rangeUp1));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[1]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[1]));

        // 0.0001 -> 10_000 WETH
        positionSizeSeed = bound(positionSizeSeed, 10 ** 15, 10 ** 20);

        // calculate the amount of ETH contracts needed to create a position with above attributes and value in ETH
        positionSize = uint128(
            getContractsForAmountAtTick(
                currentTick,
                tickLowers[0],
                tickUppers[0],
                isWETH,
                positionSizeSeed
            )
        );

        // `getContractsForAmountAtTick` calculates liquidity under the hood, but SFPM does this conversion
        // as well and using the original value could result in discrepancies due to rounding
        expectedLiqs.push(
            isWETH == 0
                ? Math
                    .getLiquidityForAmount0(tickLowers[0], tickUppers[0], positionSize)
                    .liquidity()
                : Math
                    .getLiquidityForAmount1(tickLowers[0], tickUppers[0], positionSize)
                    .liquidity()
        );

        expectedLiqs.push(
            isWETH == 0
                ? Math
                    .getLiquidityForAmount0(tickLowers[1], tickUppers[1], positionSize)
                    .liquidity()
                : Math
                    .getLiquidityForAmount1(tickLowers[1], tickUppers[1], positionSize)
                    .liquidity()
        );

        $amount0Moveds.push(
            sqrtUppers[0] < currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount0Delta(
                    sqrtLowers[0] < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLowers[0],
                    sqrtUppers[0],
                    int128(expectedLiqs[0])
                )
        );

        $amount0Moveds.push(
            sqrtUppers[1] < currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount0Delta(
                    sqrtLowers[1] < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLowers[1],
                    sqrtUppers[1],
                    int128(expectedLiqs[1])
                )
        );

        $amount1Moveds.push(
            sqrtLowers[0] > currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount1Delta(
                    sqrtLowers[0],
                    sqrtUppers[0] > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUppers[0],
                    int128(expectedLiqs[0])
                )
        );

        $amount1Moveds.push(
            sqrtLowers[1] > currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount1Delta(
                    sqrtLowers[1],
                    sqrtUppers[1] > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUppers[1],
                    int128(expectedLiqs[1])
                )
        );

        // ensure second leg is sufficiently large
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            currentSqrtPriceX96,
            sqrtLowers[1],
            sqrtUppers[1],
            expectedLiqs[1]
        );
        uint256 priceX128 = FullMath.mulDiv(currentSqrtPriceX96, currentSqrtPriceX96, 2 ** 64);
        // total ETH value must be >= 10 ** 15
        uint256 ETHValue = isWETH == 0
            ? amount0 + FullMath.mulDiv(amount1, 2 ** 128, priceX128)
            : Math.mulDiv128(amount0, priceX128) + amount1;
        vm.assume(ETHValue >= 10 ** 13);
        vm.assume(ETHValue <= 10 ** 22);
    }

    // second positionSizeSeed is to back single long leg
    function populatePositionDataLong(
        int24[2] memory width,
        int24[2] memory strike,
        uint256[2] memory positionSizeSeed
    ) internal {
        (int24 rangeDown0, int24 rangeUp0) = PanopticMath.getRangesFromStrike(
            width[0],
            tickSpacing
        );
        tickLowers.push(int24(strike[0] - rangeDown0));
        tickUppers.push(int24(strike[0] + rangeUp0));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[0]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[0]));

        (int24 rangeDown1, int24 rangeUp1) = PanopticMath.getRangesFromStrike(
            width[1],
            tickSpacing
        );
        tickLowers.push(int24(strike[1] - rangeDown1));
        tickUppers.push(int24(strike[1] + rangeUp1));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[1]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[1]));

        // 0.0001 -> 10_000 WETH
        positionSizeSeed[0] = bound(positionSizeSeed[0], 2 * 10 ** 16, 10 ** 22);
        // since this is for a long leg it has to be smaller than the short liquidity it's trying to buy
        positionSizeSeed[1] = bound(positionSizeSeed[1], 10 ** 15, positionSizeSeed[0] / 20);

        // calculate the amount of ETH contracts needed to create a position with above attributes and value in ETH
        positionSizes.push(
            uint128(
                getContractsForAmountAtTick(
                    currentTick,
                    tickLowers[1],
                    tickUppers[1],
                    isWETH,
                    positionSizeSeed[0]
                )
            )
        );

        positionSizes.push(
            uint128(
                getContractsForAmountAtTick(
                    currentTick,
                    tickLowers[1],
                    tickUppers[1],
                    isWETH,
                    positionSizeSeed[1]
                )
            )
        );

        // `getContractsForAmountAtTick` calculates liquidity under the hood, but SFPM does this conversion
        // as well and using the original value could result in discrepancies due to rounding
        expectedLiqs.push(
            isWETH == 0
                ? Math
                    .getLiquidityForAmount0(tickLowers[1], tickUppers[1], positionSizes[0])
                    .liquidity()
                : Math
                    .getLiquidityForAmount1(tickLowers[1], tickUppers[1], positionSizes[0])
                    .liquidity()
        );

        expectedLiqs.push(
            isWETH == 0
                ? Math
                    .getLiquidityForAmount0(tickLowers[0], tickUppers[0], positionSizes[1])
                    .liquidity()
                : Math
                    .getLiquidityForAmount1(tickLowers[0], tickUppers[0], positionSizes[1])
                    .liquidity()
        );

        expectedLiqs.push(
            isWETH == 0
                ? Math
                    .getLiquidityForAmount0(tickLowers[1], tickUppers[1], positionSizes[1])
                    .liquidity()
                : Math
                    .getLiquidityForAmount1(tickLowers[1], tickUppers[1], positionSizes[1])
                    .liquidity()
        );

        $amount0Moveds.push(
            sqrtUppers[1] < currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount0Delta(
                    sqrtLowers[1] < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLowers[1],
                    sqrtUppers[1],
                    int128(expectedLiqs[0])
                )
        );

        $amount0Moveds.push(
            sqrtUppers[0] < currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount0Delta(
                    sqrtLowers[0] < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLowers[0],
                    sqrtUppers[0],
                    int128(expectedLiqs[1])
                )
        );

        $amount0Moveds.push(
            sqrtUppers[1] < currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount0Delta(
                    sqrtLowers[1] < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLowers[1],
                    sqrtUppers[1],
                    -int128(expectedLiqs[2])
                )
        );

        $amount1Moveds.push(
            sqrtLowers[1] > currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount1Delta(
                    sqrtLowers[1],
                    sqrtUppers[1] > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUppers[1],
                    int128(expectedLiqs[0])
                )
        );

        $amount1Moveds.push(
            sqrtLowers[0] > currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount1Delta(
                    sqrtLowers[0],
                    sqrtUppers[0] > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUppers[0],
                    int128(expectedLiqs[1])
                )
        );

        $amount1Moveds.push(
            sqrtLowers[1] > currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount1Delta(
                    sqrtLowers[1],
                    sqrtUppers[1] > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUppers[1],
                    -int128(expectedLiqs[2])
                )
        );
    }

    function updatePositionDataLong() public {
        $amount0Moveds[1] = sqrtUppers[0] < currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                sqrtLowers[0] < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLowers[0],
                sqrtUppers[0],
                int128(expectedLiqs[1])
            );

        $amount0Moveds[2] = sqrtUppers[1] < currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                sqrtLowers[1] < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLowers[1],
                sqrtUppers[1],
                -int128(expectedLiqs[2])
            );

        $amount1Moveds[1] = sqrtLowers[0] > currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount1Delta(
                sqrtLowers[0],
                sqrtUppers[0] > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUppers[0],
                int128(expectedLiqs[1])
            );

        $amount1Moveds[2] = sqrtLowers[1] > currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount1Delta(
                sqrtLowers[1],
                sqrtUppers[1] > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUppers[1],
                -int128(expectedLiqs[2])
            );
    }

    function updatePositionDataVariable(uint256 numLegs, uint256[4] memory isLongs) public {
        for (uint256 i = 0; i < numLegs; i++) {
            $amount0Moveds[i] = sqrtUppers[i] < currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount0Delta(
                    sqrtLowers[i] < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLowers[i],
                    sqrtUppers[i],
                    (isLongs[i] == 1 ? int8(1) : -1) * int128(expectedLiqs[i])
                );

            $amount1Moveds[i] = sqrtLowers[i] > currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount1Delta(
                    sqrtLowers[i],
                    sqrtUppers[i] > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUppers[i],
                    (isLongs[i] == 1 ? int128(1) : -1) * int128(expectedLiqs[i])
                );
            $amount0MovedBurn += $amount0Moveds[i];
            $amount1MovedBurn += $amount1Moveds[i];
        }
    }

    function updateITMAmountsBurn(uint256 numLegs, uint256[4] memory tokenTypes) public {
        for (uint256 i = 0; i < numLegs; i++) {
            if (tokenTypes[i] == 1) {
                $itm0 += $amount0Moveds[i];
            } else {
                $itm1 += $amount1Moveds[i];
            }
        }
    }

    function updateSwappedAmountsBurn(uint256 numLegs, uint256[4] memory isLongs) public {
        int128[] memory liquidityDeltas = new int128[](numLegs);
        for (uint256 i = 0; i < numLegs; i++) {
            liquidityDeltas[i] =
                int128(numLegs == 1 ? expectedLiq : expectedLiqs[i]) *
                (isLongs[i] == 1 ? int8(1) : -1);
        }
        bool zeroForOne; // The direction of the swap, true for token0 to token1, false for token1 to token0
        int256 swapAmount; // The amount of token0 or token1 to swap

        if (($itm0 != 0) && ($itm1 != 0)) {
            int256 net0 = $itm0 - PanopticMath.convert1to0($itm1, currentSqrtPriceX96);

            // if net0 is negative, then the protocol has a net shortage of token0
            zeroForOne = net0 < 0;

            //compute the swap amount, set as positive (exact input)
            swapAmount = -net0;
        } else if ($itm0 != 0) {
            zeroForOne = $itm0 < 0;
            swapAmount = -$itm0;
        } else {
            zeroForOne = $itm1 > 0;
            swapAmount = -$itm1;
        }

        if (numLegs == 1) {
            tickLowers.push(tickLower);
            tickUppers.push(tickUpper);
        }

        if (swapAmount != 0) {
            vm.startPrank(address(sfpm));
            ($swap0, $swap1) = PositionUtils.simulateSwapSingleBurn(
                pool,
                tickLowers,
                tickUppers,
                liquidityDeltas,
                router,
                token0,
                token1,
                fee,
                zeroForOne,
                swapAmount
            );
            vm.startPrank(Alice);
        }
    }

    function updateIntrinsicValueBurn(
        LeftRightSigned longAmounts,
        LeftRightSigned shortAmounts
    ) public {
        $intrinsicValue0 =
            ($swap0 + $amount0MovedBurn) -
            longAmounts.rightSlot() +
            shortAmounts.rightSlot();
        $intrinsicValue1 =
            ($swap1 + $amount1MovedBurn) -
            longAmounts.leftSlot() +
            shortAmounts.leftSlot();
    }

    function populatePositionData(
        int24[3] memory width,
        int24[3] memory strike,
        uint256 positionSizeSeed
    ) internal {
        (int24 rangeDown0, int24 rangeUp0) = PanopticMath.getRangesFromStrike(
            width[0],
            tickSpacing
        );
        tickLowers.push(int24(strike[0] - rangeDown0));
        tickUppers.push(int24(strike[0] + rangeUp0));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[0]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[0]));

        (int24 rangeDown1, int24 rangeUp1) = PanopticMath.getRangesFromStrike(
            width[1],
            tickSpacing
        );
        tickLowers.push(int24(strike[1] - rangeDown1));
        tickUppers.push(int24(strike[1] + rangeUp1));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[1]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[1]));

        (int24 rangeDown2, int24 rangeUp2) = PanopticMath.getRangesFromStrike(
            width[2],
            tickSpacing
        );
        tickLowers.push(int24(strike[2] - rangeDown2));
        tickUppers.push(int24(strike[2] + rangeUp2));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[2]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[2]));

        // 0.0001 -> 10_000 WETH
        positionSizeSeed = bound(positionSizeSeed, 10 ** 15, 10 ** 20);

        // calculate the amount of ETH contracts needed to create a position with above attributes and value in ETH
        positionSize = uint128(
            getContractsForAmountAtTick(
                currentTick,
                tickLowers[0],
                tickUppers[0],
                isWETH,
                positionSizeSeed
            )
        );

        // `getContractsForAmountAtTick` calculates liquidity under the hood, but SFPM does this conversion
        // as well and using the original value could result in discrepancies due to rounding
        for (uint256 i = 0; i < 3; i++) {
            expectedLiqs.push(
                isWETH == 0
                    ? Math
                        .getLiquidityForAmount0(tickLowers[i], tickUppers[i], positionSize)
                        .liquidity()
                    : Math
                        .getLiquidityForAmount1(tickLowers[i], tickUppers[i], positionSize)
                        .liquidity()
            );

            $amount0Moveds.push(
                sqrtUppers[i] < currentSqrtPriceX96
                    ? int256(0)
                    : SqrtPriceMath.getAmount0Delta(
                        sqrtLowers[i] < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLowers[i],
                        sqrtUppers[i],
                        int128(expectedLiqs[i])
                    )
            );

            $amount1Moveds.push(
                sqrtLowers[i] > currentSqrtPriceX96
                    ? int256(0)
                    : SqrtPriceMath.getAmount1Delta(
                        sqrtLowers[i],
                        sqrtUppers[i] > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUppers[i],
                        int128(expectedLiqs[i])
                    )
            );
        }

        // ensure second leg is sufficiently large
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            currentSqrtPriceX96,
            sqrtLowers[1],
            sqrtUppers[1],
            expectedLiqs[1]
        );

        uint256 priceX128 = FullMath.mulDiv(currentSqrtPriceX96, currentSqrtPriceX96, 2 ** 64);
        // total ETH value must be >= 10 ** 15
        uint256 ETHValue = isWETH == 0
            ? amount0 + FullMath.mulDiv(amount1, 2 ** 128, priceX128)
            : Math.mulDiv128(amount0, priceX128) + amount1;
        vm.assume(ETHValue >= 10 ** 13);
        vm.assume(ETHValue <= 10 ** 22);

        // ensure third leg is sufficiently large
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            currentSqrtPriceX96,
            sqrtLowers[2],
            sqrtUppers[2],
            expectedLiqs[2]
        );

        // total ETH value must be >= 10 ** 15
        ETHValue = isWETH == 0
            ? amount0 + FullMath.mulDiv(amount1, 2 ** 128, priceX128)
            : Math.mulDiv128(amount0, priceX128) + amount1;
        vm.assume(ETHValue >= 10 ** 13);
        vm.assume(ETHValue <= 10 ** 22);
    }

    function populatePositionData(
        int24[4] memory width,
        int24[4] memory strike,
        uint256 positionSizeSeed
    ) internal {
        (int24 rangeDown0, int24 rangeUp0) = PanopticMath.getRangesFromStrike(
            width[0],
            tickSpacing
        );
        tickLowers.push(int24(strike[0] - rangeDown0));
        tickUppers.push(int24(strike[0] + rangeUp0));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[0]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[0]));

        (int24 rangeDown1, int24 rangeUp1) = PanopticMath.getRangesFromStrike(
            width[1],
            tickSpacing
        );
        tickLowers.push(int24(strike[1] - rangeDown1));
        tickUppers.push(int24(strike[1] + rangeUp1));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[1]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[1]));

        (int24 rangeDown2, int24 rangeUp2) = PanopticMath.getRangesFromStrike(
            width[2],
            tickSpacing
        );
        tickLowers.push(int24(strike[2] - rangeDown2));
        tickUppers.push(int24(strike[2] + rangeUp2));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[2]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[2]));

        (int24 rangeDown3, int24 rangeUp3) = PanopticMath.getRangesFromStrike(
            width[3],
            tickSpacing
        );
        tickLowers.push(int24(strike[3] - rangeDown3));
        tickUppers.push(int24(strike[3] + rangeUp3));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[3]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[3]));

        // 0.0001 -> 10_000 WETH
        positionSizeSeed = bound(positionSizeSeed, 10 ** 15, 10 ** 20);

        // calculate the amount of ETH contracts needed to create a position with above attributes and value in ETH
        positionSize = uint128(
            getContractsForAmountAtTick(
                currentTick,
                tickLowers[0],
                tickUppers[0],
                isWETH,
                positionSizeSeed
            )
        );
        // `getContractsForAmountAtTick` calculates liquidity under the hood, but SFPM does this conversion
        // as well and using the original value could result in discrepancies due to rounding
        for (uint256 i = 0; i < 4; i++) {
            expectedLiqs.push(
                isWETH == 0
                    ? Math
                        .getLiquidityForAmount0(tickLowers[i], tickUppers[i], positionSize)
                        .liquidity()
                    : Math
                        .getLiquidityForAmount1(tickLowers[i], tickUppers[i], positionSize)
                        .liquidity()
            );

            $amount0Moveds.push(
                sqrtUppers[i] < currentSqrtPriceX96
                    ? int256(0)
                    : SqrtPriceMath.getAmount0Delta(
                        sqrtLowers[i] < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLowers[i],
                        sqrtUppers[i],
                        int128(expectedLiqs[i])
                    )
            );

            $amount1Moveds.push(
                sqrtLowers[i] > currentSqrtPriceX96
                    ? int256(0)
                    : SqrtPriceMath.getAmount1Delta(
                        sqrtLowers[i],
                        sqrtUppers[i] > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUppers[i],
                        int128(expectedLiqs[i])
                    )
            );
        }

        // ensure second leg is sufficiently large
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            currentSqrtPriceX96,
            sqrtLowers[1],
            sqrtUppers[1],
            expectedLiqs[1]
        );

        uint256 priceX128 = FullMath.mulDiv(currentSqrtPriceX96, currentSqrtPriceX96, 2 ** 64);
        // total ETH value must be >= 10 ** 15
        uint256 ETHValue = isWETH == 0
            ? amount0 + FullMath.mulDiv(amount1, 2 ** 128, priceX128)
            : Math.mulDiv128(amount0, priceX128) + amount1;
        vm.assume(ETHValue >= 10 ** 13);
        vm.assume(ETHValue <= 10 ** 22);

        // ensure third leg is sufficiently large
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            currentSqrtPriceX96,
            sqrtLowers[2],
            sqrtUppers[2],
            expectedLiqs[2]
        );
        ETHValue = isWETH == 0
            ? amount0 + FullMath.mulDiv(amount1, 2 ** 128, priceX128)
            : Math.mulDiv128(amount0, priceX128) + amount1;

        vm.assume(ETHValue >= 10 ** 13);
        vm.assume(ETHValue <= 10 ** 22);

        // ensure fourth leg is sufficiently large
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            currentSqrtPriceX96,
            sqrtLowers[3],
            sqrtUppers[3],
            expectedLiqs[3]
        );
        ETHValue = isWETH == 0
            ? amount0 + FullMath.mulDiv(amount1, 2 ** 128, priceX128)
            : Math.mulDiv128(amount0, priceX128) + amount1;

        vm.assume(ETHValue >= 10 ** 13);
        vm.assume(ETHValue <= 10 ** 22);
    }

    function populatePositionData(
        int24[2] memory width,
        int24[2] memory strike,
        uint256[2] memory positionSizeSeeds
    ) internal {
        (int24 rangeDown0, int24 rangeUp0) = PanopticMath.getRangesFromStrike(
            width[0],
            tickSpacing
        );
        tickLowers.push(int24(strike[0] - rangeDown0));
        tickUppers.push(int24(strike[0] + rangeUp0));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[0]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[0]));

        (int24 rangeDown1, int24 rangeUp1) = PanopticMath.getRangesFromStrike(
            width[1],
            tickSpacing
        );
        tickLowers.push(int24(strike[1] - rangeDown1));
        tickUppers.push(int24(strike[1] + rangeUp1));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[1]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[1]));

        // 0.0001 -> 10_000 WETH
        positionSizeSeeds[0] = bound(positionSizeSeeds[0], 10 ** 15, 10 ** 20);
        positionSizeSeeds[1] = bound(positionSizeSeeds[1], 10 ** 15, 10 ** 20);

        // calculate the amount of ETH contracts needed to create a position with above attributes and value in ETH
        positionSizes.push(
            uint128(
                getContractsForAmountAtTick(
                    currentTick,
                    tickLowers[0],
                    tickUppers[0],
                    isWETH,
                    positionSizeSeeds[0]
                )
            )
        );

        positionSizes.push(
            uint128(
                getContractsForAmountAtTick(
                    currentTick,
                    tickLowers[1],
                    tickUppers[1],
                    isWETH,
                    positionSizeSeeds[1]
                )
            )
        );

        // `getContractsForAmountAtTick` calculates liquidity under the hood, but SFPM does this conversion
        // as well and using the original value could result in discrepancies due to rounding
        expectedLiqs.push(
            isWETH == 0
                ? Math
                    .getLiquidityForAmount0(tickLowers[0], tickUppers[0], positionSizes[0])
                    .liquidity()
                : Math
                    .getLiquidityForAmount1(tickLowers[0], tickUppers[0], positionSizes[0])
                    .liquidity()
        );

        expectedLiqs.push(
            isWETH == 0
                ? Math
                    .getLiquidityForAmount0(tickLowers[1], tickUppers[1], positionSizes[1])
                    .liquidity()
                : Math
                    .getLiquidityForAmount1(tickLowers[1], tickUppers[1], positionSizes[1])
                    .liquidity()
        );
    }

    function populatePositionData(
        int24 width,
        int24 strike,
        uint256 positionSizeSeed,
        uint256 positionSizeBurnSeed
    ) internal {
        (int24 rangeDown0, int24 rangeUp0) = PanopticMath.getRangesFromStrike(width, tickSpacing);
        tickLower = int24(strike - rangeDown0);
        tickUpper = int24(strike + rangeUp0);
        sqrtLower = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        // 0.0001 -> 10_000 WETH
        positionSizeSeed = bound(positionSizeSeed, 10 ** 15, 10 ** 20);
        positionSizeBurnSeed = bound(positionSizeBurnSeed, 10 ** 14, positionSizeSeed);

        // calculate the amount of ETH contracts needed to create a position with above attributes and value in ETH
        positionSize = uint128(
            getContractsForAmountAtTick(currentTick, tickLower, tickUpper, isWETH, positionSizeSeed)
        );

        positionSizeBurn = uint128(
            getContractsForAmountAtTick(
                currentTick,
                tickLower,
                tickUpper,
                isWETH,
                positionSizeBurnSeed
            )
        );

        // `getContractsForAmountAtTick` calculates liquidity under the hood, but SFPM does this conversion
        // as well and using the original value could result in discrepancies due to rounding

        expectedLiq = isWETH == 0
            ? Math
                .getLiquidityForAmount0(tickLower, tickUpper, positionSize - positionSizeBurn)
                .liquidity()
            : Math
                .getLiquidityForAmount1(tickLower, tickUpper, positionSize - positionSizeBurn)
                .liquidity();

        expectedLiqMint = isWETH == 0
            ? Math.getLiquidityForAmount0(tickLower, tickUpper, positionSize).liquidity()
            : Math.getLiquidityForAmount1(tickLower, tickUpper, positionSize).liquidity();

        expectedLiqBurn = isWETH == 0
            ? Math.getLiquidityForAmount0(tickLower, tickUpper, positionSizeBurn).liquidity()
            : Math.getLiquidityForAmount1(tickLower, tickUpper, positionSizeBurn).liquidity();
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    // used to accumulate premia for testing
    function twoWaySwap(uint256 swapSize) public {
        vm.startPrank(Swapper);

        swapSize = bound(swapSize, 10 ** 18, 10 ** 20);
        for (uint256 i = 0; i < 10; ++i) {
            router.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(
                    isWETH == 0 ? token0 : token1,
                    isWETH == 1 ? token0 : token1,
                    fee,
                    Bob,
                    block.timestamp,
                    swapSize,
                    0,
                    0
                )
            );

            router.exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams(
                    isWETH == 1 ? token0 : token1,
                    isWETH == 0 ? token0 : token1,
                    fee,
                    Bob,
                    block.timestamp,
                    (swapSize * (1_000_000 - fee)) / 1_000_000,
                    type(uint256).max,
                    0
                )
            );
        }

        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();
    }

    function oneWaySwap(uint256 swapSize, bool swapDirection) public {
        vm.startPrank(Swapper);
        swapSize = bound(swapSize, 10 ** 18, 10 ** 19);
        if (swapDirection) {
            router.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(
                    isWETH == 0 ? token0 : token1,
                    isWETH == 1 ? token0 : token1,
                    fee,
                    Bob,
                    block.timestamp,
                    swapSize,
                    0,
                    0
                )
            );
        } else {
            router.exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams(
                    isWETH == 1 ? token0 : token1,
                    isWETH == 0 ? token0 : token1,
                    fee,
                    Bob,
                    block.timestamp,
                    swapSize,
                    type(uint256).max,
                    0
                )
            );
        }
    }

    // convert signed int to assets
    function convertToAssets(CollateralTracker ct, int256 amount) internal view returns (int256) {
        return (amount > 0 ? int8(1) : -1) * int256(ct.convertToAssets(uint256(Math.abs(amount))));
    }

    // "virtual" deposit or withdrawal from an account without changing the share price
    function editCollateral(CollateralTracker ct, address owner, uint256 newShares) internal {
        int256 shareDelta = int256(newShares) - int256(ct.balanceOf(owner));
        int256 assetDelta = convertToAssets(ct, shareDelta);
        vm.store(
            address(ct),
            bytes32(uint256(7)),
            bytes32(
                uint256(
                    LeftRightSigned.unwrap(
                        LeftRightSigned
                            .wrap(int256(uint256(vm.load(address(ct), bytes32(uint256(7))))))
                            .add(LeftRightSigned.wrap(assetDelta))
                    )
                )
            )
        );
        deal(
            ct.asset(),
            address(ct),
            uint256(int256(IERC20Partial(ct.asset()).balanceOf(address(ct))) + assetDelta)
        );

        deal(address(ct), owner, newShares, true);
    }

    /*//////////////////////////////////////////////////////////////
                         POOL INITIALIZATION: -
    //////////////////////////////////////////////////////////////*/

    function test_Fail_startPool_PoolAlreadyInitialized(uint256 x) public {
        _initWorld(x);

        vm.expectRevert(Errors.PoolAlreadyInitialized.selector);

        pp.startPool(pool, token0, token1, ct0, ct1);
    }

    /*//////////////////////////////////////////////////////////////
                           SYSTEM PARAMETERS
    //////////////////////////////////////////////////////////////*/

    function test_Success_parameters_initialState(uint256 x) public {
        // Pick a pool from the seed and cache initial state
        _cacheWorldState(pools[bound(x, 0, pools.length - 1)]);

        _deployPanopticPool();

        assertEq(vm.load(address(ct0), bytes32(uint256(0))), bytes32(uint256(10 ** 6))); // totalSupply
        assertEq(vm.load(address(ct1), bytes32(uint256(0))), bytes32(uint256(10 ** 6))); // totalSupply

        assertEq(vm.load(address(ct0), bytes32(uint256(1))), bytes32(uint256(0))); // balanceOf slot
        assertEq(vm.load(address(ct1), bytes32(uint256(1))), bytes32(uint256(0))); // balanceOf slot

        assertEq(vm.load(address(ct0), bytes32(uint256(2))), bytes32(uint256(0))); // allowance slot
        assertEq(vm.load(address(ct1), bytes32(uint256(2))), bytes32(uint256(0))); // allowance slot

        assertEq(
            vm.load(address(ct0), bytes32(uint256(3))),
            bytes32(uint256(uint256(1 << 160) + uint160(address(token0))))
        ); // underlying token + initialized
        assertEq(
            vm.load(address(ct1), bytes32(uint256(3))),
            bytes32(uint256(uint256(1 << 160) + uint160(address(token1))))
        ); // underlying token + initialized

        assertEq(
            vm.load(address(ct0), bytes32(uint256(4))),
            bytes32(uint256(uint160(address(token0))))
        ); // token0
        assertEq(
            vm.load(address(ct1), bytes32(uint256(4))),
            bytes32(uint256(uint160(address(token0))))
        ); // token0

        assertEq(
            vm.load(address(ct0), bytes32(uint256(5))),
            bytes32(uint256(uint256(1 << 160) + uint160(address(token1))))
        ); // token1 + underlyingistoken0

        assertEq(
            vm.load(address(ct1), bytes32(uint256(5))),
            bytes32(uint256(uint160(address(token1))))
        ); // token1 + underlyingistoken0

        assertEq(
            vm.load(address(ct0), bytes32(uint256(6))),
            bytes32(uint256(uint160(address(pp))))
        ); // pool

        assertEq(
            vm.load(address(ct1), bytes32(uint256(6))),
            bytes32(uint256(uint160(address(pp))))
        ); // pool

        assertEq(vm.load(address(ct0), bytes32(uint256(7))), bytes32(uint256(1))); // poolAssets + inAMM

        assertEq(vm.load(address(ct1), bytes32(uint256(7))), bytes32(uint256(1))); // poolAssets + inAMM

        assertEq(
            vm.load(address(ct0), bytes32(uint256(8))),
            bytes32(uint256((2 * uint256(fee)) / 100 + (uint256(fee / 100) << 128)))
        ); // ITMSpreadFee + poolFee

        assertEq(
            vm.load(address(ct1), bytes32(uint256(8))),
            bytes32(uint256((2 * uint256(fee)) / 100 + (uint256(fee / 100) << 128)))
        ); // ITMSpreadFee + poolFee

        assertEq(vm.load(address(ct0), bytes32(uint256(9))), bytes32(uint256(0))); // 0

        assertEq(vm.load(address(ct1), bytes32(uint256(9))), bytes32(uint256(0))); // 0
    }

    /*//////////////////////////////////////////////////////////////
                             STATIC QUERIES
    //////////////////////////////////////////////////////////////*/

    function test_Success_assertPriceWithinBounds(
        uint256 x,
        uint256 sqrtPriceX96,
        uint256 sqrtPriceX96Lower,
        uint256 sqrtPriceX96Upper
    ) public {
        sqrtPriceX96 = bound(
            sqrtPriceX96,
            TickMath.MIN_SQRT_RATIO + 1,
            TickMath.MAX_SQRT_RATIO - 1
        );
        sqrtPriceX96Lower = bound(sqrtPriceX96Lower, TickMath.MIN_SQRT_RATIO, sqrtPriceX96 - 1);
        sqrtPriceX96Upper = bound(sqrtPriceX96Upper, sqrtPriceX96 + 1, TickMath.MAX_SQRT_RATIO);

        _initWorldAtPrice(x, 0, uint160(sqrtPriceX96));
        pp.assertPriceWithinBounds(uint160(sqrtPriceX96Lower), uint160(sqrtPriceX96Upper));
    }

    function test_Fail_assertPriceWithinBounds(
        uint256 x,
        uint256 sqrtPriceX96,
        uint256 sqrtPriceX96Lower,
        uint256 sqrtPriceX96Upper
    ) public {
        sqrtPriceX96 = bound(sqrtPriceX96, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO);
        sqrtPriceX96Lower = bound(
            sqrtPriceX96Lower,
            TickMath.MIN_SQRT_RATIO,
            TickMath.MAX_SQRT_RATIO
        );
        sqrtPriceX96Upper = bound(
            sqrtPriceX96Upper,
            TickMath.MIN_SQRT_RATIO,
            TickMath.MAX_SQRT_RATIO
        );

        vm.assume(sqrtPriceX96 <= sqrtPriceX96Lower || sqrtPriceX96 >= sqrtPriceX96Upper);
        _initWorldAtPrice(x, 0, uint160(sqrtPriceX96));
        vm.expectRevert(Errors.PriceBoundFail.selector);
        pp.assertPriceWithinBounds(uint160(sqrtPriceX96Lower), uint160(sqrtPriceX96Upper));
    }

    /// forge-config: default.fuzz.runs = 10
    function test_Success_calculateAccumulatedFeesBatch_2xOTMShortCall(
        uint256 x,
        uint256[2] memory widthSeeds,
        int256[2] memory strikeSeeds,
        uint256[2] memory positionSizeSeeds,
        uint256 swapSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeeds[0],
            strikeSeeds[0],
            uint24(tickSpacing),
            currentTick,
            0
        );

        (int24 width2, int24 strike2) = PositionUtils.getOTMSW(
            widthSeeds[1],
            strikeSeeds[1],
            uint24(tickSpacing),
            currentTick,
            0
        );
        vm.assume(width2 != width || strike2 != strike);

        populatePositionData([width, width2], [strike, strike2], positionSizeSeeds);

        // leg 1
        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        // leg 2
        TokenId tokenId2 = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike2,
            width2
        );

        {
            TokenId[] memory posIdList = new TokenId[](1);
            posIdList[0] = tokenId;

            pp.mintOptions(posIdList, positionSizes[0], 0, 0, 0);
        }

        LeftRightSigned poolUtilizationsAtMint;
        {
            (, , int256 currentPoolUtilization) = ct0.getPoolData();
            poolUtilizationsAtMint = LeftRightSigned.wrap(0).toRightSlot(
                int128(currentPoolUtilization)
            );
        }

        {
            (, , int256 currentPoolUtilization) = ct1.getPoolData();
            poolUtilizationsAtMint = poolUtilizationsAtMint.toLeftSlot(
                int128(currentPoolUtilization)
            );
        }

        {
            TokenId[] memory posIdList = new TokenId[](2);
            posIdList[0] = tokenId;
            posIdList[1] = tokenId2;

            pp.mintOptions(posIdList, positionSizes[1], 0, 0, 0);

            twoWaySwap(swapSizeSeed);
        }

        uint256[2] memory expectedPremia;
        {
            (uint256 premiumToken0, uint256 premiumToken1) = sfpm.getAccountPremium(
                address(pool),
                address(pp),
                0,
                tickLowers[0],
                tickUppers[0],
                currentTick,
                0
            );

            expectedPremia[0] += (premiumToken0 * expectedLiqs[0]) / 2 ** 64;

            expectedPremia[1] += (premiumToken1 * expectedLiqs[0]) / 2 ** 64;
        }

        {
            (uint256 premiumToken0, uint256 premiumToken1) = sfpm.getAccountPremium(
                address(pool),
                address(pp),
                0,
                tickLowers[1],
                tickUppers[1],
                currentTick,
                0
            );

            expectedPremia[0] += (premiumToken0 * expectedLiqs[1]) / 2 ** 64;

            expectedPremia[1] += (premiumToken1 * expectedLiqs[1]) / 2 ** 64;
        }

        {
            TokenId[] memory posIdList = new TokenId[](2);
            posIdList[0] = tokenId;
            posIdList[1] = tokenId2;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = pp
                .calculateAccumulatedFeesBatch(Alice, false, posIdList);
            assertEq(uint128(premium0), expectedPremia[0]);
            assertEq(uint128(premium1), expectedPremia[1]);
            assertEq(posBalanceArray[0][0], TokenId.unwrap(tokenId));
            assertEq(LeftRightUnsigned.wrap(posBalanceArray[0][1]).rightSlot(), positionSizes[0]);
            assertEq(LeftRightUnsigned.wrap(posBalanceArray[0][1]).leftSlot(), 0);
            assertEq(posBalanceArray[1][0], TokenId.unwrap(tokenId2));
            assertEq(LeftRightUnsigned.wrap(posBalanceArray[1][1]).rightSlot(), positionSizes[1]);
            assertEq(
                LeftRightUnsigned.wrap(posBalanceArray[1][1]).leftSlot(),
                uint128(poolUtilizationsAtMint.rightSlot()) +
                    (uint128(poolUtilizationsAtMint.leftSlot()) << 64)
            );
        }
    }

    function test_Success_calculateAccumulatedFeesBatch_VeryLargePremia(
        uint256 x,
        uint256 positionSizeSeed,
        uint256[2] memory premiaSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getMinWidthInRangeSW(
            uint24(tickSpacing),
            currentTick
        );

        populatePositionDataLarge(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        pp.mintOptions(posIdList, positionSize, 0, 0, 0);

        premiaSeed[0] = bound(premiaSeed[0], 2 ** 64, 2 ** 120);
        premiaSeed[1] = bound(premiaSeed[1], 2 ** 64, 2 ** 120);

        (int256 premium0Before, int256 premium1Before, ) = pp.calculateAccumulatedFeesBatch(
            Alice,
            true,
            posIdList
        );

        accruePoolFeesInRange(address(pool), expectedLiq, premiaSeed[0], premiaSeed[1]);

        vm.startPrank(address(sfpm));
        pool.burn(tickLower, tickUpper, 0);

        (int256 premium0, int256 premium1, ) = pp.calculateAccumulatedFeesBatch(
            Alice,
            false,
            posIdList
        );

        // we have not settled any accrued premium yet, so the calculated amount (excluding pending premium) should be 0
        assertEq(premium0, 0);
        assertEq(premium1, 0);

        // if we include pending premium, the amount should be the same as the accrued premium
        (premium0, premium1, ) = pp.calculateAccumulatedFeesBatch(Alice, true, posIdList);

        assertApproxEqAbs(
            uint256(premium0 - premium0Before),
            premiaSeed[0],
            premiaSeed[0] / 1_000_000
        );
        assertApproxEqAbs(
            uint256(premium1 - premium1Before),
            premiaSeed[1],
            premiaSeed[1] / 1_000_000
        );
    }

    function test_Success_calculatePortfolioValue_2xOTMShortCall(
        uint256 x,
        uint256[2] memory widthSeeds,
        int256[2] memory strikeSeeds,
        uint256[2] memory positionSizeSeeds
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeeds[0],
            strikeSeeds[0],
            uint24(tickSpacing),
            currentTick,
            0
        );

        (int24 width2, int24 strike2) = PositionUtils.getOTMSW(
            widthSeeds[1],
            strikeSeeds[1],
            uint24(tickSpacing),
            currentTick,
            0
        );
        vm.assume(width2 != width || strike2 != strike);

        populatePositionData([width, width2], [strike, strike2], positionSizeSeeds);

        // leg 1
        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        // leg 2
        TokenId tokenId2 = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike2,
            width2
        );

        {
            TokenId[] memory posIdList = new TokenId[](1);
            posIdList[0] = tokenId;

            pp.mintOptions(posIdList, positionSizes[0], 0, 0, 0);
        }

        {
            TokenId[] memory posIdList = new TokenId[](2);
            posIdList[0] = tokenId;
            posIdList[1] = tokenId2;

            pp.mintOptions(posIdList, positionSizes[1], 0, 0, 0);

            userBalance[tokenId] = LeftRightUnsigned.wrap(0).toRightSlot(positionSizes[0]);
            userBalance[tokenId2] = LeftRightUnsigned.wrap(0).toRightSlot(positionSizes[1]);

            (int256 value0, int256 value1) = FeesCalc.getPortfolioValue(
                currentTick,
                userBalance,
                posIdList
            );

            (int256 calcValue0, int256 calcValue1) = pp.calculatePortfolioValue(
                Alice,
                currentTick,
                posIdList
            );

            assertEq(uint256(value0), uint256(calcValue0));
            assertEq(uint256(value1), uint256(calcValue1));
        }
    }

    /*//////////////////////////////////////////////////////////////
                     SLIPPAGE/EFFECTIVE LIQ LIMITS
    //////////////////////////////////////////////////////////////*/

    function test_Success_mintOptions_OTMShortCall_NoLiquidityLimit(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        vm.startPrank(Bob);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        // mint option from another account to change the effective liquidity
        pp.mintOptions(posIdList, positionSize * 2, 0, 0, 0);

        vm.startPrank(Alice);

        tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, isWETH, 1, 0, 0, strike, width);
        posIdList[0] = tokenId;

        uint256 sharesToBurn;
        {
            (LeftRightSigned longAmounts, ) = PanopticMath.computeExercisedAmounts(
                tokenId,
                uint128(positionSize)
            );

            sharesToBurn = Math.mulDivRoundingUp(
                uint128((longAmounts.rightSlot() * 10) / 10000),
                ct0.totalSupply(),
                ct0.totalAssets()
            );
        }

        // type(uint64).max = no limit, ensure the operation works given the changed liquidity limit
        pp.mintOptions(posIdList, positionSize, type(uint64).max, 0, 0);

        assertEq(
            sfpm.balanceOf(address(pp), TokenId.unwrap(tokenId)),
            positionSize,
            "panoptic pool balance"
        );

        uint256 amount0 = LiquidityAmounts.getAmount0ForLiquidity(
            sqrtLower,
            sqrtUpper,
            expectedLiq
        );

        {
            (, uint256 inAMM, ) = ct0.getPoolData();
            assertApproxEqAbs(inAMM, amount0, 10, "in AMM 0");
        }

        {
            (, uint256 inAMM, ) = ct1.getPoolData();
            assertEq(inAMM, 0, "in AMM 1");
        }

        {
            assertEq(
                pp.positionsHash(Alice),
                uint248(uint256(keccak256(abi.encodePacked(tokenId))))
            );
            assertEq(pp.numberOfPositions(Alice), 1);

            (uint128 balance, uint64 poolUtilization0, uint64 poolUtilization1) = pp
                .optionPositionBalance(Alice, tokenId);

            assertEq(balance, positionSize, "balance | position size");

            (, uint256 inAMM0, ) = ct0.getPoolData();

            assertEq(poolUtilization0, (inAMM0 * 10000) / ct0.totalSupply());
            assertEq(poolUtilization1, 0);
        }

        {
            assertApproxEqAbs(
                ct0.balanceOf(Alice),
                uint256(type(uint104).max - sharesToBurn),
                10,
                "alice balance ct0"
            );

            assertEq(ct1.balanceOf(Alice), uint256(type(uint104).max), "alice balance ct1");
        }
    }

    function test_Success_mintOptions_OTMShortCall_LiquidityLimit(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        vm.startPrank(Bob);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;
        // mint option from another account to change the effective liquidity
        pp.mintOptions(posIdList, positionSize * 2, 0, 0, 0);

        vm.startPrank(Alice);

        tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, isWETH, 1, 0, 0, strike, width);
        posIdList[0] = tokenId;

        uint256 sharesToBurn;
        {
            (LeftRightSigned longAmounts, ) = PanopticMath.computeExercisedAmounts(
                tokenId,
                uint128(positionSize)
            );

            sharesToBurn = Math.mulDivRoundingUp(
                uint128((longAmounts.rightSlot() * 10) / 10000),
                ct0.totalSupply(),
                ct0.totalAssets()
            );
        }

        // type(uint64).max = no limit, ensure the operation works given the changed liquidity limit
        pp.mintOptions(posIdList, positionSize, type(uint64).max - 1, 0, 0);

        assertEq(sfpm.balanceOf(address(pp), TokenId.unwrap(tokenId)), positionSize);

        uint256 amount0 = LiquidityAmounts.getAmount0ForLiquidity(
            sqrtLower,
            sqrtUpper,
            expectedLiq
        );

        {
            (, uint256 inAMM, ) = ct0.getPoolData();
            assertApproxEqAbs(inAMM, amount0, 10);
        }

        {
            (, uint256 inAMM, ) = ct1.getPoolData();
            assertEq(inAMM, 0);
        }

        {
            assertEq(
                pp.positionsHash(Alice),
                uint248(uint256(keccak256(abi.encodePacked(tokenId))))
            );

            assertEq(pp.numberOfPositions(Alice), 1);

            (uint128 balance, uint64 poolUtilization0, uint64 poolUtilization1) = pp
                .optionPositionBalance(Alice, tokenId);

            assertEq(balance, positionSize);

            (, uint256 inAMM0, ) = ct0.getPoolData();

            assertEq(poolUtilization0, (inAMM0 * 10000) / ct0.totalSupply());

            assertEq(poolUtilization1, 0);
        }

        {
            assertApproxEqAbs(ct0.balanceOf(Alice), uint256(type(uint104).max) - sharesToBurn, 10);
            assertEq(ct1.balanceOf(Alice), uint256(type(uint104).max));
        }
    }

    function test_Fail_mintOptions_OTMShortCall_EffectiveLiquidityAboveThreshold(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        vm.startPrank(Bob);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        pp.mintOptions(posIdList, positionSize * 2, 0, 0, 0);

        vm.startPrank(Alice);

        tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, isWETH, 1, 0, 0, strike, width);
        posIdList[0] = tokenId;

        vm.expectRevert(Errors.EffectiveLiquidityAboveThreshold.selector);
        pp.mintOptions(posIdList, positionSize, 0, 0, 0);
    }

    function test_Success_mintOptions_OTMShortCall_SlippageSet(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        pp.mintOptions(posIdList, positionSize, 0, TickMath.MIN_TICK, TickMath.MAX_TICK);

        assertEq(sfpm.balanceOf(address(pp), TokenId.unwrap(tokenId)), positionSize);

        uint256 amount0 = LiquidityAmounts.getAmount0ForLiquidity(
            sqrtLower,
            sqrtUpper,
            expectedLiq
        );

        {
            (, uint256 inAMM, ) = ct0.getPoolData();
            assertApproxEqAbs(inAMM, amount0, 10);
        }

        {
            (, uint256 inAMM, ) = ct1.getPoolData();
            assertEq(inAMM, 0);
        }
        {
            assertEq(
                pp.positionsHash(Alice),
                uint248(uint256(keccak256(abi.encodePacked(tokenId))))
            );

            assertEq(pp.numberOfPositions(Alice), 1);

            (uint128 balance, uint64 poolUtilization0, uint64 poolUtilization1) = pp
                .optionPositionBalance(Alice, tokenId);

            assertEq(balance, positionSize);
            assertEq(poolUtilization0, (amount0 * 10000) / ct0.totalSupply());
            assertEq(poolUtilization1, 0);
        }

        {
            (, LeftRightSigned shortAmounts) = PanopticMath.computeExercisedAmounts(
                tokenId,
                uint128(positionSize)
            );

            assertApproxEqAbs(
                ct0.balanceOf(Alice),
                uint256(type(uint104).max) - uint128((shortAmounts.rightSlot() * 10) / 10000),
                uint256(int256(shortAmounts.rightSlot()) / 1_000_000 + 10)
            );

            assertEq(ct1.balanceOf(Alice), uint256(type(uint104).max));
        }
    }

    /*//////////////////////////////////////////////////////////////
                             OPTION MINTING
    //////////////////////////////////////////////////////////////*/

    function test_Success_mintOptions_OTMShortCall(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        pp.mintOptions(posIdList, positionSize, 0, 0, 0);

        assertEq(sfpm.balanceOf(address(pp), TokenId.unwrap(tokenId)), positionSize);

        uint256 amount0 = LiquidityAmounts.getAmount0ForLiquidity(
            sqrtLower,
            sqrtUpper,
            expectedLiq
        );

        {
            (, uint256 inAMM, ) = ct0.getPoolData();
            assertApproxEqAbs(inAMM, amount0, 10, "inAMM 0");
        }

        {
            (, uint256 inAMM, ) = ct1.getPoolData();
            assertEq(inAMM, 0, "inAMM 1");
        }
        {
            assertEq(
                pp.positionsHash(Alice),
                uint248(uint256(keccak256(abi.encodePacked(tokenId))))
            );

            assertEq(pp.numberOfPositions(Alice), 1);

            (uint128 balance, uint64 poolUtilization0, uint64 poolUtilization1) = pp
                .optionPositionBalance(Alice, tokenId);

            assertEq(balance, positionSize, "user balance");
            assertEq(poolUtilization0, (amount0 * 10000) / ct0.totalSupply(), "pu 0");
            assertEq(poolUtilization1, 0, "pu 1");
        }

        {
            (, LeftRightSigned shortAmounts) = PanopticMath.computeExercisedAmounts(
                tokenId,
                uint128(positionSize)
            );

            assertApproxEqAbs(
                ct0.balanceOf(Alice),
                uint256(type(uint104).max) - uint128((shortAmounts.rightSlot() * 10) / 10000),
                uint256(int256(shortAmounts.rightSlot()) / 1_000_000 + 10),
                "alice balance 0"
            );

            assertEq(ct1.balanceOf(Alice), uint256(type(uint104).max), "alice balance 1");
        }
    }

    function test_Success_mintOptions_OTMShortPut(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            1
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            1,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        pp.mintOptions(posIdList, positionSize, 0, 0, 0);

        assertEq(sfpm.balanceOf(address(pp), TokenId.unwrap(tokenId)), positionSize);

        uint256 amount1 = LiquidityAmounts.getAmount1ForLiquidity(
            sqrtLower,
            sqrtUpper,
            expectedLiq
        );

        {
            (, uint256 inAMM, ) = ct1.getPoolData();

            // there are some inevitable precision errors that occur when
            // converting between contract sizes and liquidity - ~.01 basis points error is acceptable
            assertApproxEqAbs(inAMM, amount1, amount1 / 1_000_000);
        }

        {
            (, uint256 inAMM, ) = ct0.getPoolData();
            assertEq(inAMM, 0);
        }

        {
            assertEq(
                pp.positionsHash(Alice),
                uint248(uint256(keccak256(abi.encodePacked(tokenId))))
            );

            assertEq(pp.numberOfPositions(Alice), 1);

            (uint128 balance, uint64 poolUtilization0, uint64 poolUtilization1) = pp
                .optionPositionBalance(Alice, tokenId);

            assertEq(balance, positionSize);
            assertEq(poolUtilization1, (amount1 * 10000) / ct1.totalSupply());
            assertEq(poolUtilization0, 0);
        }

        {
            (, LeftRightSigned shortAmounts) = PanopticMath.computeExercisedAmounts(
                tokenId,
                positionSize
            );

            assertApproxEqAbs(
                ct1.balanceOf(Alice),
                uint256(type(uint104).max) - uint128((shortAmounts.leftSlot() * 10) / 10000),
                uint256(int256(shortAmounts.leftSlot()) / 1_000_000 + 10)
            );

            assertEq(ct0.balanceOf(Alice), uint256(type(uint104).max));
        }
    }

    function test_Success_mintOptions_ITMShortCall(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getITMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        uint256 expectedSwap0;
        {
            int256 amount1Required = SqrtPriceMath.getAmount1Delta(
                sqrtLower,
                sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
                int128(expectedLiq)
            );

            (expectedSwap0, ) = PositionUtils.simulateSwap(
                pool,
                tickLower,
                tickUpper,
                expectedLiq,
                router,
                token0,
                token1,
                fee,
                true,
                -amount1Required
            );

            vm.startPrank(Alice);
        }

        {
            TokenId[] memory posIdList = new TokenId[](1);
            posIdList[0] = tokenId;

            // reversing the tick limits here to make sure they get entered into the SFPM properly
            // this test will fail if it does not (because no ITM swaps will occur)
            pp.mintOptions(posIdList, positionSize, 0, TickMath.MAX_TICK, TickMath.MIN_TICK);
        }

        assertEq(sfpm.balanceOf(address(pp), TokenId.unwrap(tokenId)), positionSize);

        uint256 amount0 = LiquidityAmounts.getAmount0ForLiquidity(
            sqrtLower,
            sqrtUpper,
            expectedLiq
        );

        {
            (, uint256 inAMM, ) = ct0.getPoolData();
            assertApproxEqAbs(inAMM, amount0, 10, "inAMM0");
        }

        {
            (, uint256 inAMM, ) = ct1.getPoolData();
            assertEq(inAMM, 0, "inAMM1");
        }
        {
            assertEq(
                pp.positionsHash(Alice),
                uint248(uint256(keccak256(abi.encodePacked(tokenId))))
            );

            assertEq(pp.numberOfPositions(Alice), 1);

            (uint128 balance, uint64 poolUtilization0, uint64 poolUtilization1) = pp
                .optionPositionBalance(Alice, tokenId);

            assertEq(balance, positionSize, "balance");
            assertEq(poolUtilization0, (amount0 * 10000) / ct0.totalSupply(), "utilization 1");
            assertEq(poolUtilization1, 0, "utilization 0");
        }

        {
            (, LeftRightSigned shortAmounts) = PanopticMath.computeExercisedAmounts(
                tokenId,
                positionSize
            );

            int256 amount0Moved = currentSqrtPriceX96 > sqrtUpper
                ? int256(0)
                : SqrtPriceMath.getAmount0Delta(
                    currentSqrtPriceX96 < sqrtLower ? sqrtLower : currentSqrtPriceX96,
                    sqrtUpper,
                    int128(expectedLiq)
                );

            int256 notionalVal = int256(expectedSwap0) + amount0Moved - shortAmounts.rightSlot();

            int256 ITMSpread = notionalVal > 0
                ? (notionalVal * int24(2 * (fee / 100))) / 10_000
                : -(notionalVal * int24(2 * (fee / 100))) / 10_000;

            assertApproxEqAbs(
                ct0.balanceOf(Alice),
                uint256(
                    int256(uint256(type(uint104).max)) -
                        notionalVal -
                        ITMSpread -
                        (shortAmounts.rightSlot() * 10) /
                        10_000
                ),
                uint256(int256(shortAmounts.rightSlot()) / 1_000_000 + 10),
                "alice balance 0"
            );

            assertEq(ct1.balanceOf(Alice), uint256(type(uint104).max), "alice balance 1");
        }
    }

    function test_Success_mintOptions_ITMShortPutShortCall(
        uint256 x,
        uint256[2] memory widthSeeds,
        int256[2] memory strikeSeeds,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width0, int24 strike0) = PositionUtils.getITMSW(
            widthSeeds[0],
            strikeSeeds[0],
            uint24(tickSpacing),
            currentTick,
            1
        );

        (int24 width1, int24 strike1) = PositionUtils.getITMSW(
            widthSeeds[1],
            strikeSeeds[1],
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData([width0, width1], [strike0, strike1], positionSizeSeed);

        // put leg
        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            1,
            0,
            strike0,
            width0
        );
        // call leg
        tokenId = tokenId.addLeg(1, 1, isWETH, 0, 0, 1, strike1, width1);

        int256 netSurplus0 = $amount0Moveds[0] -
            PanopticMath.convert1to0($amount1Moveds[1], currentSqrtPriceX96);

        (int256 amount0s, int256 amount1s) = PositionUtils.simulateSwap(
            pool,
            [tickLowers[0], tickLowers[1]],
            [tickUppers[0], tickUppers[1]],
            [expectedLiqs[0], expectedLiqs[1]],
            router,
            token0,
            token1,
            fee,
            netSurplus0 < 0,
            -netSurplus0
        );

        vm.startPrank(Alice);

        (, LeftRightSigned shortAmounts) = PanopticMath.computeExercisedAmounts(
            tokenId,
            positionSize
        );

        {
            TokenId[] memory posIdList = new TokenId[](1);
            posIdList[0] = tokenId;

            pp.mintOptions(posIdList, positionSize, 0, 0, 0);
        }
        (, currentTick, observationIndex, observationCardinality, , , ) = pool.slot0();

        fastOracleTick = PanopticMath.computeMedianObservedPrice(
            pool,
            observationIndex,
            observationCardinality,
            3,
            1
        );

        (slowOracleTick, ) = PanopticMath.computeInternalMedian(
            observationIndex,
            observationCardinality,
            60,
            pp.miniMedian(),
            pool
        );

        assertEq(sfpm.balanceOf(address(pp), TokenId.unwrap(tokenId)), positionSize);

        {
            (, uint256 inAMM, ) = ct0.getPoolData();
            assertApproxEqAbs(inAMM, uint128(shortAmounts.rightSlot()), 10);
        }

        {
            (, uint256 inAMM, ) = ct1.getPoolData();
            assertApproxEqAbs(inAMM, uint128(shortAmounts.leftSlot()), 10);
        }

        {
            assertEq(
                pp.positionsHash(Alice),
                uint248(uint256(keccak256(abi.encodePacked(tokenId))))
            );

            assertEq(pp.numberOfPositions(Alice), 1);

            (uint128 balance, uint64 poolUtilization0, uint64 poolUtilization1) = pp
                .optionPositionBalance(Alice, tokenId);

            assertEq(balance, positionSize);
            assertEq(
                poolUtilization0,
                Math.abs(fastOracleTick - slowOracleTick) > int24(2230)
                    ? 10_001
                    : (uint256($amount0Moveds[0] + $amount0Moveds[1]) * 10000) / ct0.totalSupply()
            );
            assertEq(
                poolUtilization1,
                Math.abs(fastOracleTick - slowOracleTick) > int24(2230)
                    ? 10_001
                    : (uint256($amount1Moveds[0] + $amount1Moveds[1]) * 10000) / ct1.totalSupply()
            );
        }

        {
            int256[2] memory notionalVals = [
                amount0s + $amount0Moveds[0] + $amount0Moveds[1] - shortAmounts.rightSlot(),
                amount1s + $amount1Moveds[0] + $amount1Moveds[1] - shortAmounts.leftSlot()
            ];
            int256[2] memory ITMSpreads = [
                notionalVals[0] > 0
                    ? (notionalVals[0] * int24(2 * (fee / 100))) / 10_000
                    : -((notionalVals[0] * int24(2 * (fee / 100))) / 10_000),
                notionalVals[1] > 0
                    ? (notionalVals[1] * int24(2 * (fee / 100))) / 10_000
                    : -((notionalVals[1] * int24(2 * (fee / 100))) / 10_000)
            ];

            assertApproxEqAbs(
                ct0.balanceOf(Alice),
                uint256(
                    int256(uint256(type(uint104).max)) -
                        notionalVals[0] -
                        ITMSpreads[0] -
                        (shortAmounts.rightSlot() * 10) /
                        10_000
                ),
                uint256(int256(shortAmounts.rightSlot()) / 1_000_000 + 10)
            );

            assertApproxEqAbs(
                ct1.balanceOf(Alice),
                uint256(
                    int256(uint256(type(uint104).max)) -
                        notionalVals[1] -
                        ITMSpreads[1] -
                        (shortAmounts.leftSlot() * 10) /
                        10_000
                ),
                uint256(int256(shortAmounts.leftSlot()) / 1_000_000 + 10)
            );
        }
    }

    function test_Success_mintOptions_ITMShortPutLongCall(
        uint256 x,
        uint256[2] memory widthSeeds,
        int256[2] memory strikeSeeds,
        uint256[2] memory positionSizeSeeds
    ) public {
        _initPool(x);

        (int24 width0, int24 strike0) = PositionUtils.getITMSW(
            widthSeeds[0],
            strikeSeeds[0],
            uint24(tickSpacing),
            currentTick,
            1
        );

        (int24 width1, int24 strike1) = PositionUtils.getITMSW(
            widthSeeds[1],
            strikeSeeds[1],
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionDataLong([width0, width1], [strike0, strike1], positionSizeSeeds);

        // sell short companion to long option
        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike1,
            width1
        );

        (, LeftRightSigned shortAmountsSold) = PanopticMath.computeExercisedAmounts(
            tokenId,
            positionSizes[0]
        );

        vm.startPrank(Seller);

        {
            TokenId[] memory posIdList = new TokenId[](1);
            posIdList[0] = tokenId;

            pp.mintOptions(posIdList, positionSizes[0], 0, 0, 0);
        }

        // put leg
        tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, isWETH, 0, 1, 0, strike0, width0);
        // call leg (long)
        tokenId = tokenId.addLeg(1, 1, isWETH, 1, 0, 1, strike1, width1);

        // price changes afters swap at mint so we need to update the price
        (currentSqrtPriceX96, currentTick, observationIndex, observationCardinality, , , ) = pool
            .slot0();

        fastOracleTick = PanopticMath.computeMedianObservedPrice(
            pool,
            observationIndex,
            observationCardinality,
            3,
            1
        );

        (slowOracleTick, ) = PanopticMath.computeInternalMedian(
            observationIndex,
            observationCardinality,
            60,
            pp.miniMedian(),
            pool
        );

        updatePositionDataLong();

        int256 netSurplus0 = $amount0Moveds[1] -
            PanopticMath.convert1to0($amount1Moveds[2], currentSqrtPriceX96);

        vm.startPrank(address(sfpm));
        (int256 amount0s, int256 amount1s) = PositionUtils.simulateSwapLong(
            pool,
            [tickLowers[0], tickLowers[1]],
            [tickUppers[0], tickUppers[1]],
            [int128(expectedLiqs[1]), -int128(expectedLiqs[2])],
            router,
            token0,
            token1,
            fee,
            netSurplus0 < 0,
            -netSurplus0
        );

        vm.startPrank(Alice);

        (LeftRightSigned longAmounts, LeftRightSigned shortAmounts) = PanopticMath
            .computeExercisedAmounts(tokenId, positionSizes[1]);

        uint256 sharesToBurn;
        int256[2] memory notionalVals;
        int256[2] memory ITMSpreads;
        {
            notionalVals = [
                amount0s +
                    $amount0Moveds[1] +
                    $amount0Moveds[2] -
                    shortAmounts.rightSlot() +
                    longAmounts.rightSlot(),
                amount1s + $amount1Moveds[1] + $amount1Moveds[2] - shortAmounts.leftSlot()
            ];

            ITMSpreads = [
                notionalVals[0] > 0
                    ? (notionalVals[0] * int24(2 * (fee / 100))) / 10_000
                    : -((notionalVals[0] * int24(2 * (fee / 100))) / 10_000),
                notionalVals[1] > 0
                    ? (notionalVals[1] * int24(2 * (fee / 100))) / 10_000
                    : -((notionalVals[1] * int24(2 * (fee / 100))) / 10_000)
            ];

            uint256 tokenToPay = uint256(
                notionalVals[0] +
                    ITMSpreads[0] +
                    ((shortAmounts.rightSlot() + longAmounts.rightSlot()) * 10) /
                    10_000
            );

            sharesToBurn = Math.mulDivRoundingUp(tokenToPay, ct0.totalSupply(), ct0.totalAssets());
        }

        {
            TokenId[] memory posIdList = new TokenId[](1);
            posIdList[0] = tokenId;

            pp.mintOptions(posIdList, positionSizes[1], type(uint64).max, 0, 0);
        }

        // price changes afters swap at mint so we need to update the price
        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();

        assertEq(sfpm.balanceOf(address(pp), TokenId.unwrap(tokenId)), positionSizes[1]);

        {
            (, uint256 inAMM, ) = ct0.getPoolData();
            assertApproxEqAbs(
                inAMM,
                uint128(shortAmountsSold.rightSlot() - longAmounts.rightSlot()),
                10
            );
        }

        {
            (, uint256 inAMM, ) = ct1.getPoolData();
            assertApproxEqAbs(inAMM, uint128(shortAmounts.leftSlot()), 10);
        }

        {
            assertEq(
                pp.positionsHash(Alice),
                uint248(uint256(keccak256(abi.encodePacked(tokenId))))
            );

            assertEq(pp.numberOfPositions(Alice), 1);

            (uint128 balance, uint64 poolUtilization0, uint64 poolUtilization1) = pp
                .optionPositionBalance(Alice, tokenId);

            assertEq(balance, positionSizes[1]);
            assertEq(
                int64(poolUtilization0),
                Math.abs(fastOracleTick - slowOracleTick) > int24(2230)
                    ? int64(10_001)
                    : ($amount0Moveds[0] + $amount0Moveds[1] + $amount0Moveds[2] * 10000) /
                        int256(ct0.totalSupply())
            );
            assertEq(
                int64(poolUtilization1),
                Math.abs(fastOracleTick - slowOracleTick) > int24(2230)
                    ? int64(10_001)
                    : ($amount1Moveds[0] + $amount1Moveds[1] + $amount1Moveds[2] * 10000) /
                        int256(ct1.totalSupply())
            );
        }

        {
            assertApproxEqAbs(
                ct1.balanceOf(Alice),
                uint256(
                    int256(uint256(type(uint104).max)) -
                        notionalVals[1] -
                        ITMSpreads[1] -
                        (shortAmounts.leftSlot() * 10) /
                        10_000
                ),
                uint256(int256(shortAmounts.leftSlot()) / 1_000_000 + 10),
                "Alice balance 1"
            );
        }
    }

    function test_Fail_mintOptions_LowerPriceBoundFail(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        vm.expectRevert(Errors.PriceBoundFail.selector);
        pp.mintOptions(posIdList, positionSize, 0, TickMath.MAX_TICK - 1, TickMath.MAX_TICK);
    }

    function test_Fail_mintOptions_UpperPriceBoundFail(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        vm.expectRevert(Errors.PriceBoundFail.selector);
        pp.mintOptions(posIdList, positionSize, 0, TickMath.MIN_TICK, TickMath.MIN_TICK + 1);
    }

    function test_Fail_mintOptions_IncorrectPool(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId + 1).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTokenIdParameter.selector, 0));
        pp.mintOptions(posIdList, positionSize, 0, 0, 0);
    }

    function test_Fail_mintOptions_PositionAlreadyMinted(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            1
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            1,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        pp.mintOptions(posIdList, positionSize, 0, 0, 0);

        posIdList = new TokenId[](2);
        posIdList[0] = tokenId;
        posIdList[1] = tokenId;

        vm.expectRevert(Errors.PositionAlreadyMinted.selector);
        pp.mintOptions(posIdList, uint128(positionSize), 0, 0, 0);
    }

    function test_Fail_mintOptions_PositionSizeZero(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            1
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            1,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        vm.expectRevert(Errors.OptionsBalanceZero.selector);
        pp.mintOptions(posIdList, positionSize * 0, 0, 0, 0);
    }

    function test_Fail_mintOptions_OTMShortCall_NotEnoughCollateral(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        // deposit commission so we can reach collateral check
        (, LeftRightSigned shortAmounts) = PanopticMath.computeExercisedAmounts(
            tokenId,
            positionSize
        );

        vm.startPrank(Charlie);

        ct0.deposit(
            (uint128((shortAmounts.rightSlot() * 10) / 10000) * 10015) / 10000 + 4,
            Charlie
        );

        vm.expectRevert(Errors.NotEnoughCollateral.selector);
        pp.mintOptions(posIdList, uint128(positionSize), 0, 0, 0);
    }

    function test_Fail_mintOptions_TooManyPositionsOpen() public {
        _initPool(0);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            0,
            0,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, 0);

        uint248 positionsHash;
        for (uint256 i = 0; i < 33; i++) {
            tokenIds.push(
                TokenId.wrap(0).addPoolId(poolId).addLeg(
                    0,
                    i + 1, // increment the options ratio as an easy way to get unique tokenIds
                    isWETH,
                    0,
                    0,
                    0,
                    strike,
                    width
                )
            );
            if (i == 32) vm.expectRevert(Errors.TooManyPositionsOpen.selector);
            pp.mintOptions(tokenIds, positionSize, 0, 0, 0);

            if (i < 32) {
                positionsHash =
                    positionsHash ^
                    uint248(uint256(keccak256(abi.encodePacked(tokenIds[i]))));
                assertEq(pp.positionsHash(Alice), positionsHash);
                assertEq(pp.numberOfPositions(Alice), i + 1);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                             OPTION BURNING
    //////////////////////////////////////////////////////////////*/

    function test_Success_burnOptions_OTMShortCall_noPremia(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        pp.mintOptions(posIdList, positionSize, 0, 0, 0);
        pp.burnOptions(tokenId, emptyList, 0, 0);

        assertEq(sfpm.balanceOf(address(pp), TokenId.unwrap(tokenId)), 0);

        {
            (, uint256 inAMM, ) = ct0.getPoolData();
            assertEq(inAMM, 0);
        }

        {
            (, uint256 inAMM, ) = ct1.getPoolData();
            assertEq(inAMM, 0);
        }
        {
            assertEq(pp.positionsHash(Alice), 0);

            assertEq(pp.numberOfPositions(Alice), 0);

            (uint128 balance, uint64 poolUtilization0, uint64 poolUtilization1) = pp
                .optionPositionBalance(Alice, tokenId);

            assertEq(balance, 0);
            assertEq(poolUtilization0, 0);
            assertEq(poolUtilization1, 0);
        }

        {
            (, LeftRightSigned shortAmounts) = PanopticMath.computeExercisedAmounts(
                tokenId,
                positionSize
            );

            assertApproxEqAbs(
                ct0.balanceOf(Alice),
                (uint256(type(uint104).max) - uint128((shortAmounts.rightSlot() * 10) / 10000)),
                uint256(int256(shortAmounts.rightSlot()) / 1_000_000 + 10)
            );
            assertEq(ct1.balanceOf(Alice), uint256(type(uint104).max));
        }
    }

    function test_Success_burnOptions_ITMShortCall_noPremia(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getITMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        // take snapshot for swap simulation
        vm.snapshot();

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        int256[2] memory amount0Moveds;
        int256[2] memory amount1Moveds;

        amount0Moveds[0] = currentSqrtPriceX96 > sqrtUpper
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                currentSqrtPriceX96 < sqrtLower ? sqrtLower : currentSqrtPriceX96,
                sqrtUpper,
                int128(expectedLiq)
            );

        amount1Moveds[0] = -SqrtPriceMath.getAmount1Delta(
            sqrtLower,
            sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
            int128(expectedLiq)
        );

        {
            TokenId[] memory posIdList = new TokenId[](1);
            posIdList[0] = tokenId;

            pp.mintOptions(posIdList, positionSize, 0, 0, 0);
        }

        // poke uniswap pool to update tokens owed - needed because swap happens after mint
        vm.startPrank(address(sfpm));
        pool.burn(tickLower, tickUpper, 0);
        vm.startPrank(Alice);

        // calculate additional fees owed to position
        (, , , uint128 tokensOwed0, ) = pool.positions(
            PositionKey.compute(address(sfpm), tickLower, tickUpper)
        );

        // price changes afters swap at mint so we need to update the price
        (currentSqrtPriceX96, , , , , , ) = pool.slot0();

        amount0Moveds[1] = currentSqrtPriceX96 > sqrtUpper
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                currentSqrtPriceX96 < sqrtLower ? sqrtLower : currentSqrtPriceX96,
                sqrtUpper,
                int128(expectedLiq)
            );

        amount1Moveds[1] = SqrtPriceMath.getAmount1Delta(
            sqrtLower,
            sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
            int128(expectedLiq)
        );

        {
            pp.burnOptions(tokenId, emptyList, 0, 0);
        }
        assertEq(sfpm.balanceOf(address(pp), TokenId.unwrap(tokenId)), 0);

        {
            (, uint256 inAMM, ) = ct0.getPoolData();
            assertEq(inAMM, 0);
        }

        {
            (, uint256 inAMM, ) = ct1.getPoolData();
            assertEq(inAMM, 0);
        }
        {
            assertEq(pp.positionsHash(Alice), 0);
            assertEq(pp.numberOfPositions(Alice), 0);

            (uint128 balance, uint64 poolUtilization0, uint64 poolUtilization1) = pp
                .optionPositionBalance(Alice, tokenId);
            assertEq(balance, 0);
            assertEq(poolUtilization0, 0);
            assertEq(poolUtilization1, 0);
        }

        //snapshot balances and revert to old snapshot
        uint256[2] memory balanceBefores = [ct0.balanceOf(Alice), ct1.balanceOf(Alice)];

        vm.revertTo(0);

        (uint256[2] memory expectedSwaps, ) = PositionUtils.simulateSwap(
            pool,
            tickLower,
            tickUpper,
            expectedLiq,
            router,
            token0,
            token1,
            fee,
            [true, false],
            amount1Moveds
        );

        (, LeftRightSigned shortAmounts) = PanopticMath.computeExercisedAmounts(
            tokenId,
            uint128(positionSize)
        );

        int256[2] memory notionalVals = [
            int256(expectedSwaps[0]) + amount0Moveds[0] - shortAmounts.rightSlot(),
            -int256(expectedSwaps[1]) - amount0Moveds[1] + shortAmounts.rightSlot()
        ];

        int256 ITMSpread = notionalVals[0] > 0
            ? (notionalVals[0] * int24(2 * (fee / 100))) / 10_000
            : -((notionalVals[0] * int24(2 * (fee / 100))) / 10_000);

        assertApproxEqAbs(
            balanceBefores[0],
            uint256(
                int256(uint256(type(uint104).max)) -
                    ITMSpread -
                    notionalVals[0] -
                    notionalVals[1] -
                    (shortAmounts.rightSlot() * 10) /
                    10_000 +
                    int128(tokensOwed0)
            ),
            uint256(int256(shortAmounts.rightSlot()) / 1_000_000 + 10)
        );

        assertEq(balanceBefores[1], uint256(type(uint104).max));
    }

    function test_Success_burnOptions_ITMShortCall_premia_sufficientLocked(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed,
        uint256 swapSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getITMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        // take snapshot for swap simulation
        vm.snapshot();

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        int256[2] memory amount0Moveds;
        int256[2] memory amount1Moveds;

        amount0Moveds[0] = currentSqrtPriceX96 > sqrtUpper
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                currentSqrtPriceX96 < sqrtLower ? sqrtLower : currentSqrtPriceX96,
                sqrtUpper,
                int128(expectedLiq)
            );

        amount1Moveds[0] = -SqrtPriceMath.getAmount1Delta(
            sqrtLower,
            sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
            int128(expectedLiq)
        );

        {
            TokenId[] memory posIdList = new TokenId[](1);
            posIdList[0] = tokenId;

            pp.mintOptions(posIdList, positionSize, 0, 0, 0);
        }

        twoWaySwap(swapSizeSeed);

        // poke uniswap pool to update tokens owed - needed because swap happens after mint
        vm.startPrank(address(sfpm));
        pool.burn(tickLower, tickUpper, 0);
        vm.startPrank(Alice);

        // calculate additional fees owed to position
        (, , , uint128 tokensOwed0, uint128 tokensOwed1) = pool.positions(
            PositionKey.compute(address(sfpm), tickLower, tickUpper)
        );

        // price changes afters swap at mint so we need to update the price
        (currentSqrtPriceX96, , , , , , ) = pool.slot0();

        amount0Moveds[1] = currentSqrtPriceX96 > sqrtUpper
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                currentSqrtPriceX96 < sqrtLower ? sqrtLower : currentSqrtPriceX96,
                sqrtUpper,
                int128(expectedLiq)
            );

        amount1Moveds[1] = SqrtPriceMath.getAmount1Delta(
            sqrtLower,
            sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
            int128(expectedLiq)
        );
        {
            pp.burnOptions(tokenId, emptyList, 0, 0);
        }
        assertEq(sfpm.balanceOf(address(pp), TokenId.unwrap(tokenId)), 0);

        {
            (, uint256 inAMM, ) = ct0.getPoolData();
            assertEq(inAMM, 0);
        }

        {
            (, uint256 inAMM, ) = ct1.getPoolData();
            assertEq(inAMM, 0);
        }
        {
            assertEq(pp.positionsHash(Alice), 0);
            assertEq(pp.numberOfPositions(Alice), 0);

            (uint128 balance, uint64 poolUtilization0, uint64 poolUtilization1) = pp
                .optionPositionBalance(Alice, tokenId);
            assertEq(balance, 0);
            assertEq(poolUtilization0, 0);
            assertEq(poolUtilization1, 0);
        }

        //snapshot balances and revert to old snapshot
        uint256[2] memory balanceBefores = [ct0.balanceOf(Alice), ct1.balanceOf(Alice)];

        vm.revertTo(0);

        (uint256[2] memory expectedSwaps, ) = PositionUtils.simulateSwap(
            pool,
            tickLower,
            tickUpper,
            expectedLiq,
            router,
            token0,
            token1,
            fee,
            [true, false],
            amount1Moveds
        );

        (, LeftRightSigned shortAmounts) = PanopticMath.computeExercisedAmounts(
            tokenId,
            uint128(positionSize)
        );

        int256[2] memory notionalVals = [
            int256(expectedSwaps[0]) + amount0Moveds[0] - shortAmounts.rightSlot(),
            -int256(expectedSwaps[1]) - amount0Moveds[1] + shortAmounts.rightSlot()
        ];

        int256 ITMSpread = notionalVals[0] > 0
            ? (notionalVals[0] * int24(2 * (fee / 100))) / 10_000
            : -((notionalVals[0] * int24(2 * (fee / 100))) / 10_000);

        assertApproxEqAbs(
            balanceBefores[0],
            uint256(
                int256(uint256(type(uint104).max)) -
                    ITMSpread -
                    notionalVals[0] -
                    notionalVals[1] -
                    (shortAmounts.rightSlot() * 10) /
                    10_000 +
                    int128(tokensOwed0)
            ),
            uint256(int256(shortAmounts.rightSlot()) / 1_000_000 + 10)
        );

        assertApproxEqAbs(
            balanceBefores[1],
            uint256(type(uint104).max) + tokensOwed1,
            tokensOwed1 / 1_000_000 + 10
        );
    }

    // minting a long position to reduce the premium that can be paid
    function test_Success_burnOptions_ITMShortCall_premia_insufficientLocked(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed,
        uint256 swapSizeSeed,
        uint256 longPercentageSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getITMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        tokenIds.push(
            TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, isWETH, 0, 0, 0, strike, width)
        );

        tokenIds.push(
            TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, isWETH, 1, 0, 0, strike, width)
        );

        // take snapshot for swap simulation
        vm.snapshot();

        int256[2] memory amount0Moveds;
        int256[2] memory amount1Moveds;

        amount0Moveds[0] = currentSqrtPriceX96 > sqrtUpper
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                currentSqrtPriceX96 < sqrtLower ? sqrtLower : currentSqrtPriceX96,
                sqrtUpper,
                int128(expectedLiq)
            );

        amount1Moveds[0] = -SqrtPriceMath.getAmount1Delta(
            sqrtLower,
            sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
            int128(expectedLiq)
        );

        uint128 tokensOwed0;
        uint128 tokensOwed1;
        {
            uint128[] memory tokensOwedTemp = new uint128[](2);
            TokenId[] memory posIdList = new TokenId[](1);
            posIdList[0] = tokenIds[0];

            pp.mintOptions(posIdList, positionSize, 0, 0, 0);

            // poke uniswap pool to update tokens owed - needed because swap happens after mint
            vm.startPrank(address(sfpm));
            pool.burn(tickLower, tickUpper, 0);

            // calculate additional fees owed to position
            (, , , tokensOwed0, tokensOwed1) = pool.positions(
                PositionKey.compute(address(sfpm), tickLower, tickUpper)
            );

            tokensOwedTemp[0] = tokensOwed0;
            tokensOwedTemp[1] = tokensOwed1;

            // mint a long option at some percentage of Alice's liquidity so the premium is reduced
            vm.startPrank(Bob);

            posIdList[0] = tokenIds[1];

            pp.mintOptions(
                posIdList,
                (positionSize * uint128(bound(longPercentageSeed, 1, 899))) / 1000,
                type(uint64).max,
                0,
                0
            );

            twoWaySwap(swapSizeSeed);

            // poke uniswap pool to update tokens owed - needed because swap happens after mint
            vm.startPrank(address(sfpm));
            pool.burn(tickLower, tickUpper, 0);

            // calculate additional fees owed to position
            (, , , tokensOwed0, tokensOwed1) = pool.positions(
                PositionKey.compute(address(sfpm), tickLower, tickUpper)
            );

            tokensOwedTemp[0] += tokensOwed0;
            tokensOwedTemp[1] += tokensOwed1;

            // sell enough liquidity for alice to exit
            vm.startPrank(Seller);

            posIdList[0] = tokenIds[0];

            pp.mintOptions(
                posIdList,
                (((positionSize * uint128(bound(longPercentageSeed, 1, 899))) / 1000) * 100) / 89,
                0,
                0,
                0
            );

            // poke uniswap pool to update tokens owed - needed because swap happens after mint
            vm.startPrank(address(sfpm));
            pool.burn(tickLower, tickUpper, 0);

            // calculate additional fees owed to position
            (, , , tokensOwed0, tokensOwed1) = pool.positions(
                PositionKey.compute(address(sfpm), tickLower, tickUpper)
            );

            tokensOwed0 += tokensOwedTemp[0];
            tokensOwed1 += tokensOwedTemp[1];
        }

        // price changes afters swap at mint so we need to update the price
        (currentSqrtPriceX96, , , , , , ) = pool.slot0();

        amount0Moveds[1] = currentSqrtPriceX96 > sqrtUpper
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                currentSqrtPriceX96 < sqrtLower ? sqrtLower : currentSqrtPriceX96,
                sqrtUpper,
                int128(expectedLiq)
            );

        amount1Moveds[1] = SqrtPriceMath.getAmount1Delta(
            sqrtLower,
            sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
            int128(expectedLiq)
        );

        vm.startPrank(Alice);
        {
            pp.burnOptions(tokenIds[0], emptyList, 0, 0);
        }

        //snapshot balances and revert to old snapshot
        uint256[2] memory balanceBefores = [ct0.balanceOf(Alice), ct1.balanceOf(Alice)];

        vm.revertTo(0);

        (uint256[2] memory expectedSwaps, ) = PositionUtils.simulateSwap(
            pool,
            tickLower,
            tickUpper,
            expectedLiq,
            router,
            token0,
            token1,
            fee,
            [true, false],
            amount1Moveds
        );

        (, LeftRightSigned shortAmounts) = PanopticMath.computeExercisedAmounts(
            tokenIds[0],
            uint128(positionSize)
        );

        int256[2] memory notionalVals = [
            int256(expectedSwaps[0]) + amount0Moveds[0] - shortAmounts.rightSlot(),
            -int256(expectedSwaps[1]) - amount0Moveds[1] + shortAmounts.rightSlot()
        ];

        int256 ITMSpread = notionalVals[0] > 0
            ? (notionalVals[0] * int24(2 * (fee / 100))) / 10_000
            : -((notionalVals[0] * int24(2 * (fee / 100))) / 10_000);

        assertApproxEqAbs(
            int256(balanceBefores[0]) - int256(uint256(type(uint104).max)),
            -ITMSpread -
                notionalVals[0] -
                notionalVals[1] -
                (shortAmounts.rightSlot() * 10) /
                10_000 +
                int128(tokensOwed0),
            (uint256(int256(shortAmounts.rightSlot())) + tokensOwed0) /
                1_000_000 +
                (expectedSwaps[0] + expectedSwaps[1]) /
                100 +
                10,
            "Incorrect token0 delta"
        );

        assertApproxEqAbs(
            int256(balanceBefores[1]) - int256(uint256(type(uint104).max)),
            int256(uint256(tokensOwed1)),
            tokensOwed1 / 1_000_000 + 10,
            "Incorrect token1 delta"
        );
    }

    function test_Success_burnOptions_burnAllOptionsFrom(
        uint256 x,
        uint256 widthSeed,
        uint256 widthSeed2,
        int256 strikeSeed,
        int256 strikeSeed2,
        uint256 positionSizeSeed,
        uint256 positionSize2Seed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        (int24 width2, int24 strike2) = PositionUtils.getOTMSW(
            widthSeed2,
            strikeSeed2,
            uint24(tickSpacing),
            currentTick,
            0
        );
        vm.assume(width2 != width || strike2 != strike);

        populatePositionData(
            [width, width2],
            [strike, strike2],
            [positionSizeSeed, positionSize2Seed]
        );

        // leg 1
        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        // leg 2
        TokenId tokenId2 = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike2,
            width2
        );
        {
            TokenId[] memory posIdList = new TokenId[](1);
            posIdList[0] = tokenId;

            pp.mintOptions(posIdList, positionSizes[0], 0, 0, 0);
        }

        {
            TokenId[] memory posIdList = new TokenId[](2);
            posIdList[0] = tokenId;
            posIdList[1] = tokenId2;

            pp.mintOptions(posIdList, uint128(positionSizes[1]), 0, 0, 0);

            pp.burnOptions(posIdList, emptyList, 0, 0);

            (uint256 token0Balance, , ) = pp.optionPositionBalance(Alice, tokenId);
            (uint256 token1Balance, , ) = pp.optionPositionBalance(Alice, tokenId2);
            assertEq(token0Balance, 0);
            assertEq(token1Balance, 0);
        }
    }

    function test_Fail_burnOptions_notEnoughCollateral(
        uint256 x,
        uint256 numLegs,
        uint256 legsToBurn,
        uint256[4] memory isLongs,
        uint256[4] memory tokenTypes,
        uint256[4] memory widthSeeds,
        int256[4] memory strikeSeeds,
        uint256 positionSizeSeed,
        uint256 collateralBalanceSeed,
        uint256 collateralRatioSeed
    ) public {
        _initPool(x);

        numLegs = bound(numLegs, 2, 4);
        legsToBurn = bound(legsToBurn, 1, numLegs - 1);

        int24[4] memory widths;
        int24[4] memory strikes;

        for (uint256 i = 0; i < numLegs; ++i) {
            tokenTypes[i] = bound(tokenTypes[i], 0, 1);
            isLongs[i] = bound(isLongs[i], 0, 1);
            (widths[i], strikes[i]) = getValidSW(
                widthSeeds[i],
                strikeSeeds[i],
                uint24(tickSpacing),
                // distancing tickSpacing ensures this position stays OTM throughout this test case. ITM is tested elsewhere.
                currentTick
            );

            // make sure there are no conflicts
            for (uint256 j = 0; j < i; ++j) {
                vm.assume(
                    widths[i] != widths[j] ||
                        strikes[i] != strikes[j] ||
                        tokenTypes[i] != tokenTypes[j]
                );
            }
        }
        if (numLegs == 1) populatePositionData(widths[0], strikes[0], positionSizeSeed);
        if (numLegs == 2)
            populatePositionData(
                [widths[0], widths[1]],
                [strikes[0], strikes[1]],
                positionSizeSeed
            );
        if (numLegs == 3)
            populatePositionData(
                [widths[0], widths[1], widths[2]],
                [strikes[0], strikes[1], strikes[2]],
                positionSizeSeed
            );
        if (numLegs == 4) populatePositionData(widths, strikes, positionSizeSeed);

        // this is a long option; so need to sell before it can be bought (let's say 2x position size for now)
        vm.startPrank(Bob);

        for (uint256 i = 0; i < numLegs; ++i) {
            $posIdLists[0].push(
                TokenId.wrap(0).addPoolId(poolId).addLeg(
                    0,
                    1,
                    isWETH,
                    0,
                    tokenTypes[i],
                    0,
                    strikes[i],
                    widths[i]
                )
            );
            pp.mintOptions($posIdLists[0], positionSize * 10, 0, 0, 0);
        }

        // now we can mint the long option we are force exercising
        vm.startPrank(Alice);

        for (uint256 i = 0; i < numLegs; ++i) {
            $posIdLists[1].push(
                TokenId.wrap(0).addPoolId(poolId).addLeg(
                    0,
                    1,
                    isWETH,
                    isLongs[i],
                    tokenTypes[i],
                    0,
                    strikes[i],
                    widths[i]
                )
            );
            pp.mintOptions($posIdLists[1], positionSize, type(uint64).max, 0, 0);

            if ($posIdLists[3].length < legsToBurn) {
                $posIdLists[3].push($posIdLists[1][i]);
            } else {
                $posIdLists[2].push($posIdLists[1][i]);
            }
        }

        lastCollateralBalance0[Alice] = ct0.balanceOf(Alice);
        lastCollateralBalance1[Alice] = ct1.balanceOf(Alice);
        {
            uint256 snap = vm.snapshot();

            if ($posIdLists[3].length > 1) {
                pp.burnOptions($posIdLists[3], $posIdLists[2], 0, 0);
            } else {
                pp.burnOptions($posIdLists[3][0], $posIdLists[2], 0, 0);
            }

            int256 balanceDelta0 = int256(ct0.balanceOf(Alice)) -
                int256(lastCollateralBalance0[Alice]);
            int256 balanceDelta1 = int256(ct1.balanceOf(Alice)) -
                int256(lastCollateralBalance1[Alice]);
            (, , observationIndex, observationCardinality, , , ) = pool.slot0();
            int24 _fastOracleTick = PanopticMath.computeMedianObservedPrice(
                pool,
                observationIndex,
                observationCardinality,
                3,
                1
            );
            vm.revertTo(snap);

            fastOracleTick = _fastOracleTick;
            $balanceDelta0 = balanceDelta0;
            $balanceDelta1 = balanceDelta1;
        }

        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();

        (, uint256 totalCollateralRequired0) = ph.checkCollateral(
            pp,
            Alice,
            fastOracleTick,
            0,
            $posIdLists[2]
        );

        uint256 totalCollateralB0 = bound(
            collateralBalanceSeed,
            1,
            (totalCollateralRequired0 * 1_000) / 10_000
        );

        vm.assume(
            int256(
                ct0.convertToShares(
                    (totalCollateralB0 * bound(collateralRatioSeed, 5_000, 6_000)) / 10_000
                )
            ) -
                $balanceDelta0 >
                0
        );
        vm.assume(
            int256(
                ct1.convertToShares(
                    uint256(
                        int256(
                            PanopticMath.convert0to1(
                                (totalCollateralB0 *
                                    (10_000 - bound(collateralRatioSeed, 5_000, 6_000))) / 10_000,
                                Math.getSqrtRatioAtTick(fastOracleTick)
                            )
                        )
                    )
                )
            ) -
                $balanceDelta1 >
                0
        );

        editCollateral(
            ct0,
            Alice,
            uint256(
                int256(
                    ct0.convertToShares(
                        (totalCollateralB0 * bound(collateralRatioSeed, 5_000, 6_000)) / 10_000
                    )
                ) - $balanceDelta0
            )
        );
        editCollateral(
            ct1,
            Alice,
            uint256(
                int256(
                    ct1.convertToShares(
                        uint256(
                            int256(
                                PanopticMath.convert0to1(
                                    (totalCollateralB0 *
                                        (10_000 - bound(collateralRatioSeed, 5_000, 6_000))) /
                                        10_000,
                                    Math.getSqrtRatioAtTick(fastOracleTick)
                                )
                            )
                        )
                    )
                ) - $balanceDelta1
            )
        );

        vm.expectRevert();
        if ($posIdLists[3].length > 1) {
            pp.burnOptions($posIdLists[3], $posIdLists[2], 0, 0);
        } else {
            pp.burnOptions($posIdLists[3][0], $posIdLists[2], 0, 0);
        }
    }

    function test_Fail_burnOptions_OptionsBalanceZero(uint256 x) public {
        _initPool(x);

        vm.expectRevert(Errors.OptionsBalanceZero.selector);

        pp.burnOptions(TokenId.wrap(0), emptyList, 0, 0);
    }

    function test_Fail_burnOptions_WrongIdList(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        pp.mintOptions(posIdList, positionSize, 0, 0, 0);

        vm.expectRevert(Errors.InputListFail.selector);

        pp.burnOptions(tokenId, posIdList, 0, 0);
    }

    function test_fail_burnOptions_burnAllOptionsFrom(
        uint256 x,
        uint256 widthSeed,
        uint256 widthSeed2,
        int256 strikeSeed,
        int256 strikeSeed2,
        uint256 positionSizeSeed,
        uint256 positionSize2Seed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        (int24 width2, int24 strike2) = PositionUtils.getOTMSW(
            widthSeed2,
            strikeSeed2,
            uint24(tickSpacing),
            currentTick,
            0
        );
        vm.assume(width2 != width || strike2 != strike);

        populatePositionData(
            [width, width2],
            [strike, strike2],
            [positionSizeSeed, positionSize2Seed]
        );

        // leg 1
        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        // leg 2
        TokenId tokenId2 = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike2,
            width2
        );
        // leg 3
        TokenId tokenId3 = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            2,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );
        // leg 4
        TokenId tokenId4 = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            3,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );
        {
            TokenId[] memory posIdList = new TokenId[](1);
            posIdList[0] = tokenId;

            pp.mintOptions(posIdList, positionSizes[0], 0, 0, 0);

            vm.expectRevert(Errors.InputListFail.selector);
            pp.burnOptions(tokenId, posIdList, 0, 0);
        }

        {
            TokenId[] memory posIdList = new TokenId[](2);
            posIdList[0] = tokenId;
            posIdList[1] = tokenId2;

            pp.mintOptions(posIdList, uint128(positionSizes[1]), 0, 0, 0);

            vm.expectRevert(Errors.InputListFail.selector);
            pp.burnOptions(tokenId, emptyList, 0, 0);
        }
        {
            TokenId[] memory posIdList = new TokenId[](3);
            posIdList[0] = tokenId;
            posIdList[1] = tokenId2;
            posIdList[2] = tokenId3;

            pp.mintOptions(posIdList, uint128(positionSizes[0]), 0, 0, 0);

            vm.expectRevert(Errors.InputListFail.selector);
            pp.burnOptions(tokenId, posIdList, 0, 0);
        }

        {
            TokenId[] memory posIdList = new TokenId[](4);
            posIdList[0] = tokenId;
            posIdList[1] = tokenId2;
            posIdList[2] = tokenId3;
            posIdList[3] = tokenId4;

            pp.mintOptions(posIdList, uint128(positionSizes[1]), 0, 0, 0);

            TokenId[] memory burnIdList = new TokenId[](2);
            burnIdList[0] = tokenId;
            burnIdList[1] = tokenId2;

            vm.expectRevert(Errors.InputListFail.selector);
            pp.burnOptions(burnIdList, posIdList, 0, 0);

            TokenId[] memory leftoverIdList = new TokenId[](2);
            leftoverIdList[0] = tokenId3;
            leftoverIdList[1] = tokenId4;

            pp.burnOptions(burnIdList, leftoverIdList, 0, 0);
        }
    }

    function test_Success_forceExerciseDelta(
        uint256 x,
        uint256 numLegs,
        uint256[4] memory isLongs,
        uint256[4] memory tokenTypes,
        uint256[4] memory widthSeeds,
        int256[4] memory strikeSeeds,
        uint256 positionSizeSeed,
        uint256 swapSizeSeed,
        bool swapDirection
    ) public {
        _initPool(x);

        numLegs = bound(numLegs, 1, 4);

        int24[4] memory widths;
        int24[4] memory strikes;

        for (uint256 i = 0; i < numLegs; ++i) {
            tokenTypes[i] = bound(tokenTypes[i], 0, 1);
            isLongs[i] = bound(isLongs[i], 0, 1);
            (widths[i], strikes[i]) = getValidSW(
                widthSeeds[i],
                strikeSeeds[i],
                uint24(tickSpacing),
                currentTick
            );
        }

        for (uint256 i = 0; i < numLegs; ++i) {
            // make sure there are no double-touched chunks
            for (uint256 j = 0; j < i; ++j) {
                vm.assume(
                    widths[i] != widths[j] ||
                        strikes[i] != strikes[j] ||
                        tokenTypes[i] != tokenTypes[j]
                );
            }
        }

        if (numLegs == 1) populatePositionData(widths[0], strikes[0], positionSizeSeed);
        if (numLegs == 2)
            populatePositionData(
                [widths[0], widths[1]],
                [strikes[0], strikes[1]],
                positionSizeSeed
            );
        if (numLegs == 3)
            populatePositionData(
                [widths[0], widths[1], widths[2]],
                [strikes[0], strikes[1], strikes[2]],
                positionSizeSeed
            );
        if (numLegs == 4) populatePositionData(widths, strikes, positionSizeSeed);
        {
            uint256 exerciseableCount;
            // make sure position is exercisable - the uniswap twap is used to determine exercisability
            // so it could potentially be both OTM and non-exercisable (in-range)
            TWAPtick = pp.getUniV3TWAP_();
            for (uint256 i = 0; i < numLegs; ++i) {
                if (
                    (TWAPtick < (numLegs == 1 ? tickLower : tickLowers[i]) ||
                        TWAPtick >= (numLegs == 1 ? tickUpper : tickUppers[i])) && isLongs[i] == 1
                ) exerciseableCount++;
            }
            vm.assume(exerciseableCount > 0);
        }

        // this is a long option; so need to sell before it can be bought (let's say 2x position size for now)
        vm.startPrank(Seller);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId);

        for (uint256 i = 0; i < numLegs; ++i) {
            tokenId = tokenId.addLeg(i, 1, isWETH, 0, tokenTypes[i], i, strikes[i], widths[i]);
        }

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        pp.mintOptions(posIdList, positionSize * 2, 0, 0, 0);

        // now we can mint the long option we are force exercising
        vm.startPrank(Alice);

        // reset tokenId so we can fill for what we're actually testing (the bought option)
        tokenId = TokenId.wrap(0).addPoolId(poolId);

        for (uint256 i = 0; i < numLegs; ++i) {
            tokenId = tokenId.addLeg(
                i,
                1,
                isWETH,
                isLongs[i],
                tokenTypes[i],
                i,
                strikes[i],
                widths[i]
            );
        }

        posIdList[0] = tokenId;

        (LeftRightSigned longAmounts, LeftRightSigned shortAmounts) = PanopticMath
            .computeExercisedAmounts(tokenId, positionSize);

        try pp.mintOptions(posIdList, positionSize, type(uint64).max, 0, 0) {} catch (
            bytes memory reason
        ) {
            if (bytes4(reason) == Errors.TransferFailed.selector) {
                vm.assume(false);
            }
            revert();
        }

        lastCollateralBalance0[Alice] = ct0.convertToAssets(ct0.balanceOf(Alice));
        lastCollateralBalance1[Alice] = ct1.convertToAssets(ct1.balanceOf(Alice));

        twoWaySwap(swapSizeSeed);

        oneWaySwap(swapSizeSeed, swapDirection);

        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();

        updatePositionDataVariable(numLegs, isLongs);

        updateITMAmountsBurn(numLegs, tokenTypes);

        updateSwappedAmountsBurn(numLegs, isLongs);

        // make sure pool has enough tokens to perform the swap (if there is tons of slippage it may not)
        vm.assume(
            2 * $swap0 <= int256(IERC20Partial(token0).balanceOf(address(pp))) &&
                2 * $swap1 <= int256(IERC20Partial(token1).balanceOf(address(pp)))
        );

        updateIntrinsicValueBurn(longAmounts, shortAmounts);

        ($expectedPremia0, $expectedPremia1, ) = pp.calculateAccumulatedFeesBatch(
            Alice,
            true,
            posIdList
        );

        vm.startPrank(Bob);
        (currentSqrtPriceX96, currentTick, observationIndex, observationCardinality, , , ) = pool
            .slot0();

        for (uint256 i = 0; i < numLegs; ++i) {
            if (isLongs[i] == 0) continue;

            int256 legRanges;
            {
                int24 rangeDown;
                int24 rangeUp;
                (rangeDown, rangeUp) = PanopticMath.getRangesFromStrike(
                    widths[i],
                    int24(tickSpacing)
                );

                legRanges = currentTick < strikes[i] - rangeUp
                    ? ((strikes[i] - rangeUp - currentTick)) / rangeUp
                    : ((currentTick - strikes[i] - rangeUp)) / rangeUp;
            }

            rangesFromStrike = legRanges > rangesFromStrike ? legRanges : rangesFromStrike;

            medianSqrtPriceX96 = TickMath.getSqrtRatioAtTick(TWAPtick);

            LiquidityChunk liquidityChunk = PanopticMath.getLiquidityChunk(
                tokenId,
                i,
                positionSize
            );

            (currentValue0, currentValue1) = LiquidityAmounts.getAmountsForLiquidity(
                TickMath.getSqrtRatioAtTick(currentTick),
                TickMath.getSqrtRatioAtTick(liquidityChunk.tickLower()),
                TickMath.getSqrtRatioAtTick(liquidityChunk.tickUpper()),
                liquidityChunk.liquidity()
            );

            (medianValue0, medianValue1) = LiquidityAmounts.getAmountsForLiquidity(
                medianSqrtPriceX96,
                TickMath.getSqrtRatioAtTick(liquidityChunk.tickLower()),
                TickMath.getSqrtRatioAtTick(liquidityChunk.tickUpper()),
                liquidityChunk.liquidity()
            );

            // compensate user for loss in value if chunk has lost money between current and median tick
            // note: the delta for one token will be positive and the other will be negative. This cancels out any moves in their positions
            if (
                (tokenTypes[i] == 0 && currentValue1 < medianValue1) ||
                (tokenTypes[i] == 1 && currentValue0 < medianValue0)
            ) {
                exerciseFeeAmounts[0] += int256(medianValue0) - int256(currentValue0);
                exerciseFeeAmounts[1] += int256(medianValue1) - int256(currentValue1);
            }
        }

        // since the position is sufficiently OTM, the spread between value at current tick and median tick is 0
        // given that it is OTM at both points. Therefore, that spread is not charged as a fee and we just have the proximity fee
        // note: we HAVE to start with a negative number as the base exercise cost because when shifting a negative number right by n bits,
        // the result is rounded DOWN and NOT toward zero
        // this divergence is observed when n (the number of half ranges) is > 10 (ensuring the floor is not zero, but -1 = 1bps at that point)
        int256 exerciseFee = int256(-1024) >> uint256(rangesFromStrike);

        exerciseFeeAmounts[0] += (longAmounts.rightSlot() * (-exerciseFee)) / 10_000;
        exerciseFeeAmounts[1] += (longAmounts.leftSlot() * (-exerciseFee)) / 10_000;

        pp.forceExercise(Alice, posIdList, new TokenId[](0), new TokenId[](0));

        assertApproxEqAbs(
            int256(ct0.balanceOf(Bob)) - int256(uint256(type(uint104).max)),
            -(exerciseFeeAmounts[0] < 0 ? -1 : int8(1)) *
                int256(ct0.convertToShares(uint256(Math.abs(exerciseFeeAmounts[0])))),
            10,
            "Incorrect balance delta for token0 (Force Exercisor)"
        );
        assertApproxEqAbs(
            int256(ct1.balanceOf(Bob)) - int256(uint256(type(uint104).max)),
            -(exerciseFeeAmounts[1] < 0 ? -1 : int8(1)) *
                int256(ct1.convertToShares(uint256(Math.abs(exerciseFeeAmounts[1])))),
            10,
            "Incorrect balance delta for token1 (Force Exercisor)"
        );

        assertEq(sfpm.balanceOf(address(pp), TokenId.unwrap(tokenId)), 0);

        {
            (, uint256 inAMM, ) = ct0.getPoolData();
            assertApproxEqAbs(
                inAMM,
                uint128(longAmounts.rightSlot() + shortAmounts.rightSlot()) * 2,
                10
            );
        }

        {
            (, uint256 inAMM, ) = ct1.getPoolData();
            assertApproxEqAbs(
                inAMM,
                uint128(longAmounts.leftSlot() + shortAmounts.leftSlot()) * 2,
                10
            );
        }
        {
            assertEq(pp.positionsHash(Alice), 0);

            assertEq(pp.numberOfPositions(Alice), 0);

            (uint128 balance, uint64 poolUtilization0, uint64 poolUtilization1) = pp
                .optionPositionBalance(Alice, tokenId);

            assertEq(balance, 0);
            assertEq(poolUtilization0, 0);
            assertEq(poolUtilization1, 0);
        }

        {
            $balanceDelta0 = int256(exerciseFeeAmounts[0]) - $intrinsicValue0 + $expectedPremia0;

            $balanceDelta0 = $balanceDelta0 > 0
                ? int256(uint256($balanceDelta0))
                : -int256(uint256(-$balanceDelta0));

            $balanceDelta1 = int256(exerciseFeeAmounts[1]) - $intrinsicValue1 + $expectedPremia1;

            $balanceDelta1 = $balanceDelta1 > 0
                ? int256(uint256($balanceDelta1))
                : -int256(uint256(-$balanceDelta1));

            assertApproxEqAbs(
                int256(ct0.convertToAssets(ct0.balanceOf(Alice))) -
                    int256(lastCollateralBalance0[Alice]),
                $balanceDelta0,
                uint256(
                    int256((longAmounts.rightSlot() + shortAmounts.rightSlot()) / 1_000_000 + 10)
                ),
                "Incorrect balance delta for token0 (Force Exercisee)"
            );
            assertApproxEqAbs(
                int256(ct1.convertToAssets(ct1.balanceOf(Alice))) -
                    int256(lastCollateralBalance1[Alice]),
                $balanceDelta1,
                uint256(
                    int256((longAmounts.leftSlot() + shortAmounts.leftSlot()) / 1_000_000 + 10)
                ),
                "Incorrect balance delta for token1 (Force Exercisee)"
            );
        }
    }

    function test_Success_getRefundAmounts(
        uint256 x,
        uint256 balance0,
        uint256 balance1,
        int256 refund0,
        int256 refund1,
        int256 atTickSeed
    ) public {
        _initPool(x);

        balance0 = bound(balance0, 0, type(uint104).max);
        balance1 = bound(balance1, 0, type(uint104).max);
        refund0 = bound(
            refund0,
            -int256(uint256(type(uint104).max)),
            int256(uint256(type(uint104).max))
        );
        refund1 = bound(
            refund1,
            -int256(uint256(type(uint104).max)),
            int256(uint256(type(uint104).max))
        );
        // possible for the amounts used here to overflow beyond these ticks
        // convert0To1 is tested on the full tickrange elsewhere
        atTick = int24(bound(atTickSeed, -159_000, 159_000));

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(int24(atTick));

        vm.startPrank(Charlie);
        ct0.deposit(balance0, Charlie);
        ct1.deposit(balance1, Charlie);

        int256 shortage = refund0 - int(ct0.convertToAssets(ct0.balanceOf(Charlie)));

        if (shortage > 0) {
            LeftRightSigned refundAmounts = PanopticMath.getRefundAmounts(
                Charlie,
                LeftRightSigned.wrap(0).toRightSlot(int128(refund0)).toLeftSlot(int128(refund1)),
                int24(atTick),
                ct0,
                ct1
            );

            refund0 = refund0 - shortage;
            refund1 = PanopticMath.convert0to1(shortage, sqrtPriceX96) + refund1;

            assertEq(refundAmounts.rightSlot(), refund0);
            assertEq(refundAmounts.leftSlot(), refund1);
            // if there is a shortage of token1, it won't be reached since it's only considered possible to have a shortage
            // of one token with force exercises. If there is a shortage of both the account is insolvent and it will fail
            // when trying to transfer the tokens
            return;
        }

        shortage = refund1 - int(ct1.convertToAssets(ct1.balanceOf(Charlie)));

        if (shortage > 0) {
            LeftRightSigned refundAmounts = PanopticMath.getRefundAmounts(
                Charlie,
                LeftRightSigned.wrap(0).toRightSlot(int128(refund0)).toLeftSlot(int128(refund1)),
                int24(atTick),
                ct0,
                ct1
            );

            refund1 = refund1 - shortage;
            refund0 = PanopticMath.convert1to0(shortage, sqrtPriceX96) + refund0;

            assertEq(refundAmounts.rightSlot(), refund0);
            assertEq(refundAmounts.leftSlot(), refund1);
        }
    }

    function test_Fail_forceExercise_ExercisorNotSolvent(
        uint256 x,
        uint256 numLegs,
        uint256[4] memory isLongs,
        uint256[4] memory tokenTypes,
        uint256[4] memory widthSeeds,
        int256[4] memory strikeSeeds,
        uint256 positionSizeSeed,
        uint256 swapSizeSeed,
        uint256 collateralBalanceSeed,
        uint256 collateralRatioSeed
    ) public {
        _initPool(x);

        numLegs = bound(numLegs, 2, 4);

        int24[4] memory widths;
        int24[4] memory strikes;

        for (uint256 i = 0; i < numLegs; ++i) {
            tokenTypes[i] = bound(tokenTypes[i], 0, 1);
            isLongs[i] = bound(isLongs[i], 0, 1);
            (widths[i], strikes[i]) = getValidSW(
                widthSeeds[i],
                strikeSeeds[i],
                uint24(tickSpacing),
                // distancing tickSpacing ensures this position stays OTM throughout this test case. ITM is tested elsewhere.
                currentTick
            );

            // make sure there are no conflicts
            for (uint256 j = 0; j < i; ++j) {
                vm.assume(
                    widths[i] != widths[j] ||
                        strikes[i] != strikes[j] ||
                        tokenTypes[i] != tokenTypes[j]
                );
            }
        }
        if (numLegs == 1) populatePositionData(widths[0], strikes[0], positionSizeSeed);
        if (numLegs == 2)
            populatePositionData(
                [widths[0], widths[1]],
                [strikes[0], strikes[1]],
                positionSizeSeed
            );
        if (numLegs == 3)
            populatePositionData(
                [widths[0], widths[1], widths[2]],
                [strikes[0], strikes[1], strikes[2]],
                positionSizeSeed
            );
        if (numLegs == 4) populatePositionData(widths, strikes, positionSizeSeed);

        {
            uint256 exerciseableCount;
            // make sure position is exercisable - the uniswap twap is used to determine exercisability
            // so it could potentially be both OTM and non-exercisable (in-range)
            TWAPtick = pp.getUniV3TWAP_();
            for (uint256 i = 0; i < numLegs; ++i) {
                if (
                    (TWAPtick < (numLegs == 1 ? tickLower : tickLowers[i]) ||
                        TWAPtick >= (numLegs == 1 ? tickUpper : tickUppers[i])) && isLongs[i] == 1
                ) exerciseableCount++;
            }
            vm.assume(exerciseableCount > 0);
        }

        // this is a long option; so need to sell before it can be bought (let's say 2x position size for now)
        vm.startPrank(Bob);

        for (uint256 i = 0; i < numLegs; ++i) {
            $posIdLists[0].push(
                TokenId.wrap(0).addPoolId(poolId).addLeg(
                    0,
                    1,
                    isWETH,
                    0,
                    tokenTypes[i],
                    0,
                    strikes[i],
                    widths[i]
                )
            );
            pp.mintOptions($posIdLists[0], positionSize * 10, 0, 0, 0);
        }

        twoWaySwap(swapSizeSeed);

        // now we can mint the long option we are force exercising
        vm.startPrank(Alice);

        for (uint256 i = 0; i < numLegs; ++i) {
            $posIdLists[1].push(
                TokenId.wrap(0).addPoolId(poolId).addLeg(
                    0,
                    1,
                    isWETH,
                    isLongs[i],
                    tokenTypes[i],
                    0,
                    strikes[i],
                    widths[i]
                )
            );

            $posIdLists[3].push($posIdLists[1][$posIdLists[1].length - 1]);

            if (
                (TWAPtick < (numLegs == 1 ? tickLower : tickLowers[i]) ||
                    TWAPtick >= (numLegs == 1 ? tickUpper : tickUppers[i])) &&
                isLongs[i] == 1 &&
                $posIdLists[2].length == 0
            ) {
                $posIdLists[2].push($posIdLists[1][$posIdLists[1].length - 1]);
                $posIdLists[3].pop();
            }

            pp.mintOptions($posIdLists[1], positionSize, type(uint64).max, 0, 0);
        }

        twoWaySwap(swapSizeSeed);

        lastCollateralBalance0[Alice] = ct0.balanceOf(Alice);
        lastCollateralBalance1[Alice] = ct1.balanceOf(Alice);
        {
            uint256 snap = vm.snapshot();

            vm.startPrank(Bob);
            pp.forceExercise(Alice, $posIdLists[2], $posIdLists[3], $posIdLists[0]);

            int256 balanceDelta0 = int256(ct0.balanceOf(Alice)) -
                int256(lastCollateralBalance0[Alice]);
            int256 balanceDelta1 = int256(ct1.balanceOf(Alice)) -
                int256(lastCollateralBalance1[Alice]);
            vm.revertTo(snap);

            $balanceDelta0 = balanceDelta0;
            $balanceDelta1 = balanceDelta1;
        }

        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();

        (, uint256 totalCollateralRequired0) = ph.checkCollateral(
            pp,
            Bob,
            pp.getUniV3TWAP_(),
            0,
            $posIdLists[0]
        );

        uint256 totalCollateralB0 = bound(
            collateralBalanceSeed,
            1,
            (totalCollateralRequired0 * 1_000) / 10_000
        );

        vm.assume(
            int256(totalCollateralRequired0) +
                int256(
                    PanopticMath.convert1to0(
                        $balanceDelta1,
                        Math.getSqrtRatioAtTick(pp.getUniV3TWAP_())
                    ) + $balanceDelta0
                ) *
                2 >
                int256(totalCollateralB0)
        );

        editCollateral(
            ct0,
            Bob,
            ct0.convertToShares(
                (totalCollateralB0 * bound(collateralRatioSeed, 5_000, 6_000)) / 10_000
            )
        );
        editCollateral(
            ct1,
            Bob,
            ct1.convertToShares(
                PanopticMath.convert0to1(
                    (totalCollateralB0 * (10_000 - bound(collateralRatioSeed, 5_000, 6_000))) /
                        10_000,
                    Math.getSqrtRatioAtTick(pp.getUniV3TWAP_())
                )
            )
        );

        vm.startPrank(Bob);

        vm.expectRevert();
        pp.forceExercise(Alice, $posIdLists[2], $posIdLists[3], $posIdLists[0]);
    }

    function test_Fail_forceExercise_ExerciseeNotSolvent(
        uint256 x,
        uint256 numLegs,
        uint256[4] memory isLongs,
        uint256[4] memory tokenTypes,
        uint256[4] memory widthSeeds,
        int256[4] memory strikeSeeds,
        uint256 positionSizeSeed,
        uint256 swapSizeSeed,
        uint256 collateralBalanceSeed,
        uint256 collateralRatioSeed
    ) public {
        _initPool(x);

        numLegs = bound(numLegs, 2, 4);

        int24[4] memory widths;
        int24[4] memory strikes;

        for (uint256 i = 0; i < numLegs; ++i) {
            tokenTypes[i] = bound(tokenTypes[i], 0, 1);
            isLongs[i] = bound(isLongs[i], 0, 1);
            (widths[i], strikes[i]) = getValidSW(
                widthSeeds[i],
                strikeSeeds[i],
                uint24(tickSpacing),
                // distancing tickSpacing ensures this position stays OTM throughout this test case. ITM is tested elsewhere.
                currentTick
            );

            // make sure there are no conflicts
            for (uint256 j = 0; j < i; ++j) {
                vm.assume(
                    widths[i] != widths[j] ||
                        strikes[i] != strikes[j] ||
                        tokenTypes[i] != tokenTypes[j]
                );
            }
        }
        if (numLegs == 1) populatePositionData(widths[0], strikes[0], positionSizeSeed);
        if (numLegs == 2)
            populatePositionData(
                [widths[0], widths[1]],
                [strikes[0], strikes[1]],
                positionSizeSeed
            );
        if (numLegs == 3)
            populatePositionData(
                [widths[0], widths[1], widths[2]],
                [strikes[0], strikes[1], strikes[2]],
                positionSizeSeed
            );
        if (numLegs == 4) populatePositionData(widths, strikes, positionSizeSeed);

        {
            uint256 exerciseableCount;
            // make sure position is exercisable - the uniswap twap is used to determine exercisability
            // so it could potentially be both OTM and non-exercisable (in-range)
            TWAPtick = pp.getUniV3TWAP_();
            for (uint256 i = 0; i < numLegs; ++i) {
                if (
                    (TWAPtick < (numLegs == 1 ? tickLower : tickLowers[i]) ||
                        TWAPtick >= (numLegs == 1 ? tickUpper : tickUppers[i])) && isLongs[i] == 1
                ) exerciseableCount++;
            }
            vm.assume(exerciseableCount > 0);
        }

        // this is a long option; so need to sell before it can be bought (let's say 2x position size for now)
        vm.startPrank(Seller);

        for (uint256 i = 0; i < numLegs; ++i) {
            $posIdLists[0].push(
                TokenId.wrap(0).addPoolId(poolId).addLeg(
                    0,
                    1,
                    isWETH,
                    0,
                    tokenTypes[i],
                    0,
                    strikes[i],
                    widths[i]
                )
            );
            pp.mintOptions($posIdLists[0], positionSize * 2, 0, 0, 0);
        }

        twoWaySwap(swapSizeSeed);

        // now we can mint the long option we are force exercising
        vm.startPrank(Alice);

        for (uint256 i = 0; i < numLegs; ++i) {
            $posIdLists[1].push(
                TokenId.wrap(0).addPoolId(poolId).addLeg(
                    0,
                    1,
                    isWETH,
                    isLongs[i],
                    tokenTypes[i],
                    0,
                    strikes[i],
                    widths[i]
                )
            );

            $posIdLists[3].push($posIdLists[1][$posIdLists[1].length - 1]);

            if (
                (TWAPtick < (numLegs == 1 ? tickLower : tickLowers[i]) ||
                    TWAPtick >= (numLegs == 1 ? tickUpper : tickUppers[i])) &&
                isLongs[i] == 1 &&
                $posIdLists[2].length == 0
            ) {
                $posIdLists[2].push($posIdLists[1][$posIdLists[1].length - 1]);
                $posIdLists[3].pop();
            }

            pp.mintOptions($posIdLists[1], positionSize, type(uint64).max, 0, 0);
        }

        twoWaySwap(swapSizeSeed);

        lastCollateralBalance0[Alice] = ct0.balanceOf(Alice);
        lastCollateralBalance1[Alice] = ct1.balanceOf(Alice);
        {
            uint256 snap = vm.snapshot();

            vm.startPrank(Bob);
            pp.forceExercise(Alice, $posIdLists[2], $posIdLists[3], new TokenId[](0));

            int256 balanceDelta0 = int256(ct0.balanceOf(Alice)) -
                int256(lastCollateralBalance0[Alice]);
            int256 balanceDelta1 = int256(ct1.balanceOf(Alice)) -
                int256(lastCollateralBalance1[Alice]);
            vm.revertTo(snap);

            $balanceDelta0 = balanceDelta0;
            $balanceDelta1 = balanceDelta1;
        }

        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();

        (, uint256 totalCollateralRequired0) = ph.checkCollateral(
            pp,
            Alice,
            pp.getUniV3TWAP_(),
            0,
            $posIdLists[3]
        );

        uint256 totalCollateralB0 = bound(
            collateralBalanceSeed,
            1,
            (totalCollateralRequired0 * 1_000) / 10_000
        );

        vm.assume(
            int256(totalCollateralRequired0) -
                int256(
                    PanopticMath.convert1to0(
                        $balanceDelta1,
                        Math.getSqrtRatioAtTick(pp.getUniV3TWAP_())
                    ) + $balanceDelta0
                ) *
                2 >
                int256(totalCollateralB0)
        );

        editCollateral(
            ct0,
            Alice,
            ct0.convertToShares(
                (totalCollateralB0 * bound(collateralRatioSeed, 0, 10_000)) / 10_000
            )
        );
        editCollateral(
            ct1,
            Alice,
            ct1.convertToShares(
                PanopticMath.convert0to1(
                    (totalCollateralB0 * (10_000 - bound(collateralRatioSeed, 0, 10_000))) / 10_000,
                    Math.getSqrtRatioAtTick(pp.getUniV3TWAP_())
                )
            )
        );

        vm.startPrank(Bob);

        vm.expectRevert();
        pp.forceExercise(Alice, $posIdLists[2], $posIdLists[3], new TokenId[](0));
    }

    function test_Fail_forceExercise_InvalidExerciseeList(
        uint256 x,
        uint256 numLegs,
        uint256[4] memory isLongs,
        uint256[4] memory tokenTypes,
        uint256[4] memory widthSeeds,
        int256[4] memory strikeSeeds,
        uint256 positionSizeSeed,
        uint256 swapSizeSeed
    ) public {
        _initPool(x);

        numLegs = bound(numLegs, 2, 4);

        int24[4] memory widths;
        int24[4] memory strikes;

        for (uint256 i = 0; i < numLegs; ++i) {
            tokenTypes[i] = bound(tokenTypes[i], 0, 1);
            isLongs[i] = bound(isLongs[i], 0, 1);
            (widths[i], strikes[i]) = getValidSW(
                widthSeeds[i],
                strikeSeeds[i],
                uint24(tickSpacing),
                // distancing tickSpacing ensures this position stays OTM throughout this test case. ITM is tested elsewhere.
                currentTick
            );

            // make sure there are no conflicts
            for (uint256 j = 0; j < i; ++j) {
                vm.assume(
                    widths[i] != widths[j] ||
                        strikes[i] != strikes[j] ||
                        tokenTypes[i] != tokenTypes[j]
                );
            }
        }
        if (numLegs == 1) populatePositionData(widths[0], strikes[0], positionSizeSeed);
        if (numLegs == 2)
            populatePositionData(
                [widths[0], widths[1]],
                [strikes[0], strikes[1]],
                positionSizeSeed
            );
        if (numLegs == 3)
            populatePositionData(
                [widths[0], widths[1], widths[2]],
                [strikes[0], strikes[1], strikes[2]],
                positionSizeSeed
            );
        if (numLegs == 4) populatePositionData(widths, strikes, positionSizeSeed);

        {
            uint256 exerciseableCount;
            // make sure position is exercisable - the uniswap twap is used to determine exercisability
            // so it could potentially be both OTM and non-exercisable (in-range)
            TWAPtick = pp.getUniV3TWAP_();
            for (uint256 i = 0; i < numLegs; ++i) {
                if (
                    (TWAPtick < (numLegs == 1 ? tickLower : tickLowers[i]) ||
                        TWAPtick >= (numLegs == 1 ? tickUpper : tickUppers[i])) && isLongs[i] == 1
                ) exerciseableCount++;
            }
            vm.assume(exerciseableCount > 0);
        }

        // this is a long option; so need to sell before it can be bought (let's say 2x position size for now)
        vm.startPrank(Seller);

        for (uint256 i = 0; i < numLegs; ++i) {
            $posIdLists[0].push(
                TokenId.wrap(0).addPoolId(poolId).addLeg(
                    0,
                    1,
                    isWETH,
                    0,
                    tokenTypes[i],
                    0,
                    strikes[i],
                    widths[i]
                )
            );
            pp.mintOptions($posIdLists[0], positionSize * 2, 0, 0, 0);
        }

        twoWaySwap(swapSizeSeed);

        // now we can mint the long option we are force exercising
        vm.startPrank(Alice);

        for (uint256 i = 0; i < numLegs; ++i) {
            $posIdLists[1].push(
                TokenId.wrap(0).addPoolId(poolId).addLeg(
                    0,
                    1,
                    isWETH,
                    isLongs[i],
                    tokenTypes[i],
                    0,
                    strikes[i],
                    widths[i]
                )
            );

            $posIdLists[3].push($posIdLists[1][$posIdLists[1].length - 1]);

            if (
                (TWAPtick < (numLegs == 1 ? tickLower : tickLowers[i]) ||
                    TWAPtick >= (numLegs == 1 ? tickUpper : tickUppers[i])) &&
                isLongs[i] == 1 &&
                $posIdLists[2].length == 0
            ) {
                $posIdLists[2].push($posIdLists[1][$posIdLists[1].length - 1]);
                $posIdLists[3].pop();
            }

            pp.mintOptions($posIdLists[1], positionSize, type(uint64).max, 0, 0);
        }

        twoWaySwap(swapSizeSeed);

        vm.startPrank(Bob);

        vm.expectRevert(Errors.InputListFail.selector);
        pp.forceExercise(Alice, new TokenId[](0), $posIdLists[3], new TokenId[](0));
    }

    function test_Fail_forceExercise_InvalidExercisorList(
        uint256 x,
        uint256[2] memory widthSeeds,
        int256[2] memory strikeSeeds,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getITMSW(
            widthSeeds[0],
            strikeSeeds[0],
            uint24(tickSpacing),
            currentTick,
            0
        );

        (int24 width2, int24 strike2) = PositionUtils.getOTMSW(
            widthSeeds[1],
            strikeSeeds[1],
            uint24(tickSpacing),
            currentTick,
            0
        );
        vm.assume(width2 != width || strike2 != strike);

        populatePositionData([width, width2], [strike, strike2], positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        pp.mintOptions(posIdList, positionSize, 0, 0, 0);

        posIdList = new TokenId[](2);
        posIdList[0] = tokenId;

        TokenId tokenId2 = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike2,
            width2
        );

        posIdList[1] = tokenId2;

        pp.mintOptions(posIdList, positionSize, 0, 0, 0);

        vm.startPrank(Bob);

        posIdList = new TokenId[](1);
        posIdList[0] = tokenId2;

        vm.expectRevert(Errors.InputListFail.selector);
        pp.forceExercise(Alice, new TokenId[](1), new TokenId[](0), posIdList);
    }

    function test_Fail_forceExercise_1PositionNotSpecified(
        uint256 x,
        TokenId[] memory touchedIds
    ) public {
        _initPool(x);

        vm.assume(touchedIds.length != 1);

        vm.expectRevert(Errors.InputListFail.selector);

        pp.forceExercise(Alice, touchedIds, new TokenId[](0), new TokenId[](0));
    }

    function test_Fail_forceExercise_PositionNotExercisable(uint256 x) public {
        _initPool(x);
        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            0,
            0,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, 0);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );
        TokenId[] memory touchedIds = new TokenId[](1);
        touchedIds[0] = tokenId;

        vm.startPrank(Alice);
        pp.mintOptions(touchedIds, positionSize, 0, 0, 0);

        vm.startPrank(Bob);

        vm.expectRevert(Errors.NoLegsExercisable.selector);
        pp.forceExercise(Alice, touchedIds, touchedIds, new TokenId[](0));
    }

    /*//////////////////////////////////////////////////////////////
                           LIQUIDAuinTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_success_liquidate(
        uint256 x,
        uint256 numLegs,
        uint256[4] memory isLongs,
        uint256[4] memory tokenTypes,
        uint256[4] memory widthSeeds,
        int256[4] memory strikeSeeds,
        uint256 positionSizeSeed,
        uint256 swapSizeSeed,
        uint256 collateralBalanceSeed,
        uint256 collateralRatioSeed
    ) public {
        _initPool(x);

        numLegs = bound(numLegs, 1, 4);

        int24[4] memory widths;
        int24[4] memory strikes;

        for (uint256 i = 0; i < numLegs; ++i) {
            tokenTypes[i] = bound(tokenTypes[i], 0, 1);
            isLongs[i] = bound(isLongs[i], 0, 1);
            (widths[i], strikes[i]) = getValidSW(
                widthSeeds[i],
                strikeSeeds[i],
                uint24(tickSpacing),
                // distancing tickSpacing ensures this position stays OTM throughout this test case. ITM is tested elsewhere.
                currentTick
            );

            // make sure there are no conflicts
            for (uint256 j = 0; j < i; ++j) {
                vm.assume(
                    widths[i] != widths[j] ||
                        strikes[i] != strikes[j] ||
                        tokenTypes[i] != tokenTypes[j]
                );
            }
        }
        if (numLegs == 1) populatePositionData(widths[0], strikes[0], positionSizeSeed);
        if (numLegs == 2)
            populatePositionData(
                [widths[0], widths[1]],
                [strikes[0], strikes[1]],
                positionSizeSeed
            );
        if (numLegs == 3)
            populatePositionData(
                [widths[0], widths[1], widths[2]],
                [strikes[0], strikes[1], strikes[2]],
                positionSizeSeed
            );
        if (numLegs == 4) populatePositionData(widths, strikes, positionSizeSeed);

        // this is a long option; so need to sell before it can be bought (let's say 2x position size for now)
        vm.startPrank(Seller);

        for (uint256 i = 0; i < numLegs; ++i) {
            $posIdLists[0].push(
                TokenId.wrap(0).addPoolId(poolId).addLeg(
                    0,
                    1,
                    isWETH,
                    0,
                    tokenTypes[i],
                    0,
                    strikes[i],
                    widths[i]
                )
            );
            pp.mintOptions($posIdLists[0], positionSize * 2, 0, 0, 0);
        }

        twoWaySwap(swapSizeSeed);

        // now we can mint the options being liquidated
        vm.startPrank(Alice);

        for (uint256 i = 0; i < numLegs; ++i) {
            $posIdLists[1].push(
                TokenId.wrap(0).addPoolId(poolId).addLeg(
                    0,
                    1,
                    isWETH,
                    isLongs[i],
                    tokenTypes[i],
                    0,
                    strikes[i],
                    widths[i]
                )
            );

            pp.mintOptions($posIdLists[1], positionSize, type(uint64).max, 0, 0);
        }

        twoWaySwap(swapSizeSeed);

        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();

        vm.assume(Math.abs(int256(currentTick) - pp.getUniV3TWAP_()) <= 513);

        (, uint256 totalCollateralRequired0) = ph.checkCollateral(
            pp,
            Alice,
            pp.getUniV3TWAP_(),
            0,
            $posIdLists[1]
        );

        uint256 totalCollateralB0 = bound(
            collateralBalanceSeed,
            1,
            (totalCollateralRequired0 * 9_999) / 10_000
        );

        editCollateral(
            ct0,
            Alice,
            ct0.convertToShares(
                (totalCollateralB0 * bound(collateralRatioSeed, 0, 10_000)) / 10_000
            )
        );
        editCollateral(
            ct1,
            Alice,
            ct1.convertToShares(
                PanopticMath.convert0to1(
                    (totalCollateralB0 * (10_000 - bound(collateralRatioSeed, 0, 10_000))) / 10_000,
                    Math.getSqrtRatioAtTick(pp.getUniV3TWAP_())
                )
            )
        );

        TWAPtick = pp.getUniV3TWAP_();
        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();

        ($expectedPremia0, $expectedPremia1, $positionBalanceArray) = pp
            .calculateAccumulatedFeesBatch(Alice, false, $posIdLists[1]);

        $tokenData0 = ct0.getAccountMarginDetails(
            Alice,
            TWAPtick,
            $positionBalanceArray,
            $expectedPremia0
        );

        $tokenData1 = ct1.getAccountMarginDetails(
            Alice,
            TWAPtick,
            $positionBalanceArray,
            $expectedPremia1
        );

        // initialize collateral share deltas - we measure the flow of value out of Alice account to find the bonus
        $shareDelta0 = int256(ct0.balanceOf(Alice));
        $shareDelta1 = int256(ct1.balanceOf(Alice));

        // delegate bobs entire balance so we don't have the protocol loss in his unutilized collateral as a source of error
        deal(address(ct0), Bob, ct0.convertToShares(type(uint96).max));
        deal(address(ct1), Bob, ct1.convertToShares(type(uint96).max));

        // simulate burning all options to compare against the liquidation
        uint256 snapshot = vm.snapshot();

        vm.startPrank(address(pp));

        ct0.delegate(Bob, Alice, type(uint96).max);
        ct1.delegate(Bob, Alice, type(uint96).max);

        int256[2] memory shareDeltasLiquidatee = [
            int256(ct0.balanceOf(Alice)),
            int256(ct1.balanceOf(Alice))
        ];

        vm.startPrank(Alice);

        int24 currentTickFinal;
        {
            (LeftRightSigned[4][] memory premiasByLeg, LeftRightSigned netExchanged) = pp
                .burnAllOptionsFrom($posIdLists[1], 0, 0);

            shareDeltasLiquidatee = [
                int256(ct0.balanceOf(Alice)) - shareDeltasLiquidatee[0],
                int256(ct1.balanceOf(Alice)) - shareDeltasLiquidatee[1]
            ];

            (, currentTickFinal, , , , , ) = pool.slot0();

            uint256[2][4][] memory settledTokensTemp = new uint256[2][4][]($posIdLists[1].length);
            for (uint256 i = 0; i < $posIdLists[1].length; ++i) {
                for (uint256 j = 0; j < $posIdLists[1][i].countLegs(); ++j) {
                    bytes32 chunk = keccak256(
                        abi.encodePacked(
                            $posIdLists[1][i].strike(j),
                            $posIdLists[1][i].width(j),
                            $posIdLists[1][i].tokenType(j)
                        )
                    );
                    settledTokensTemp[i][j] = [
                        uint256(chunk),
                        LeftRightUnsigned.unwrap(pp.settledTokens(chunk))
                    ];
                }
            }

            uint256 totalSupply0 = ct0.totalSupply();
            uint256 totalSupply1 = ct1.totalSupply();
            uint256 totalAssets0 = ct0.totalAssets();
            uint256 totalAssets1 = ct1.totalAssets();

            int256 burnDelta0C = convertToAssets(ct0, shareDeltasLiquidatee[0]) +
                PanopticMath.convert1to0(
                    convertToAssets(ct1, shareDeltasLiquidatee[1]),
                    TickMath.getSqrtRatioAtTick(currentTickFinal)
                );
            int256 burnDelta0 = convertToAssets(ct0, shareDeltasLiquidatee[0]);
            int256 burnDelta1 = convertToAssets(ct1, shareDeltasLiquidatee[1]);

            vm.revertTo(snapshot);

            $totalSupply0 = totalSupply0;
            $totalSupply1 = totalSupply1;
            $totalAssets0 = totalAssets0;
            $totalAssets1 = totalAssets1;

            $burnDelta0Combined = burnDelta0C;
            $burnDelta0 = burnDelta0;
            $burnDelta1 = burnDelta1;

            $netExchanged = netExchanged;

            for (uint256 i = 0; i < $posIdLists[1].length; ++i) {
                for (uint256 j = 0; j < $posIdLists[1][i].countLegs(); ++j) {
                    longPremium0 += premiasByLeg[i][j].rightSlot() < 0
                        ? -premiasByLeg[i][j].rightSlot()
                        : int128(0);
                    longPremium0 += PanopticMath.convert1to0(
                        premiasByLeg[i][j].leftSlot() < 0
                            ? -premiasByLeg[i][j].leftSlot()
                            : int128(0),
                        TickMath.getSqrtRatioAtTick(currentTickFinal)
                    );
                    $settledTokens[bytes32(settledTokensTemp[i][j][0])] = LeftRightUnsigned.wrap(
                        settledTokensTemp[i][j][1]
                    );
                }
            }
        }

        vm.startPrank(Bob);

        $accValueBefore0 =
            ct0.convertToAssets(ct0.balanceOf(Bob)) +
            PanopticMath.convert1to0(
                ct1.convertToAssets(ct1.balanceOf(Bob)),
                TickMath.getSqrtRatioAtTick(currentTickFinal)
            );

        {
            (int128 premium0, int128 premium1, ) = pp.calculateAccumulatedFeesBatch(
                Alice,
                false,
                $posIdLists[1]
            );
            $premia = LeftRightSigned.wrap(0).toRightSlot(premium0).toLeftSlot(premium1);
        }

        ($bonus0, $bonus1, ) = PanopticMath.getLiquidationBonus(
            $tokenData0,
            $tokenData1,
            Math.getSqrtRatioAtTick(TWAPtick),
            Math.getSqrtRatioAtTick(currentTickFinal),
            $netExchanged,
            $premia
        );

        $delegated0 = uint256(
            int256(ct0.convertToShares(uint256(int256(uint256(type(uint96).max)) + $bonus0)))
        );
        $delegated1 = uint256(
            int256(ct1.convertToShares(uint256(int256(uint256(type(uint96).max)) + $bonus1)))
        );

        pp.liquidate(
            new TokenId[](0),
            Alice,
            LeftRightUnsigned.wrap(type(uint96).max).toLeftSlot(type(uint96).max),
            $posIdLists[1]
        );

        // take the difference between the share deltas after burn and after mint - that should be the bonus
        $shareDelta0 = shareDeltasLiquidatee[0] - (int256(ct0.balanceOf(Alice)) - $shareDelta0);
        $shareDelta1 = shareDeltasLiquidatee[1] - (int256(ct1.balanceOf(Alice)) - $shareDelta1);

        // bonus can be very small on the threshold leading to a loss (of 1-2 tokens) due to precision, which is fine
        assertGe(
            ct0.convertToAssets(ct0.balanceOf(Bob)) +
                PanopticMath.convert1to0(
                    ct1.convertToAssets(ct1.balanceOf(Bob)),
                    TickMath.getSqrtRatioAtTick(currentTickFinal)
                ) +
                1,
            $accValueBefore0,
            "liquidator lost money"
        );

        // get total balance for Alice before liquidation
        $combinedBalance0NoPremium = int256(
            (int256(uint256($tokenData0.rightSlot())) - Math.max($premia.rightSlot(), 0)) +
                PanopticMath.convert1to0(
                    int256(uint256($tokenData1.rightSlot())) - Math.max($premia.leftSlot(), 0),
                    TickMath.getSqrtRatioAtTick(TWAPtick)
                )
        );
        $combinedBalance0Premium = int256(
            ($tokenData0.rightSlot()) +
                PanopticMath.convert1to0(
                    $tokenData1.rightSlot(),
                    TickMath.getSqrtRatioAtTick(TWAPtick)
                )
        );
        $bonusCombined0 = Math.min(
            $combinedBalance0Premium / 2,
            int256(
                $tokenData0.leftSlot() +
                    PanopticMath.convert1to0(
                        $tokenData1.leftSlot(),
                        TickMath.getSqrtRatioAtTick(TWAPtick)
                    )
            ) - $combinedBalance0Premium
        );

        // make sure value outlay for Alice matches the bonus structure
        // if Alice is completely insolvent the deltas will be wrong because
        // some of the bonus will come from PLPs
        // in that case we just assert that the delta is less than whatever the bonus was supposed to be
        // which ensures Alice wasn't overcharged

        // The protocol loss is the value of shares added to the supply multiplied by the portion of NON-DELEGATED collateral
        // (losses in collateral that was returned to the liquidator post-delegation are compensated, so they are not included)
        $protocolLoss0Actual = int256(
            (ct0.convertToAssets(
                (ct0.totalSupply() - $totalSupply0) -
                    ((ct0.totalAssets() - $totalAssets0) * $totalSupply0) /
                    $totalAssets0
            ) * ($totalSupply0 - $delegated0)) /
                ($totalSupply0 - (ct0.totalSupply() - $totalSupply0)) +
                PanopticMath.convert1to0(
                    (ct1.convertToAssets(
                        (ct1.totalSupply() - $totalSupply1) -
                            ((ct1.totalAssets() - $totalAssets1) * $totalSupply1) /
                            $totalAssets1
                    ) * ($totalSupply1 - $delegated1)) /
                        ($totalSupply1 - (ct1.totalSupply() - $totalSupply1)),
                    TickMath.getSqrtRatioAtTick(currentTickFinal)
                )
        );

        // every time an option is burnt, the owner can lose up to 1 share (worth much less than 1 token) due to rounding
        // (in this test n = number of options = numLegs)
        // this happens on *both* liquidations and burns, but during liquidations 1-n shares can be clawed back from PLPs
        // this is because the assets refunded to the liquidator are only rounded down once,
        // so they could correspond to a higher amount of overall shares than the liquidatee had
        if (
            (ct0.totalSupply() - $totalSupply0 <= numLegs) &&
            (ct1.totalSupply() - $totalSupply1 <= numLegs)
        ) {
            assertApproxEqAbs(
                convertToAssets(ct0, $shareDelta0) +
                    PanopticMath.convert1to0(
                        convertToAssets(ct1, $shareDelta1),
                        TickMath.getSqrtRatioAtTick(currentTickFinal)
                    ),
                Math.min(
                    $combinedBalance0Premium / 2,
                    int256(
                        $tokenData0.leftSlot() +
                            PanopticMath.convert1to0(
                                $tokenData1.leftSlot(),
                                TickMath.getSqrtRatioAtTick(TWAPtick)
                            )
                    ) - $combinedBalance0Premium
                ),
                10,
                "liquidatee was debited incorrect bonus value (funds leftover)"
            );

            for (uint256 i = 0; i < $posIdLists[1].length; ++i) {
                for (uint256 j = 0; j < $posIdLists[1][i].countLegs(); ++j) {
                    bytes32 chunk = keccak256(
                        abi.encodePacked(
                            $posIdLists[1][i].strike(j),
                            $posIdLists[1][i].width(j),
                            $posIdLists[1][i].tokenType(j)
                        )
                    );
                    assertEq(
                        LeftRightUnsigned.unwrap(pp.settledTokens(chunk)),
                        LeftRightUnsigned.unwrap($settledTokens[chunk]),
                        "settled tokens were modified when a haircut was not needed"
                    );
                }
            }
        } else {
            assertLe(
                convertToAssets(ct0, $shareDelta0) +
                    PanopticMath.convert1to0(
                        convertToAssets(ct1, $shareDelta1),
                        TickMath.getSqrtRatioAtTick(currentTickFinal)
                    ),
                Math.min(
                    $combinedBalance0Premium / 2,
                    int256(
                        $tokenData0.leftSlot() +
                            PanopticMath.convert1to0(
                                $tokenData1.leftSlot(),
                                TickMath.getSqrtRatioAtTick(TWAPtick)
                            )
                    ) - $combinedBalance0Premium
                ),
                "liquidatee was debited incorrectly high bonus value (no funds leftover)"
            );
        }

        settledTokens0.push(0);
        settledTokens0.push(0);

        for (uint256 i = 0; i < $posIdLists[1].length; ++i) {
            for (uint256 j = 0; j < $posIdLists[1][i].countLegs(); ++j) {
                bytes32 chunk = keccak256(
                    abi.encodePacked(
                        $posIdLists[1][i].strike(j),
                        $posIdLists[1][i].width(j),
                        $posIdLists[1][i].tokenType(j)
                    )
                );
                settledTokens0[0] += $settledTokens[chunk].rightSlot();
                settledTokens0[1] += pp.settledTokens(chunk).rightSlot();
                settledTokens0[0] += PanopticMath.convert1to0(
                    $settledTokens[chunk].leftSlot(),
                    TickMath.getSqrtRatioAtTick(currentTickFinal)
                );
                settledTokens0[1] += PanopticMath.convert1to0(
                    pp.settledTokens(chunk).leftSlot(),
                    TickMath.getSqrtRatioAtTick(currentTickFinal)
                );
            }
        }

        int256 balanceCombined0CT = int256(
            $tokenData0.rightSlot() +
                PanopticMath.convert1to0(
                    $tokenData1.rightSlot(),
                    TickMath.getSqrtRatioAtTick(TWAPtick)
                )
        );

        $balance0CombinedPostBurn =
            int256(uint256($tokenData0.rightSlot())) -
            Math.max($premia.rightSlot(), 0) +
            $burnDelta0 +
            int256(
                PanopticMath.convert1to0(
                    int256(uint256($tokenData1.rightSlot())) -
                        Math.max($premia.leftSlot(), 0) +
                        $burnDelta1,
                    TickMath.getSqrtRatioAtTick(currentTickFinal)
                )
            );

        $protocolLoss0BaseExpected = Math.max(
            -($balance0CombinedPostBurn -
                Math.min(
                    balanceCombined0CT / 2,
                    int256(
                        $tokenData0.leftSlot() +
                            PanopticMath.convert1to0(
                                $tokenData1.leftSlot(),
                                TickMath.getSqrtRatioAtTick(TWAPtick)
                            )
                    ) - balanceCombined0CT
                )),
            0
        );

        assertApproxEqAbs(
            int256(settledTokens0[0]) - int256(settledTokens0[1]),
            Math.min(longPremium0, $protocolLoss0BaseExpected),
            10,
            "incorrect amount of premium was haircut"
        );

        assertApproxEqAbs(
            $protocolLoss0Actual,
            $protocolLoss0BaseExpected - Math.min(longPremium0, $protocolLoss0BaseExpected),
            10,
            "not all premium was haircut during protocol loss"
        );

        assertApproxEqAbs(
            int256(
                ct0.convertToAssets(ct0.balanceOf(Bob)) +
                    PanopticMath.convert1to0(
                        ct1.convertToAssets(ct1.balanceOf(Bob)),
                        TickMath.getSqrtRatioAtTick(currentTickFinal)
                    )
            ) - int256($accValueBefore0),
            $bonusCombined0,
            10,
            "liquidator did not receive correct bonus"
        );
    }

    function test_Fail_liquidate_validatePositionListLiquidatee(
        uint256 x,
        uint256[2] memory widthSeeds,
        int256[2] memory strikeSeeds,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getITMSW(
            widthSeeds[0],
            strikeSeeds[0],
            uint24(tickSpacing),
            currentTick,
            0
        );

        (int24 width2, int24 strike2) = PositionUtils.getOTMSW(
            widthSeeds[1],
            strikeSeeds[1],
            uint24(tickSpacing),
            currentTick,
            0
        );
        vm.assume(width2 != width || strike2 != strike);

        populatePositionData([width, width2], [strike, strike2], positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        pp.mintOptions(posIdList, positionSize, 0, 0, 0);

        posIdList = new TokenId[](2);
        posIdList[0] = tokenId;

        TokenId tokenId2 = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike2,
            width2
        );

        posIdList[1] = tokenId2;

        pp.mintOptions(posIdList, positionSize, 0, 0, 0);

        vm.startPrank(Bob);

        posIdList = new TokenId[](1);
        posIdList[0] = tokenId2;

        vm.expectRevert(Errors.InputListFail.selector);
        pp.liquidate(new TokenId[](0), Alice, LeftRightUnsigned.wrap(0), posIdList);
    }

    function test_Fail_liquidate_validatePositionIdListLiquidator(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            0
        );

        populatePositionData(width, strike, positionSizeSeed);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        TokenId[] memory posIdList = new TokenId[](1);

        posIdList[0] = tokenId;

        pp.mintOptions(posIdList, positionSize, 0, 0, 0);

        vm.startPrank(Bob);

        pp.mintOptions(posIdList, positionSize, 0, 0, 0);

        editCollateral(ct0, Alice, 0);
        editCollateral(ct1, Alice, 0);

        vm.expectRevert(Errors.InputListFail.selector);
        pp.liquidate(new TokenId[](0), Alice, LeftRightUnsigned.wrap(0), posIdList);
    }

    function test_Fail_liquidate_StaleTWAP(uint256 x, int256 tickDeltaSeed) public {
        _initPool(x);
        int256 tickDelta = int256(
            bound(
                tickDeltaSeed,
                -(int256(currentTick) - int256(Constants.MIN_V3POOL_TICK)),
                int256(Constants.MAX_V3POOL_TICK) - int256(currentTick)
            )
        );
        vm.assume(Math.abs((int256(currentTick) + tickDelta) - pp.getUniV3TWAP_()) > 513);
        vm.store(
            address(pool),
            bytes32(0),
            bytes32(
                (uint256(vm.load(address(pool), bytes32(0))) &
                    0xffffffffffffffffff000000ffffffffffffffffffffffffffffffffffffffff) +
                    (uint256(uint24(int24(int256(currentTick) + int256(tickDelta)))) << 160)
            )
        );

        vm.expectRevert(Errors.StaleTWAP.selector);
        pp.liquidate(new TokenId[](0), Alice, LeftRightUnsigned.wrap(0), new TokenId[](0));
    }

    function test_Fail_liquidate_NotMarginCalled(
        uint256 x,
        uint256 numLegs,
        uint256[4] memory isLongs,
        uint256[4] memory tokenTypes,
        uint256[4] memory widthSeeds,
        int256[4] memory strikeSeeds,
        uint256 positionSizeSeed,
        uint256 swapSizeSeed,
        uint256 collateralBalanceSeed,
        uint256 collateralRatioSeed
    ) public {
        _initPool(x);

        numLegs = bound(numLegs, 1, 4);

        int24[4] memory widths;
        int24[4] memory strikes;

        for (uint256 i = 0; i < numLegs; ++i) {
            tokenTypes[i] = bound(tokenTypes[i], 0, 1);
            isLongs[i] = bound(isLongs[i], 0, 1);
            (widths[i], strikes[i]) = getValidSW(
                widthSeeds[i],
                strikeSeeds[i],
                uint24(tickSpacing),
                // distancing tickSpacing ensures this position stays OTM throughout this test case. ITM is tested elsewhere.
                currentTick
            );

            // make sure there are no conflicts
            for (uint256 j = 0; j < i; ++j) {
                vm.assume(
                    widths[i] != widths[j] ||
                        strikes[i] != strikes[j] ||
                        tokenTypes[i] != tokenTypes[j]
                );
            }
        }
        if (numLegs == 1) populatePositionData(widths[0], strikes[0], positionSizeSeed);
        if (numLegs == 2)
            populatePositionData(
                [widths[0], widths[1]],
                [strikes[0], strikes[1]],
                positionSizeSeed
            );
        if (numLegs == 3)
            populatePositionData(
                [widths[0], widths[1], widths[2]],
                [strikes[0], strikes[1], strikes[2]],
                positionSizeSeed
            );
        if (numLegs == 4) populatePositionData(widths, strikes, positionSizeSeed);

        // this is a long option; so need to sell before it can be bought (let's say 2x position size for now)
        vm.startPrank(Seller);

        for (uint256 i = 0; i < numLegs; ++i) {
            $posIdLists[0].push(
                TokenId.wrap(0).addPoolId(poolId).addLeg(
                    0,
                    1,
                    isWETH,
                    0,
                    tokenTypes[i],
                    0,
                    strikes[i],
                    widths[i]
                )
            );
            pp.mintOptions($posIdLists[0], positionSize * 2, 0, 0, 0);
        }

        twoWaySwap(swapSizeSeed);

        // now we can mint the long option we are force exercising
        vm.startPrank(Alice);

        for (uint256 i = 0; i < numLegs; ++i) {
            $posIdLists[1].push(
                TokenId.wrap(0).addPoolId(poolId).addLeg(
                    0,
                    1,
                    isWETH,
                    isLongs[i],
                    tokenTypes[i],
                    0,
                    strikes[i],
                    widths[i]
                )
            );

            pp.mintOptions($posIdLists[1], positionSize, type(uint64).max, 0, 0);
        }

        twoWaySwap(swapSizeSeed);

        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();

        vm.assume(Math.abs(int256(currentTick) - pp.getUniV3TWAP_()) <= 513);

        (, uint256 totalCollateralRequired0) = ph.checkCollateral(
            pp,
            Alice,
            pp.getUniV3TWAP_(),
            0,
            $posIdLists[1]
        );

        uint256 totalCollateralB0 = bound(
            collateralBalanceSeed,
            (totalCollateralRequired0 * 10_001) / 10_000,
            uint256(
                Math.min(
                    int256(uint256(type(uint104).max)),
                    int256(PanopticMath.convert1to0(type(uint104).max, currentSqrtPriceX96))
                )
            )
        );

        editCollateral(
            ct0,
            Alice,
            ct0.convertToShares(
                (totalCollateralB0 * bound(collateralRatioSeed, 0, 10_000)) / 10_000
            )
        );
        editCollateral(
            ct1,
            Alice,
            ct1.convertToShares(
                PanopticMath.convert0to1(
                    (totalCollateralB0 * (10_000 - bound(collateralRatioSeed, 0, 10_000))) / 10_000,
                    Math.getSqrtRatioAtTick(pp.getUniV3TWAP_())
                )
            )
        );

        vm.startPrank(Bob);

        vm.expectRevert(Errors.NotMarginCalled.selector);
        pp.liquidate(new TokenId[](0), Alice, LeftRightUnsigned.wrap(0), $posIdLists[1]);
    }
}
