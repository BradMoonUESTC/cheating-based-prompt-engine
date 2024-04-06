// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Errors} from "@libraries/Errors.sol";
import {PanopticMath} from "@libraries/PanopticMath.sol";
import {TokenId} from "@types/TokenId.sol";
import {LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";
import {LiquidityChunk} from "@types/LiquidityChunk.sol";
import {IDonorNFT} from "@tokens/interfaces/IDonorNFT.sol";
import {DonorNFT} from "@periphery/DonorNFT.sol";
import {IERC20Partial} from "@tokens/interfaces/IERC20Partial.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";
import {FixedPoint128} from "v3-core/libraries/FixedPoint128.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {PoolAddress} from "v3-periphery/libraries/PoolAddress.sol";
import {PositionKey} from "v3-periphery/libraries/PositionKey.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {SemiFungiblePositionManager} from "@contracts/SemiFungiblePositionManager.sol";
import {PanopticPool} from "@contracts/PanopticPool.sol";
import {CollateralTracker} from "@contracts/CollateralTracker.sol";
import {PanopticFactory} from "@contracts/PanopticFactory.sol";
import {PanopticHelper} from "@periphery/PanopticHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PositionUtils} from "../testUtils/PositionUtils.sol";
import {UniPoolPriceMock} from "../testUtils/PriceMocks.sol";

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

    /**
     * @notice compute the TWAP price from the last 600s = 10mins
     * @return twapTick the TWAP price in ticks
     */
    function getUniV3TWAP_() external view returns (int24 twapTick) {
        twapTick = PanopticMath.twapFilter(s_univ3pool, TWAP_WINDOW);
    }

    constructor(SemiFungiblePositionManager _sfpm) PanopticPool(_sfpm) {}
}

contract PanopticHelperTest is PositionUtils {
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
    IUniswapV3Pool[3] public pools = [USDC_WETH_5, USDC_WETH_5, USDC_WETH_5];

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

    int24 medianTick;
    int24 TWAPtick;

    PanopticFactory factory;
    PanopticPoolHarness pp;
    PanopticHelper ph;
    CollateralTracker ct0;
    CollateralTracker ct1;

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
    mapping(TokenId tokenId => uint256 balance) userBalance;

    mapping(address actor => uint256 lastBalance0) lastCollateralBalance0;
    mapping(address actor => uint256 lastBalance1) lastCollateralBalance1;

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

    uint256[] tokenIds;

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

    int256 $balanceDelta0;
    int256 $balanceDelta1;

    LeftRightUnsigned tokenData0;
    LeftRightUnsigned tokenData1;

    uint256 collateralBalance;
    uint256 requiredCollateral;

    uint256 calculatedCollateralBalance;
    uint256 calculatedRequiredCollateral;

    int24 atTick;

    /*//////////////////////////////////////////////////////////////
                               ENV SETUP
    //////////////////////////////////////////////////////////////*/

    function _initPool(uint256 seed) internal {
        _initWorld(seed);
    }

    function _initWorldAtTick(uint256 seed, int24 tick) internal {
        // Pick a pool from the seed and cache initial state
        _cacheWorldState(pools[bound(seed, 0, pools.length - 1)]);

        // replace pool with a mock and set the tick
        vm.etch(address(pool), address(new UniPoolPriceMock()).code);

        UniPoolPriceMock(address(pool)).construct(
            UniPoolPriceMock.Slot0(TickMath.getSqrtRatioAtTick(tick), tick, 0, 0, 0, 0, true),
            address(token0),
            address(token1),
            fee,
            tickSpacing
        );

        _deployPanopticPool();

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
        ph = new PanopticHelper(SemiFungiblePositionManager(sfpm));

        // deploy reference pool and collateral token
        poolReference = address(new PanopticPoolHarness(sfpm));
        collateralReference = address(
            new CollateralTracker(10, 2_000, 1_000, -1_024, 5_000, 9_000, 20_000)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          TEST DATA POPULATION
    //////////////////////////////////////////////////////////////*/

    function populatePositionData(
        int24[2] memory width,
        int24[2] memory strike,
        uint256[2] memory positionSizeSeeds
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
        positionSizeSeeds[0] = bound(positionSizeSeeds[0], 10 ** 15, 10 ** 22);
        positionSizeSeeds[1] = bound(positionSizeSeeds[1], 10 ** 15, 10 ** 22);

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
                ? LiquidityAmounts.getLiquidityForAmount0(
                    sqrtLowers[0],
                    sqrtUppers[0],
                    positionSizes[0]
                )
                : LiquidityAmounts.getLiquidityForAmount1(
                    sqrtLowers[0],
                    sqrtUppers[0],
                    positionSizes[0]
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
    }

    /// forge-config: default.fuzz.runs = 500
    function test_Success_wrapUnwrapTokenIds_1Leg(
        uint256 x,
        int24 width,
        int24 strike,
        bool isLong,
        uint8 optionRatio,
        bool tokenType,
        bool asset
    ) public {
        _initPool(x);

        width = int24(bound(width, 1, 2 ** 11 - 1) * 2);
        strike = (strike / pool.tickSpacing()) * pool.tickSpacing();

        optionRatio = uint8(bound(optionRatio, uint8(1), uint8(2 ** 7 - 1)));

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            optionRatio,
            asset ? 1 : 0,
            isLong ? 1 : 0,
            tokenType ? 1 : 0,
            0,
            strike,
            width
        );
        tokenId.validate();

        PanopticHelper.Leg memory inputLeg = PanopticHelper.Leg({
            poolId: poolId,
            UniswapV3Pool: address(pool),
            optionRatio: optionRatio,
            asset: asset ? 1 : 0,
            isLong: isLong ? 1 : 0,
            tokenType: tokenType ? 1 : 0,
            riskPartner: 0,
            strike: strike,
            width: width
        });

        uint256 keccakIn = uint256(keccak256(abi.encode(inputLeg)));

        PanopticHelper.Leg[] memory unwrappedLeg = ph.unwrapTokenId(tokenId);
        uint256 keccakOut = uint256(keccak256(abi.encode(unwrappedLeg[0])));

        assertEq(keccakIn, keccakOut);
    }

    /// forge-config: default.fuzz.runs = 5
    function test_Success_wrapUnwrapTokenIds_2LegsSpread(
        uint256 x,
        int24 width,
        int24 strike1,
        int24 strike2,
        bool isLong,
        uint8 optionRatio,
        bool tokenType
    ) public {
        _initPool(x);

        width = int24(bound(width, 1, 2 ** 11 - 1) * 2);
        strike1 = (strike1 / pool.tickSpacing()) * pool.tickSpacing();
        strike2 = (strike2 / pool.tickSpacing()) * pool.tickSpacing();

        vm.assume(strike1 != strike2);

        optionRatio = uint8(bound(optionRatio, uint8(1), uint8(2 ** 7 - 1)));

        uint256 long = isLong ? 1 : 0;
        uint256 tt = tokenType ? 1 : 0;
        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId);

        {
            tokenId = tokenId.addOptionRatio(optionRatio, 0);
            tokenId = tokenId.addIsLong(long, 0);
            tokenId = tokenId.addTokenType(tt, 0);
            tokenId = tokenId.addStrike(strike1, 0);
            tokenId = tokenId.addWidth(width, 0);
            tokenId = tokenId.addRiskPartner(1, 0);
        }
        {
            tokenId = tokenId.addOptionRatio(optionRatio, 1);
            tokenId = tokenId.addIsLong(1 - long, 1);
            tokenId = tokenId.addTokenType(tt, 1);
            tokenId = tokenId.addStrike(strike2, 1);
            tokenId = tokenId.addWidth(width, 1);
        }
        tokenId.validate();
        PanopticHelper.Leg[2] memory inputLeg;
        inputLeg[0] = PanopticHelper.Leg({
            poolId: poolId,
            UniswapV3Pool: address(pool),
            optionRatio: optionRatio,
            asset: 0,
            isLong: long,
            tokenType: tt,
            riskPartner: 1,
            strike: strike1,
            width: width
        });
        inputLeg[1] = PanopticHelper.Leg({
            poolId: poolId,
            UniswapV3Pool: address(pool),
            optionRatio: optionRatio,
            asset: 0,
            isLong: 1 - long,
            tokenType: tt,
            riskPartner: 0,
            strike: strike2,
            width: width
        });

        uint256 keccakIn = uint256(keccak256(abi.encode(inputLeg)));

        PanopticHelper.Leg[] memory unwrappedLeg = ph.unwrapTokenId(tokenId);
        PanopticHelper.Leg[2] memory outputLeg;
        outputLeg[0] = unwrappedLeg[0];
        outputLeg[1] = unwrappedLeg[1];
        uint256 keccakOut = uint256(keccak256(abi.encode(outputLeg)));

        assertEq(keccakIn, keccakOut);
    }

    /// forge-config: default.fuzz.runs = 100
    function test_Success_wrapUnwrapTokenIds_multiLegsNoPartners(uint256 x, uint256 seed) public {
        _initPool(x);

        uint256 numberOfLegs = uint256((seed % 4) + 1);
        PanopticHelper.Leg[] memory inputLeg = new PanopticHelper.Leg[](numberOfLegs);

        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId);

        for (uint256 i; i < numberOfLegs; ++i) {
            // update seed
            seed = uint256(keccak256(abi.encode(seed)));

            // add optionRatio
            uint256 optionRatio = uint256(seed % 2 ** 7);
            optionRatio = optionRatio == 0 ? 1 : optionRatio;
            tokenId = tokenId.addOptionRatio(optionRatio, i);

            // add tokenType
            uint256 tokenType = uint256((seed >> 7) % 2);
            tokenId = tokenId.addTokenType(tokenType, i);

            // add isLong
            uint256 isLong = uint256((seed >> 8) % 2);
            tokenId = tokenId.addIsLong(isLong, i);

            // add asset
            uint256 asset = uint256((seed >> 9) % 2);
            tokenId = tokenId.addAsset(asset, i);

            // add riskPartner
            tokenId = tokenId.addRiskPartner(i, i);

            // add strike
            uint256 strikeTemp = uint256((seed >> 10) % 2 ** 20);
            uint256 strikeSign = uint256((seed >> 30) % 2);
            int24 strike = strikeTemp > 887272
                ? int24(uint24(strikeTemp / 2))
                : int24(uint24(strikeTemp));
            strike = strikeSign == 0 ? -strike : strike;
            strike = (strike / pool.tickSpacing()) * pool.tickSpacing();
            tokenId = tokenId.addStrike(strike, i);

            // add width
            int24 width = int24(uint24(uint256((seed >> 31) % 2 ** 12)));
            width = (width / 2) * 2;
            width = width == 0 ? int24(2) : width;
            tokenId = tokenId.addWidth(width, i);

            // add to input array of legs
            PanopticHelper.Leg memory _Leg = PanopticHelper.Leg({
                poolId: poolId,
                UniswapV3Pool: address(pool),
                optionRatio: optionRatio,
                asset: asset,
                isLong: isLong,
                tokenType: tokenType,
                riskPartner: i,
                strike: strike,
                width: width
            });
            inputLeg[i] = _Leg;
        }

        for (uint256 legIndex; legIndex < tokenId.countLegs(); legIndex++) {
            for (uint256 j = legIndex + 1; j < tokenId.countLegs(); ++j) {
                vm.assume(
                    !(tokenId.strike(legIndex) == tokenId.strike(j) &&
                        tokenId.width(legIndex) == tokenId.width(j) &&
                        tokenId.tokenType(legIndex) == tokenId.tokenType(j))
                );
            }
        }

        tokenId.validate();

        PanopticHelper.Leg[] memory unwrappedLeg = ph.unwrapTokenId(tokenId);

        uint256 keccakIn = uint256(keccak256(abi.encode(inputLeg)));

        uint256 keccakOut = uint256(keccak256(abi.encode(unwrappedLeg)));

        assertEq(keccakIn, keccakOut);
    }

    /// forge-config: default.fuzz.runs = 100
    function test_Success_wrapUnwrapTokenIds_multiLegsWithPartners_Spreads(
        uint256 x,
        uint256 seed
    ) public {
        _initPool(x);

        uint256 numberOfLegs = 4;

        PanopticHelper.Leg[] memory inputLeg = new PanopticHelper.Leg[](numberOfLegs);

        TokenId[10] memory riskArray;
        riskArray[0] = TokenId
            .wrap(0)
            .addRiskPartner(0, 0)
            .addRiskPartner(1, 1)
            .addRiskPartner(2, 2)
            .addRiskPartner(3, 3);
        riskArray[1] = TokenId
            .wrap(0)
            .addRiskPartner(0, 0)
            .addRiskPartner(2, 1)
            .addRiskPartner(1, 2)
            .addRiskPartner(3, 3);
        riskArray[2] = TokenId
            .wrap(0)
            .addRiskPartner(0, 0)
            .addRiskPartner(3, 1)
            .addRiskPartner(2, 2)
            .addRiskPartner(1, 3);
        riskArray[3] = TokenId
            .wrap(0)
            .addRiskPartner(0, 0)
            .addRiskPartner(1, 1)
            .addRiskPartner(3, 2)
            .addRiskPartner(2, 3);
        riskArray[4] = TokenId
            .wrap(0)
            .addRiskPartner(1, 0)
            .addRiskPartner(0, 1)
            .addRiskPartner(2, 2)
            .addRiskPartner(3, 3);
        riskArray[5] = TokenId
            .wrap(0)
            .addRiskPartner(1, 0)
            .addRiskPartner(0, 1)
            .addRiskPartner(3, 2)
            .addRiskPartner(2, 3);
        riskArray[6] = TokenId
            .wrap(0)
            .addRiskPartner(2, 0)
            .addRiskPartner(1, 1)
            .addRiskPartner(0, 2)
            .addRiskPartner(3, 3);
        riskArray[7] = TokenId
            .wrap(0)
            .addRiskPartner(2, 0)
            .addRiskPartner(3, 1)
            .addRiskPartner(0, 2)
            .addRiskPartner(1, 3);
        riskArray[8] = TokenId
            .wrap(0)
            .addRiskPartner(3, 0)
            .addRiskPartner(1, 1)
            .addRiskPartner(2, 2)
            .addRiskPartner(0, 3);
        riskArray[9] = TokenId
            .wrap(0)
            .addRiskPartner(3, 0)
            .addRiskPartner(2, 1)
            .addRiskPartner(1, 2)
            .addRiskPartner(0, 3);

        TokenId[10] memory isLongArray; // first of the partered leg is long, the rest are not
        isLongArray[0] = TokenId.wrap(0);
        isLongArray[1] = TokenId.wrap(0).addIsLong(1, 1);
        isLongArray[2] = TokenId.wrap(0).addIsLong(1, 1);
        isLongArray[3] = TokenId.wrap(0).addIsLong(1, 2);
        isLongArray[4] = TokenId.wrap(0).addIsLong(1, 0);
        isLongArray[5] = TokenId.wrap(0).addIsLong(1, 0).addIsLong(1, 2);
        isLongArray[6] = TokenId.wrap(0).addIsLong(1, 0);
        isLongArray[7] = TokenId.wrap(0).addIsLong(1, 0).addIsLong(1, 1);
        isLongArray[8] = TokenId.wrap(0).addIsLong(1, 0);
        isLongArray[9] = TokenId.wrap(0).addIsLong(1, 0).addIsLong(1, 1);

        uint256 riskPreset = uint256(keccak256(abi.encode(seed))) % 10;
        TokenId tokenId = TokenId.wrap(
            TokenId.unwrap(riskArray[riskPreset].addPoolId(poolId)) +
                TokenId.unwrap(isLongArray[riskPreset])
        );

        uint256 optionRatio = uint256(seed % 2 ** 7);
        optionRatio = optionRatio == 0 ? 1 : optionRatio;

        uint256 tokenType = uint256((seed >> 7) % 2);
        int24 width = int24(uint24(uint256((seed >> 31) % 2 ** 12)));
        width = (width / 2) * 2;
        width = width == 0 ? int24(2) : width;
        uint256 asset = uint256((seed >> 9) % 2);

        for (uint256 i; i < numberOfLegs; ++i) {
            // update seed
            seed = uint256(keccak256(abi.encode(seed)));

            // add optionRatio
            tokenId = tokenId.addOptionRatio(optionRatio, i);

            // add tokenType
            tokenId = tokenId.addTokenType(tokenType, i);

            // add asset
            tokenId = tokenId.addAsset(asset, i);

            // add strike
            uint256 strikeTemp = uint256((seed >> 10) % 2 ** 20);
            uint256 strikeSign = uint256((seed >> 30) % 2);
            int24 strike = strikeTemp > 887272
                ? int24(uint24(strikeTemp / 2))
                : int24(uint24(strikeTemp));
            strike = strikeSign == 0 ? -strike : strike;
            strike = (strike / pool.tickSpacing()) * pool.tickSpacing();
            tokenId = tokenId.addStrike(strike, i);

            // add width
            tokenId = tokenId.addWidth(width, i);

            // add to input array of legs
            PanopticHelper.Leg memory _Leg = PanopticHelper.Leg({
                poolId: poolId,
                UniswapV3Pool: address(pool),
                optionRatio: optionRatio,
                asset: asset,
                isLong: tokenId.isLong(i),
                tokenType: tokenType,
                riskPartner: tokenId.riskPartner(i),
                strike: strike,
                width: width
            });
            inputLeg[i] = _Leg;
        }

        for (uint256 legIndex; legIndex < tokenId.countLegs(); legIndex++) {
            for (uint256 j = legIndex + 1; j < tokenId.countLegs(); ++j) {
                vm.assume(
                    !(tokenId.strike(legIndex) == tokenId.strike(j) &&
                        tokenId.width(legIndex) == tokenId.width(j) &&
                        tokenId.tokenType(legIndex) == tokenId.tokenType(j))
                );
            }
        }

        tokenId.validate();
        PanopticHelper.Leg[] memory unwrappedLeg = ph.unwrapTokenId(tokenId);

        uint256 keccakIn = uint256(keccak256(abi.encode(inputLeg)));

        uint256 keccakOut = uint256(keccak256(abi.encode(unwrappedLeg)));

        assertEq(keccakIn, keccakOut);
    }

    /// forge-config: default.fuzz.runs = 100
    function test_Success_wrapUnwrapTokenIds_multiLegsWithPartners_Strangles(
        uint256 x,
        uint256 seed
    ) public {
        _initPool(x);

        uint256 numberOfLegs = 4;

        PanopticHelper.Leg[] memory inputLeg = new PanopticHelper.Leg[](numberOfLegs);

        TokenId[10] memory riskArray;
        riskArray[0] = TokenId
            .wrap(0)
            .addRiskPartner(0, 0)
            .addRiskPartner(1, 1)
            .addRiskPartner(2, 2)
            .addRiskPartner(3, 3);
        riskArray[1] = TokenId
            .wrap(0)
            .addRiskPartner(0, 0)
            .addRiskPartner(2, 1)
            .addRiskPartner(1, 2)
            .addRiskPartner(3, 3);
        riskArray[2] = TokenId
            .wrap(0)
            .addRiskPartner(0, 0)
            .addRiskPartner(3, 1)
            .addRiskPartner(2, 2)
            .addRiskPartner(1, 3);
        riskArray[3] = TokenId
            .wrap(0)
            .addRiskPartner(0, 0)
            .addRiskPartner(1, 1)
            .addRiskPartner(3, 2)
            .addRiskPartner(2, 3);
        riskArray[4] = TokenId
            .wrap(0)
            .addRiskPartner(1, 0)
            .addRiskPartner(0, 1)
            .addRiskPartner(2, 2)
            .addRiskPartner(3, 3);
        riskArray[5] = TokenId
            .wrap(0)
            .addRiskPartner(1, 0)
            .addRiskPartner(0, 1)
            .addRiskPartner(3, 2)
            .addRiskPartner(2, 3);
        riskArray[6] = TokenId
            .wrap(0)
            .addRiskPartner(2, 0)
            .addRiskPartner(1, 1)
            .addRiskPartner(0, 2)
            .addRiskPartner(3, 3);
        riskArray[7] = TokenId
            .wrap(0)
            .addRiskPartner(2, 0)
            .addRiskPartner(3, 1)
            .addRiskPartner(0, 2)
            .addRiskPartner(1, 3);
        riskArray[8] = TokenId
            .wrap(0)
            .addRiskPartner(3, 0)
            .addRiskPartner(1, 1)
            .addRiskPartner(2, 2)
            .addRiskPartner(0, 3);
        riskArray[9] = TokenId
            .wrap(0)
            .addRiskPartner(3, 0)
            .addRiskPartner(2, 1)
            .addRiskPartner(1, 2)
            .addRiskPartner(0, 3);

        TokenId[10] memory tokenTypeArray; // first of the partered leg is 1, the other are 0
        tokenTypeArray[0] = TokenId.wrap(0);
        tokenTypeArray[1] = TokenId.wrap(0).addTokenType(1, 1);
        tokenTypeArray[2] = TokenId.wrap(0).addTokenType(1, 1);
        tokenTypeArray[3] = TokenId.wrap(0).addTokenType(1, 2);
        tokenTypeArray[4] = TokenId.wrap(0).addTokenType(1, 0);
        tokenTypeArray[5] = TokenId.wrap(0).addTokenType(1, 0).addTokenType(1, 2);
        tokenTypeArray[6] = TokenId.wrap(0).addTokenType(1, 0);
        tokenTypeArray[7] = TokenId.wrap(0).addTokenType(1, 0).addTokenType(1, 1);
        tokenTypeArray[8] = TokenId.wrap(0).addTokenType(1, 0);
        tokenTypeArray[9] = TokenId.wrap(0).addTokenType(1, 0).addTokenType(1, 1);

        uint256 riskPreset = uint256(keccak256(abi.encode(seed))) % 10;
        TokenId tokenId = TokenId.wrap(
            TokenId.unwrap(riskArray[riskPreset].addPoolId(poolId)) +
                TokenId.unwrap(tokenTypeArray[riskPreset])
        );

        uint256 optionRatio = uint256(seed % 2 ** 7);
        optionRatio = optionRatio == 0 ? 1 : optionRatio;

        uint256 isLong = uint256((seed >> 7) % 2);
        int24 width = int24(uint24(uint256((seed >> 31) % 2 ** 12)));
        width = (width / 2) * 2;
        width = width == 0 ? int24(2) : width;
        uint256 asset = uint256((seed >> 9) % 2);

        for (uint256 i; i < numberOfLegs; ++i) {
            // update seed
            seed = uint256(keccak256(abi.encode(seed)));

            // add optionRatio
            tokenId = tokenId.addOptionRatio(optionRatio, i);

            // add isLong
            tokenId = tokenId.addIsLong(isLong, i);

            // add asset
            tokenId = tokenId.addAsset(asset, i);

            // add strike
            uint256 strikeTemp = uint256((seed >> 10) % 2 ** 20);
            uint256 strikeSign = uint256((seed >> 30) % 2);
            int24 strike = strikeTemp > 887272
                ? int24(uint24(strikeTemp / 2))
                : int24(uint24(strikeTemp));
            strike = strikeSign == 0 ? -strike : strike;
            strike = (strike / pool.tickSpacing()) * pool.tickSpacing();
            tokenId = tokenId.addStrike(strike, i);

            // add width
            tokenId = tokenId.addWidth(width, i);

            // add to input array of legs
            PanopticHelper.Leg memory _Leg = PanopticHelper.Leg({
                poolId: poolId,
                UniswapV3Pool: address(pool),
                optionRatio: optionRatio,
                asset: asset,
                isLong: isLong,
                tokenType: tokenId.tokenType(i),
                riskPartner: tokenId.riskPartner(i),
                strike: strike,
                width: width
            });
            inputLeg[i] = _Leg;
        }

        for (uint256 i; i < numberOfLegs; ++i) {
            // long strangles cannot be partnered; only short strangles
            if (
                tokenId.riskPartner(i) != i &&
                tokenId.tokenType(i) != tokenId.tokenType(tokenId.riskPartner(i))
            ) {
                vm.assume(tokenId.isLong(i) != 1);
            }
        }

        for (uint256 legIndex; legIndex < tokenId.countLegs(); legIndex++) {
            for (uint256 j = legIndex + 1; j < tokenId.countLegs(); ++j) {
                vm.assume(
                    !(tokenId.strike(legIndex) == tokenId.strike(j) &&
                        tokenId.width(legIndex) == tokenId.width(j) &&
                        tokenId.tokenType(legIndex) == tokenId.tokenType(j))
                );
            }
        }

        tokenId.validate();
        PanopticHelper.Leg[] memory unwrappedLeg = ph.unwrapTokenId(tokenId);

        uint256 keccakIn = uint256(keccak256(abi.encode(inputLeg)));

        uint256 keccakOut = uint256(keccak256(abi.encode(unwrappedLeg)));

        assertEq(keccakIn, keccakOut);
    }

    function test_Success_checkCollateral_OTMandITMShortCall(
        uint256 x,
        uint256[2] memory widthSeeds,
        int256[2] memory strikeSeeds,
        uint256[2] memory positionSizeSeeds,
        int256 atTickSeed,
        bool returnTokenType
    ) public {
        _initPool(x);

        ($width, $strike) = PositionUtils.getOTMSW(
            widthSeeds[0],
            strikeSeeds[0],
            uint24(tickSpacing),
            currentTick,
            0
        );

        ($width2, $strike2) = PositionUtils.getITMSW(
            widthSeeds[1],
            strikeSeeds[1],
            uint24(tickSpacing),
            currentTick,
            1
        );
        vm.assume($width2 != $width || $strike2 != $strike);

        populatePositionData([$width, $width2], [$strike, $strike2], positionSizeSeeds);

        atTick = int24(bound(atTickSeed, TickMath.MIN_TICK, TickMath.MAX_TICK));

        /// position size is denominated in the opposite of asset, so we do it in the token that is not WETH
        // leg 1
        TokenId tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            0,
            0,
            $strike,
            $width
        );
        // leg 2
        TokenId tokenId2 = TokenId.wrap(0).addPoolId(poolId).addLeg(
            0,
            1,
            isWETH,
            0,
            1,
            0,
            $strike2,
            $width2
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

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = pp
                .calculateAccumulatedFeesBatch(Alice, false, posIdList);

            tokenData0 = ct0.getAccountMarginDetails(Alice, atTick, posBalanceArray, premium0);
            tokenData1 = ct1.getAccountMarginDetails(Alice, atTick, posBalanceArray, premium1);

            (calculatedCollateralBalance, calculatedRequiredCollateral) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, returnTokenType ? 1 : 0, atTick);

            // these are the balance/required cross, reusing variables to save stack space
            (collateralBalance, requiredCollateral) = ph.checkCollateral(
                pp,
                Alice,
                atTick,
                returnTokenType ? 1 : 0,
                posIdList
            );

            assertEq(collateralBalance, calculatedCollateralBalance);
            assertEq(requiredCollateral, calculatedRequiredCollateral);
        }
    }
}
