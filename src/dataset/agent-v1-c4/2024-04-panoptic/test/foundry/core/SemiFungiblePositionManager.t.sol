// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {stdMath} from "forge-std/StdMath.sol";
import {Errors} from "@libraries/Errors.sol";
import {Math} from "@libraries/Math.sol";
import {PanopticMath} from "@libraries/PanopticMath.sol";
import {CallbackLib} from "@libraries/CallbackLib.sol";
import {TokenId} from "@types/TokenId.sol";
import {LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";
import {IERC20Partial} from "@tokens/interfaces/IERC20Partial.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";
import {FixedPoint128} from "v3-core/libraries/FixedPoint128.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {SqrtPriceMath} from "v3-core/libraries/SqrtPriceMath.sol";
import {PoolAddress} from "v3-periphery/libraries/PoolAddress.sol";
import {PositionKey} from "v3-periphery/libraries/PositionKey.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {SemiFungiblePositionManager} from "@contracts/SemiFungiblePositionManager.sol";
import {PanopticHelper} from "@periphery/PanopticHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PositionUtils} from "../testUtils/PositionUtils.sol";
import {UniPoolPriceMock} from "../testUtils/PriceMocks.sol";
import {ReenterMint, ReenterBurn, Reenter1155Initialize, ReenterTransferSingle, ReenterTransferBatch} from "../testUtils/ReentrancyMocks.sol";

contract SemiFungiblePositionManagerHarness is SemiFungiblePositionManager {
    constructor(IUniswapV3Factory _factory) SemiFungiblePositionManager(_factory) {}

    function poolContext(uint64 poolId) public view returns (PoolAddressAndLock memory) {
        return s_poolContext[poolId];
    }

    function addrToPoolId(address pool) public view returns (uint256) {
        return s_AddrToPoolIdData[pool];
    }
}

contract UniswapV3FactoryMock {
    uint160 nextPool;

    function getPool(address, address, uint24) external view returns (address) {
        return address(nextPool << 24);
    }

    function increment() external {
        nextPool++;
    }
}

contract SemiFungiblePositionManagerTest is PositionUtils {
    /*//////////////////////////////////////////////////////////////
                           MAINNET CONTRACTS
    //////////////////////////////////////////////////////////////*/

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
    IUniswapV3Pool[3] public pools = [USDC_WETH_5, USDC_WETH_5, USDC_WETH_30];

    /*//////////////////////////////////////////////////////////////
                              WORLD STATE
    //////////////////////////////////////////////////////////////*/

    // the instance of SFPM we are testing
    SemiFungiblePositionManagerHarness sfpm;

    // immutable data about the pool being tested
    IUniswapV3Pool pool;
    uint64 poolId;
    address token0;
    address token1;
    uint24 fee;
    int24 tickSpacing;
    uint256 isWETH; // We fuzz position size in terms of WETH, so we need to store which token is WETH

    // state data from the pool being tested
    int24 currentTick;
    uint160 currentSqrtPriceX96;
    uint256 feeGrowthGlobal0X128;
    uint256 feeGrowthGlobal1X128;

    // generic actor accounts
    address Alice = address(0x123456);
    address Bob = address(0x12345678);
    address Swapper = address(0x123456789);

    /*//////////////////////////////////////////////////////////////
                               TEST DATA
    //////////////////////////////////////////////////////////////*/

    //used to avoid stack too deep on return values
    LeftRightSigned totalCollectedBurn;
    LeftRightSigned totalSwappedBurn;
    LeftRightSigned totalCollectedMint;
    LeftRightSigned totalSwappedMint;
    LeftRightUnsigned accountLiquidities;
    uint256 premium0ShortOld;
    uint256 premium1ShortOld;
    uint256 premium0LongOld;
    uint256 premium1LongOld;

    uint256 premium0Short;
    uint256 premium1Short;
    uint256 premium0Long;
    uint256 premium1Long;

    int24 tickLower;
    int24 tickUpper;
    uint160 sqrtLower;
    uint160 sqrtUpper;

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

    uint256[2] premiaError0;
    uint256[2] premiaError1;

    uint256 $swap0;
    uint256 $swap1;

    uint256 balanceBefore0;
    uint256 balanceBefore1;

    int24[] tickLowers;
    int24[] tickUppers;
    uint160[] sqrtLowers;
    uint160[] sqrtUppers;

    uint128[] positionSizes;
    uint128[] positionSizesBurn;

    uint128[] expectedLiqs;
    uint128[] expectedLiqsMint;
    uint128[] expectedLiqsBurn;

    int256[] $amount0Moveds;
    int256[] $amount1Moveds;
    int256[] $amount0MovedsMint;
    int256[] $amount1MovedsMint;
    int256[] $amount0MovedsBurn;
    int256[] $amount1MovedsBurn;

    /*//////////////////////////////////////////////////////////////
                               ENV SETUP
    //////////////////////////////////////////////////////////////*/

    /// @notice Intialize testing pool in the SFPM instance after world state is setup
    function _initPool(uint256 seed) internal {
        _initWorld(seed);
        sfpm.initializeAMMPool(token0, token1, fee);
    }

    /// @notice Set up world state with data from a random pool off the list and fund+approve actors
    function _initWorld(uint256 seed) internal {
        // Pick a pool from the seed and cache initial state
        _cacheWorldState(pools[bound(seed, 0, pools.length - 1)]);

        // Fund some of the the generic actor accounts
        vm.startPrank(Bob);

        deal(token0, Bob, type(uint128).max);
        deal(token1, Bob, type(uint128).max);

        IERC20Partial(token0).approve(address(sfpm), type(uint256).max);
        IERC20Partial(token1).approve(address(sfpm), type(uint256).max);

        IERC20Partial(token0).approve(address(router), type(uint256).max);
        IERC20Partial(token1).approve(address(router), type(uint256).max);

        vm.startPrank(Swapper);

        IERC20Partial(token0).approve(address(router), type(uint256).max);
        IERC20Partial(token1).approve(address(router), type(uint256).max);

        deal(token0, Swapper, type(uint128).max);
        deal(token1, Swapper, type(uint128).max);

        vm.startPrank(Alice);

        deal(token0, Alice, type(uint128).max);
        deal(token1, Alice, type(uint128).max);

        IERC20Partial(token0).approve(address(sfpm), type(uint256).max);
        IERC20Partial(token1).approve(address(sfpm), type(uint256).max);

        IERC20Partial(token0).approve(address(router), type(uint256).max);
        IERC20Partial(token1).approve(address(router), type(uint256).max);
    }

    /// @notice Populate world state with data from a given pool
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
    }

    function setUp() public {
        sfpm = new SemiFungiblePositionManagerHarness(V3FACTORY);
    }

    /*//////////////////////////////////////////////////////////////
                          TEST DATA POPULATION
    //////////////////////////////////////////////////////////////*/

    function populatePositionData(int24 width, int24 strike, uint256 positionSizeSeed) internal {
        tickLower = int24(strike - (width * tickSpacing) / 2);
        tickUpper = int24(strike + (width * tickSpacing) / 2);
        sqrtLower = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        // 0.0001 -> 10_000 WETH
        positionSizeSeed = bound(positionSizeSeed, 10 ** 15, 10 ** 22);

        // calculate the amount of ETH contracts needed to create a position with above attributes and value in ETH
        positionSize = uint128(
            getContractsForAmountAtTick(currentTick, tickLower, tickUpper, isWETH, positionSizeSeed)
        );

        // `getContractsForAmountAtTick` calculates liquidity under the hood, but SFPM does this conversion
        // as well and using the original value could result in discrepancies due to rounding
        expectedLiq = isWETH == 0
            ? LiquidityAmounts.getLiquidityForAmount0(sqrtLower, sqrtUpper, positionSize)
            : LiquidityAmounts.getLiquidityForAmount1(sqrtLower, sqrtUpper, positionSize);
        expectedLiqs.push(expectedLiq);

        $amount0Moved = sqrtUpper < currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
                sqrtUpper,
                int128(expectedLiq)
            );
        $amount0Moveds.push($amount0Moved);

        $amount1Moved = sqrtLower > currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount1Delta(
                sqrtLower,
                sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
                int128(expectedLiq)
            );
        $amount1Moveds.push($amount1Moved);
    }

    function populatePositionData(
        int24 width,
        int24 strike,
        uint256[2] memory positionSizeSeeds
    ) internal {
        tickLower = int24(strike - (width * tickSpacing) / 2);
        tickUpper = int24(strike + (width * tickSpacing) / 2);
        sqrtLower = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        positionSizeSeeds[0] = bound(positionSizeSeeds[0], 10 ** 15, 10 ** 22);
        positionSizeSeeds[1] = bound(positionSizeSeeds[1], 10 ** 15, 10 ** 22);

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
                ? LiquidityAmounts.getLiquidityForAmount0(sqrtLower, sqrtUpper, positionSizes[0])
                : LiquidityAmounts.getLiquidityForAmount1(sqrtLower, sqrtUpper, positionSizes[0])
        );

        expectedLiqs.push(
            isWETH == 0
                ? LiquidityAmounts.getLiquidityForAmount0(sqrtLower, sqrtUpper, positionSizes[1])
                : LiquidityAmounts.getLiquidityForAmount1(sqrtLower, sqrtUpper, positionSizes[1])
        );

        $amount0Moveds.push(
            sqrtUpper < currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount0Delta(
                    sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
                    sqrtUpper,
                    int128(expectedLiqs[0])
                )
        );

        $amount0Moveds.push(
            sqrtUpper < currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount0Delta(
                    sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
                    sqrtUpper,
                    int128(expectedLiqs[1])
                )
        );

        $amount1Moveds.push(
            sqrtLower > currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount1Delta(
                    sqrtLower,
                    sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
                    int128(expectedLiqs[0])
                )
        );

        $amount1Moveds.push(
            sqrtLower > currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount1Delta(
                    sqrtLower,
                    sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
                    int128(expectedLiqs[1])
                )
        );
    }

    function populatePositionData(
        int24[2] memory width,
        int24[2] memory strike,
        uint256 positionSizeSeed
    ) internal {
        tickLowers.push(int24(strike[0] - (width[0] * tickSpacing) / 2));
        tickUppers.push(int24(strike[0] + (width[0] * tickSpacing) / 2));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[0]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[0]));

        tickLowers.push(int24(strike[1] - (width[1] * tickSpacing) / 2));
        tickUppers.push(int24(strike[1] + (width[1] * tickSpacing) / 2));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[1]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[1]));

        // 0.0001 -> 10_000 WETH
        positionSizeSeed = bound(positionSizeSeed, 10 ** 15, 10 ** 22);

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
                ? LiquidityAmounts.getLiquidityForAmount0(
                    sqrtLowers[0],
                    sqrtUppers[0],
                    positionSize
                )
                : LiquidityAmounts.getLiquidityForAmount1(
                    sqrtLowers[0],
                    sqrtUppers[0],
                    positionSize
                )
        );

        expectedLiqs.push(
            isWETH == 0
                ? LiquidityAmounts.getLiquidityForAmount0(
                    sqrtLowers[1],
                    sqrtUppers[1],
                    positionSize
                )
                : LiquidityAmounts.getLiquidityForAmount1(
                    sqrtLowers[1],
                    sqrtUppers[1],
                    positionSize
                )
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
        vm.assume(ETHValue >= 10 ** 15);
        vm.assume(ETHValue <= 10 ** 22);
    }

    // second positionSizeSeed is to back single long leg
    function populatePositionDataLong(
        int24[2] memory width,
        int24[2] memory strike,
        uint256[2] memory positionSizeSeed
    ) internal {
        tickLowers.push(int24(strike[0] - (width[0] * tickSpacing) / 2));
        tickUppers.push(int24(strike[0] + (width[0] * tickSpacing) / 2));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[0]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[0]));

        tickLowers.push(int24(strike[1] - (width[1] * tickSpacing) / 2));
        tickUppers.push(int24(strike[1] + (width[1] * tickSpacing) / 2));
        sqrtLowers.push(TickMath.getSqrtRatioAtTick(tickLowers[1]));
        sqrtUppers.push(TickMath.getSqrtRatioAtTick(tickUppers[1]));

        // 0.0001 -> 10_000 WETH
        positionSizeSeed[0] = bound(positionSizeSeed[0], 10 ** 16, 10 ** 22);
        // since this is for a long leg it has to be smaller than the short liquidity it's trying to buy
        positionSizeSeed[1] = bound(positionSizeSeed[1], 10 ** 15, positionSizeSeed[0] / 10);

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
                ? LiquidityAmounts.getLiquidityForAmount0(
                    sqrtLowers[1],
                    sqrtUppers[1],
                    positionSizes[0]
                )
                : LiquidityAmounts.getLiquidityForAmount1(
                    sqrtLowers[1],
                    sqrtUppers[1],
                    positionSizes[0]
                )
        );

        expectedLiqs.push(
            isWETH == 0
                ? LiquidityAmounts.getLiquidityForAmount0(
                    sqrtLowers[0],
                    sqrtUppers[0],
                    positionSizes[1]
                )
                : LiquidityAmounts.getLiquidityForAmount1(
                    sqrtLowers[0],
                    sqrtUppers[0],
                    positionSizes[1]
                )
        );

        expectedLiqs.push(
            isWETH == 0
                ? LiquidityAmounts.getLiquidityForAmount0(
                    sqrtLowers[1],
                    sqrtUppers[1],
                    positionSizes[1]
                )
                : LiquidityAmounts.getLiquidityForAmount1(
                    sqrtLowers[1],
                    sqrtUppers[1],
                    positionSizes[1]
                )
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

        // ensure second leg is sufficiently large
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            currentSqrtPriceX96,
            sqrtLowers[0],
            sqrtUppers[0],
            expectedLiqs[1]
        );
        uint256 priceX128 = FullMath.mulDiv(currentSqrtPriceX96, currentSqrtPriceX96, 2 ** 64);
        // total ETH value must be >= 10 ** 15
        uint256 ETHValue = isWETH == 0
            ? amount0 + FullMath.mulDiv(amount1, 2 ** 128, priceX128)
            : Math.mulDiv128(amount0, priceX128) + amount1;
        vm.assume(ETHValue >= 10 ** 15);
        vm.assume(ETHValue <= 10 ** 22);
    }

    function updatePositionLiqSingleLong() public {
        expectedLiqs.push(
            isWETH == 0
                ? LiquidityAmounts.getLiquidityForAmount0(sqrtLower, sqrtUpper, positionSize)
                : LiquidityAmounts.getLiquidityForAmount1(sqrtLower, sqrtUpper, positionSize)
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

    function populatePositionData(
        int24 width,
        int24 strike,
        uint256 positionSizeSeed,
        uint256 positionSizeBurnSeed
    ) internal {
        tickLower = int24(strike - (width * tickSpacing) / 2);
        tickUpper = int24(strike + (width * tickSpacing) / 2);
        sqrtLower = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        // 0.0001 -> 10_000 WETH
        positionSizeSeed = bound(positionSizeSeed, 10 ** 15, 10 ** 22);
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
            ? LiquidityAmounts.getLiquidityForAmount0(
                sqrtLower,
                sqrtUpper,
                positionSize - positionSizeBurn
            )
            : LiquidityAmounts.getLiquidityForAmount1(
                sqrtLower,
                sqrtUpper,
                positionSize - positionSizeBurn
            );

        expectedLiqMint = isWETH == 0
            ? LiquidityAmounts.getLiquidityForAmount0(sqrtLower, sqrtUpper, positionSize)
            : LiquidityAmounts.getLiquidityForAmount1(sqrtLower, sqrtUpper, positionSize);

        expectedLiqBurn = isWETH == 0
            ? LiquidityAmounts.getLiquidityForAmount0(sqrtLower, sqrtUpper, positionSizeBurn)
            : LiquidityAmounts.getLiquidityForAmount1(sqrtLower, sqrtUpper, positionSizeBurn);

        $amount0MovedBurn = sqrtUpper < currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
                sqrtUpper,
                int128(expectedLiqBurn)
            );

        $amount1MovedBurn = sqrtLower > currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount1Delta(
                sqrtLower,
                sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
                int128(expectedLiqBurn)
            );

        $amount0MovedMint = sqrtUpper < currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
                sqrtUpper,
                int128(expectedLiqMint)
            );

        $amount1MovedMint = sqrtLower > currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount1Delta(
                sqrtLower,
                sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
                int128(expectedLiqMint)
            );
    }

    function updateAmountsMovedSingle(int128 liquidity) internal {
        $amount0Moved = sqrtUpper < currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
                sqrtUpper,
                liquidity
            );

        $amount1Moved = sqrtLower > currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount1Delta(
                sqrtLower,
                sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
                liquidity
            );
    }

    function updateAmountsMovedSingleSwap(int128 liquidity, uint256 tokenType) internal {
        $amount0Moved = sqrtUpper < currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
                sqrtUpper,
                liquidity
            );

        $amount1Moved = sqrtLower > currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount1Delta(
                sqrtLower,
                sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
                liquidity
            );

        bool zeroForOne;
        int256 swapAmount;
        if (tokenType == 0) {
            zeroForOne = $amount1Moved > 0;
            swapAmount = -$amount1Moved;
        } else {
            zeroForOne = $amount0Moved < 0;
            swapAmount = -$amount0Moved;
        }

        vm.startPrank(address(sfpm));
        ($swap0, $swap1) = PositionUtils.simulateSwap(
            pool,
            tickLower,
            tickUpper,
            liquidity,
            router,
            token0,
            token1,
            fee,
            zeroForOne,
            swapAmount
        );

        if (tokenType == 0) {
            $amount0Moved = liquidity > 0 ? int256($swap0) : -int256($swap0) + $amount0Moved;
            $amount1Moved = 0;
        } else {
            $amount0Moved = 0;
            $amount1Moved = liquidity > 0 ? int256($swap1) : -int256($swap1) + $amount1Moved;
        }
    }

    // used to accumulate premia for testing
    function twoWaySwap(uint256 swapSize) public {
        vm.startPrank(Swapper);

        swapSize = bound(swapSize, 10 ** 18, 10 ** 20);
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

        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();
    }

    /*//////////////////////////////////////////////////////////////
                         POOL INITIALIZATION: +
    //////////////////////////////////////////////////////////////*/

    function test_Success_initializeAMMPool_Single(uint256 x) public {
        _initPool(x);

        // Check that the pool address is set correctly
        assertEq(
            address(sfpm.poolContext(PanopticMath.getPoolId(address(pool))).pool),
            address(pool)
        );

        // Check that the pool ID is set correctly
        assertEq(
            sfpm.addrToPoolId(address(pool)),
            PanopticMath.getPoolId(address(pool)) + 2 ** 255
        );
    }

    function test_Success_initializeAMMPool_Multiple() public {
        // Loop through all pools and test
        for (uint256 i = 0; i < pools.length; i++) {
            _cacheWorldState(pools[i]);
            sfpm.initializeAMMPool(token0, token1, fee);

            // Check that the pool address is set correctly
            assertEq(
                address(sfpm.poolContext(PanopticMath.getPoolId(address(pool))).pool),
                address(pool)
            );

            // Check that the pool ID is set correctly
            assertEq(
                sfpm.addrToPoolId(address(pool)),
                PanopticMath.getPoolId(address(pool)) + 2 ** 255
            );
        }
    }

    function test_Success_initializeAMMPool_HandleCollisions() public {
        // Create a mock factory that generates colliding pool addresses
        UniswapV3FactoryMock factoryMock = new UniswapV3FactoryMock();

        // Create an instance of the SFPM tied to the factory mock that generates colliding pool addresses
        SemiFungiblePositionManagerHarness sfpm_t = new SemiFungiblePositionManagerHarness(
            IUniswapV3Factory(address(factoryMock))
        );

        UniPoolPriceMock pm = new UniPoolPriceMock();
        uint64 poolIdNew = (200 << 48);
        for (uint160 i = 0; i < 100; i++) {
            factoryMock.increment();

            vm.etch(address((i + 1) << 24), address(pm).code);

            pm = UniPoolPriceMock(address((i + 1) << 24));
            pm.construct(
                UniPoolPriceMock.Slot0({
                    sqrtPriceX96: 0,
                    tick: 0,
                    observationIndex: 0,
                    observationCardinality: 0,
                    observationCardinalityNext: 0,
                    feeProtocol: 0,
                    unlocked: false
                }),
                address(0),
                address(0),
                0,
                200
            );

            // etch tickSpacing
            // These values are zero at this point, but they are ignored by the factory mock
            sfpm_t.initializeAMMPool(token0, token1, fee);

            if (i != 0) {
                poolIdNew = PanopticMath.incrementPoolPattern(poolIdNew);
            }

            // Check that the pool address is set correctly
            assertEq(address(sfpm_t.poolContext(poolIdNew).pool), address((i + 1) << 24));

            // Check that the pool ID is set correctly
            // Addresses output from the factory mock start at 1 to avoid errors so we need to add that to the address
            assertEq(sfpm_t.addrToPoolId(address((i + 1) << 24)), 2 ** 255 + poolIdNew);

            token0 = address(uint160(token0) + 1);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         POOL INITIALIZATION: -
    //////////////////////////////////////////////////////////////*/

    function test_Fail_initializeAMMPool_uniswapPoolNotInitialized() public {
        vm.expectRevert(Errors.UniswapPoolNotInitialized.selector);

        // These values are zero at this point; thus there is no corresponding uni pool and we should revert
        sfpm.initializeAMMPool(token0, token1, fee);
    }

    /// NOTE - the definitions of "call" and "put" can vary by Uniswap pair and which token is considered the asset
    /// For the purposes of these tests, we define the asset to be token1
    /// This means that "call" is `tokenType` = 0 and "put" is `tokenType` = 1

    /*//////////////////////////////////////////////////////////////
                         OUT-OF-RANGE MINTS: +
    //////////////////////////////////////////////////////////////*/

    function test_Success_mintTokenizedPosition_OutsideRangeShortCall(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped) = sfpm
            .mintTokenizedPosition(
                tokenId,
                uint128(positionSize),
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

        assertEq(
            LeftRightUnsigned.unwrap(collectedByLeg[0]) +
                LeftRightUnsigned.unwrap(collectedByLeg[1]) +
                LeftRightUnsigned.unwrap(collectedByLeg[2]) +
                LeftRightUnsigned.unwrap(collectedByLeg[3]),
            0
        );

        assertEq(totalSwapped.rightSlot(), $amount0Moved);
        assertEq(totalSwapped.leftSlot(), $amount1Moved);

        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(tokenId)), positionSize);

        accountLiquidities = sfpm.getAccountLiquidity(
            address(pool),
            Alice,
            0,
            tickLower,
            tickUpper
        );

        assertEq(accountLiquidities.leftSlot(), 0);
        assertEq(accountLiquidities.rightSlot(), expectedLiq);

        (uint256 realLiq, , , , ) = pool.positions(
            keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
        );

        assertEq(realLiq, expectedLiq);
    }

    function test_Success_mintTokenizedPosition_OutsideRangeShortPut(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped) = sfpm
            .mintTokenizedPosition(
                tokenId,
                uint128(positionSize),
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

        assertEq(
            LeftRightUnsigned.unwrap(collectedByLeg[0]) +
                LeftRightUnsigned.unwrap(collectedByLeg[1]) +
                LeftRightUnsigned.unwrap(collectedByLeg[2]) +
                LeftRightUnsigned.unwrap(collectedByLeg[3]),
            0
        );

        assertEq(totalSwapped.rightSlot(), $amount0Moved);
        assertEq(totalSwapped.leftSlot(), $amount1Moved);

        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(tokenId)), positionSize);

        accountLiquidities = sfpm.getAccountLiquidity(
            address(pool),
            Alice,
            1,
            tickLower,
            tickUpper
        );

        assertEq(accountLiquidities.leftSlot(), 0);
        assertEq(accountLiquidities.rightSlot(), expectedLiq);

        (uint256 realLiq, , , , ) = pool.positions(
            keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
        );

        assertEq(realLiq, expectedLiq);
    }

    function test_Success_mintTokenizedPosition_OutOfRangeShortCallLongCall(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed,
        uint256 shortRatio,
        uint256 longRatio
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        shortRatio = bound(shortRatio, 1, 127);
        longRatio = bound(longRatio, 1, shortRatio);

        // ensure that the true positionSize is the equal to the generated value
        // positionSizeReal = positionSize * optionRatio
        positionSize = positionSize / uint128(shortRatio);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            shortRatio,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        // long leg
        TokenId longTokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            longRatio,
            isWETH,
            1,
            0,
            0,
            strike,
            width
        );

        // we can't use the populated values because they don't account for the option ratios, so must recalculate
        expectedLiq = isWETH == 0
            ? LiquidityAmounts.getLiquidityForAmount0(
                sqrtLower,
                sqrtUpper,
                positionSize * shortRatio
            )
            : LiquidityAmounts.getLiquidityForAmount1(
                sqrtLower,
                sqrtUpper,
                positionSize * shortRatio
            );
        uint256 removedLiq = isWETH == 0
            ? LiquidityAmounts.getLiquidityForAmount0(
                sqrtLower,
                sqrtUpper,
                positionSize * longRatio
            )
            : LiquidityAmounts.getLiquidityForAmount1(
                sqrtLower,
                sqrtUpper,
                positionSize * longRatio
            );

        $amount0Moved = sqrtUpper < currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
                sqrtUpper,
                int128(expectedLiq)
            );

        $amount1Moved = sqrtLower > currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount1Delta(
                sqrtLower,
                sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
                int128(expectedLiq)
            );

        (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped) = sfpm
            .mintTokenizedPosition(
                tokenId,
                uint128(positionSize),
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

        (LeftRightUnsigned[4] memory collectedByLegLong, LeftRightSigned totalSwappedLong) = sfpm
            .mintTokenizedPosition(
                longTokenId,
                uint128(positionSize),
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

        assertEq(
            LeftRightUnsigned.unwrap(collectedByLeg[0]) +
                LeftRightUnsigned.unwrap(collectedByLeg[1]) +
                LeftRightUnsigned.unwrap(collectedByLeg[2]) +
                LeftRightUnsigned.unwrap(collectedByLeg[3]),
            0
        );
        assertEq(
            LeftRightUnsigned.unwrap(collectedByLegLong[0]) +
                LeftRightUnsigned.unwrap(collectedByLegLong[1]) +
                LeftRightUnsigned.unwrap(collectedByLegLong[2]) +
                LeftRightUnsigned.unwrap(collectedByLegLong[3]),
            0
        );

        assertApproxEqAbs(
            totalSwapped.rightSlot(),
            $amount0Moved,
            uint256($amount0Moved / 1_000_000 + 10)
        );
        assertApproxEqAbs(
            totalSwapped.leftSlot(),
            $amount1Moved,
            uint256($amount1Moved / 1_000_000 + 10)
        );

        $amount0Moved = sqrtUpper < currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
                sqrtUpper,
                -int128(int256(removedLiq))
            );

        $amount1Moved = sqrtLower > currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount1Delta(
                sqrtLower,
                sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
                -int128(int256(removedLiq))
            );

        assertApproxEqAbs(
            totalSwappedLong.rightSlot(),
            $amount0Moved,
            uint256($amount0Moved / 1_000_000 + 10)
        );
        assertApproxEqAbs(
            totalSwappedLong.leftSlot(),
            $amount1Moved,
            uint256($amount1Moved / 1_000_000 + 10)
        );

        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(tokenId)), positionSize);
        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(longTokenId)), positionSize);

        accountLiquidities = sfpm.getAccountLiquidity(
            address(pool),
            Alice,
            0,
            tickLower,
            tickUpper
        );

        assertEq(accountLiquidities.leftSlot(), removedLiq);
        assertApproxEqAbs(accountLiquidities.rightSlot(), expectedLiq - removedLiq, 10);

        (uint256 realLiq, , , uint256 tokensOwed0, uint256 tokensOwed1) = pool.positions(
            keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
        );
        assertApproxEqAbs(realLiq, expectedLiq - removedLiq, 10);
        assertEq(tokensOwed0, 0);
        assertEq(tokensOwed1, 0);

        assertEq(IERC20Partial(token0).balanceOf(address(sfpm)), 0);
        assertEq(IERC20Partial(token1).balanceOf(address(sfpm)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                           IN-RANGE MINTS: +
    //////////////////////////////////////////////////////////////*/

    function test_Success_mintTokenizedPosition_InRangeShortPutNoSwap(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getInRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped) = sfpm
            .mintTokenizedPosition(
                tokenId,
                uint128(positionSize),
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

        assertEq(
            LeftRightUnsigned.unwrap(collectedByLeg[0]) +
                LeftRightUnsigned.unwrap(collectedByLeg[1]) +
                LeftRightUnsigned.unwrap(collectedByLeg[2]) +
                LeftRightUnsigned.unwrap(collectedByLeg[3]),
            0
        );

        assertEq(totalSwapped.rightSlot(), $amount0Moved);
        assertEq(totalSwapped.leftSlot(), $amount1Moved);

        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(tokenId)), positionSize);

        accountLiquidities = sfpm.getAccountLiquidity(
            address(pool),
            Alice,
            1,
            tickLower,
            tickUpper
        );

        assertEq(accountLiquidities.leftSlot(), 0);
        assertEq(accountLiquidities.rightSlot(), expectedLiq);

        (uint256 realLiq, , , , ) = pool.positions(
            keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
        );

        assertEq(realLiq, expectedLiq);
    }

    function test_Success_mintTokenizedPosition_InRangeShortPutSwap(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getInRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        int256 amount0Required = SqrtPriceMath.getAmount0Delta(
            sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
            sqrtUpper,
            int128(expectedLiq)
        );

        int256 amount1Moved = SqrtPriceMath.getAmount1Delta(
            sqrtLower,
            sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
            int128(expectedLiq)
        );

        (, uint256 amount1) = PositionUtils.simulateSwap(
            pool,
            tickLower,
            tickUpper,
            expectedLiq,
            router,
            token0,
            token1,
            fee,
            false,
            -amount0Required
        );

        vm.startPrank(Alice);

        // The max/min tick cannot be set as slippage limits, so we subtract/add 1
        // We also invert the order; this is how we tell SFPM to trigger a swap
        (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped) = sfpm
            .mintTokenizedPosition(
                tokenId,
                positionSize,
                TickMath.MAX_TICK - 1,
                TickMath.MIN_TICK + 1
            );

        assertEq(
            LeftRightUnsigned.unwrap(collectedByLeg[0]) +
                LeftRightUnsigned.unwrap(collectedByLeg[1]) +
                LeftRightUnsigned.unwrap(collectedByLeg[2]) +
                LeftRightUnsigned.unwrap(collectedByLeg[3]),
            0
        );

        assertEq(totalSwapped.rightSlot(), 0);
        assertEq(totalSwapped.leftSlot(), int256(amount1) + amount1Moved);

        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(tokenId)), positionSize);

        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Alice,
                1,
                tickLower,
                tickUpper
            );

            assertEq(accountLiquidities.leftSlot(), 0);
            assertEq(accountLiquidities.rightSlot(), expectedLiq);

            (uint256 realLiq, , , , ) = pool.positions(
                keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
            );

            assertEq(realLiq, expectedLiq);
        }

        {
            assertEq(IERC20Partial(token0).balanceOf(Alice), type(uint128).max);
        }
    }

    function test_Success_mintTokenizedPosition_InRangeShortCallSwap(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getInRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        int256 amount0Moved = SqrtPriceMath.getAmount0Delta(
            sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
            sqrtUpper,
            int128(expectedLiq)
        );

        int256 amount1Required = SqrtPriceMath.getAmount1Delta(
            sqrtLower,
            sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
            int128(expectedLiq)
        );

        (uint256 amount0, ) = PositionUtils.simulateSwap(
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

        // The max/min tick cannot be set as slippage limits, so we subtract/add 1
        // We also invert the order; this is how we tell SFPM to trigger a swap
        (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped) = sfpm
            .mintTokenizedPosition(
                tokenId,
                uint128(positionSize),
                TickMath.MAX_TICK - 1,
                TickMath.MIN_TICK + 1
            );

        assertEq(
            LeftRightUnsigned.unwrap(collectedByLeg[0]) +
                LeftRightUnsigned.unwrap(collectedByLeg[1]) +
                LeftRightUnsigned.unwrap(collectedByLeg[2]) +
                LeftRightUnsigned.unwrap(collectedByLeg[3]),
            0
        );
        assertEq(totalSwapped.rightSlot(), int256(amount0) + amount0Moved);
        assertEq(totalSwapped.leftSlot(), 0);

        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(tokenId)), positionSize);

        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Alice,
                0,
                tickLower,
                tickUpper
            );

            assertEq(accountLiquidities.leftSlot(), 0);
            assertEq(accountLiquidities.rightSlot(), expectedLiq);

            (uint256 realLiq, , , , ) = pool.positions(
                keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
            );

            assertEq(realLiq, expectedLiq);
        }

        {
            assertEq(IERC20Partial(token1).balanceOf(Alice), type(uint128).max);
        }
    }

    function test_Success_mintTokenizedPosition_ITMShortPutShortCallCombinedSwap(
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

        vm.assume(width0 != width1 || strike0 != strike1);

        populatePositionData([width0, width1], [strike0, strike1], positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        // The max/min tick cannot be set as slippage limits, so we subtract/add 1
        // We also invert the order; this is how we tell SFPM to trigger a swap
        (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped) = sfpm
            .mintTokenizedPosition(
                tokenId,
                positionSize,
                TickMath.MAX_TICK - 1,
                TickMath.MIN_TICK + 1
            );

        assertEq(
            LeftRightUnsigned.unwrap(collectedByLeg[0]) +
                LeftRightUnsigned.unwrap(collectedByLeg[1]) +
                LeftRightUnsigned.unwrap(collectedByLeg[2]) +
                LeftRightUnsigned.unwrap(collectedByLeg[3]),
            0
        );

        assertEq(totalSwapped.rightSlot(), amount0s + $amount0Moveds[0] + $amount0Moveds[1]);
        assertEq(totalSwapped.leftSlot(), amount1s + $amount1Moveds[0] + $amount1Moveds[1]);

        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(tokenId)), positionSize);

        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Alice,
                1,
                tickLowers[0],
                tickUppers[0]
            );
            assertEq(accountLiquidities.leftSlot(), 0);
            assertEq(accountLiquidities.rightSlot(), expectedLiqs[0]);

            (uint256 realLiq, , , , ) = pool.positions(
                keccak256(abi.encodePacked(address(sfpm), tickLowers[0], tickUppers[0]))
            );

            assertEq(realLiq, expectedLiqs[0]);
        }

        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Alice,
                0,
                tickLowers[1],
                tickUppers[1]
            );
            assertEq(accountLiquidities.leftSlot(), 0);
            assertEq(accountLiquidities.rightSlot(), expectedLiqs[1]);

            (uint256 realLiq, , , , ) = pool.positions(
                keccak256(abi.encodePacked(address(sfpm), tickLowers[1], tickUppers[1]))
            );

            assertEq(realLiq, expectedLiqs[1]);
        }
    }

    function test_Success_mintTokenizedPosition_ITMShortPutLongCallCombinedSwap(
        uint256 x,
        uint256[2] memory widthSeeds,
        int256[2] memory strikeSeeds,
        uint256[2] memory positionSizeSeed
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

        vm.assume(width0 != width1 || strike0 != strike1);

        populatePositionDataLong([width0, width1], [strike0, strike1], positionSizeSeed);

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

        sfpm.mintTokenizedPosition(
            tokenId,
            positionSizes[0],
            TickMath.MIN_TICK + 1,
            TickMath.MAX_TICK - 1
        );

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
        // put leg
        tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, isWETH, 0, 1, 0, strike0, width0);

        // call leg
        tokenId = tokenId.addLeg(1, 1, isWETH, 1, 0, 1, strike1, width1);

        // price changes afters swap at mint so we need to update the price
        (currentSqrtPriceX96, , , , , , ) = pool.slot0();
        updatePositionDataLong();

        int256 netSurplus0 = $amount0Moveds[1] -
            PanopticMath.convert1to0($amount1Moveds[2], currentSqrtPriceX96);

        // we have to burn from the SFPM because it owns the liquidity
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

        // The max/min tick cannot be set as slippage limits, so we subtract/add 1
        // We also invert the order; this is how we tell SFPM to trigger a swap
        (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped) = sfpm
            .mintTokenizedPosition(
                tokenId,
                positionSizes[1],
                TickMath.MAX_TICK - 1,
                TickMath.MIN_TICK + 1
            );

        assertEq(
            LeftRightUnsigned.unwrap(collectedByLeg[0]) +
                LeftRightUnsigned.unwrap(collectedByLeg[1]) +
                LeftRightUnsigned.unwrap(collectedByLeg[2]) +
                LeftRightUnsigned.unwrap(collectedByLeg[3]),
            0
        );

        assertEq(totalSwapped.rightSlot(), amount0s + $amount0Moveds[1] + $amount0Moveds[2]);
        assertEq(totalSwapped.leftSlot(), amount1s + $amount1Moveds[1] + $amount1Moveds[2]);

        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(tokenId)), positionSizes[1]);

        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Alice,
                1,
                tickLowers[0],
                tickUppers[0]
            );
            assertEq(accountLiquidities.leftSlot(), 0);
            assertEq(accountLiquidities.rightSlot(), expectedLiqs[1]);

            (uint256 realLiq, , , , ) = pool.positions(
                keccak256(abi.encodePacked(address(sfpm), tickLowers[0], tickUppers[0]))
            );

            assertEq(realLiq, expectedLiqs[1]);
        }

        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Alice,
                0,
                tickLowers[1],
                tickUppers[1]
            );
            assertEq(accountLiquidities.leftSlot(), expectedLiqs[2]);
            assertEq(accountLiquidities.rightSlot(), expectedLiqs[0] - expectedLiqs[2]);

            (uint256 realLiq, , , , ) = pool.positions(
                keccak256(abi.encodePacked(address(sfpm), tickLowers[1], tickUppers[1]))
            );

            assertEq(realLiq, expectedLiqs[0] - expectedLiqs[2]);
        }
    }

    function test_Success_mintTokenizedPosition_PriceBound(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed,
        int256 lowerBound,
        int256 upperBound
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        lowerBound = bound(lowerBound, TickMath.MIN_TICK, currentTick - 1);
        upperBound = bound(upperBound, currentTick + 1, TickMath.MAX_TICK);

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            int24(lowerBound),
            int24(upperBound)
        );
    }

    /*//////////////////////////////////////////////////////////////
                         OUT-OF-RANGE MINTS: -
    //////////////////////////////////////////////////////////////*/

    function test_Fail_mintTokenizedPosition_positionSize0(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        vm.expectRevert(Errors.OptionsBalanceZero.selector);

        sfpm.mintTokenizedPosition(tokenId, uint128(0), TickMath.MIN_TICK, TickMath.MAX_TICK);
    }

    // previously there was a dust threshold on minting for tokens below the amount of 50
    // now there is no restriction on the amount
    function test_Success_mintTokenizedPosition_minorPosition(
        uint256 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed
    ) public {
        // dust threshold is only in effect if both tokens are <10 wei so it's easiest to use a pool with a price close to 1
        _cacheWorldState(USDC_USDT_5);

        // since we didn't go through the standard setup flow we need to repeat some of the initialization tasks here
        vm.startPrank(Alice);

        deal(token0, Alice, type(uint128).max);
        deal(token1, Alice, type(uint128).max);

        IERC20Partial(token0).approve(address(sfpm), type(uint256).max);
        IERC20Partial(token1).approve(address(sfpm), type(uint256).max);

        // Initialize the world pool
        sfpm.initializeAMMPool(token0, token1, fee);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        positionSize = uint128(bound(positionSizeSeed, 1, 9));

        tickLower = int24(strike - (width * tickSpacing) / 2);
        tickUpper = int24(strike + (width * tickSpacing) / 2);
        sqrtLower = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        expectedLiq = LiquidityAmounts.getLiquidityForAmount0(sqrtLower, sqrtUpper, positionSize);

        // make sure actual liquidity being added is nonzero
        vm.assume(expectedLiq > 0);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 0, 0, 0, 0, strike, width);

        sfpm.mintTokenizedPosition(tokenId, positionSize, TickMath.MIN_TICK, TickMath.MAX_TICK);

        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Alice,
                0,
                tickLower,
                tickUpper
            );
            assertEq(accountLiquidities.leftSlot(), 0);
            assertEq(accountLiquidities.rightSlot(), expectedLiq);

            (uint256 realLiq, , , , ) = pool.positions(
                keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
            );

            assertEq(realLiq, expectedLiq);
        }
    }

    function test_Fail_mintTokenizedPosition_PoolNotInitialized(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        // we call _initWorld here instead of _initPool so that the initializeAMMPool call is skipped and this fails
        _initWorld(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        vm.expectRevert(Errors.UniswapPoolNotInitialized.selector);

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
    }

    function test_Fail_mintTokenizedPosition_PriceBoundFail(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed,
        int256 lowerBound,
        int256 upperBound
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        lowerBound = bound(lowerBound, TickMath.MIN_TICK, TickMath.MAX_TICK);
        upperBound = bound(
            upperBound,
            lowerBound,
            currentTick <= lowerBound ? TickMath.MAX_TICK : currentTick
        );

        vm.expectRevert(Errors.PriceBoundFail.selector);

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            int24(lowerBound),
            int24(upperBound)
        );
    }

    function test_Fail_mintTokenizedPosition_OutsideRangeInsufficientLiq(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed,
        uint256 shortRatio,
        uint256 longRatio
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        longRatio = bound(longRatio, 2, 127);
        shortRatio = bound(shortRatio, 1, longRatio - 1);

        // ensure that the true positionSize is the equal to the generated value
        // positionSizeReal = positionSize * optionRatio
        positionSize = positionSize / uint128(shortRatio);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            shortRatio,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        vm.expectRevert(Errors.NotEnoughLiquidity.selector);

        // long leg
        tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            longRatio,
            isWETH,
            1,
            0,
            0,
            strike,
            width
        );
        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
    }

    /*//////////////////////////////////////////////////////////////
                               BURNING: +
    //////////////////////////////////////////////////////////////*/

    function test_Success_burnTokenizedPosition_OutsideRangeShortCall(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed,
        uint256 positionSizeBurnSeed
    ) public {
        _initPool(x);
        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed, positionSizeBurnSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        // cache the minter's balance
        uint256 balance0Before = IERC20Partial(token0).balanceOf(Alice);
        uint256 balance1Before = IERC20Partial(token1).balanceOf(Alice);

        // price changes afters swap at mint so we need to update the price
        (currentSqrtPriceX96, , , , , , ) = pool.slot0();

        (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped) = sfpm
            .burnTokenizedPosition(
                tokenId,
                uint128(positionSizeBurn),
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

        assertApproxEqAbs(totalSwapped.rightSlot(), -$amount0MovedBurn, 10);
        assertApproxEqAbs(totalSwapped.leftSlot(), -$amount1MovedBurn, 10);
        assertEq(
            LeftRightUnsigned.unwrap(collectedByLeg[0]) +
                LeftRightUnsigned.unwrap(collectedByLeg[1]) +
                LeftRightUnsigned.unwrap(collectedByLeg[2]) +
                LeftRightUnsigned.unwrap(collectedByLeg[3]),
            0
        );

        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(tokenId)), positionSize - positionSizeBurn);

        accountLiquidities = sfpm.getAccountLiquidity(
            address(pool),
            Alice,
            0,
            tickLower,
            tickUpper
        );

        assertEq(accountLiquidities.leftSlot(), 0);
        assertApproxEqAbs(accountLiquidities.rightSlot(), expectedLiq, 10);

        (uint256 realLiq, , , , ) = pool.positions(
            keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
        );

        assertApproxEqAbs(realLiq, expectedLiq, 10);

        // ensure burned amount of tokens was collected and sent to the minter
        assertApproxEqAbs(
            IERC20Partial(token0).balanceOf(Alice),
            balance0Before + uint256($amount0MovedBurn),
            10
        );

        assertApproxEqAbs(
            IERC20Partial(token1).balanceOf(address(Alice)),
            balance1Before + uint256($amount1MovedBurn),
            10
        );
    }

    function test_Success_burnTokenizedPosition_InRangeShortPutSwap(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed,
        uint256 positionSizeBurnSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getInRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed, positionSizeBurnSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        // we must calculate both values at mint and burn, since different amounts with different impacts will be swapped
        // required at mint is negative because we need that exact amount hence "required"
        // moved at burn is positive because we just swap the amount moved out after burn for as much as possible
        int256 amount0RequiredMint = SqrtPriceMath.getAmount0Delta(
            sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
            sqrtUpper,
            int128(expectedLiqMint)
        );

        // take snapshot for swap simulation
        vm.snapshot();

        // The max/min tick cannot be set as slippage limits, so we subtract/add 1
        // We also invert the order; this is how we tell SFPM to trigger a swap
        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MAX_TICK - 1,
            TickMath.MIN_TICK + 1
        );

        // poke uniswap pool to update tokens owed - needed because swap happens after mint
        vm.startPrank(address(sfpm));
        pool.burn(tickLower, tickUpper, 0);
        vm.startPrank(Alice);

        // calculate additional fees owed to position
        (, , , , uint128 tokensOwed1) = pool.positions(
            PositionKey.compute(address(sfpm), tickLower, tickUpper)
        );

        // cache the minter's balance so we can assert the difference after burn
        uint256 balance1Before = IERC20Partial(token1).balanceOf(Alice);

        // price changes afters swap at mint so we need to update the price
        (currentSqrtPriceX96, , , , , , ) = pool.slot0();

        // subtract 1 to account for precision loss
        int256 amount1MovedBurn = sqrtLower > currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount1Delta(
                sqrtLower,
                sqrtUpper > currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtUpper,
                int128(expectedLiqBurn)
            ) - 1;

        int256 amount0MovedBurn = sqrtUpper < currentSqrtPriceX96
            ? int256(0)
            : SqrtPriceMath.getAmount0Delta(
                sqrtLower < currentSqrtPriceX96 ? currentSqrtPriceX96 : sqrtLower,
                sqrtUpper,
                int128(expectedLiqBurn)
            ) - 1;

        (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped) = sfpm
            .burnTokenizedPosition(
                tokenId,
                uint128(positionSizeBurn),
                TickMath.MAX_TICK - 1,
                TickMath.MIN_TICK + 1
            );

        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(tokenId)), positionSize - positionSizeBurn);

        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Alice,
                1,
                tickLower,
                tickUpper
            );

            assertEq(accountLiquidities.leftSlot(), 0);
            assertApproxEqAbs(accountLiquidities.rightSlot(), expectedLiq, 10);

            (uint256 realLiq, , , , ) = pool.positions(
                keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
            );

            assertEq(realLiq, accountLiquidities.rightSlot());
        }

        {
            assertEq(IERC20Partial(token0).balanceOf(Alice), type(uint128).max);
        }

        // get final balance before state is cleared
        uint256 balance1Final = IERC20Partial(token1).balanceOf(Alice);

        // we have to do this simulation after mint/burn because revertTo deletes all snapshots taken ahead of it
        vm.revertTo(0);

        int256[2] memory amount0Moveds = [-amount0RequiredMint, amount0MovedBurn];

        (, uint256[2] memory amount1) = PositionUtils.simulateSwap(
            pool,
            tickLower,
            tickUpper,
            [expectedLiqMint, expectedLiqBurn],
            router,
            token0,
            token1,
            fee,
            [false, true],
            amount0Moveds
        );

        // the swap at mint generates a small amount of fees that need to be accounted for (the burned amount is excluded even though it is technically collected)
        // this is because the totalCollected value that gets returned is used for premia calculation, and the burned amount originally left the caller
        assertEq(
            collectedByLeg[0].rightSlot() +
                LeftRightUnsigned.unwrap(collectedByLeg[1]) +
                LeftRightUnsigned.unwrap(collectedByLeg[2]) +
                LeftRightUnsigned.unwrap(collectedByLeg[3]),
            0
        );
        assertApproxEqAbs(uint128(collectedByLeg[0].leftSlot()), tokensOwed1, 1);

        assertEq(totalSwapped.rightSlot(), 0);
        assertEq(totalSwapped.leftSlot(), -amount1MovedBurn - int256(amount1[1]));

        // ensure correct amount of tokens were collected and sent to the minter
        assertApproxEqAbs(
            balance1Final,
            balance1Before + uint256(amount1[1]) + uint256(amount1MovedBurn) + tokensOwed1,
            1
        );
    }

    function test_Success_burnTokenizedPosition_OutsideRangeShortCallLongCall(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed,
        uint256 positionSizeBurnSeed,
        uint256 shortRatio,
        uint256 longRatio
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed, positionSizeBurnSeed);

        shortRatio = bound(shortRatio, 1, 127);
        longRatio = bound(longRatio, 1, shortRatio);

        // ensure that the true positionSize is the equal to the generated value
        // positionSizeReal = positionSize * optionRatio
        positionSize = positionSize / uint128(shortRatio);

        positionSizeBurn = positionSizeBurn / uint128(shortRatio);

        // we can't use the populated values because they don't account for the option ratios, so must recalculate
        expectedLiq = isWETH == 0
            ? LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                (positionSize - positionSizeBurn) * (shortRatio - longRatio)
            )
            : LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                (positionSize - positionSizeBurn) * (shortRatio - longRatio)
            );

        // why do we calculate these seperately? see below for explanation
        uint128 expectedAddedLiqBurn = isWETH == 0
            ? LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                (positionSizeBurn) * (longRatio)
            )
            : LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                (positionSizeBurn) * (longRatio)
            );

        uint128 expectedRemovedLiqBurn = isWETH == 0
            ? LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                (positionSizeBurn) * (shortRatio)
            )
            : LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                (positionSizeBurn) * (shortRatio)
            );

        uint128 removedLiq = isWETH == 0
            ? LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                (positionSize - positionSizeBurn) * longRatio
            )
            : LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                (positionSize - positionSizeBurn) * longRatio
            );

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            shortRatio,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        // long leg
        TokenId tokenIdLong = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            longRatio,
            isWETH,
            1,
            0,
            0,
            strike,
            width
        );

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        sfpm.mintTokenizedPosition(
            tokenIdLong,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        // price changes afters swap at mint so we need to update the price
        (currentSqrtPriceX96, , , , , , ) = pool.slot0();

        // cache the minter's balance
        uint256 balance0Before = IERC20Partial(token0).balanceOf(Alice);
        uint256 balance1Before = IERC20Partial(token1).balanceOf(Alice);

        // it may seem counterintuitive not to simply calculate from the net liquidity, but since this is the way the math is actually done in the contract,
        // precision losses would make the results too different
        int256[2] memory amount0MovedsBurn = [
            TickMath.getSqrtRatioAtTick(tickUpper) < currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(tickLower) < currentSqrtPriceX96
                        ? currentSqrtPriceX96
                        : TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    int128(expectedRemovedLiqBurn)
                ),
            -(
                TickMath.getSqrtRatioAtTick(tickUpper) < currentSqrtPriceX96
                    ? int256(0)
                    : SqrtPriceMath.getAmount0Delta(
                        TickMath.getSqrtRatioAtTick(tickLower) < currentSqrtPriceX96
                            ? currentSqrtPriceX96
                            : TickMath.getSqrtRatioAtTick(tickLower),
                        TickMath.getSqrtRatioAtTick(tickUpper),
                        int128(expectedAddedLiqBurn)
                    )
            )
        ];

        int256[2] memory amount1MovedsBurn = [
            TickMath.getSqrtRatioAtTick(tickLower) > currentSqrtPriceX96
                ? int256(0)
                : SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper) > currentSqrtPriceX96
                        ? currentSqrtPriceX96
                        : TickMath.getSqrtRatioAtTick(tickUpper),
                    int128(expectedRemovedLiqBurn)
                ),
            -(
                TickMath.getSqrtRatioAtTick(tickLower) > currentSqrtPriceX96
                    ? int256(0)
                    : SqrtPriceMath.getAmount1Delta(
                        TickMath.getSqrtRatioAtTick(tickLower),
                        TickMath.getSqrtRatioAtTick(tickUpper) > currentSqrtPriceX96
                            ? currentSqrtPriceX96
                            : TickMath.getSqrtRatioAtTick(tickUpper),
                        int128(expectedAddedLiqBurn)
                    )
            )
        ];

        (LeftRightUnsigned[4] memory collectedByLegLong, LeftRightSigned totalSwappedLong) = sfpm
            .burnTokenizedPosition(
                tokenIdLong,
                uint128(positionSizeBurn),
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

        (LeftRightUnsigned[4] memory collectedByLeg, LeftRightSigned totalSwapped) = sfpm
            .burnTokenizedPosition(
                tokenId,
                uint128(positionSizeBurn),
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

        assertEq(
            LeftRightUnsigned.unwrap(collectedByLeg[0]) +
                LeftRightUnsigned.unwrap(collectedByLeg[1]) +
                LeftRightUnsigned.unwrap(collectedByLeg[2]) +
                LeftRightUnsigned.unwrap(collectedByLeg[3]),
            0
        );
        assertEq(
            LeftRightUnsigned.unwrap(collectedByLegLong[0]) +
                LeftRightUnsigned.unwrap(collectedByLegLong[1]) +
                LeftRightUnsigned.unwrap(collectedByLegLong[2]) +
                LeftRightUnsigned.unwrap(collectedByLegLong[3]),
            0
        );

        assertApproxEqAbs(
            totalSwapped.rightSlot(),
            -amount0MovedsBurn[0],
            uint256(amount0MovedsBurn[0] / 1_000_000 + 10)
        );
        assertApproxEqAbs(
            totalSwapped.leftSlot(),
            -amount1MovedsBurn[0],
            uint256(amount1MovedsBurn[0] / 1_000_000 + 10)
        );

        assertApproxEqAbs(
            totalSwappedLong.rightSlot(),
            -amount0MovedsBurn[1],
            uint256(amount0MovedsBurn[1] / 1_000_000 + 10)
        );
        assertApproxEqAbs(
            totalSwappedLong.leftSlot(),
            -amount1MovedsBurn[1],
            uint256(amount1MovedsBurn[1] / 1_000_000 + 10)
        );

        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(tokenId)), positionSize - positionSizeBurn);

        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Alice,
                0,
                tickLower,
                tickUpper
            );
            assertApproxEqAbs(accountLiquidities.leftSlot(), removedLiq, 10);
            assertApproxEqAbs(accountLiquidities.rightSlot(), expectedLiq, 10);
        }

        (uint256 realLiq, , , uint256 tokensOwed0, uint256 tokensOwed1) = pool.positions(
            keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
        );

        assertApproxEqAbs(realLiq, expectedLiq, 10);
        assertEq(tokensOwed0, 0);
        assertEq(tokensOwed1, 0);

        assertApproxEqAbs(
            int256(IERC20Partial(token0).balanceOf(Alice)),
            int256(balance0Before) + amount0MovedsBurn[0] + amount0MovedsBurn[1],
            10
        );
        assertApproxEqAbs(
            int256(IERC20Partial(token1).balanceOf(Alice)),
            int256(balance1Before) + amount1MovedsBurn[0] + amount1MovedsBurn[1],
            10
        );
    }

    /*//////////////////////////////////////////////////////////////
                         TRANSFER HOOK LOGIC: +
    //////////////////////////////////////////////////////////////*/

    function testSuccess_afterTokenTransfer_Single(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        (int128 feesBase0old, int128 feesBase1old) = sfpm.getAccountFeesBase(
            address(pool),
            Alice,
            1,
            tickLower,
            tickUpper
        );

        sfpm.safeTransferFrom(Alice, Bob, TokenId.unwrap(tokenId), positionSize, "");

        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(tokenId)), 0);
        assertEq(sfpm.balanceOf(Bob, TokenId.unwrap(tokenId)), positionSize);
        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Alice,
                1,
                tickLower,
                tickUpper
            );
            assertEq(accountLiquidities.leftSlot(), 0);
            assertEq(accountLiquidities.rightSlot(), 0);
        }
        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Bob,
                1,
                tickLower,
                tickUpper
            );
            assertEq(accountLiquidities.leftSlot(), 0);
            assertEq(accountLiquidities.rightSlot(), expectedLiq);
        }

        {
            (int128 feesBase0new, int128 feesBase1new) = sfpm.getAccountFeesBase(
                address(pool),
                Bob,
                1,
                tickLower,
                tickUpper
            );

            assertEq(feesBase0new, feesBase0old);
            assertEq(feesBase1new, feesBase1old);
        }

        (uint256 realLiq, , , , ) = pool.positions(
            keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
        );

        assertEq(realLiq, expectedLiq);
    }

    function testSuccess_afterTokenTransfer_Batch(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        TokenId tokenId2 = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            strike,
            width
        );

        sfpm.mintTokenizedPosition(
            tokenId2,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = TokenId.unwrap(tokenId);
        tokenIds[1] = TokenId.unwrap(tokenId2);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = positionSize;
        amounts[1] = positionSize;
        sfpm.safeBatchTransferFrom(Alice, Bob, tokenIds, amounts, "");

        assertEq(sfpm.balanceOf(Alice, TokenId.unwrap(tokenId)), 0);
        assertEq(sfpm.balanceOf(Bob, TokenId.unwrap(tokenId)), positionSize);
        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Alice,
                1,
                tickLower,
                tickUpper
            );
            assertEq(accountLiquidities.leftSlot(), 0);
            assertEq(accountLiquidities.rightSlot(), 0);
        }
        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Alice,
                0,
                tickLower,
                tickUpper
            );
            assertEq(accountLiquidities.leftSlot(), 0);
            assertEq(accountLiquidities.rightSlot(), 0);
        }
        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Bob,
                1,
                tickLower,
                tickUpper
            );
            assertEq(accountLiquidities.leftSlot(), 0);
            assertEq(accountLiquidities.rightSlot(), expectedLiq);
        }
        {
            accountLiquidities = sfpm.getAccountLiquidity(
                address(pool),
                Bob,
                0,
                tickLower,
                tickUpper
            );
            assertEq(accountLiquidities.leftSlot(), 0);
            assertEq(accountLiquidities.rightSlot(), expectedLiq);
        }
        {
            uint256 expectedLiqTotal = isWETH == 0
                ? LiquidityAmounts.getLiquidityForAmount0(sqrtLower, sqrtUpper, positionSize * 2)
                : LiquidityAmounts.getLiquidityForAmount1(sqrtLower, sqrtUpper, positionSize * 2);

            (uint256 realLiq, , , , ) = pool.positions(
                keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
            );

            assertApproxEqAbs(realLiq, expectedLiqTotal, 10);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         TRANSFER HOOK LOGIC: -
    //////////////////////////////////////////////////////////////*/

    function test_Fail_afterTokenTransfer_NotAllLiquidityTransferred(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed,
        uint256 transferSize
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        transferSize = bound(transferSize, 1, positionSize - 1);

        // it's possible under certain conditions for the delta between the transfer size and the user's balance to be *so small*
        // that calculation results in the same amount of liquidity, in which case it would not fail,
        // since the assertion is that all liquidity must be transferred, and not necessarily all balance

        vm.assume(
            expectedLiq !=
                (
                    isWETH == 0
                        ? LiquidityAmounts.getLiquidityForAmount0(
                            sqrtLower,
                            sqrtUpper,
                            transferSize
                        )
                        : LiquidityAmounts.getLiquidityForAmount1(
                            sqrtLower,
                            sqrtUpper,
                            transferSize
                        )
                )
        );

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        vm.expectRevert(Errors.TransferFailed.selector);

        sfpm.safeTransferFrom(Alice, Bob, TokenId.unwrap(tokenId), transferSize, "");
    }

    // mint a short leg, long some of that leg, then transfer the long leg
    // should fail as you shouldnt be able to transfer removedliquidity
    function test_Fail_afterTokenTransfer_LongChunkTransferredSolo(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
        TokenId tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            1,
            0,
            strike,
            width
        );

        sfpm.mintTokenizedPosition(
            tokenId1,
            uint128(positionSize * 2),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        TokenId tokenId2 = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            1,
            1,
            0,
            strike,
            width
        );

        sfpm.mintTokenizedPosition(
            tokenId2,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        vm.expectRevert(Errors.TransferFailed.selector);

        sfpm.safeTransferFrom(Alice, Bob, TokenId.unwrap(tokenId2), positionSize, "");
    }

    function test_Fail_afterTokenTransfer_RecipientAlreadyOwns(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256[2] memory positionSizeSeeds,
        uint256 transferSize
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeeds);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSizes[0]),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        vm.startPrank(Bob);

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSizes[1]),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        vm.startPrank(Alice);

        vm.expectRevert(Errors.TransferFailed.selector);

        transferSize = bound(transferSize, 1, positionSizes[0] - 1);

        sfpm.safeTransferFrom(Alice, Bob, TokenId.unwrap(tokenId), transferSize, "");
    }

    /*//////////////////////////////////////////////////////////////
                          UNISWAP CALLBACKS: -
    //////////////////////////////////////////////////////////////*/

    function test_Fail_uniswapV3MintCallback_Unauthorized(uint256 x) public {
        _initWorld(x);

        vm.expectRevert();
        sfpm.uniswapV3MintCallback(
            0,
            0,
            abi.encode(
                CallbackLib.CallbackData(CallbackLib.PoolFeatures(token0, token1, fee), address(0))
            )
        );
    }

    function test_Fail_uniswapV3SwapCallback_Unauthorized(uint256 x) public {
        _initWorld(x);

        vm.expectRevert();
        sfpm.uniswapV3SwapCallback(
            0,
            0,
            abi.encode(
                CallbackLib.CallbackData(CallbackLib.PoolFeatures(token0, token1, fee), address(0))
            )
        );
    }

    function test_Success_getAccountPremium_getAccountFeesBase_ShortOnly(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed,
        uint256 swapSize
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getInRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        (int128 feesBase0, int128 feesBase1) = sfpm.getAccountFeesBase(
            address(pool),
            Alice,
            1,
            tickLower,
            tickUpper
        );
        {
            (, uint256 _feeGrowthInside0LastX128, uint256 _feeGrowthInside1LastX128, , ) = pool
                .positions(PositionKey.compute(address(sfpm), tickLower, tickUpper));
            assertEq(
                feesBase0,
                int128(int256(Math.mulDiv128RoundingUp(_feeGrowthInside0LastX128, expectedLiq)))
            );
            assertEq(
                feesBase1,
                int128(int256(Math.mulDiv128RoundingUp(_feeGrowthInside1LastX128, expectedLiq)))
            );
        }

        {
            (uint128 premiumToken0, uint128 premiumtoken1) = sfpm.getAccountPremium(
                address(pool),
                Alice,
                1,
                tickLower,
                tickUpper,
                currentTick,
                0
            );
            assertEq(premiumToken0, 0);
            assertEq(premiumtoken1, 0);
        }

        vm.startPrank(Bob);

        swapSize = bound(swapSize, 10 ** 15, 10 ** 19);

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
                swapSize - (swapSize * fee) / 1_000_000,
                type(uint256).max,
                0
            )
        );

        (, currentTick, , , , , ) = pool.slot0();

        // poke uniswap pool
        vm.startPrank(address(sfpm));
        pool.burn(tickLower, tickUpper, 0);
        vm.startPrank(Alice);

        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(
            PositionKey.compute(address(sfpm), tickLower, tickUpper)
        );

        {
            (uint128 premiumToken0, uint128 premiumtoken1) = sfpm.getAccountPremium(
                address(pool),
                Alice,
                1,
                tickLower,
                tickUpper,
                currentTick,
                0
            );
            assertEq(
                premiumToken0,
                FullMath.mulDiv(
                    uint128(
                        int128(int256(Math.mulDiv128(feeGrowthInside0LastX128, expectedLiq))) -
                            feesBase0 >
                            0
                            ? int128(
                                int256(Math.mulDiv128(feeGrowthInside0LastX128, expectedLiq))
                            ) - feesBase0
                            : int128(0)
                    ),
                    uint256(expectedLiq) * 2 ** 64,
                    uint256(expectedLiq) ** 2
                )
            );
            assertEq(
                premiumtoken1,
                FullMath.mulDiv(
                    uint128(
                        int128(int256(Math.mulDiv128(feeGrowthInside1LastX128, expectedLiq))) -
                            feesBase1 >
                            0
                            ? int128(
                                int256(Math.mulDiv128(feeGrowthInside1LastX128, expectedLiq))
                            ) - feesBase1
                            : int128(0)
                    ),
                    uint256(expectedLiq) * 2 ** 64,
                    uint256(expectedLiq) ** 2
                )
            );

            // cached premia has not been updated yet, so should still be 0
            (premiumToken0, premiumtoken1) = sfpm.getAccountPremium(
                address(pool),
                Alice,
                1,
                tickLower,
                tickUpper,
                type(int24).max,
                0
            );
            assertEq(premiumToken0, 0);
            assertEq(premiumtoken1, 0);
        }

        {
            sfpm.burnTokenizedPosition(
                tokenId,
                uint128(positionSize),
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
            (, , , uint256 tokensowed0, uint256 tokensowed1) = pool.positions(
                PositionKey.compute(address(sfpm), tickLower, tickUpper)
            );

            assertLe(tokensowed0, 1);
            assertLe(tokensowed1, 1);

            assertApproxEqAbs(
                IERC20Partial(token0).balanceOf(Alice),
                uint256(type(uint128).max) +
                    uint128(
                        int128(int256(Math.mulDiv128(feeGrowthInside0LastX128, expectedLiq))) -
                            feesBase0 >
                            0
                            ? int128(
                                int256(Math.mulDiv128(feeGrowthInside0LastX128, expectedLiq))
                            ) - feesBase0
                            : int128(0)
                    ),
                10
            );
            assertApproxEqAbs(
                IERC20Partial(token1).balanceOf(Alice),
                uint256(type(uint128).max) +
                    uint128(
                        int128(int256(Math.mulDiv128(feeGrowthInside1LastX128, expectedLiq))) -
                            feesBase1 >
                            0
                            ? int128(
                                int256(Math.mulDiv128(feeGrowthInside1LastX128, expectedLiq))
                            ) - feesBase1
                            : int128(0)
                    ),
                10
            );
        }
    }

    function test_Success_premiaSpreadMechanism(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 effectiveLiqRatio,
        uint256 swapSizeSeed,
        uint256 tokenType
    ) public {
        _initPool(x);

        tokenType = bound(tokenType, 0, 1);
        (int24 width, int24 strike) = PositionUtils.getITMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            tokenType
        );

        populatePositionData(width, strike, type(uint128).max);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            tokenType,
            0,
            strike,
            width
        );

        sfpm.mintTokenizedPosition(tokenId, positionSize, TickMath.MAX_TICK, TickMath.MIN_TICK);

        accountLiquidities = sfpm.getAccountLiquidity(
            address(pool),
            Alice,
            tokenType,
            tickLower,
            tickUpper
        );

        assertEq(accountLiquidities.leftSlot(), 0);
        assertEq(accountLiquidities.rightSlot(), expectedLiq);

        // premia is updated BEFORE the ITM swap, so cached (last collected) premia should still be 0
        (premium0Short, premium1Short) = sfpm.getAccountPremium(
            address(pool),
            Alice,
            tokenType,
            tickLower,
            tickUpper,
            type(int24).max,
            0
        );
        assertEq(premium0Short, 0);
        assertEq(premium1Short, 0);

        (premium0Long, premium1Long) = sfpm.getAccountPremium(
            address(pool),
            Alice,
            tokenType,
            tickLower,
            tickUpper,
            type(int24).max,
            1
        );
        assertEq(premium0Long, 0);
        assertEq(premium1Long, 0);

        twoWaySwap(swapSizeSeed);
        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();
        vm.startPrank(address(sfpm));
        pool.burn(tickLower, tickUpper, 0);
        vm.startPrank(Alice);

        (, , , uint256 tokensOwed0, uint256 tokensOwed1) = pool.positions(
            keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
        );
        (premium0Short, premium1Short) = sfpm.getAccountPremium(
            address(pool),
            Alice,
            tokenType,
            tickLower,
            tickUpper,
            currentTick,
            0
        );

        assertApproxEqAbs(
            premium0Short,
            (tokensOwed0 * 2 ** 64) / expectedLiq,
            (1 * 2 ** 64) / expectedLiq + 1
        );
        assertApproxEqAbs(
            premium1Short,
            (tokensOwed1 * 2 ** 64) / expectedLiq,
            (1 * 2 ** 64) / expectedLiq + 1
        );

        (premium0Long, premium1Long) = sfpm.getAccountPremium(
            address(pool),
            Alice,
            tokenType,
            tickLower,
            tickUpper,
            currentTick,
            1
        );
        assertApproxEqAbs(
            premium0Long,
            (tokensOwed0 * 2 ** 64) / expectedLiq,
            (1 * 2 ** 64) / expectedLiq + 1
        );
        assertApproxEqAbs(
            premium1Long,
            (tokensOwed1 * 2 ** 64) / expectedLiq,
            (1 * 2 ** 64) / expectedLiq + 1
        );

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
        TokenId tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            1,
            tokenType,
            0,
            strike,
            width
        );

        balanceBefore0 = IERC20Partial(token0).balanceOf(Alice);
        balanceBefore1 = IERC20Partial(token1).balanceOf(Alice);
        effectiveLiqRatio = bound(effectiveLiqRatio, 1000, 900_000);
        positionSize = uint128((positionSize * effectiveLiqRatio) / 1_000_000);

        // updates liquidity for new position size
        updatePositionLiqSingleLong();

        updateAmountsMovedSingleSwap(-int128(expectedLiqs[1]), tokenType);

        vm.startPrank(Alice);
        sfpm.mintTokenizedPosition(tokenId1, positionSize, TickMath.MAX_TICK, TickMath.MIN_TICK);

        assertApproxEqAbs(
            int256(IERC20Partial(token0).balanceOf(Alice)),
            int256(balanceBefore0) + int256(tokensOwed0) - $amount0Moved,
            1
        );

        assertApproxEqAbs(
            int256(IERC20Partial(token1).balanceOf(Alice)),
            int256(balanceBefore1) + int256(tokensOwed1) - $amount1Moved,
            1
        );

        twoWaySwap(swapSizeSeed);

        vm.startPrank(Alice);

        // NOTE: all error bounds here are 10 + the delta in premium if collectedAmount changes by 1.
        // It's possible to be off-by-one there due to rounding errors

        (premium0Short, premium1Short) = sfpm.getAccountPremium(
            address(pool),
            Alice,
            tokenType,
            tickLower,
            tickUpper,
            type(int24).max,
            0
        );

        assertApproxEqAbs(
            premium0Short,
            (tokensOwed0 * 2 ** 64) / expectedLiq,
            (1 * 2 ** 64) / expectedLiq + 10
        );
        assertApproxEqAbs(
            premium1Short,
            (tokensOwed1 * 2 ** 64) / expectedLiq,
            (1 * 2 ** 64) / expectedLiq + 10
        );

        (premium0Long, premium1Long) = sfpm.getAccountPremium(
            address(pool),
            Alice,
            tokenType,
            tickLower,
            tickUpper,
            type(int24).max,
            1
        );
        assertApproxEqAbs(
            premium0Long,
            (tokensOwed0 * 2 ** 64) / expectedLiq,
            (1 * 2 ** 64) / expectedLiq + 10
        );
        assertApproxEqAbs(
            premium1Long,
            (tokensOwed1 * 2 ** 64) / expectedLiq,
            (1 * 2 ** 64) / expectedLiq + 10
        );

        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();
        vm.startPrank(address(sfpm));
        pool.burn(tickLower, tickUpper, 0);
        vm.startPrank(Alice);

        (, , , tokensOwed0, tokensOwed1) = pool.positions(
            keccak256(abi.encodePacked(address(sfpm), tickLower, tickUpper))
        );

        premium0ShortOld = premium0Short;
        premium0LongOld = premium0Long;
        premium1ShortOld = premium1Short;
        premium1LongOld = premium1Long;

        (premium0Short, premium1Short) = sfpm.getAccountPremium(
            address(pool),
            Alice,
            tokenType,
            tickLower,
            tickUpper,
            currentTick,
            0
        );

        {
            // net = CURRENTLY in AMM
            // short = REMOVED from AMM
            // 2 ** 2 = 2 ** VEGOID (VEGOID=2)
            uint256 netLiq = expectedLiq - expectedLiqs[1];
            uint256 shortLiq = expectedLiqs[1];
            uint256 basePremia = FullMath.mulDiv(
                tokensOwed0,
                uint256(expectedLiq) * 2 ** 64,
                netLiq ** 2
            );
            premiaError0[0] =
                ((1 * 2 ** 64) / expectedLiq) +
                (
                    tokensOwed0 == 0
                        ? uint(0)
                        : FullMath.mulDiv(
                            (basePremia * 2) / tokensOwed0,
                            uint256(expectedLiq) ** 2 -
                                uint256(expectedLiq) *
                                shortLiq +
                                (shortLiq ** 2 / 2 ** 2),
                            uint256(expectedLiq) ** 2
                        )
                ) +
                10;
            assertApproxEqAbs(
                premium0Short - premium0ShortOld,
                FullMath.mulDiv(
                    basePremia,
                    uint256(expectedLiq) ** 2 -
                        uint256(expectedLiq) *
                        shortLiq +
                        (shortLiq ** 2 / 2 ** 2),
                    uint256(expectedLiq) ** 2
                ),
                premiaError0[0]
            );

            basePremia = FullMath.mulDiv(tokensOwed1, uint256(expectedLiq) * 2 ** 64, netLiq ** 2);
            //store for later
            premiaError1[0] =
                ((1 * 2 ** 64) / expectedLiq) +
                (
                    tokensOwed1 == 0
                        ? uint(0)
                        : FullMath.mulDiv(
                            (basePremia * 2) / tokensOwed1,
                            uint256(expectedLiq) ** 2 -
                                uint256(expectedLiq) *
                                shortLiq +
                                (shortLiq ** 2 / 2 ** 2),
                            uint256(expectedLiq) ** 2
                        )
                ) +
                10;
            assertApproxEqAbs(
                premium1Short - premium1ShortOld,
                FullMath.mulDiv(
                    basePremia,
                    uint256(expectedLiq) ** 2 -
                        uint256(expectedLiq) *
                        shortLiq +
                        (shortLiq ** 2 / 2 ** 2),
                    uint256(expectedLiq) ** 2
                ),
                premiaError1[0]
            );
        }

        (premium0Long, premium1Long) = sfpm.getAccountPremium(
            address(pool),
            Alice,
            tokenType,
            tickLower,
            tickUpper,
            currentTick,
            1
        );

        {
            // net = CURRENTLY in AMM
            // short = REMOVED from AMM
            // 2 ** 2 = 2 ** VEGOID (VEGOID=2)
            // note - we do not need to calculate base premium seperately here because the totalLiquidity fully cancels
            uint256 netLiq = expectedLiq - expectedLiqs[1];
            uint256 shortLiq = expectedLiqs[1];

            premiaError0[1] =
                (1 * 2 ** 64) /
                expectedLiq +
                (
                    tokensOwed0 == 0
                        ? uint(0)
                        : (2 * 2 ** 64 * (netLiq + shortLiq / 2 ** 2)) / (netLiq ** 2)
                ) +
                10;

            assertApproxEqAbs(
                premium0Long - premium0LongOld,
                FullMath.mulDiv(tokensOwed0 * 2 ** 64, netLiq + shortLiq / 2 ** 2, netLiq ** 2),
                premiaError0[1]
            );

            premiaError1[1] =
                (1 * 2 ** 64) /
                expectedLiq +
                (
                    tokensOwed1 == 0
                        ? uint(0)
                        : (2 * 2 ** 64 * (netLiq + shortLiq / 2 ** 2)) / (netLiq ** 2)
                ) +
                10;
            assertApproxEqAbs(
                premium1Long - premium1LongOld,
                FullMath.mulDiv(tokensOwed1 * 2 ** 64, netLiq + shortLiq / 2 ** 2, netLiq ** 2),
                premiaError1[1]
            );
        }

        sfpm.burnTokenizedPosition(
            tokenId1,
            uint128((positionSize * effectiveLiqRatio) / 1_000_000),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();

        premium0LongOld = premium0Long;
        premium1LongOld = premium1Long;
        (premium0Long, premium1Long) = sfpm.getAccountPremium(
            address(pool),
            Alice,
            tokenType,
            tickLower,
            tickUpper,
            type(int24).max,
            1
        );
        assertApproxEqAbs(premium0Long, premium0LongOld, premiaError0[1]);
        assertApproxEqAbs(premium1Long, premium1LongOld, premiaError1[1]);

        (premium0Long, premium1Long) = sfpm.getAccountPremium(
            address(pool),
            Alice,
            tokenType,
            tickLower,
            tickUpper,
            currentTick,
            1
        );
        assertApproxEqAbs(premium0Long, premium0LongOld, premiaError0[1]);
        assertApproxEqAbs(premium1Long, premium1LongOld, premiaError1[1]);

        sfpm.burnTokenizedPosition(tokenId, positionSize, TickMath.MIN_TICK, TickMath.MAX_TICK);

        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();

        premium0ShortOld = premium0Short;
        premium1ShortOld = premium1Short;

        (premium0Short, premium1Short) = sfpm.getAccountPremium(
            address(pool),
            Alice,
            tokenType,
            tickLower,
            tickUpper,
            type(int24).max,
            0
        );

        assertApproxEqAbs(premium0Short, premium0ShortOld, premiaError0[0]);
        assertApproxEqAbs(premium1Short, premium1ShortOld, premiaError1[0]);

        (premium0Short, premium1Short) = sfpm.getAccountPremium(
            address(pool),
            Alice,
            tokenType,
            tickLower,
            tickUpper,
            currentTick,
            0
        );
        assertApproxEqAbs(premium0Short, premium0ShortOld, premiaError0[0]);
        assertApproxEqAbs(premium1Short, premium1ShortOld, premiaError1[0]);
    }

    // make sure that we allow the premium to overflow and it does not revert when too much is accumulated with a huge multiplier
    function test_Success_PremiumDOSPrevention(uint256 widthSeed, int256 strikeSeed) public {
        _initPool(0);

        (int24 width, int24 strike) = PositionUtils.getInRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, type(uint256).max);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
        TokenId tokenIdShort = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            1,
            0,
            strike,
            width
        );

        sfpm.mintTokenizedPosition(
            tokenIdShort,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        TokenId tokenIdLong = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            1,
            1,
            0,
            strike,
            width
        );

        // mint a long position with 1 wei of liquidity less than available, resulting in a huge multiplier

        sfpm.mintTokenizedPosition(
            tokenIdLong,
            uint128(Math.mulDiv(positionSize, (2 ** 64 - 1), 2 ** 64)),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        vm.startPrank(Bob);

        uint256 swapSize = 10 ** 20;

        for (uint256 i = 0; i < 500; ++i) {
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
                    swapSize - (swapSize * fee) / 1_000_000,
                    type(uint256).max,
                    0
                )
            );
        }

        vm.startPrank(Alice);

        // this succeeding is the test - it should overflow cleanly instead of reverting and DOS-ing the positions
        sfpm.burnTokenizedPosition(
            tokenIdLong,
            uint128(Math.mulDiv(positionSize, (2 ** 64 - 1), 2 ** 64)),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        sfpm.burnTokenizedPosition(
            tokenIdShort,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
    }

    /*//////////////////////////////////////////////////////////////
                               REENTRANCY
    //////////////////////////////////////////////////////////////*/

    function test_Fail_mintTokenizedPosition_ReentrancyLock(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        // replace the Uniswap pool with a mock contract that can answer some queries correctly,
        // but will attempt to callback with mintTokenizedPosition on any other call
        vm.etch(address(pool), address(new ReenterMint()).code);

        ReenterMint(address(pool)).construct(
            ReenterMint.Slot0(
                TickMath.getSqrtRatioAtTick(currentTick),
                currentTick,
                0,
                0,
                0,
                0,
                true
            ),
            address(token0),
            address(token1),
            fee,
            tickSpacing
        );

        vm.expectRevert(Errors.ReentrantCall.selector);

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
    }

    // make sure single transfers check reentrancy lock state
    function test_Fail_TransferSingle_ReentrancyLock(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        // replace the Uniswap pool with a mock contract that can answer some queries correctly,
        // but will attempt to callback with mintTokenizedPosition on any other call
        vm.etch(address(pool), address(new ReenterTransferSingle()).code);

        ReenterTransferSingle(address(pool)).construct(
            ReenterTransferSingle.Slot0(
                TickMath.getSqrtRatioAtTick(currentTick),
                currentTick,
                0,
                0,
                0,
                0,
                true
            ),
            address(token0),
            address(token1),
            fee,
            tickSpacing
        );

        vm.expectRevert(Errors.ReentrantCall.selector);

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
    }

    // make sure batch transfers check reentrancy lock state
    function test_Fail_TransferBatch_ReentrancyLock(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        // replace the Uniswap pool with a mock contract that can answer some queries correctly,
        // but will attempt to callback with mintTokenizedPosition on any other call
        vm.etch(address(pool), address(new ReenterTransferBatch()).code);

        ReenterTransferBatch(address(pool)).construct(
            ReenterTransferBatch.Slot0(
                TickMath.getSqrtRatioAtTick(currentTick),
                currentTick,
                0,
                0,
                0,
                0,
                true
            ),
            address(token0),
            address(token1),
            fee,
            tickSpacing
        );

        vm.expectRevert(Errors.ReentrantCall.selector);

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
    }

    // make sure reentrancy lock state is persisted through pool init
    function test_Fail_mintTokenizedPosition_ReentrancyLock_Uninitialized(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed
    ) public {
        _initWorld(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        // allow Alice to try to initialize and then reenter when getting the onERC1155Received callback
        vm.etch(address(Alice), address(new Reenter1155Initialize()).code);

        Reenter1155Initialize(Alice).construct(address(token0), address(token1), fee, poolId);

        vm.expectRevert(Errors.ReentrantCall.selector);

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
    }

    function test_Fail_burnTokenizedPosition_ReentrancyLock(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 positionSizeSeed,
        uint256 positionSizeBurnSeed
    ) public {
        _initPool(x);

        (int24 width, int24 strike) = PositionUtils.getOutOfRangeSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick
        );

        populatePositionData(width, strike, positionSizeSeed, positionSizeBurnSeed);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(positionSize),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        // replace the Uniswap pool with a mock that responds correctly to queries but calls back on
        // any other operations
        vm.etch(address(pool), address(new ReenterBurn()).code);

        ReenterBurn(address(pool)).construct(
            ReenterBurn.Slot0(
                TickMath.getSqrtRatioAtTick(currentTick),
                currentTick,
                0,
                0,
                0,
                0,
                true
            ),
            address(token0),
            address(token1),
            fee,
            tickSpacing
        );

        vm.expectRevert(Errors.ReentrantCall.selector);

        sfpm.burnTokenizedPosition(
            tokenId,
            uint128(positionSizeBurn),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 SANITY
    //////////////////////////////////////////////////////////////*/

    function test_Sanity_ITMSwapApprox(uint256 price, int256 itm0, int256 itm1) public {
        price = bound(price, 10 ** 3, 10 ** 9);
        itm0 = bound(itm0, -10 ** 27, 10 ** 27);
        itm1 = bound(itm1, -10 ** 27, 10 ** 27);

        vm.assume(stdMath.abs(itm0) > 100_000);
        vm.assume(stdMath.abs(itm1) > 100_000);

        bool zeroForOne;
        int256 swapAmount;

        int256 net0 = itm0 - (itm1 * 10 ** 6) / int256(price);

        // if net0 is negative, then the protocol has a net surplus of token0
        zeroForOne = net0 < 0;

        //compute the swap amount, set as positive (exact input)
        swapAmount = -net0;

        (int256 d0, int256 d1) = evalSwapFixed(swapAmount, zeroForOne, int256(price));
        (int256 d0_, int256 d1_) = dualITMSwap(price, itm0, itm1);

        assertApproxEqAbs(d0, d0_, 1000);
        assertApproxEqAbs(d1, d1_, 1000);
    }

    function dualITMSwap(
        uint256 price,
        int256 itm0,
        int256 itm1
    ) internal pure returns (int256, int256) {
        bool zeroForOne = itm0 < 0;
        int256 swapAmount = -itm0;
        (int256 d0, int256 d1) = evalSwapFixed(swapAmount, zeroForOne, int256(price));

        zeroForOne = itm1 > 0;
        swapAmount = -itm1;
        (int256 d0_, int256 d1_) = evalSwapFixed(swapAmount, zeroForOne, int256(price));
        return (d0 + d0_, d1 + d1_);
    }

    function evalSwapFixed(
        int256 swapAmount,
        bool zeroForOne,
        int256 price
    ) internal pure returns (int256 d0, int256 d1) {
        if (zeroForOne) {
            d0 = -(swapAmount > 0 ? swapAmount : (-swapAmount * 10 ** 6) / price);
            d1 = swapAmount > 0 ? (swapAmount * price) / 10 ** 6 : -swapAmount;
        } else {
            d0 = swapAmount > 0 ? (swapAmount * 10 ** 6) / price : -swapAmount;
            d1 = -(swapAmount > 0 ? swapAmount : (-swapAmount * price) / 10 ** 6);
        }
    }

    function test_Fail_RemovedLiquidity_Overflow() public {
        _initPool(0);

        // need a super wide position to exxagerate position size units
        _cacheWorldState(USDC_WETH_30);
        sfpm.initializeAMMPool(token0, token1, fee);

        int24 width = 4090;
        int24 strike = 0;
        populatePositionData(width, strike, 0, 0);

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
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

        sfpm.mintTokenizedPosition(
            tokenId,
            uint128(1_000_000),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );

        tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, isWETH, 1, 0, 0, strike, width);

        for (uint256 i = 0; i < 10; i++) {
            sfpm.mintTokenizedPosition(tokenId, uint128(922), TickMath.MIN_TICK, TickMath.MAX_TICK);

            sfpm.burnTokenizedPosition(tokenId, uint128(462), TickMath.MIN_TICK, TickMath.MAX_TICK);
        }

        vm.expectRevert();
        sfpm.burnTokenizedPosition(
            tokenId,
            uint128(10 * (922 - 462)),
            TickMath.MIN_TICK,
            TickMath.MAX_TICK
        );
    }
}
