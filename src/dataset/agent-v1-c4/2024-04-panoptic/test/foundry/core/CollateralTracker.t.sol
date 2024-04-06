// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Foundry
import "forge-std/Test.sol";
// Panoptic Core
import {PanopticPool} from "@contracts/PanopticPool.sol";
import {SemiFungiblePositionManager} from "@contracts/SemiFungiblePositionManager.sol";
import {CollateralTracker} from "@contracts/CollateralTracker.sol";
import {PanopticHelper} from "@periphery/PanopticHelper.sol";

// Panoptic Libraries
import {PanopticMath} from "@libraries/PanopticMath.sol";
import {Math} from "@libraries/PanopticMath.sol";
import {Errors} from "@libraries/Errors.sol";
import {LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";
import {TokenId} from "@types/TokenId.sol";
import {LiquidityChunk} from "@types/LiquidityChunk.sol";
import {Constants} from "@libraries/Constants.sol";
// Panoptic Interfaces
import {IERC20Partial} from "@tokens/interfaces/IERC20Partial.sol";
// Uniswap - Panoptic's version 0.8
import {FullMath} from "v3-core/libraries/FullMath.sol";
// Uniswap Libraries
import {TransferHelper} from "v3-periphery/libraries/TransferHelper.sol";
import {FixedPoint96} from "v3-core/libraries/FixedPoint96.sol";
import {PoolAddress} from "v3-periphery/libraries/PoolAddress.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
// Uniswap Interfaces
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";

import {PositionUtils, MiniPositionManager} from "../testUtils/PositionUtils.sol";

// CollateralTracker with extended functionality intended to expose internal data
contract CollateralTrackerHarness is CollateralTracker, PositionUtils, MiniPositionManager {
    constructor() CollateralTracker(10, 2_000, 1_000, -1_024, 5_000, 9_000, 20_000) {}

    // view deployer (panoptic pool)
    function panopticPool() external view returns (PanopticPool) {
        return s_panopticPool;
    }

    // whether the token has been initialized already or not
    function initalized() external view returns (bool) {
        return s_initialized;
    }

    // whether the current instance is token 0
    function underlyingIsToken0() external view returns (bool) {
        return s_underlyingIsToken0;
    }

    function _inAMM() external view returns (uint256) {
        return s_inAMM;
    }

    function _totalAssets() external view returns (uint256 totalManagedAssets) {
        return totalAssets();
    }

    function _availableAssets() external view returns (uint256) {
        return s_poolAssets;
    }

    function setPoolAssets(uint256 amount) external {
        s_poolAssets = uint128(amount);
    }

    function setInAMM(int128 amount) external {
        s_inAMM = uint128(int128(s_inAMM) + amount);
    }

    function setBalance(address owner, uint256 amount) external {
        balanceOf[owner] = amount;
    }

    function getRequiredCollateralAtUtilization(
        uint128 amount,
        uint256 isLong,
        int64 utilization
    ) external view returns (uint256 required) {
        return _getRequiredCollateralAtUtilization(amount, isLong, utilization);
    }

    function poolUtilizationHook() external view returns (int128) {
        return int128(_poolUtilization());
    }

    function getTotalRequiredCollateral(
        int24 currentTick,
        uint256[2][] memory positionBalanceArray
    ) external view returns (uint256 tokenRequired) {
        return _getTotalRequiredCollateral(currentTick, positionBalanceArray);
    }

    function sellCollateralRatio(int256 utilization) external view returns (uint256) {
        return _sellCollateralRatio(utilization);
    }

    function buyCollateralRatio(int256 utilization) external view returns (uint256) {
        return _buyCollateralRatio(uint256(utilization));
    }
}

// Inherits all of PanopticPool's functionality, however uses a modified version of startPool
// which enables us to use our modified CollateralTracker harness that exposes internal data
contract PanopticPoolHarness is PanopticPool {
    constructor(SemiFungiblePositionManager _SFPM) PanopticPool(_SFPM) {}

    function modifiedStartPool(
        address token0,
        address token1,
        IUniswapV3Pool uniswapPool
    ) external {
        // Store the univ3Pool variable
        s_univ3pool = IUniswapV3Pool(uniswapPool);

        // store token0 and token1
        address s_token0 = uniswapPool.token0();
        address s_token1 = uniswapPool.token1();

        // Start and store the collateral token0/1
        _initalizeCollateralPair(token0, token1, uniswapPool);

        (, , uint16 observationIndex, uint16 observationCardinality, , , ) = uniswapPool.slot0();

        int24 slowOracleTick = PanopticMath.computeMedianObservedPrice(
            uniswapPool,
            observationIndex,
            observationCardinality,
            SLOW_ORACLE_CARDINALITY,
            SLOW_ORACLE_PERIOD
        );

        unchecked {
            s_miniMedian =
                (uint256(block.number) << 216) +
                // magic number which adds (7,5,3,1,0,2,4,6) order and minTick in positions 7, 5, 3 and maxTick in 6, 4, 2
                // see comment on s_miniMedian initialization for format of this magic number
                (uint256(0xF590A6F276170D89E9F276170D89E9F276170D89E9000000000000)) +
                (uint256(uint24(slowOracleTick)) << 24) + // add to slot 4
                (uint256(uint24(slowOracleTick))); // add to slot 3
        }

        // Approve transfers of Panoptic Pool funds by SFPM
        IERC20Partial(s_token0).approve(address(SFPM), type(uint256).max);
        IERC20Partial(s_token1).approve(address(SFPM), type(uint256).max);

        // Approve transfers of Panoptic Pool funds by Collateral token
        IERC20Partial(s_token0).approve(address(s_collateralToken0), type(uint256).max);
        IERC20Partial(s_token1).approve(address(s_collateralToken1), type(uint256).max);
    }

    // Generate a new pair of collateral tokens from a univ3 pool
    function _initalizeCollateralPair(
        address token0,
        address token1,
        IUniswapV3Pool uniswapPool
    ) internal {
        // Deploy collateral tokens
        s_collateralToken0 = new CollateralTrackerHarness();
        s_collateralToken1 = new CollateralTrackerHarness();

        // initialize the token
        s_collateralToken0.startToken(true, token0, token1, uniswapPool.fee(), this);
        s_collateralToken1.startToken(false, token0, token1, uniswapPool.fee(), this);
    }

    // mimics an internal Panoptic pool _delegate call onto the collateral tracker
    function delegate(
        address delegator,
        address delegatee,
        uint128 assets,
        CollateralTracker collateralToken
    ) external {
        collateralToken.delegate(delegator, delegatee, assets);
    }

    function delegate(
        address delegatee,
        uint128 assets,
        CollateralTracker collateralToken
    ) external {
        collateralToken.delegate(delegatee, assets);
    }

    // mimics an internal Panoptic pool  revoke call onto the collateral tracker
    function revoke(
        address delegator,
        address delegatee,
        uint256 requestedAmount,
        CollateralTracker collateralToken
    ) external {
        collateralToken.revoke(delegator, delegatee, requestedAmount);
    }

    function refund(
        address delegator,
        address delegatee,
        int256 requestedAmount,
        CollateralTracker collateralToken
    ) external {
        collateralToken.refund(delegator, delegatee, requestedAmount);
    }

    function refund(
        address delegatee,
        uint256 requestedAmount,
        CollateralTracker collateralToken
    ) external {
        collateralToken.refund(delegatee, requestedAmount);
    }

    function getTWAP() external view returns (int24 twapTick) {
        return PanopticPool.getUniV3TWAP();
    }

    function positionBalance(
        address account,
        TokenId tokenId
    ) external view returns (LeftRightUnsigned balanceAndUtilizations) {
        balanceAndUtilizations = s_positionBalance[account][tokenId];
    }
}

contract SemiFungiblePositionManagerHarness is SemiFungiblePositionManager {
    constructor(IUniswapV3Factory _factory) SemiFungiblePositionManager(_factory) {}

    function accountLiquidity(
        bytes32 positionKey
    ) external view returns (LeftRightUnsigned shortAndNetLiquidity) {
        return s_accountLiquidity[positionKey];
    }
}

contract UniswapV3PoolMock {
    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }

    struct Info {
        // the total position liquidity that references this tick
        uint128 liquidityGross;
        // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left),
        int128 liquidityNet;
        // fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
        // only has relative meaning, not absolute — the value depends on when the tick is initialized
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        // the cumulative tick value on the other side of the tick
        int56 tickCumulativeOutside;
        // the seconds per unit of liquidity on the _other_ side of this tick (relative to the current tick)
        // only has relative meaning, not absolute — the value depends on when the tick is initialized
        uint160 secondsPerLiquidityOutsideX128;
        // the seconds spent on the other side of the tick (relative to the current tick)
        // only has relative meaning, not absolute — the value depends on when the tick is initialized
        uint32 secondsOutside;
        // true iff the tick is initialized, i.e. the value is exactly equivalent to the expression liquidityGross != 0
        // these 8 bits are set to prevent fresh sstores when crossing newly initialized ticks
        bool initialized;
    }

    Slot0 public slot0;
    mapping(int24 => Info) public ticks;
    int24 public tickSpacing;

    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;

    constructor(int24 _tickSpacing) {
        tickSpacing = _tickSpacing;
    }

    // helper to set info for the given tick
    function setInfo(
        int24 tick,
        uint256 _feeGrowthOutside0X128,
        uint256 _feeGrowthOutside1X128
    ) external {
        Info storage info = ticks[tick];

        info.feeGrowthOutside0X128 = _feeGrowthOutside0X128;
        info.feeGrowthOutside1X128 = _feeGrowthOutside1X128;
    }

    // directly tweak the fee growth values
    function setGlobal(uint256 _feeGrowthGlobal0X128, uint256 _feeGrowthGlobal1X128) external {
        feeGrowthGlobal0X128 = _feeGrowthGlobal0X128;
        feeGrowthGlobal1X128 = _feeGrowthGlobal1X128;
    }

    // allows dynamic setting of the current tick
    function setSlot0(int24 _tick) external {
        slot0.tick = _tick;
        slot0.sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_tick);
    }
}

contract CollateralTrackerTest is Test, PositionUtils {
    using Math for uint256;

    // users who will send/receive deposits, transfers, and withdrawals
    address Alice = makeAddr("Alice");
    address Bob = makeAddr("Bob");
    address Charlie = makeAddr("Charlie");
    address Swapper = makeAddr("Swapper");

    /*//////////////////////////////////////////////////////////////
                           MAINNET CONTRACTS
    //////////////////////////////////////////////////////////////*/

    IUniswapV3Pool constant USDC_WETH_5 =
        IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);

    IUniswapV3Pool constant WBTC_ETH_30 =
        IUniswapV3Pool(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD);

    IUniswapV3Pool constant MATIC_ETH_30 =
        IUniswapV3Pool(0x290A6a7460B308ee3F19023D2D00dE604bcf5B42);

    // 1 bps pool
    IUniswapV3Pool constant DAI_USDC_1 = IUniswapV3Pool(0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168);

    IUniswapV3Pool constant WSTETH_ETH_1 =
        IUniswapV3Pool(0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa);

    IUniswapV3Pool[5] public pools = [
        USDC_WETH_5,
        WBTC_ETH_30,
        MATIC_ETH_30,
        DAI_USDC_1,
        WSTETH_ETH_1
    ];

    // Mainnet factory address
    IUniswapV3Factory V3FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    // Mainnet router address - used for swaps
    ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // Mainnet WETH address
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // granted token amounts
    uint256 constant initialMockTokens = type(uint112).max;

    /*//////////////////////////////////////////////////////////////
                              WORLD STATE
    //////////////////////////////////////////////////////////////*/

    // store some data about the pool we are testing
    IUniswapV3Pool pool;
    uint64 poolId;
    uint256 isWETH;
    address token0;
    address token1;
    uint24 fee;
    int24 tickSpacing;
    int24 currentTick;
    uint160 currentSqrtPriceX96;
    uint256 feeGrowthGlobal0X128;
    uint256 feeGrowthGlobal1X128;

    // Current instance of Panoptic Pool, CollateralTokens, and SFPM
    PanopticPoolHarness panopticPool;
    address panopticPoolAddress;
    PanopticHelper panopticHelper;
    SemiFungiblePositionManagerHarness sfpm;
    CollateralTrackerHarness collateralToken0;
    CollateralTrackerHarness collateralToken1;

    /*//////////////////////////////////////////////////////////////
                            POSITION DATA
    //////////////////////////////////////////////////////////////*/

    uint128 positionSize0;
    uint128 positionSize1;
    TokenId[] positionIdList1;
    TokenId[] positionIdList;
    TokenId tokenId;
    TokenId tokenId1;

    // Positional details
    int24 width;
    int24 strike;
    int24 width1;
    int24 strike1;
    int24 rangeDown0;
    int24 rangeUp0;
    int24 rangeDown1;
    int24 rangeUp1;
    int24 legLowerTick;
    int24 legUpperTick;
    uint160 sqrtRatioAX96;
    uint160 sqrtRatioBX96;

    // Collateral
    int64 utilization;
    uint256 sellCollateralRatio;
    uint256 buyCollateralRatio;

    // notional / contracts
    uint128 notionalMoved;
    LeftRightUnsigned amountsMoved;
    LeftRightUnsigned amountsMovedPartner;
    uint256 movedRight;
    uint256 movedLeft;
    uint256 movedPartnerRight;
    uint256 movedPartnerLeft;

    // risk status
    int24 baseStrike;
    int24 partnerStrike;
    uint256 partnerIndex;
    uint256 tokenType;
    uint256 tokenTypeP;
    uint256 isLong;
    uint256 isLongP;

    // liquidity
    LiquidityChunk liquidityChunk;
    uint256 liquidity;

    uint256 balanceData0;
    uint256 thresholdData0;

    function _initWorld(uint256 seed) internal {
        // Pick a pool from the seed and cache initial state
        _cacheWorldState(pools[bound(seed, 0, pools.length - 1)]);

        _deployCustomPanopticPool(token0, token1, pool);
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
    }

    function _deployCustomPanopticPool(
        address _token0,
        address _token1,
        IUniswapV3Pool uniswapPool
    ) internal {
        // deploy the semiFungiblePositionManager
        sfpm = new SemiFungiblePositionManagerHarness(V3FACTORY);

        // Initialize the world pool
        sfpm.initializeAMMPool(_token0, _token1, fee);

        panopticHelper = new PanopticHelper(SemiFungiblePositionManager(sfpm));

        // deploy modified Panoptic pool
        panopticPool = new PanopticPoolHarness(sfpm);

        // initalize Panoptic Pool
        panopticPool.modifiedStartPool(_token0, _token1, uniswapPool);

        collateralToken0 = CollateralTrackerHarness(address(panopticPool.collateralToken0()));
        collateralToken1 = CollateralTrackerHarness(address(panopticPool.collateralToken1()));

        // store panoptic pool address
        panopticPoolAddress = address(panopticPool);
    }

    function _grantTokens(address recipient) internal {
        // give sender the max amount of underlying tokens
        deal(token0, recipient, initialMockTokens);
        deal(token1, recipient, initialMockTokens);
        assertEq(IERC20Partial(token0).balanceOf(recipient), initialMockTokens);
        assertEq(IERC20Partial(token1).balanceOf(recipient), initialMockTokens);
    }

    function _mockMaxDeposit(address recipient) internal {
        // award corresponding shares
        deal(
            address(collateralToken0),
            recipient,
            collateralToken0.previewDeposit(initialMockTokens),
            true
        );
        deal(
            address(collateralToken1),
            recipient,
            collateralToken1.previewDeposit(initialMockTokens),
            true
        );

        // equal deposits for both collateral token pairs for testing purposes
        // deposit to panoptic pool
        collateralToken0.setPoolAssets(collateralToken0._availableAssets() + initialMockTokens);
        collateralToken1.setPoolAssets(collateralToken1._availableAssets() + initialMockTokens);
        deal(
            token0,
            address(panopticPool),
            IERC20Partial(token0).balanceOf(panopticPoolAddress) + initialMockTokens
        );
        deal(
            token1,
            address(panopticPool),
            IERC20Partial(token1).balanceOf(panopticPoolAddress) + initialMockTokens
        );
    }

    //@note move this and panopticPool helper into position utils
    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    // used to accumulate premia for testing
    function twoWaySwap(uint256 swapSize) public {
        vm.startPrank(Swapper);

        // give Swapper the max amount of tokens
        _grantTokens(Swapper);

        IERC20Partial(token0).approve(address(router), type(uint256).max);
        IERC20Partial(token1).approve(address(router), type(uint256).max);

        swapSize = bound(swapSize, 10 ** 18, 10 ** 22);
        router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams(
                isWETH == 0 ? token0 : token1,
                isWETH == 1 ? token0 : token1,
                fee,
                address(0x23),
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
                address(0x23),
                block.timestamp,
                (swapSize * (1_000_000 - fee)) / 1_000_000,
                type(uint256).max,
                0
            )
        );

        (currentSqrtPriceX96, currentTick, , , , , ) = pool.slot0();
    }

    function setUp() public {}

    /*//////////////////////////////////////////////////////////////
                        START TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Success_StartToken_virtualShares() public {
        _initWorld(0);
        CollateralTracker ct = new CollateralTracker(
            10,
            2_000,
            1_000,
            -1_024,
            5_000,
            9_000,
            20_000
        );
        ct.startToken(false, token0, token1, fee, panopticPool);

        assertEq(ct.totalSupply(), 10 ** 6);
        assertEq(ct.totalAssets(), 1);
    }

    function test_Fail_startToken_alreadyInitializedToken(uint256 x) public {
        _initWorld(x);

        // Deploy collateral token
        collateralToken0 = new CollateralTrackerHarness();

        // initialize the token
        collateralToken0.startToken(false, token0, token1, fee, PanopticPool(address(0)));

        // fails if already initialized
        vm.expectRevert(Errors.CollateralTokenAlreadyInitialized.selector);
        collateralToken0.startToken(false, token0, token1, fee, PanopticPool(address(0)));
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/
    function test_Success_deposit(uint256 x, uint104 assets) public {
        // initalize world state
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on the msg.senders behalf
        IERC20Partial(token0).approve(address(collateralToken0), assets);
        IERC20Partial(token1).approve(address(collateralToken1), assets);

        // the amount of shares that can be minted
        // supply == 0 ? assets : FullMath.mulDiv(assets, supply, totalAssets());
        uint256 sharesToken0 = FullMath.mulDiv(
            uint256(assets) * 9_990,
            collateralToken0.totalSupply(),
            collateralToken0.totalAssets() * 10_000
        );
        uint256 sharesToken1 = FullMath.mulDiv(
            uint256(assets) * 9_990,
            collateralToken1.totalSupply(),
            collateralToken1.totalAssets() * 10_000
        );

        // deposit a number of assets determined via fuzzing
        // equal deposits for both collateral token pairs for testing purposes
        uint256 returnedShares0 = collateralToken0.deposit(assets, Bob);
        uint256 returnedShares1 = collateralToken1.deposit(assets, Bob);

        // check shares were calculated correctly
        assertEq(sharesToken0, returnedShares0);
        assertEq(sharesToken1, returnedShares1);

        // check if receiver got the shares
        assertEq(sharesToken0, collateralToken0.balanceOf(Bob));
        assertEq(sharesToken1, collateralToken1.balanceOf(Bob));

        address underlyingToken0 = collateralToken0.asset();
        address underlyingToken1 = collateralToken1.asset();

        // check if the panoptic pool got transferred the correct underlying assets
        assertEq(assets, IERC20Partial(underlyingToken0).balanceOf(address(panopticPool)));
        assertEq(assets, IERC20Partial(underlyingToken1).balanceOf(address(panopticPool)));
    }

    function test_Fail_deposit_DepositTooLarge(uint256 x, uint256 assets) public {
        // initalize world state
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on the msg.senders behalf
        IERC20Partial(token0).approve(address(collateralToken0), assets);
        IERC20Partial(token1).approve(address(collateralToken1), assets);

        // deposit more than the maximum (2**104 - 1)
        assets = bound(assets, uint256(type(uint104).max) + 1, type(uint256).max);

        vm.expectRevert(Errors.DepositTooLarge.selector);
        collateralToken0.deposit(assets, Bob);
        vm.expectRevert(Errors.DepositTooLarge.selector);
        collateralToken1.deposit(assets, Bob);
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    // fuzz for a random pool
    // fuzz for random asset amount to withdraw
    function test_Success_withdraw(uint256 x, uint104 assets) public {
        // initalize world state
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on the msg.senders behalf
        IERC20Partial(token0).approve(address(collateralToken0), assets);
        IERC20Partial(token1).approve(address(collateralToken1), assets);

        // deposit a number of assets determined via fuzzing
        // equal deposits for both collateral token pairs for testing purposes
        uint256 returnedShares0 = collateralToken0.deposit(assets, Bob);
        uint256 returnedShares1 = collateralToken1.deposit(assets, Bob);

        // Bob's token balance before withdraw
        uint256 balanceBefore0 = IERC20Partial(token0).balanceOf(Bob);
        uint256 balanceBefore1 = IERC20Partial(token1).balanceOf(Bob);

        // total amount of shares before withdrawal
        uint256 sharesBefore0 = convertToAssets(collateralToken0.totalSupply(), collateralToken0);
        uint256 sharesBefore1 = convertToAssets(collateralToken1.totalSupply(), collateralToken1);

        uint256 assetsToken0 = convertToAssets(returnedShares0, collateralToken0);
        uint256 assetsToken1 = convertToAssets(returnedShares1, collateralToken1);

        // withdraw tokens
        collateralToken0.withdraw(assetsToken0, Bob, Bob);
        collateralToken1.withdraw(assetsToken1, Bob, Bob);

        // Total amount of shares after withdrawal (after burn)
        uint256 sharesAfter0 = convertToAssets(collateralToken0.totalSupply(), collateralToken0);
        uint256 sharesAfter1 = convertToAssets(collateralToken1.totalSupply(), collateralToken1);

        // Bob's token balance after withdraw
        uint256 balanceAfter0 = IERC20Partial(token0).balanceOf(Bob);
        uint256 balanceAfter1 = IERC20Partial(token1).balanceOf(Bob);

        // check the correct amount of shares were burned
        // should be back to baseline
        assertEq(assetsToken0, sharesBefore0 - sharesAfter0);
        assertEq(assetsToken1, sharesBefore1 - sharesAfter1);

        // ensure underlying tokens were received back
        assertEq(assetsToken0, balanceAfter0 - balanceBefore0);
        assertEq(assetsToken1, balanceAfter1 - balanceBefore1);
    }

    // fail if attempting to withdraw more assets than the max withdraw amount
    function test_Fail_withdraw_ExceedsMax(uint256 x) public {
        // initalize world state
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // maxDeposit
        uint256 maxDeposit0 = collateralToken0.maxDeposit(Bob);
        uint256 maxDeposit1 = collateralToken1.maxDeposit(Bob);

        // approve collateral tracker to move tokens on the msg.senders behalf
        IERC20Partial(token0).approve(address(collateralToken0), maxDeposit0);
        IERC20Partial(token1).approve(address(collateralToken1), maxDeposit1);

        // deposit the max amount
        _mockMaxDeposit(Bob);

        // max withdrawable amount
        uint256 maxAssets = collateralToken0.maxWithdraw(Bob);

        // attempt to withdraw
        // fail as assets > maxWithdraw(owner)
        vm.expectRevert(Errors.ExceedsMaximumRedemption.selector);
        collateralToken0.withdraw(maxAssets + 1, Bob, Bob);
    }

    function test_Success_withdraw_OnBehalf(uint256 x, uint104 assets) public {
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), assets);
        IERC20Partial(token1).approve(address(collateralToken1), assets);

        // approve Alice to move tokens on Bob's behalf
        collateralToken0.approve(Alice, convertToShares(assets, collateralToken0));
        collateralToken1.approve(Alice, convertToShares(assets, collateralToken1));

        // deposit fuzzed amount of tokens
        _mockMaxDeposit(Bob);

        vm.startPrank(Alice);

        // Bob's token balance before withdraw
        uint256 balanceBefore0 = IERC20Partial(token0).balanceOf(Alice);
        uint256 balanceBefore1 = IERC20Partial(token1).balanceOf(Alice);

        // attempt to withdraw
        collateralToken0.withdraw(assets, Alice, Bob);
        collateralToken1.withdraw(assets, Alice, Bob);

        // Bob's token balance after withdraw
        uint256 balanceAfter0 = IERC20Partial(token0).balanceOf(Alice);
        uint256 balanceAfter1 = IERC20Partial(token1).balanceOf(Alice);

        // check the withdrawal was successful
        assertEq(assets, balanceAfter0 - balanceBefore0);
        assertEq(assets, balanceAfter1 - balanceBefore1);
    }

    function test_Fail_withdraw_onBehalf(uint256 x) public {
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        uint256 assets = type(uint104).max;

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), assets);
        IERC20Partial(token1).approve(address(collateralToken1), assets);

        // deposit fuzzed amount of tokens
        _mockMaxDeposit(Bob);

        vm.stopPrank();
        vm.startPrank(Alice);

        // attempt to withdraw
        // fail as user does not have approval to transfer on behalf
        vm.expectRevert(stdError.arithmeticError);
        collateralToken0.withdraw(100, Alice, Bob);
    }

    /*//////////////////////////////////////////////////////////////
                        MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Success_mint(uint256 x, uint104 shares) public {
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        shares = uint104(bound(shares, 0, (uint256(type(uint104).max) * 1000) / 1001));

        console2.log("test shares", shares);
        console2.log("test totalassets", collateralToken0.totalAssets());
        console2.log("test totalsupply", collateralToken0.totalSupply());
        // the amount of assets that would be deposited
        uint256 assetsToken0 = Math.mulDivRoundingUp(
            uint256(shares) * 10_000,
            collateralToken0.totalAssets(),
            collateralToken0.totalSupply() * 9_990
        );
        uint256 assetsToken1 = Math.mulDivRoundingUp(
            uint256(shares) * 10_000,
            collateralToken1.totalAssets(),
            collateralToken1.totalSupply() * 9_990
        );

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), type(uint256).max);
        IERC20Partial(token1).approve(address(collateralToken1), type(uint256).max);

        // deposit a number of assets determined via fuzzing
        // equal deposits for both collateral token pairs for testing purposes
        uint256 returnedAssets0 = collateralToken0.mint(shares, Bob);
        uint256 returnedAssets1 = collateralToken1.mint(shares, Bob);

        vm.stopPrank();

        // check shares were calculated correctly
        assertEq(assetsToken0, returnedAssets0);
        assertEq(assetsToken1, returnedAssets1);

        // check if receiver got the shares
        assertEq(shares, collateralToken0.balanceOf(Bob));
        assertEq(shares, collateralToken1.balanceOf(Bob));

        address underlyingToken0 = collateralToken0.asset();
        address underlyingToken1 = collateralToken1.asset();

        // check if the panoptic pool got transferred the correct underlying assets
        assertEq(returnedAssets0, IERC20Partial(underlyingToken0).balanceOf(address(panopticPool)));
        assertEq(returnedAssets1, IERC20Partial(underlyingToken1).balanceOf(address(panopticPool)));
    }

    function test_Fail_mint_DepositTooLarge(uint256 x, uint256 shares) public {
        // initalize world state
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on the msg.senders behalf
        IERC20Partial(token0).approve(address(collateralToken0), type(uint256).max);
        IERC20Partial(token1).approve(address(collateralToken1), type(uint256).max);

        // change the share price a little so we know it's checking the assets
        collateralToken0.deposit(2 ** 64, Bob);
        collateralToken1.deposit(2 ** 64, Bob);

        IERC20Partial(token0).transfer(address(panopticPool), 2 ** 64);
        IERC20Partial(token1).transfer(address(panopticPool), 2 ** 64);

        // mint more than the maximum (2**128 - 1)
        shares = bound(shares, collateralToken0.maxMint(address(0)), type(uint128).max);

        // clean out some incorrectly lower bounded values, the floor/ceiling functions make the line a bit murky
        vm.assume((collateralToken0.convertToAssets(shares) * 10_000) / 10_010 > type(uint104).max);

        vm.expectRevert(Errors.DepositTooLarge.selector);
        collateralToken0.mint(shares, Bob);
        vm.expectRevert(Errors.DepositTooLarge.selector);
        collateralToken1.mint(shares, Bob);
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    // transfer
    function test_Success_transfer(uint256 x, uint104 amount) public {
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), amount);
        IERC20Partial(token1).approve(address(collateralToken1), amount);

        // deposit a number of assets determined via fuzzing
        // equal deposits for both collateral token pairs for testing purposes
        _mockMaxDeposit(Bob);

        uint256 bal0 = collateralToken0.balanceOf(Bob);
        uint256 bal1 = collateralToken1.balanceOf(Bob);

        // Transfer to Alice
        collateralToken0.transfer(Alice, bal0);
        collateralToken1.transfer(Alice, bal1);

        // Check Alice received the correct amounts
        assertEq(bal0, collateralToken0.balanceOf(Alice));
        assertEq(bal1, collateralToken1.balanceOf(Alice));
    }

    // transfer fail Errors.PositionCountNotZero()
    function test_Fail_transfer_positionCountNotZero(
        uint256 x,
        uint104 amount,
        uint256 widthSeed,
        int256 strikeSeed,
        uint128 positionSizeSeed
    ) public {
        _initWorld(x);

        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve Collateral Token's to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
        IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

        // deposit a significant amount of assets into the Panoptic pool
        _mockMaxDeposit(Bob);

        // call will be minted in range
        (width, strike) = PositionUtils.getOTMSW(
            widthSeed,
            strikeSeed,
            uint24(tickSpacing),
            currentTick,
            1
        );

        // sell as Bob
        tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 0, 0, strike, width);
        positionIdList.push(tokenId);

        /// calculate position size
        (legLowerTick, legUpperTick) = tokenId.asTicks(0);

        positionSize0 = uint128(bound(positionSizeSeed, 2, 2 ** 104));
        _assumePositionValidity(Bob, tokenId, positionSize0);

        panopticPool.mintOptions(positionIdList, positionSize0, 0, 0, 0);

        // Attempt a transfer to Alice from Bob
        vm.expectRevert(Errors.PositionCountNotZero.selector);
        collateralToken0.transfer(Alice, amount);

        vm.expectRevert(Errors.PositionCountNotZero.selector);
        collateralToken1.transfer(Alice, amount);
    }

    // transferFrom
    function test_Success_transferFrom(uint256 x, uint104 amount) public {
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), amount);
        IERC20Partial(token1).approve(address(collateralToken1), amount);

        // approve Alice to move tokens on Bob's behalf
        collateralToken0.approve(Alice, convertToShares(amount, collateralToken0));
        collateralToken1.approve(Alice, convertToShares(amount, collateralToken1));

        // deposit a number of assets determined via fuzzing
        // equal deposits for both collateral token pairs for testing purposes
        collateralToken0.deposit(amount, Bob);
        collateralToken1.deposit(amount, Bob);

        vm.startPrank(Alice);

        uint256 bal0 = collateralToken0.balanceOf(Bob);
        uint256 bal1 = collateralToken1.balanceOf(Bob);

        // Alice executes transferFrom Bob to herself
        collateralToken0.transferFrom(Bob, Alice, bal0);
        collateralToken1.transferFrom(Bob, Alice, bal1);

        // Check Alice received the correct amounts
        assertEq(bal0, collateralToken0.balanceOf(Alice));
        assertEq(bal1, collateralToken1.balanceOf(Alice));
    }

    // transferFrom fail Errors.PositionCountNotZero()
    function test_Fail_transferFrom_positionCountNotZero(
        uint256 x,
        uint256 widthSeed,
        int256 strikeSeed,
        uint128 positionSizeSeed
    ) public {
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), type(uint256).max);
        IERC20Partial(token1).approve(address(collateralToken1), type(uint256).max);

        // award corresponding shares
        _mockMaxDeposit(Bob);

        {
            // call will be minted in range
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                1
            );

            // sell as Bob
            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 1, 0, strike, width);
            positionIdList.push(tokenId);

            positionSize0 = uint128(bound(positionSizeSeed, 2, 2 ** 104));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            panopticPool.mintOptions(positionIdList, positionSize0, 0, 0, 0);
        }

        // approve Alice to move shares on Bob's behalf
        IERC20Partial(address(collateralToken0)).approve(Alice, type(uint256).max);
        IERC20Partial(address(collateralToken1)).approve(Alice, type(uint256).max);

        uint256 bal0 = collateralToken0.balanceOf(Bob);
        uint256 bal1 = collateralToken1.balanceOf(Bob);

        // redeem from Alice on behalf of Bob
        vm.startPrank(Alice);

        // Check if test reverted
        vm.expectRevert(Errors.PositionCountNotZero.selector);
        collateralToken0.transferFrom(Bob, Alice, bal0);

        // Check if test reverted
        vm.expectRevert(Errors.PositionCountNotZero.selector);
        collateralToken1.transferFrom(Bob, Alice, bal1);
    }

    /*//////////////////////////////////////////////////////////////
                        SHARE REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Success_redeem(uint256 x, uint104 shares) public {
        uint256 assetsToken0;
        uint256 assetsToken1;

        uint256 debitedBalance0;
        uint256 debitedBalance1;
        {
            _initWorld(x);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // calculate underlying assets via amount of shares
            assetsToken0 = convertToAssets(shares, collateralToken0);
            assetsToken1 = convertToAssets(shares, collateralToken1);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), assetsToken0);
            IERC20Partial(token1).approve(address(collateralToken1), assetsToken1);

            // deposit a number of assets determined via fuzzing
            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Bob);

            // Bob's asset balance after depositing to the Panoptic pool
            debitedBalance0 = IERC20Partial(token0).balanceOf(Bob);
            debitedBalance1 = IERC20Partial(token1).balanceOf(Bob);
        }

        // Bound the shares redemption to the maxRedeemable amount
        uint256 shares0 = bound(shares, 0, collateralToken0.maxRedeem(Bob));
        uint256 shares1 = bound(shares, 0, collateralToken1.maxRedeem(Bob));

        // amount of shares Bob held before burn
        uint256 sharesBefore0 = collateralToken0.balanceOf(Bob);
        uint256 sharesBefore1 = collateralToken1.balanceOf(Bob);

        // execute redemption
        uint256 returnedAssets0 = collateralToken0.redeem(shares0, Bob, Bob);
        uint256 returnedAssets1 = collateralToken1.redeem(shares1, Bob, Bob);

        // amount of shares Bob holds after burn
        uint256 sharesAfter0 = collateralToken0.balanceOf(Bob);
        uint256 sharesAfter1 = collateralToken1.balanceOf(Bob);

        // check shares were burned correctly
        assertEq(sharesAfter0, sharesBefore0 - shares0);
        assertEq(sharesAfter1, sharesBefore1 - shares1);

        // Bob's current asset balance after redeemed assets were returned to him
        uint256 creditedBalance0 = IERC20Partial(token0).balanceOf(Bob);
        uint256 creditedBalance1 = IERC20Partial(token1).balanceOf(Bob);

        // check correct amount of assets were moved from the the Panoptic Pool to LP
        assertEq(returnedAssets0, creditedBalance0 - debitedBalance0);
        assertEq(returnedAssets1, creditedBalance1 - debitedBalance1);
    }

    function test_Fail_redeem_exceedsMax(uint256 x, uint256 sharesSeed) public {
        // fuzz
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), type(uint256).max);
        IERC20Partial(token1).approve(address(collateralToken1), type(uint256).max);

        // deposit a number of assets determined via fuzzing
        // equal deposits for both collateral token pairs for testing purposes
        _mockMaxDeposit(Bob);

        // Get minimum amount to bound for
        // as we want to gurantee a redemption attempt of above the max redeemable amount
        uint256 exceedsMaxRedeem0 = collateralToken0.maxRedeem(Bob) + 1;
        uint256 exceedsMaxRedeem1 = collateralToken1.maxRedeem(Bob) + 1;

        // Bound the shares redemption to the maxRedeemable amount
        uint256 shares0 = bound(sharesSeed, exceedsMaxRedeem0, type(uint136).max);
        uint256 shares1 = bound(sharesSeed, exceedsMaxRedeem1, type(uint136).max);

        // execute redemption
        vm.expectRevert(Errors.ExceedsMaximumRedemption.selector);
        collateralToken0.redeem(shares0, Bob, Bob);

        vm.expectRevert(Errors.ExceedsMaximumRedemption.selector);
        collateralToken1.redeem(shares1, Bob, Bob);
    }

    function test_Success_Redeem_onBehalf(uint128 x, uint104 shares) public {
        uint256 assetsToken0;
        uint256 assetsToken1;

        {
            _initWorld(x);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // calculate underlying assets via amount of shares
            assetsToken0 = convertToAssets(shares, collateralToken0);
            assetsToken1 = convertToAssets(shares, collateralToken1);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), assetsToken0);
            IERC20Partial(token1).approve(address(collateralToken1), assetsToken1);

            // deposit a number of assets determined via fuzzing
            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Bob);
        }

        // Bound the shares redemption to the maxRedeemable amount
        uint256 shares0 = bound(shares, 0, collateralToken0.maxRedeem(Bob));
        uint256 shares1 = bound(shares, 0, collateralToken1.maxRedeem(Bob));

        // amount of shares Bob held before burn
        uint256 sharesBefore0 = collateralToken0.balanceOf(Bob);
        uint256 sharesBefore1 = collateralToken1.balanceOf(Bob);

        // approve Alice to move shares/assets on Bob's behalf
        IERC20Partial(address(collateralToken0)).approve(Alice, shares0);
        IERC20Partial(address(collateralToken1)).approve(Alice, shares1);

        vm.startPrank(Alice);

        // execute redemption
        uint256 returnedAssets0 = collateralToken0.redeem(shares0, Alice, Bob);
        uint256 returnedAssets1 = collateralToken1.redeem(shares1, Alice, Bob);

        // amount of shares Bob holds after burn
        uint256 sharesAfter0 = collateralToken0.balanceOf(Bob);
        uint256 sharesAfter1 = collateralToken1.balanceOf(Bob);

        // check shares were burned correctly
        assertEq(sharesAfter0, sharesBefore0 - shares0);
        assertEq(sharesAfter1, sharesBefore1 - shares1);

        // Bob's current asset balance after redeemed assets were returned to him
        uint256 AliceBal0 = IERC20Partial(token0).balanceOf(Alice);
        uint256 AliceBal1 = IERC20Partial(token1).balanceOf(Alice);

        // // check correct amount of assets were moved from pool to Alice
        assertEq(returnedAssets0, AliceBal0);
        assertEq(returnedAssets1, AliceBal1);
    }

    function test_Fail_redeem_onBehalf(uint128 x) public {
        _initWorld(x);

        // hardcoded amount of shares to redeem
        uint256 shares = 10 ** 6;

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // calculate underlying assets via amount of shares
        uint256 assetsToken0 = convertToAssets(shares, collateralToken0);
        uint256 assetsToken1 = convertToAssets(shares, collateralToken1);

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), assetsToken0);
        IERC20Partial(token1).approve(address(collateralToken1), assetsToken1);

        // equal deposits for both collateral token pairs for testing purposes
        _mockMaxDeposit(Bob);

        // Start new interactions with user Alice
        vm.startPrank(Alice);

        // execute redemption
        // should fail as Alice is not authorized to withdraw assets on Bob behalf
        vm.expectRevert(stdError.arithmeticError);
        collateralToken0.redeem(assetsToken0, Alice, Bob);

        vm.expectRevert(stdError.arithmeticError);
        collateralToken1.redeem(assetsToken1, Alice, Bob);
    }

    /*//////////////////////////////////////////////////////////////
                        DELEGATE/REVOKE TESTS
    //////////////////////////////////////////////////////////////*/

    // transfer from delegator to delgatee
    function test_Success_delegate(uint256 x, uint104 assets) public {
        // fuzz
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), assets);
        IERC20Partial(token1).approve(address(collateralToken1), assets);

        // deposit a number of assets determined via fuzzing
        // equal deposits for both collateral token pairs for testing purposes
        collateralToken0.deposit(assets, Bob);
        collateralToken1.deposit(assets, Bob);

        // check delegatee balance before
        uint256 assetsBefore0 = convertToAssets(collateralToken0.balanceOf(Bob), collateralToken0);
        uint256 assetsBefore1 = convertToAssets(collateralToken1.balanceOf(Bob), collateralToken1);

        // invoke delegate transactions from the Panoptic pool
        panopticPool.delegate(Bob, Alice, uint128(assetsBefore0), collateralToken0);

        panopticPool.delegate(Bob, Alice, uint128(assetsBefore1), collateralToken1);

        // check delegatee balance after
        uint256 assetsAfter0 = convertToAssets(collateralToken0.balanceOf(Alice), collateralToken0);
        uint256 assetsAfter1 = convertToAssets(collateralToken1.balanceOf(Alice), collateralToken1);

        assertApproxEqAbs(assetsBefore0, assetsAfter0, 5);
        assertApproxEqAbs(assetsBefore1, assetsAfter1, 5);
    }

    function test_Success_delegate_virtual(uint256 x, uint104 assets) public {
        // fuzz
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        uint256 convertedShares = convertToShares(1_000_000_000, collateralToken0);

        // invoke delegate transactions from the Panoptic pool
        panopticPool.delegate(Alice, assets, collateralToken0);

        panopticPool.delegate(Alice, assets, collateralToken1);

        // check delegatee balance after
        uint256 sharesAfter0 = collateralToken0.balanceOf(Alice);
        uint256 sharesAfter1 = collateralToken1.balanceOf(Alice);

        // make sure share price stays the same
        assertEq(convertedShares, convertToShares(1_000_000_000, collateralToken0));

        assertEq(convertToShares(assets, collateralToken0), sharesAfter0);
        assertEq(convertToShares(assets, collateralToken0), sharesAfter1);
    }

    // transfer from delegatee to delegator
    function test_Success_revoke(uint256 x, uint104 shares) public {
        {
            // fuzz
            _initWorld(x);

            // Invoke all interactions with the Collateral Tracker from user Alice
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            uint256 assetsToken0 = bound(
                convertToAssets(shares, collateralToken0),
                1,
                type(uint104).max
            );
            uint256 assetsToken1 = bound(
                convertToAssets(shares, collateralToken1),
                1,
                type(uint104).max
            );

            // approve collateral tracker to move tokens on Alice's behalf
            IERC20Partial(token0).approve(address(collateralToken0), assetsToken0);
            IERC20Partial(token1).approve(address(collateralToken1), assetsToken1);

            // deposit a number of assets determined via fuzzing
            // equal deposits for both collateral token pairs for testing purposes
            collateralToken0.deposit(uint128(assetsToken0), Alice);
            collateralToken1.deposit(uint128(assetsToken1), Alice);
        }

        // check delegator balance before
        uint256 sharesBefore0 = collateralToken0.balanceOf(Bob);
        uint256 sharesBefore1 = collateralToken1.balanceOf(Bob);

        // invoke delegate transactions from the Panoptic pool
        panopticPool.revoke(
            Bob,
            Alice,
            convertToShares(collateralToken0.balanceOf(Alice), collateralToken0),
            collateralToken0
        );
        panopticPool.revoke(
            Bob,
            Alice,
            convertToShares(collateralToken1.balanceOf(Alice), collateralToken1),
            collateralToken1
        );

        // check delegatee balance after
        uint256 sharesAfter0 = collateralToken0.balanceOf(Alice);
        uint256 sharesAfter1 = collateralToken1.balanceOf(Alice);

        assertApproxEqAbs(sharesBefore0, sharesAfter0, 5);
        assertApproxEqAbs(sharesBefore1, sharesAfter1, 5);
    }

    function test_Success_revoke_mint(
        uint256 x,
        uint128 shares,
        uint256 existingShares,
        uint256 mintSeed
    ) public {
        vm.assume(shares < type(uint104).max - 100);
        // fuzz
        _initWorld(x);

        vm.startPrank(Charlie);

        _grantTokens(Charlie);

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);

        // deposit a number of assets determined via fuzzing
        collateralToken0.mint(
            bound(existingShares, 0, (uint256(type(uint104).max) * 10_000) / 10_010),
            Charlie
        );

        // Invoke all interactions with the Collateral Tracker from user Alice
        vm.startPrank(Alice);

        // give Bob the max amount of tokens
        _grantTokens(Alice);

        uint256 assetsToken0 = bound(
            convertToAssets(shares, collateralToken0),
            1,
            type(uint104).max
        );

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), assetsToken0);

        // deposit a number of assets determined via fuzzing
        // equal deposits for both collateral token pairs for testing purposes
        collateralToken0.deposit(uint128(assetsToken0), Alice);

        uint256 assetsBefore0 = collateralToken0.convertToAssets(
            collateralToken0.balanceOf(Alice)
        ) +
            bound(
                mintSeed,
                0,
                collateralToken0.convertToAssets(collateralToken0.balanceOf(Charlie))
            );
        vm.assume(collateralToken0.totalAssets() - assetsBefore0 > 0);
        // invoke delegate transactions from the Panoptic pool
        // attempt to request an amount greater than the delegatee's balance
        panopticPool.revoke(Bob, Alice, assetsBefore0, collateralToken0);

        // check delegatee balance after
        uint256 assetsAfter0 = collateralToken0.convertToAssets(collateralToken0.balanceOf(Bob));

        assertApproxEqAbs(assetsBefore0, assetsAfter0, 5);
    }

    function test_Success_refund_virtual(uint256 x, uint104 shares) public {
        {
            // fuzz
            _initWorld(x);

            // Invoke all interactions with the Collateral Tracker from user Alice
            vm.startPrank(Alice);

            // give Alice the max amount of tokens
            _grantTokens(Alice);

            uint256 assetsToken0 = bound(
                convertToAssets(shares, collateralToken0),
                1,
                type(uint104).max
            );
            uint256 assetsToken1 = bound(
                convertToAssets(shares, collateralToken1),
                1,
                type(uint104).max
            );

            // approve collateral tracker to move tokens on Alice's behalf
            IERC20Partial(token0).approve(address(collateralToken0), assetsToken0);
            IERC20Partial(token1).approve(address(collateralToken1), assetsToken1);

            // deposit a number of assets determined via fuzzing
            // equal deposits for both collateral token pairs for testing purposes
            collateralToken0.deposit(uint128(assetsToken0), Alice);
            collateralToken1.deposit(uint128(assetsToken1), Alice);
        }

        // check delegator balance before
        uint256 sharesBefore0 = collateralToken0.balanceOf(Alice);
        uint256 sharesBefore1 = collateralToken1.balanceOf(Alice);

        uint256 convertedShares = convertToShares(1_000_000_000, collateralToken0);

        // invoke delegate transactions from the Panoptic pool
        panopticPool.refund(
            Alice,
            convertToAssets(sharesBefore0, collateralToken0),
            collateralToken0
        );
        panopticPool.refund(
            Alice,
            convertToAssets(sharesBefore1, collateralToken1),
            collateralToken1
        );

        // make sure share price stays the same
        assertEq(convertedShares, convertToShares(1_000_000_000, collateralToken0));

        // check delegatee balance after
        uint256 sharesAfter0 = collateralToken0.balanceOf(Alice);
        uint256 sharesAfter1 = collateralToken1.balanceOf(Alice);

        assertApproxEqAbs(0, convertToAssets(sharesAfter0, collateralToken0), 5);
        assertApproxEqAbs(0, convertToAssets(sharesAfter1, collateralToken1), 5);
    }

    function test_success_refund_positive(uint256 x, uint104 shares) public {
        {
            // fuzz
            _initWorld(x);

            // Invoke all interactions with the Collateral Tracker from user Alice
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            uint256 assetsToken0 = bound(
                convertToAssets(shares, collateralToken0),
                1,
                type(uint104).max
            );
            uint256 assetsToken1 = bound(
                convertToAssets(shares, collateralToken1),
                1,
                type(uint104).max
            );

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), assetsToken0);
            IERC20Partial(token1).approve(address(collateralToken1), assetsToken1);

            // deposit a number of assets determined via fuzzing
            // equal deposits for both collateral token pairs for testing purposes
            collateralToken0.deposit(uint128(assetsToken0), Alice);
            collateralToken1.deposit(uint128(assetsToken1), Alice);
        }

        // invoke delegate transactions from the Panoptic pool
        panopticPool.refund(
            Alice,
            Bob,
            int256(convertToAssets(collateralToken0.balanceOf(Alice), collateralToken0)),
            collateralToken0
        );
        panopticPool.refund(
            Alice,
            Bob,
            int256(convertToAssets(collateralToken1.balanceOf(Alice), collateralToken1)),
            collateralToken1
        );

        // check delegatee balance after
        uint256 sharesAfter0 = collateralToken0.balanceOf(Alice);
        uint256 sharesAfter1 = collateralToken1.balanceOf(Alice);

        assertApproxEqAbs(0, convertToAssets(sharesAfter0, collateralToken0), 5);
        assertApproxEqAbs(0, convertToAssets(sharesAfter1, collateralToken1), 5);
    }

    function test_success_refund_negative(uint256 x, uint104 assets) public {
        // fuzz
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), assets);
        IERC20Partial(token1).approve(address(collateralToken1), assets);

        // deposit a number of assets determined via fuzzing
        // equal deposits for both collateral token pairs for testing purposes
        collateralToken0.deposit(assets, Bob);
        collateralToken1.deposit(assets, Bob);

        // check delegatee balance before
        uint256 sharesBefore0 = collateralToken0.balanceOf(Bob);

        // invoke delegate transactions from the Panoptic pool
        panopticPool.refund(
            Alice,
            Bob,
            -int256(convertToAssets(sharesBefore0, collateralToken0)),
            collateralToken0
        );

        panopticPool.refund(
            Alice,
            Bob,
            -int256(convertToAssets(sharesBefore0, collateralToken1)),
            collateralToken1
        );

        // check delegatee balance after
        uint256 sharesAfter0 = collateralToken0.balanceOf(Bob);
        uint256 sharesAfter1 = collateralToken1.balanceOf(Bob);

        assertApproxEqAbs(0, convertToAssets(sharesAfter0, collateralToken0), 5);
        assertApproxEqAbs(0, convertToAssets(sharesAfter1, collateralToken1), 5);
    }

    // access control on delegate/revoke/settlement functions
    function test_Fail_All_OnlyPanopticPool(uint256 x, address caller) public {
        _initWorld(x);
        vm.assume(caller != address(panopticPool));

        vm.prank(caller);

        vm.expectRevert(Errors.NotPanopticPool.selector);
        collateralToken0.delegate(address(0), address(0), 0);

        vm.expectRevert(Errors.NotPanopticPool.selector);
        collateralToken0.delegate(address(0), 0);

        vm.expectRevert(Errors.NotPanopticPool.selector);
        collateralToken0.refund(address(0), 0);

        vm.expectRevert(Errors.NotPanopticPool.selector);
        collateralToken0.revoke(address(0), address(0), 0);

        vm.expectRevert(Errors.NotPanopticPool.selector);
        collateralToken0.refund(address(0), address(0), 0);

        vm.expectRevert(Errors.NotPanopticPool.selector);
        collateralToken0.takeCommissionAddData(address(0), 0, 0, 0);

        vm.expectRevert(Errors.NotPanopticPool.selector);
        collateralToken0.exercise(address(0), 0, 0, 0, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            STRANGLES
    //////////////////////////////////////////////////////////////*/

    function test_Success_collateralCheck_shortStrangle(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        uint256 widthSeed2,
        int256 strikeSeed2,
        int24 atTick,
        uint128 utilizationSeed
    ) public {
        vm.assume(strikeSeed != strikeSeed2);

        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            (width1, strike1) = PositionUtils.getOTMSW(
                widthSeed2,
                strikeSeed2,
                uint24(tickSpacing),
                currentTick,
                1
            );

            vm.assume(width != width1 || strike != strike1);
            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 0, 0, 0, 0, strike, width);
            tokenId = tokenId.addLeg(1, 1, 0, 0, 1, 1, strike1, width1);
            positionIdList.push(tokenId);

            /// calculate position size
            (legLowerTick, legUpperTick) = tokenId.asTicks(0);

            positionSize0 = uint128(bound(positionSizeSeed, 10 ** 18, 10 ** 20));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            // Alice buys
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            _mockMaxDeposit(Alice);

            tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 0, 0, 0, 1, strike, width);
            tokenId1 = tokenId1.addLeg(1, 1, 0, 0, 1, 0, strike1, width1);
            positionIdList1.push(tokenId1);

            _assumePositionValidity(Alice, tokenId1, positionSize0 / 2);

            uint256 snapshot = vm.snapshot();

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 2,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            uint256 inAMMOffset = collateralToken0._inAMM();

            vm.revertTo(snapshot);

            // set utilization before minting
            // take into account the offsets as states are updated before utilization is checked for the mint
            uint64 targetUtilization = uint64(bound(utilizationSeed, 1, 9_999));
            setUtilization(collateralToken0, token1, int64(targetUtilization), inAMMOffset, false);

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 2,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Alice, tokenId1);

            uint128 poolUtilizations = uint128(poolUtilization0 == 0 ? 1 : poolUtilization0) +
                (uint128(poolUtilization1 == 0 ? 1 : poolUtilization1) << 64);

            (uint128 tokensRequired0, uint128 tokensRequired1) = _strangleTokensRequired(
                tokenId1,
                positionSize0 / 2,
                poolUtilizations,
                atTick,
                premium0,
                premium1
            );

            // checks tokens required
            assertEq(tokensRequired0, tokenData0.leftSlot(), "required token0");
            assertEq(tokensRequired1, tokenData1.leftSlot(), "required token1");
        }

        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 1, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                panopticPool,
                Alice,
                currentTick,
                1,
                positionIdList1
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    /*//////////////////////////////////////////////////////////////
                            SPREADS
    //////////////////////////////////////////////////////////////*/

    function test_Success_collateralCheck_OTMputSpread(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        uint256 widthSeed2,
        int256 strikeSeed,
        int256 strikeSeed2,
        int24 atTick,
        uint24 swapSizeSeed
    ) public {
        vm.assume(strikeSeed != strikeSeed2);

        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // award corresponding shares
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                1
            );

            (width1, strike1) = PositionUtils.getOTMSW(
                widthSeed2,
                strikeSeed2,
                uint24(tickSpacing),
                currentTick,
                1
            );

            vm.assume(width != width1 || strike != strike1);
            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 1, 0, strike, width);
            tokenId = tokenId.addLeg(1, 1, 1, 0, 1, 1, strike1, width1);
            positionIdList.push(tokenId);

            positionSize0 = uint128(bound(positionSizeSeed, 2, 2 ** 128));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            // Alice buys
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // award corresponding shares
            _mockMaxDeposit(Alice);

            tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 1, 1, 1, strike, width);
            tokenId1 = tokenId1.addLeg(1, 1, 1, 0, 1, 0, strike1, width1);
            positionIdList1.push(tokenId1);

            _assumePositionValidity(Alice, tokenId1, positionSize0 / 2);

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 2,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Alice, tokenId1);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint128 required = _spreadTokensRequired(tokenId1, positionSize0 / 2, poolUtilizations);

            // only add premium requirement if there is net premia owed
            premium0 = premium0 < 0 ? int128(10_000 * uint128(-premium0)) / 10_000 : int128(0);
            required += premium1 < 0 ? uint128((uint128(10_000) * uint128(-premium1)) / 10_000) : 0;

            assertEq(premium0, int128(tokenData0.leftSlot()), "required token0");
            assertEq(required, tokenData1.leftSlot(), "required token1");
        }

        {
            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 1, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                PanopticPool(address(panopticPool)),
                Alice,
                currentTick,
                1,
                positionIdList1
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    function test_Success_collateralCheck_OTMcallSpread(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        uint256 widthSeed2,
        int256 strikeSeed,
        int256 strikeSeed2,
        int24 atTick,
        uint256 swapSizeSeed
    ) public {
        vm.assume(strikeSeed != strikeSeed2);

        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // award corresponding shares
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            (width1, strike1) = PositionUtils.getOTMSW(
                widthSeed2,
                strikeSeed2,
                uint24(tickSpacing),
                currentTick,
                0
            );

            vm.assume(width != width1 || strike != strike1);
            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 0, 0, strike, width);
            tokenId = tokenId.addLeg(1, 1, 1, 0, 0, 1, strike1, width1);
            positionIdList.push(tokenId);

            positionSize0 = uint128(bound(positionSizeSeed, 2, 2 ** 128));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Alice, tokenId1);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            _spreadTokensRequired(tokenId1, positionSize0, poolUtilizations);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            // Alice buys
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Alice);

            tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 1, 0, 1, strike, width);
            tokenId1 = tokenId1.addLeg(1, 1, 1, 0, 0, 0, strike1, width1);
            positionIdList1.push(tokenId1);

            _assumePositionValidity(Alice, tokenId1, positionSize0 / 4);

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 4,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Alice, tokenId1);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint128 required = _spreadTokensRequired(tokenId1, positionSize0 / 4, poolUtilizations);

            // only add premium requirement if there is net premia owed
            required += premium0 < 0 ? uint128((uint128(10_000) * uint128(-premium0)) / 10_000) : 0;
            premium1 = premium1 < 0 ? int128(10_000 * uint128(-premium1)) / 10_000 : int128(0);
            assertEq(required, tokenData0.leftSlot(), "required token0");
            assertEq(premium1, int128(tokenData1.leftSlot()), "required token1");
        }

        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 1, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                PanopticPool(address(panopticPool)),
                Alice,
                currentTick,
                1,
                positionIdList1
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    function test_Success_collateralCheck_ITMputSpread(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        uint256 widthSeed2,
        int256 strikeSeed,
        int256 strikeSeed2,
        int24 atTick,
        uint256 swapSizeSeed
    ) public {
        vm.assume(strikeSeed != strikeSeed2);

        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // award corresponding shares
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getITMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                1
            );

            (width1, strike1) = PositionUtils.getITMSW(
                widthSeed2,
                strikeSeed2,
                uint24(tickSpacing),
                currentTick,
                1
            );

            vm.assume(width != width1 || strike != strike1);
            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 1, 0, strike, width);
            tokenId = tokenId.addLeg(1, 1, 1, 0, 1, 1, strike1, width1);
            positionIdList.push(tokenId);

            /// calculate position
            positionSize0 = uint128(bound(positionSizeSeed, 2, 2 ** 64));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Alice, tokenId1);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            _spreadTokensRequired(tokenId1, positionSize0, poolUtilizations);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            // Alice buys
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // award corresponding shares
            _mockMaxDeposit(Alice);

            tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 1, 1, 1, strike, width);
            tokenId1 = tokenId1.addLeg(1, 1, 1, 0, 1, 0, strike1, width1);
            positionIdList1.push(tokenId1);

            _assumePositionValidity(Alice, tokenId1, positionSize0 / 2);

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 2,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Alice, tokenId1);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint128 required = _spreadTokensRequired(tokenId1, positionSize0 / 2, poolUtilizations);

            // only add premium requirement if there is net premia owed
            premium0 = premium0 < 0 ? int128((10_000 * uint128(-premium0)) / 10_000) : int128(0);
            required += premium1 < 0 ? uint128((uint128(10_000) * uint128(-premium1)) / 10_000) : 0;
            assertEq(premium0, int128(tokenData0.leftSlot()), "required token0");
            assertEq(required, tokenData1.leftSlot(), "required token1");
        }

        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 1, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                PanopticPool(address(panopticPool)),
                Alice,
                currentTick,
                1,
                positionIdList1
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    function test_Success_collateralCheck_ITMcallSpread_assetTT1(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        uint256 widthSeed2,
        int256 strikeSeed,
        int256 strikeSeed2,
        int24 atTick,
        uint256 swapSizeSeed
    ) public {
        vm.assume(strikeSeed != strikeSeed2);

        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // award corresponding shares
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getITMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            (width1, strike1) = PositionUtils.getITMSW(
                widthSeed2,
                strikeSeed2,
                uint24(tickSpacing),
                currentTick,
                0
            );

            (rangeDown0, rangeUp0) = PanopticMath.getRangesFromStrike(width, tickSpacing);

            (rangeDown1, rangeUp1) = PanopticMath.getRangesFromStrike(width1, tickSpacing);

            vm.assume(width != width1 || strike != strike1);
            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
                0,
                1,
                isWETH,
                0,
                0,
                0,
                strike,
                width
            );
            tokenId = tokenId.addLeg(1, 1, isWETH, 0, 0, 1, strike1, width1);
            positionIdList.push(tokenId);

            positionSizeSeed = uint128(bound(positionSizeSeed, 10 ** 15, 10 ** 20));
            positionSize0 = uint128(
                Math.min(
                    getContractsForAmountAtTick(
                        currentTick,
                        strike - rangeDown0,
                        strike + rangeUp0,
                        isWETH,
                        positionSizeSeed
                    ),
                    getContractsForAmountAtTick(
                        currentTick,
                        strike1 - rangeDown1,
                        strike1 + rangeUp1,
                        isWETH,
                        positionSizeSeed
                    )
                )
            );
            _assumePositionValidity(Bob, tokenId, positionSize0);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            // Alice buys
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // award corresponding shares
            _mockMaxDeposit(Alice);

            tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(
                0,
                1,
                isWETH,
                1,
                0,
                1,
                strike,
                width
            );
            tokenId1 = tokenId1.addLeg(1, 1, isWETH, 0, 0, 0, strike1, width1);
            positionIdList1.push(tokenId1);

            _assumePositionValidity(Alice, tokenId1, positionSize0 / 2);

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 2,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Alice, tokenId1);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint128 required = _spreadTokensRequired(tokenId1, positionSize0 / 2, poolUtilizations);
            _assumePositionValidity(Alice, tokenId1, positionSize0 / 2);

            // only add premium requirement if there is net premia owed
            required += premium0 < 0 ? uint128((uint128(10_000) * uint128(-premium0)) / 10_000) : 0;
            premium1 = premium1 < 0 ? int128((10_000 * uint128(-premium1)) / 10_000) : int128(0);
            assertEq(required, tokenData0.leftSlot(), "required token0");
            assertEq(premium1, int128(tokenData1.leftSlot()), "required token1");
        }

        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 1, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                PanopticPool(address(panopticPool)),
                Alice,
                currentTick,
                1,
                positionIdList1
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    function test_Success_collateralCheck_ITMcallSpread_assetTT0(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        uint256 widthSeed2,
        int256 strikeSeed,
        int256 strikeSeed2,
        int24 atTick,
        uint256 swapSizeSeed
    ) public {
        vm.assume(strikeSeed != strikeSeed2);

        uint128 required;

        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // award corresponding shares
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getITMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            (width1, strike1) = PositionUtils.getITMSW(
                widthSeed2,
                strikeSeed2,
                uint24(tickSpacing),
                currentTick,
                0
            );

            (rangeDown0, rangeUp0) = PanopticMath.getRangesFromStrike(width, tickSpacing);
            (rangeDown1, rangeUp1) = PanopticMath.getRangesFromStrike(width1, tickSpacing);
            vm.assume(width != width1 || strike != strike1);
            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
                0,
                1,
                isWETH,
                0,
                0,
                0,
                strike,
                width
            );
            tokenId = tokenId.addLeg(1, 1, isWETH, 0, 0, 1, strike1, width1);
            positionIdList.push(tokenId);

            positionSizeSeed = uint128(bound(positionSizeSeed, 10 ** 15, 10 ** 20));
            positionSize0 = uint128(
                Math.min(
                    getContractsForAmountAtTick(
                        currentTick,
                        strike - rangeDown0,
                        strike + rangeUp0,
                        isWETH,
                        positionSizeSeed
                    ),
                    getContractsForAmountAtTick(
                        currentTick,
                        strike1 - rangeDown1,
                        strike1 + rangeUp1,
                        isWETH,
                        positionSizeSeed
                    )
                )
            );
            _assumePositionValidity(Bob, tokenId, positionSize0);

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Alice, tokenId1);
            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            _spreadTokensRequired(tokenId1, positionSize0, poolUtilizations);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            // Alice buys
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // award corresponding shares
            _mockMaxDeposit(Alice);

            tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(
                0,
                1,
                isWETH,
                1,
                0,
                1,
                strike,
                width
            );
            tokenId1 = tokenId1.addLeg(1, 1, isWETH, 0, 0, 0, strike1, width1);
            positionIdList1.push(tokenId1);

            _assumePositionValidity(Alice, tokenId1, positionSize0 / 2);
            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 2,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Alice, tokenId1);

            uint128 poolUtilizations = uint128(poolUtilization0 == 0 ? 1 : poolUtilization0) +
                (uint128(poolUtilization1 == 0 ? 1 : poolUtilization1) << 64);

            required = _spreadTokensRequired(tokenId1, positionSize0 / 2, poolUtilizations);
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Alice, tokenId1);
            console2.log("PU0", poolUtilization0);
            console2.log("PU1", poolUtilization1);

            // only add premium requirement if there is net premia owed
            required += premium0 < 0 ? uint128((uint128(10_000) * uint128(-premium0)) / 10_000) : 0;
            console2.log("premium0", premium0);
            premium1 = premium1 < 0 ? int128((10_000 * uint128(-premium1)) / 10_000) : int128(0);
            assertEq(required, tokenData0.leftSlot(), "required token0");
            assertEq(premium1, int128(tokenData1.leftSlot()), "required token1");
        }

        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 1, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                panopticPool,
                Alice,
                currentTick,
                1,
                positionIdList1
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    /* buy utilization checks */

    // use dynamic var for real utilization values instead of harcoding

    // utilization < targetPoolUtilization
    function test_Success_collateralCheck_buyCallMinUtilization(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        int256 strikeSeed2,
        uint64 utilizationSeed,
        int24 atTick,
        uint256 swapSizeSeed
    ) public {
        vm.assume(strikeSeed != strikeSeed2);

        uint64 targetUtilization;
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 0, 0, strike, width);
            positionIdList.push(tokenId);

            /// calculate position size
            (legLowerTick, legUpperTick) = tokenId.asTicks(0);

            positionSize0 = uint128(bound(positionSizeSeed, 2, 2 ** 104));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            // Alice buys
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Alice);

            tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 1, 0, 0, strike, width);
            positionIdList1.push(tokenId1);

            uint256 snapshot = vm.snapshot();

            uint256 inAMMBefore = collateralToken0._inAMM();

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 2,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            uint256 inAMMOffset = inAMMBefore - collateralToken0._inAMM();

            vm.revertTo(snapshot);

            // set utilization before minting
            // take into account the offsets as states are updated before utilization is checked for the mint
            targetUtilization = uint64(bound(utilizationSeed, 1, 4_999));
            setUtilization(collateralToken0, token0, int64(targetUtilization), inAMMOffset, true);

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 2,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            int128 currentUtilization = collateralToken0.poolUtilizationHook();
            vm.assume(currentUtilization < 5_000);
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Alice, tokenId1);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint256[2] memory checkSingle = [uint256(0), uint256(0)];
            uint128 required = _tokensRequired(
                tokenId1,
                positionSize0 / 2,
                atTick,
                poolUtilizations,
                checkSingle
            );

            // only add premium requirement if there is net premia owed
            required += premium0 < 0 ? uint128((uint128(10_000) * uint128(-premium0)) / 10_000) : 0;
            premium1 = premium1 < 0 ? int128((10_000 * uint128(-premium1)) / 10_000) : int128(0);
            assertEq(required, tokenData0.leftSlot(), "required token0");
            assertEq(premium1, int128(tokenData1.leftSlot()), "required token1");
        }

        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 0, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                PanopticPool(address(panopticPool)),
                Alice,
                currentTick,
                0,
                positionIdList1
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    // // utilization > DECIMALS_128
    // function test_Success_collateralCheck_buyUtilizationMax(
    //     uint256 x,
    //     uint128 positionSizeSeed,
    //     uint256 widthSeed,
    //     int256 strikeSeed,
    //     uint256 widthSeed2,
    //     int256 strikeSeed2
    // ) public {
    // }

    // gt than targetPoolUtilization and lt saturatedPoolUtilization
    function test_Success_collateralCheck_buyBetweenTargetSaturated(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        int256 strikeSeed2,
        uint64 utilizationSeed,
        int24 atTick,
        uint256 swapSizeSeed
    ) public {
        vm.assume(strikeSeed != strikeSeed2);

        uint64 targetUtilization;
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 0, 0, strike, width);
            positionIdList.push(tokenId);

            /// calculate position size
            (legLowerTick, legUpperTick) = tokenId.asTicks(0);

            positionSize0 = uint128(bound(positionSizeSeed, 2, 2 ** 120));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            // Alice buys
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Alice);

            tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 1, 0, 0, strike, width);
            positionIdList1.push(tokenId1);

            uint256 snapshot = vm.snapshot();

            uint256 inAMMBefore = collateralToken0._inAMM();

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 2,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            uint256 inAMMOffset = inAMMBefore - collateralToken0._inAMM();

            vm.revertTo(snapshot);

            // set utilization before minting
            // take into account the offsets as states are updated before utilization is checked for the mint
            targetUtilization = uint64(bound(utilizationSeed, 5_000, 9_000));
            setUtilization(collateralToken0, token0, int64(targetUtilization), inAMMOffset, true);

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 2,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            int128 currentUtilization = collateralToken0.poolUtilizationHook();
            vm.assume(currentUtilization > 5_000 && currentUtilization < 9_000);
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Alice, tokenId1);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint256[2] memory checkSingle = [uint256(0), uint256(0)];
            uint128 required = _tokensRequired(
                tokenId1,
                positionSize0 / 2,
                atTick,
                poolUtilizations,
                checkSingle
            );

            // only add premium requirement if there is net premia owed
            required += premium0 < 0 ? uint128((uint128(10_000) * uint128(-premium0)) / 10_000) : 0;
            premium1 = premium1 < 0 ? int128((10_000 * uint128(-premium1)) / 10_000) : int128(0);
            assertEq(required, tokenData0.leftSlot(), "required token0");
            assertEq(premium1, int128(tokenData1.leftSlot()), "required token1");
        }

        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 0, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                PanopticPool(address(panopticPool)),
                Alice,
                currentTick,
                0,
                positionIdList1
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    // gt than saturatedPoolUtilization
    function test_Success_collateralCheck_buyGTSaturatedPoolUtilization(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        uint64 utilizationSeed,
        int24 atTick,
        uint256 swapSizeSeed
    ) public {
        uint64 targetUtilization;
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 0, 0, strike, width);
            positionIdList.push(tokenId);

            /// calculate position size
            (legLowerTick, legUpperTick) = tokenId.asTicks(0);

            positionSize0 = uint128(bound(positionSizeSeed, 2, 2 ** 104));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            // Alice buys
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Alice);

            tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 1, 0, 0, strike, width);
            positionIdList1.push(tokenId1);

            uint256 snapshot = vm.snapshot();

            uint256 inAMMBefore = collateralToken0._inAMM();

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 2,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            uint256 inAMMOffset = inAMMBefore - collateralToken0._inAMM();

            vm.revertTo(snapshot);

            // set utilization before minting
            // take into account the offsets as states are updated before utilization is checked for the mint
            targetUtilization = uint64(bound(utilizationSeed, 9_001, 9_999));
            setUtilization(collateralToken0, token0, int64(targetUtilization), inAMMOffset, true);

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 2,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            int128 currentUtilization = collateralToken0.poolUtilizationHook();
            vm.assume(currentUtilization > 9_000);
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Alice, tokenId1);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint256[2] memory checkSingle = [uint256(0), uint256(0)];
            uint128 required = _tokensRequired(
                tokenId1,
                positionSize0 / 2,
                atTick,
                poolUtilizations,
                checkSingle
            );

            // checks tokens required
            premium1 = premium1 < 0 ? int128((10_000 * uint128(-premium1)) / 10_000) : int128(0);
            required += premium0 < 0 ? uint128((uint128(10_000) * uint128(-premium0)) / 10_000) : 0;
            assertEq(required, tokenData0.leftSlot(), "required token0");
            assertEq(premium1, int128(tokenData1.leftSlot()), "required token1");
        }

        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Alice, false, positionIdList1);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Alice,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 0, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                PanopticPool(address(panopticPool)),
                Alice,
                currentTick,
                0,
                positionIdList1
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    /* sell utilization checks */

    // utilization > DECIMALS_128

    // utilization < targetPoolUtilization
    function test_Success_collateralCheck_sellCallMinUtilization(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        uint64 utilizationSeed,
        int24 atTick,
        uint256 swapSizeSeed
    ) public {
        uint64 targetUtilization;
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 0, 0, strike, width);
            positionIdList.push(tokenId);

            /// calculate position size
            (legLowerTick, legUpperTick) = tokenId.asTicks(0);

            positionSize0 = uint128(bound(positionSizeSeed, 2, 2 ** 104));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            uint256 snapshot = vm.snapshot();

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            uint256 inAMMOffset = collateralToken0._inAMM();

            vm.revertTo(snapshot);

            // set utilization before minting
            // take into account the offsets as states are updated before utilization is checked for the mint
            targetUtilization = uint64(bound(utilizationSeed, 1, 4_999));
            setUtilization(
                collateralToken0,
                token0,
                int64((targetUtilization)),
                inAMMOffset,
                false
            );

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            vm.assume(
                collateralToken0.poolUtilizationHook() < 5_000 // targetPoolUtilization
            );
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Bob, tokenId);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint256[2] memory checkSingle = [uint256(0), uint256(0)];
            uint128 required = _tokensRequired(
                tokenId,
                positionSize0,
                atTick,
                poolUtilizations,
                checkSingle
            );

            // only add premium requirement if there is net premia owed
            premium1 = premium1 < 0 ? int128((10_000 * uint128(-premium1)) / 10_000) : int128(0);
            assertEq(required, tokenData0.leftSlot(), "required token0");
            assertEq(premium1, int128(tokenData1.leftSlot()), "required token1");
        }

        //check collateral output against panoptic pool at current tick
        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 0, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                panopticPool,
                Bob,
                currentTick,
                0,
                positionIdList
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    function test_Success_collateralCheck_sellPutMinUtilization(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        uint64 utilizationSeed,
        int24 atTick,
        uint256 swapSizeSeed
    ) public {
        uint64 targetUtilization;
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                1
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 1, 0, strike, width);
            positionIdList.push(tokenId);

            /// calculate position size
            (legLowerTick, legUpperTick) = tokenId.asTicks(0);

            positionSize0 = uint128(bound(positionSizeSeed, 10 ** 15, 10 ** 20));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            uint256 snapshot = vm.snapshot();

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            uint256 inAMMOffset = collateralToken0._inAMM();

            vm.revertTo(snapshot);

            // set utilization before minting
            // take into account the offsets as states are updated before utilization is checked for the mint
            targetUtilization = uint64(bound(utilizationSeed, 1, 4_999));
            setUtilization(
                collateralToken0,
                token0,
                int64((targetUtilization)),
                inAMMOffset,
                false
            );

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            vm.assume(collateralToken0.poolUtilizationHook() < 5_000);
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Bob, tokenId);

            // check user packed utilization
            assertApproxEqAbs(targetUtilization, poolUtilization0, 1, "utilization ct 0");
            assertApproxEqAbs(0, poolUtilization1, 1, "utilization ct 1");

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint256[2] memory checkSingle = [uint256(0), uint256(0)];
            uint128 required = _tokensRequired(
                tokenId,
                positionSize0,
                atTick,
                poolUtilizations,
                checkSingle
            );

            // only add premium requirement if there is net premia owed
            premium0 = premium0 < 0 ? int128((10_000 * uint128(-premium0)) / 10_000) : int128(0);
            required += premium1 < 0 ? uint128((uint128(10_000) * uint128(-premium1)) / 10_000) : 0;
            assertEq(premium0, int128(tokenData0.leftSlot()), "required token0");
            assertEq(required, tokenData1.leftSlot(), "required token1");
        }

        //check collateral output against panoptic pool at current tick
        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 0, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                PanopticPool(address(panopticPool)),
                Bob,
                currentTick,
                0,
                positionIdList
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    // utilization > saturatedPoolUtilization
    function test_Success_collateralCheck_sellCallGTSaturatedPoolUtilization_TT0(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        int256 strikeSeed2,
        uint64 utilizationSeed,
        int24 atTick,
        uint256 swapSizeSeed
    ) public {
        vm.assume(strikeSeed != strikeSeed2);

        uint64 targetUtilization;
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 0, 0, strike, width);
            positionIdList.push(tokenId);

            /// calculate position size
            (legLowerTick, legUpperTick) = tokenId.asTicks(0);

            positionSize0 = uint128(bound(positionSizeSeed, 2, 2 ** 128));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            uint256 snapshot = vm.snapshot();

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            uint256 inAMMOffset = collateralToken0._inAMM();

            vm.revertTo(snapshot);

            // set utilization before minting
            // take into account the offsets as states are updated before utilization is checked for the mint
            targetUtilization = uint64(bound(utilizationSeed, 9_001, 9_999));
            setUtilization(collateralToken0, token0, int64(targetUtilization), inAMMOffset, false);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            int128 currentUtilization = collateralToken0.poolUtilizationHook();
            vm.assume(currentUtilization > 8_999); // account for round by 1
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Bob, tokenId);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint256[2] memory checkSingle = [uint256(0), uint256(0)];
            uint128 required = _tokensRequired(
                tokenId,
                positionSize0,
                atTick,
                poolUtilizations,
                checkSingle
            );

            // checks tokens required
            required += premium0 < 0 ? uint128((uint128(10_000) * uint128(-premium0)) / 10_000) : 0;
            premium1 = premium1 < 0 ? int128((10_000 * uint128(-premium1)) / 10_000) : int128(0);
            assertEq(required, tokenData0.leftSlot(), "required token0");
            assertEq(premium1, int128(tokenData1.leftSlot()), "required token1");
        }

        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 0, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                PanopticPool(address(panopticPool)),
                Bob,
                currentTick,
                0,
                positionIdList
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    function test_Success_collateralCheck_sellPutGTSaturatedPoolUtilization(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        int256 strikeSeed2,
        uint64 utilizationSeed,
        int24 atTick,
        uint256 swapSizeSeed
    ) public {
        vm.assume(strikeSeed != strikeSeed2);

        uint64 targetUtilization;
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                1
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 1, 0, strike, width);
            positionIdList.push(tokenId);

            /// calculate position size
            (legLowerTick, legUpperTick) = tokenId.asTicks(0);

            positionSize0 = uint128(bound(positionSizeSeed, 2, 2 ** 128));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            uint256 snapshot = vm.snapshot();

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            uint256 inAMMOffset = collateralToken1._inAMM();

            vm.revertTo(snapshot);

            // set utilization before minting
            // take into account the offsets as states are updated before utilization is checked for the mint
            targetUtilization = uint64(bound(utilizationSeed, 9_001, 9_999));
            setUtilization(collateralToken1, token1, int64(targetUtilization), inAMMOffset, false);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            int128 currentUtilization = collateralToken1.poolUtilizationHook();
            vm.assume(currentUtilization > 8_999); // account for round by 1
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Bob, tokenId);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint256[2] memory checkSingle = [uint256(0), uint256(0)];
            uint128 required = _tokensRequired(
                tokenId,
                positionSize0,
                atTick,
                poolUtilizations,
                checkSingle
            );

            // only add premium requirement if there is net premia owed
            premium0 = premium0 < 0 ? int128((10_000 * uint128(-premium0)) / 10_000) : int128(0);
            required += premium1 < 0 ? uint128((uint128(10_000) * uint128(-premium1)) / 10_000) : 0;
            assertEq(premium0, int128(tokenData0.leftSlot()), "required token0");
            assertEq(required, tokenData1.leftSlot(), "required token1");
        }

        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 0, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                panopticPool,
                Bob,
                currentTick,
                0,
                positionIdList
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    // targetPoolUtilization < utilization < saturatedPoolUtilization
    function test_Success_collateralCheck_sellCallBetweenTargetSaturated_asset1(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        int256 strikeSeed2,
        uint64 utilizationSeed,
        int24 atTick,
        uint256 swapSizeSeed
    ) public {
        vm.assume(strikeSeed != strikeSeed2);

        uint64 targetUtilization;
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 0, 0, strike, width);
            positionIdList.push(tokenId);

            positionSize0 = uint128(bound(positionSizeSeed, 2, 2 ** 104));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            uint256 snapshot = vm.snapshot();

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            uint256 inAMMOffset = collateralToken0._inAMM();

            vm.revertTo(snapshot);

            // set utilization before minting
            // take into account the offsets as states are updated before utilization is checked for the mint
            targetUtilization = uint64(bound(utilizationSeed, 5_000, 8_999));
            setUtilization(collateralToken0, token0, int64(targetUtilization), inAMMOffset, false);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            int128 currentUtilization = collateralToken0.poolUtilizationHook();
            vm.assume(currentUtilization > 4_999 && currentUtilization < 9_000);
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Bob, tokenId);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint256[2] memory checkSingle = [uint256(0), uint256(0)];
            uint128 required = _tokensRequired(
                tokenId,
                positionSize0,
                atTick,
                poolUtilizations,
                checkSingle
            );

            // only add premium requirement if there is net premia owed
            premium1 = premium1 < 0 ? int128((10_000 * uint128(-premium1)) / 10_000) : int128(0);
            assertEq(required, tokenData0.leftSlot(), "required token0");
            assertEq(premium1, int128(tokenData1.leftSlot()), "required token1");
        }

        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 0, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                PanopticPool(address(panopticPool)),
                Bob,
                currentTick,
                0,
                positionIdList
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    function test_Success_collateralCheck_sellPutBetweenTargetSaturated_asset0(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        int256 strikeSeed2,
        uint64 utilizationSeed,
        int24 atTick,
        uint256 swapSizeSeed
    ) public {
        vm.assume(strikeSeed != strikeSeed2);

        uint64 targetUtilization;
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                1
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 0, 0, 1, 0, strike, width);
            positionIdList.push(tokenId);

            positionSize0 = uint128(bound(positionSizeSeed, 2, 2 ** 104));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            uint256 snapshot = vm.snapshot();

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

            uint256 inAMMOffset = collateralToken1._inAMM();

            vm.revertTo(snapshot);

            // set utilization before minting
            // take into account the offsets as states are updated before utilization is checked for the mint
            targetUtilization = uint64(bound(utilizationSeed, 5_000, 8_999));
            setUtilization(collateralToken1, token1, int64(targetUtilization), inAMMOffset, false);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
            int128 currentUtilization = collateralToken1.poolUtilizationHook();
            vm.assume(currentUtilization > 5_000 && currentUtilization < 9_000);
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Bob, tokenId);

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint256[2] memory checkSingle = [uint256(0), uint256(0)];
            uint128 required = _tokensRequired(
                tokenId,
                positionSize0,
                atTick,
                poolUtilizations,
                checkSingle
            );

            // only add premium requirement if there is net premia owed
            premium0 = premium0 < 0 ? int128((10_000 * uint128(-premium0)) / 10_000) : int128(0);
            required += premium1 < 0 ? uint128((uint128(10_000) * uint128(-premium1)) / 10_000) : 0;
            assertEq(premium0, int128(tokenData0.leftSlot()), "required token0");
            assertEq(required, tokenData1.leftSlot(), "required token1");
        }

        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 0, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                panopticPool,
                Bob,
                currentTick,
                0,
                positionIdList
            );

            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    // Positive premia
    function test_Success_collateralCheck_sellPosPremia(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        int24 atTick,
        uint24 swapSizeSeed
    ) public {
        uint64 targetUtilization;
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            collateralToken0.deposit(type(uint104).max, Bob);
            collateralToken1.deposit(type(uint104).max, Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                1
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 1, 0, strike, width);
            positionIdList.push(tokenId);

            /// calculate position size
            (legLowerTick, legUpperTick) = tokenId.asTicks(0);

            positionSize0 = uint128(bound(positionSizeSeed, 10 ** 15, 10 ** 20));
            _assumePositionValidity(Bob, tokenId, positionSize0);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        // mimic pool activity
        twoWaySwap(swapSizeSeed);

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                atTick,
                posBalanceArray,
                premium1
            );

            (, uint64 poolUtilization0, uint64 poolUtilization1) = panopticPool
                .optionPositionBalance(Bob, tokenId);

            // check user packed utilization
            assertApproxEqAbs(targetUtilization, poolUtilization0, 1, "utilization ct 0");
            assertApproxEqAbs(0, poolUtilization1, 1, "utilization ct 1");

            uint128 poolUtilizations = uint128(poolUtilization0) +
                (uint128(poolUtilization1) << 64);

            uint256[2] memory checkSingle = [uint256(0), uint256(0)];
            uint128 required = _tokensRequired(
                tokenId,
                positionSize0,
                atTick,
                poolUtilizations,
                checkSingle
            );

            assertTrue(premium0 >= 0 && premium1 >= 0, "invalid premia");

            // checks tokens required
            // only add premium requirement, if there is net premia owed
            required += premium1 < 0 ? uint128((uint128(10_000) * uint128(-premium1)) / 10_000) : 0;
            premium0 = premium0 < 0 ? int128((10_000 * uint128(-premium0)) / 10_000) : int128(0);
            assertEq(premium0, int128(tokenData0.leftSlot()), "required token0");
            assertEq(required, tokenData1.leftSlot(), "required token1");
        }

        //check collateral output against panoptic pool at current tick
        {
            (, currentTick, , , , , ) = pool.slot0();

            (int128 premium0, int128 premium1, uint256[2][] memory posBalanceArray) = panopticPool
                .calculateAccumulatedFeesBatch(Bob, false, positionIdList);

            LeftRightUnsigned tokenData0 = collateralToken0.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium0
            );
            LeftRightUnsigned tokenData1 = collateralToken1.getAccountMarginDetails(
                Bob,
                currentTick,
                posBalanceArray,
                premium1
            );

            (uint256 calcBalanceCross, uint256 calcThresholdCross) = PanopticMath
                .convertCollateralData(tokenData0, tokenData1, 0, currentTick);

            (balanceData0, thresholdData0) = panopticHelper.checkCollateral(
                PanopticPool(address(panopticPool)),
                Bob,
                currentTick,
                0,
                positionIdList
            );
            assertEq(balanceData0, calcBalanceCross, "0");
            assertEq(thresholdData0, calcThresholdCross, "1");
        }
    }

    // check force exercise range changes
    // check ranges are indeed evaluated at correct lower and upper tick bounds

    // try to force exercise an OTM option
    // call -> _currentTick < (strike - rangeDown)

    // put -> _currentTick > (strike + rangeUp)

    function test_Success_exerciseCostRanges_OTMCall(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        int24 atTick
    ) public {
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 0, 0, 0, strike, width);
            positionIdList.push(tokenId);

            // must be minimum at least 2 so there is enough liquidity to buy
            positionSize0 = uint128(bound(positionSizeSeed, 8, 2 ** 32));

            _assumePositionValidity(Bob, tokenId, positionSize0);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            // Alice buys
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Alice);

            tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(0, 1, 1, 1, 0, 0, strike, width);
            positionIdList1.push(tokenId1);

            _assumePositionValidity(Alice, tokenId1, positionSize0 / 4);

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 4,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (legLowerTick, legUpperTick) = tokenId1.asTicks(0);
            (, int24 rangeUp) = PanopticMath.getRangesFromStrike(width, tickSpacing);

            // strike - rangeDown
            vm.assume(atTick < legLowerTick);

            (LeftRightSigned longAmounts, ) = PanopticMath.computeExercisedAmounts(
                tokenId1,
                positionSize0 / 4
            );

            uint256 currNumRangesFromStrikeDown = uint256(
                (int256(strike - rangeUp - atTick)) / rangeUp
            );

            int256 feeUp = (-1_024 >> currNumRangesFromStrikeDown);

            int256 exerciseFee0 = (longAmounts.rightSlot() * feeUp) / 10_000;
            int256 exerciseFee1 = (longAmounts.leftSlot() * feeUp) / 10_000;

            LeftRightSigned exerciseFees = collateralToken0.exerciseCost(
                atTick,
                atTick, // use the fuzzed tick as the median tick for testing purposes
                tokenId1,
                positionSize0 / 4,
                longAmounts
            );

            assertEq(exerciseFees.rightSlot(), exerciseFee0);
            assertEq(exerciseFees.leftSlot(), exerciseFee1);
        }
    }

    function test_Success_exerciseCostRanges_OTMPut(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        int24 atTick,
        uint256 asset
    ) public {
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
                0,
                1,
                asset % 1,
                0,
                1,
                0,
                strike,
                width
            );
            positionIdList.push(tokenId);

            // must be minimum at least 2 so there is enough liquidity to buy
            positionSize0 = uint128(bound(positionSizeSeed, 8, 2 ** 32));

            _assumePositionValidity(Bob, tokenId, positionSize0);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            // Alice buys
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Alice);

            tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(
                0,
                1,
                asset % 1,
                1,
                1,
                0,
                strike,
                width
            );
            positionIdList1.push(tokenId1);

            _assumePositionValidity(Alice, tokenId1, positionSize0 / 4);

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 4,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (legLowerTick, legUpperTick) = tokenId1.asTicks(0);
            (, int24 rangeUp) = PanopticMath.getRangesFromStrike(width, tickSpacing);

            // strike - rangeDown
            vm.assume(atTick < legLowerTick);

            (LeftRightSigned longAmounts, ) = PanopticMath.computeExercisedAmounts(
                tokenId1,
                positionSize0 / 4
            );

            uint256 currNumRangesFromStrikeDown = uint256(
                (int256(strike - rangeUp - atTick)) / rangeUp
            );

            int256 feeUp = (-1_024 >> currNumRangesFromStrikeDown);

            int256 exerciseFee0 = (longAmounts.rightSlot() * feeUp) / 10_000;
            int256 exerciseFee1 = (longAmounts.leftSlot() * feeUp) / 10_000;

            LeftRightSigned exerciseFees = collateralToken0.exerciseCost(
                atTick,
                atTick, // use the fuzzed tick as the median tick for testing purposes
                tokenId1,
                positionSize0 / 4,
                longAmounts
            );

            assertEq(exerciseFees.rightSlot(), exerciseFee0);
            assertEq(exerciseFees.leftSlot(), exerciseFee1);
        }
    }

    function test_Success_exerciseCostRanges_ITMCall(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        int24 atTick,
        uint256 asset
    ) public {
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
                0,
                1,
                asset % 1,
                0,
                0,
                0,
                strike,
                width
            );
            positionIdList.push(tokenId);

            // must be minimum at least 2 so there is enough liquidity to buy
            positionSize0 = uint128(bound(positionSizeSeed, 8, 2 ** 32));

            _assumePositionValidity(Bob, tokenId, positionSize0);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            // Alice buys
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Alice);

            tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(
                0,
                1,
                asset % 1,
                1,
                0,
                0,
                strike,
                width
            );
            positionIdList1.push(tokenId1);

            _assumePositionValidity(Alice, tokenId1, positionSize0 / 4);

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 4,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (legLowerTick, legUpperTick) = tokenId1.asTicks(0);
            (, int24 rangeUp) = PanopticMath.getRangesFromStrike(width, tickSpacing);

            // strike - rangeDown
            vm.assume(atTick > legUpperTick);

            (LeftRightSigned longAmounts, ) = PanopticMath.computeExercisedAmounts(
                tokenId1,
                positionSize0 / 4
            );

            uint256 currNumRangesFromStrikeDown = uint256(
                (int256(atTick - strike - rangeUp)) / rangeUp
            );

            int256 feeUp = (-1_024 >> currNumRangesFromStrikeDown);

            int256 exerciseFee0 = (longAmounts.rightSlot() * feeUp) / 10_000;
            int256 exerciseFee1 = (longAmounts.leftSlot() * feeUp) / 10_000;

            LeftRightSigned exerciseFees = collateralToken0.exerciseCost(
                atTick,
                atTick, // use the fuzzed tick as the median tick for testing purposes
                tokenId1,
                positionSize0 / 4,
                longAmounts
            );

            assertEq(exerciseFees.rightSlot(), exerciseFee0);
            assertEq(exerciseFees.leftSlot(), exerciseFee1);
        }
    }

    function test_Success_exerciseCostRanges_ITMPut(
        uint256 x,
        uint128 positionSizeSeed,
        uint256 widthSeed,
        int256 strikeSeed,
        int24 atTick,
        uint256 asset
    ) public {
        {
            _initWorld(x);

            // initalize a custom Panoptic pool
            _deployCustomPanopticPool(token0, token1, pool);

            // Invoke all interactions with the Collateral Tracker from user Bob
            vm.startPrank(Bob);

            // give Bob the max amount of tokens
            _grantTokens(Bob);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Bob);

            // have Bob sell
            (width, strike) = PositionUtils.getOTMSW(
                widthSeed,
                strikeSeed,
                uint24(tickSpacing),
                currentTick,
                0
            );

            tokenId = TokenId.wrap(0).addPoolId(poolId).addLeg(
                0,
                1,
                asset % 1,
                0,
                1,
                0,
                strike,
                width
            );
            positionIdList.push(tokenId);

            // must be minimum at least 2 so there is enough liquidity to buy
            positionSize0 = uint128(bound(positionSizeSeed, 8, 2 ** 32));

            _assumePositionValidity(Bob, tokenId, positionSize0);

            panopticPool.mintOptions(
                positionIdList,
                positionSize0,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        {
            // Alice buys
            vm.startPrank(Alice);

            // give Bob the max amount of tokens
            _grantTokens(Alice);

            // approve collateral tracker to move tokens on Bob's behalf
            IERC20Partial(token0).approve(address(collateralToken0), type(uint128).max);
            IERC20Partial(token1).approve(address(collateralToken1), type(uint128).max);

            // equal deposits for both collateral token pairs for testing purposes
            _mockMaxDeposit(Alice);

            tokenId1 = TokenId.wrap(0).addPoolId(poolId).addLeg(
                0,
                1,
                asset % 1,
                1,
                1,
                0,
                strike,
                width
            );
            positionIdList1.push(tokenId1);

            _assumePositionValidity(Alice, tokenId1, positionSize0 / 4);

            panopticPool.mintOptions(
                positionIdList1,
                positionSize0 / 4,
                type(uint64).max,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );
        }

        // check requirement at fuzzed tick
        {
            atTick = int24(bound(atTick, TickMath.MIN_TICK, TickMath.MAX_TICK));
            atTick = (atTick / tickSpacing) * tickSpacing;

            (legLowerTick, legUpperTick) = tokenId1.asTicks(0);
            (, int24 rangeUp) = PanopticMath.getRangesFromStrike(width, tickSpacing);

            // strike - rangeDown
            vm.assume(atTick > legUpperTick);

            (LeftRightSigned longAmounts, ) = PanopticMath.computeExercisedAmounts(
                tokenId1,
                positionSize0 / 4
            );

            uint256 currNumRangesFromStrikeDown = uint256(
                (int256(atTick - strike - rangeUp)) / rangeUp
            );

            int256 feeUp = (-1_024 >> currNumRangesFromStrikeDown);

            int256 exerciseFee0 = (longAmounts.rightSlot() * feeUp) / 10_000;
            int256 exerciseFee1 = (longAmounts.leftSlot() * feeUp) / 10_000;

            LeftRightSigned exerciseFees = collateralToken0.exerciseCost(
                atTick,
                atTick, // use the fuzzed tick as the median tick for testing purposes
                tokenId1,
                positionSize0 / 4,
                longAmounts
            );

            assertEq(exerciseFees.rightSlot(), exerciseFee0);
            assertEq(exerciseFees.leftSlot(), exerciseFee1);
        }
    }

    /* Utilization setter */
    function setUtilization(
        CollateralTrackerHarness collateralToken,
        address token,
        int256 targetUtilization,
        uint inAMMOffset,
        bool isBuy
    ) public {
        // utilization = inAMM * DECIMALS / totalAssets()
        // totalAssets() = PanopticPoolBal - lockedFunds + inAMM
        //        totalAssets() = z + inAMM
        //
        //
        // DECIMALS = 10_000
        //
        // utilization = (inAMM * DECIMALS) / ((PanopticPoolBal - lockedFunds) + inAMM)
        //      z = (PanopticPoolBal - lockedFunds)
        //      utilization =  (inAMM * DECIMALS) / z + inAMM
        //      inAMM = (utilization * z) / (10_000 - utilization)
        //      inAMM / z = utilization / (10_000 - utilization)
        //
        // inAMM / (PanopticPoolBal - lockedFunds) = (utilization / (10_000(DECIMALS) - utilization))
        //
        // i.e utilization of 9_000
        //    inAMM / (PanopticPoolBal - lockedFunds) = 9_000 / 10_000 - 9_000
        //    inAMM / (PanopticPoolBal - lockedFunds) = 9
        //    assume bal of (pool > lockedFunds) and (bal pool - lockedFunds) + inAMM > 0)
        //
        //    i.e 900 / (110 - 10) = 9
        //    utilization = (inAMM * DECIMALS) / ((PanopticPoolBal - lockedFunds) + inAMM)
        //    utilization = (900 * 10_000) / ((110 - 10) + 900)
        //    utilization = 9000.0
        //
        //-----------------------------------------------------------
        int128 _poolBalance = int128(int256(IERC20Partial(token).balanceOf(address(panopticPool))));
        // Solve for a mocked inAMM amount using real lockedFunds and pool bal
        // satisfy the condition of poolBalance > lockedFunds
        // let poolBalance and lockedFunds be fuzzed
        // inAMM = utilization * (PanopticPoolBal - lockedFunds) / (10_000 - utilization)
        vm.assume(_poolBalance < type(int128).max);
        int256 inAMM = (targetUtilization * (_poolBalance)) / (10_000 - targetUtilization);
        isBuy ? inAMM += int128(int256((inAMMOffset))) : inAMM -= int128(int256((inAMMOffset)));

        // set states
        collateralToken.setInAMM(int128(inAMM));
        deal(token, address(panopticPool), uint128(_poolBalance));
    }

    /*//////////////////////////////////////////////////////////////
                        CONVERT TO ASSETS
    //////////////////////////////////////////////////////////////*/

    function test_Success_convertToAssets_supplyNonZero(uint256 x, uint104 shares) public {
        // fuzz
        _initWorld(x);

        _testconvertToAssetsNonZero(shares);
    }

    // convert to assets tests with a non-zero supply
    // internal function as this is used in many other preview tests
    function _testconvertToAssetsNonZero(uint104 shares) internal returns (uint256) {
        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), shares);
        IERC20Partial(token1).approve(address(collateralToken1), shares);

        // deposit a number of assets determined via fuzzing
        // equal deposits for both collateral token pairs for testing purposes
        collateralToken0.deposit(shares, Bob);
        collateralToken1.deposit(shares, Bob);

        // amount of assets user deposited computed in amount of shares
        uint256 assets0 = convertToAssets(shares, collateralToken0);
        uint256 assets1 = convertToAssets(shares, collateralToken1);

        // actual value of current shares redeemable
        uint256 actualValue0 = collateralToken0.convertToAssets(shares);
        uint256 actualValue1 = collateralToken1.convertToAssets(shares);

        // ensure the correct amount of shares to assets is computed
        assertEq(assets0, actualValue0);
        assertEq(assets1, actualValue1);

        return assets0;
    }

    /*//////////////////////////////////////////////////////////////
                        CONVERT TO SHARES
    //////////////////////////////////////////////////////////////*/

    function test_Success_convertToShares_supplyNonZero(uint256 x, uint104 assets) public {
        // fuzz
        _initWorld(x);

        _testconvertToSharesNonZero(assets);
    }

    // convert to assets tests with a non-zero supply
    // internal function as this is used in many other preview tests
    function _testconvertToSharesNonZero(uint104 assets) internal returns (uint256 shares0) {
        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), assets);
        IERC20Partial(token1).approve(address(collateralToken1), assets);

        // deposit a number of assets determined via fuzzing
        // equal deposits for both collateral token pairs for testing purposes
        collateralToken0.deposit(assets, Bob);
        collateralToken1.deposit(assets, Bob);

        // amount of assets user deposited computed in amount of shares
        shares0 = convertToShares(assets, collateralToken0);
        uint256 shares1 = convertToShares(assets, collateralToken1);

        // actual value of current shares redeemable
        uint256 actualValue0 = collateralToken0.convertToAssets(shares0);
        uint256 actualValue1 = collateralToken1.convertToAssets(shares1);

        // ensure the correct amount of assets to shares is computed
        assertApproxEqAbs(assets, actualValue0, 5);
        assertApproxEqAbs(assets, actualValue1, 5);

        return shares0;
    }

    /*//////////////////////////////////////////////////////////////
                        MISCELLANEOUS QUERIES
    //////////////////////////////////////////////////////////////*/

    function test_Success_previewRedeem(uint256 x) public {
        _initWorld(x);

        // use a fixed amount for single test
        uint256 expectedValue = _testconvertToAssetsNonZero(1000);

        // real value
        uint256 actualValue = collateralToken0.previewRedeem(1000);

        assertEq(expectedValue, actualValue);
    }

    // maxRedeem
    function test_Success_maxRedeem(uint256 x, uint104 shares) public {
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // calculate underlying assets via amount of shares
        uint256 assetsToken0 = convertToAssets(shares, collateralToken0);
        uint256 assetsToken1 = convertToAssets(shares, collateralToken1);

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), assetsToken0);
        IERC20Partial(token1).approve(address(collateralToken1), assetsToken1);

        // deposit a number of assets determined via fuzzing
        // equal deposits for both collateral token pairs for testing purposes
        collateralToken0.deposit(uint128(assetsToken0), Bob);
        collateralToken1.deposit(uint128(assetsToken1), Bob);

        // how many funds that can be redeemed currently
        uint256 availableAssets0 = convertToShares(
            collateralToken0._availableAssets(),
            collateralToken0
        );
        uint256 availableAssets1 = convertToShares(
            collateralToken1._availableAssets(),
            collateralToken1
        );

        // current share balance of owner
        uint256 balance0 = collateralToken0.balanceOf(Bob);
        uint256 balance1 = collateralToken1.balanceOf(Bob);

        // actual maxRedeem returned value
        uint256 actualValue0 = collateralToken0.maxRedeem(Bob);
        uint256 actualValue1 = collateralToken1.maxRedeem(Bob);

        // if there are option positions this should return 0
        if (panopticPool.numberOfPositions(Bob) != 0) {
            assertEq(0, actualValue0);
            assertEq(0, actualValue1);
            // if available is greater than the user balance
            // return the user balance
        } else if (availableAssets0 > balance0) {
            assertEq(balance0, actualValue0);
            assertEq(balance1, actualValue1);
        } else {
            assertEq(availableAssets0, actualValue0);
            assertEq(availableAssets1, actualValue1);
        }
    }

    // previewWithdraw
    function test_Success_previewWithdraw(uint256 x) public {
        _initWorld(x);

        // use a fixed amount for single test
        _testconvertToSharesNonZero(1000);

        // real value
        uint256 actualValue = collateralToken0.previewWithdraw(1000);

        assertEq(actualValue, 999001000);
    }

    // maxWithdraw
    function test_Success_maxWithdraw(uint256 x, uint104 assets) public {
        _initWorld(x);

        // Invoke all interactions with the Collateral Tracker from user Bob
        vm.startPrank(Bob);

        // give Bob the max amount of tokens
        _grantTokens(Bob);

        // approve collateral tracker to move tokens on Bob's behalf
        IERC20Partial(token0).approve(address(collateralToken0), assets);
        IERC20Partial(token1).approve(address(collateralToken1), assets);

        // deposit a number of assets determined via fuzzing
        // equal deposits for both collateral token pairs for testing purposes
        collateralToken0.deposit(assets, Bob);
        collateralToken1.deposit(assets, Bob);

        // how many funds that can be redeemed currently
        uint256 availableAssets0 = convertToShares(
            collateralToken0._availableAssets(),
            collateralToken0
        );

        // current share balance of owner
        uint256 balance0 = convertToAssets(collateralToken0.balanceOf(Bob), collateralToken0);
        uint256 balance1 = convertToAssets(collateralToken1.balanceOf(Bob), collateralToken0);

        // actual maxRedeem returned value
        uint256 actualValue0 = collateralToken0.maxWithdraw(Bob);
        uint256 actualValue1 = collateralToken1.maxWithdraw(Bob);

        // if there are option positions this should return 0
        if (panopticPool.numberOfPositions(Bob) != 0) {
            assertEq(0, actualValue0, "with open positions 0");
            assertEq(0, actualValue1, "with open positions 1");
            // if available is greater than the user balance
            // return the user balance
        } else if (availableAssets0 > balance0) {
            assertEq(balance0, actualValue0, "user balance 0");
            assertEq(balance1, actualValue1, "user balance 1");
        } else {
            uint256 available0 = collateralToken0._availableAssets();
            uint256 available1 = collateralToken1._availableAssets();

            assertEq(available0, actualValue0, "available assets 0");
            assertEq(available1, actualValue1, "available assets 1");
        }
    }

    // previewMint
    function test_Success_previewMint(uint256 x, uint104 shares) public {
        _initWorld(x);
        // use a fixed amount for single test
        _testconvertToAssetsNonZero(shares);

        uint256 expectedValue = convertToAssets(shares, collateralToken0);

        // real value
        uint256 actualValue = collateralToken0.previewMint(shares);

        assertApproxEqAbs(((expectedValue * 10_000) / 9_990), actualValue, 5);
    }

    // maxMint
    function test_Success_maxMint(uint256 x) public {
        _initWorld(x);

        // use a fixed amount for single test
        uint256 expectedValue = (collateralToken0.convertToShares(type(uint104).max) * 1000) / 1001;

        // real value
        uint256 actualValue = collateralToken0.maxMint(Bob);

        assertEq(expectedValue, actualValue);
    }

    // previewDeposit
    function test_Success_previewDeposit(uint256 x) public {
        _initWorld(x);

        // use a fixed amount for single test
        uint256 expectedValue = _testconvertToSharesNonZero(1000);

        // real value
        uint256 actualValue = collateralToken0.previewDeposit(1000);

        assertEq((expectedValue * 9_990) / 10_000, actualValue);
    }

    // maxDeposit
    function test_Success_maxDeposit(uint256 x) public {
        _initWorld(x);

        uint256 expectedValue = type(uint104).max;

        // real value
        uint256 actualValue = collateralToken0.maxDeposit(Bob);

        assertEq(expectedValue, actualValue);
    }

    // availableAssets
    function test_Success_availableAssets(uint256 x, uint256 balance) public {
        _initWorld(x);

        balance = bound(balance, 0, uint128(type(uint128).max));

        // set total balance of underlying asset in the Panoptic pool
        collateralToken0.setPoolAssets(balance);
        collateralToken1.setPoolAssets(balance);

        // expected values
        uint256 expectedValue = balance;

        // actual values
        uint256 actualValue0 = collateralToken0._availableAssets();
        uint256 actualValue1 = collateralToken1._availableAssets();

        assertEq(expectedValue, actualValue0);
        assertEq(expectedValue, actualValue1);
    }

    // totalAssets
    function test_Success_totalAssets(uint256 x, uint128 balance, uint128 inAMM) public {
        vm.assume(balance > 0 && balance < uint128(type(int128).max));
        inAMM = uint128(bound(inAMM, 0, balance));

        _initWorld(x);

        // set total balance of underlying asset in the Panoptic pool
        collateralToken0.setPoolAssets(balance);
        collateralToken1.setPoolAssets(balance);

        // set how many funds are locked
        collateralToken0.setInAMM(int128(inAMM));
        collateralToken1.setInAMM(int128(inAMM));

        // expected values
        uint256 expectedValue = (balance) + inAMM;

        // actual values
        uint256 actualValue0 = collateralToken0.totalAssets();
        uint256 actualValue1 = collateralToken1.totalAssets();

        assertEq(expectedValue, actualValue0);
        assertEq(expectedValue, actualValue1);
    }

    /*//////////////////////////////////////////////////////////////
                        INFORMATION TESTS
    //////////////////////////////////////////////////////////////*/
    function test_Success_poolData(uint256 x) public {
        _initWorld(x);

        // expected values

        collateralToken0.setPoolAssets(10 ** 10); // give pool 10 ** 10 tokens
        uint256 expectedBal = 10 ** 10;

        collateralToken0.setInAMM(100);
        uint256 expectedInAMM = 100;

        // bal + inAMM - totalAssets()
        uint256 expectedTotalBalance = expectedBal + expectedInAMM;

        // _inAMM() * DECIMALS) / totalAssets()
        uint256 expectedPoolUtilization = (expectedInAMM * 10_000) / expectedTotalBalance;

        (uint256 poolAssets, uint256 insideAMM, int256 currentPoolUtilization) = collateralToken0
            .getPoolData();

        assertEq(expectedBal, poolAssets);
        assertEq(expectedInAMM, insideAMM);
        assertEq(expectedPoolUtilization, uint256(currentPoolUtilization));
    }

    function test_Success_name(uint256 x) public {
        _initWorld(x);

        // string memory expectedName =
        //     string.concat(
        //             "POPT-V1",
        //             " ",
        //             IERC20Metadata(s_univ3token0).symbol(),
        //             " LP on ",
        //             symbol0,
        //             "/",
        //             symbol1,
        //             " ",
        //             fee % 100 == 0
        //                 ? Strings.toString(fee / 100)
        //                 : string.concat(Strings.toString(fee / 100), ".", Strings.toString(fee % 100)),
        //             "bps"
        //         );

        string memory returnedName = collateralToken0.name();
        console2.log(returnedName);
    }

    function test_Success_symbol(uint256 x) public {
        _initWorld(x);

        // string.concat(TICKER_PREFIX, symbol);
        // "po" + symbol IERC20Metadata(s_underlyingToken).symbol()

        string memory returnedSymbol = collateralToken0.symbol();
        console2.log(returnedSymbol);
    }

    function test_Success_decimals(uint256 x) public {
        _initWorld(x);

        //IERC20Metadata(s_underlyingToken).decimals()

        console2.log(collateralToken0.decimals());
    }

    /*//////////////////////////////////////////////////////////////
                    REPLICATED FUNCTIONS (TEST HELPERS)
    //////////////////////////////////////////////////////////////*/

    function convertToShares(
        uint256 assets,
        CollateralTracker collateralToken
    ) public view returns (uint256 shares) {
        uint256 supply = collateralToken.totalSupply();
        return Math.mulDiv(assets, supply, collateralToken.totalAssets());
    }

    function convertToAssets(
        uint256 shares,
        CollateralTracker collateralToken
    ) public view returns (uint256 assets) {
        uint256 supply = collateralToken.totalSupply();
        return Math.mulDiv(shares, collateralToken.totalAssets(), supply);
    }

    /*//////////////////////////////////////////////////////////////
                    POSITION VALIDITY CHECKER
    //////////////////////////////////////////////////////////////*/

    struct CallbackData {
        PoolAddress.PoolKey univ3poolKey;
        address payer;
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        // Decode the mint callback data
        CallbackData memory decoded = abi.decode(data, (CallbackData));

        // Sends the amount0Owed and amount1Owed quantities provided
        if (amount0Owed > 0)
            TransferHelper.safeTransferFrom(
                decoded.univ3poolKey.token0,
                decoded.payer,
                msg.sender,
                amount0Owed
            );
        if (amount1Owed > 0)
            TransferHelper.safeTransferFrom(
                decoded.univ3poolKey.token1,
                decoded.payer,
                msg.sender,
                amount1Owed
            );
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        // Decode the swap callback data, checks that the UniswapV3Pool has the correct address.
        CallbackData memory decoded = abi.decode(data, (CallbackData));

        // Extract the address of the token to be sent (amount0 -> token0, amount1 -> token1)
        address token = amount0Delta > 0
            ? address(decoded.univ3poolKey.token0)
            : address(decoded.univ3poolKey.token1);

        // Transform the amount to pay to uint256 (take positive one from amount0 and amount1)
        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);

        // Pay the required token from the payer to the caller of this contract
        TransferHelper.safeTransferFrom(token, decoded.payer, msg.sender, amountToPay);
    }

    function _swapITM(int128 itm0, int128 itm1) internal {
        // Initialize variables
        bool zeroForOne; // The direction of the swap, true for token0 to token1, false for token1 to token0
        int256 swapAmount; // The amount of token0 or token1 to swap
        bytes memory data;

        // construct the swap callback struct
        data = abi.encode(
            CallbackData({
                univ3poolKey: PoolAddress.PoolKey({
                    token0: pool.token0(),
                    token1: pool.token1(),
                    fee: pool.fee()
                }),
                payer: address(panopticPool)
            })
        );

        if ((itm0 != 0) && (itm1 != 0)) {
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

            /// @dev we need to compare (deltaX = itm0 - itm1/price) to (deltaY =  itm1 - itm0 * price) to only swap the owed balance
            /// To reduce the number of computation steps, we do the following:
            ///    deltaX = (itm0*sqrtPrice - itm1/sqrtPrice)/sqrtPrice
            ///    deltaY = -(itm0*sqrtPrice - itm1/sqrtPrice)*sqrtPrice
            int256 net0 = itm0 + PanopticMath.convert1to0(itm1, sqrtPriceX96);

            int256 net1 = itm1 + PanopticMath.convert0to1(itm0, sqrtPriceX96);

            // if net1 is negative, then the protocol has a surplus of token0
            zeroForOne = net1 < net0;

            //compute the swap amount, set as positive (exact input)
            swapAmount = zeroForOne ? net0 : net1;
        } else if (itm0 != 0) {
            zeroForOne = itm0 < 0;
            swapAmount = -itm0;
        } else {
            zeroForOne = itm1 > 0;
            swapAmount = -itm1;
        }

        // assert the pool has enough funds to complete the swap for an ITM position (exchange tokens to token type)
        bytes memory callData = abi.encodeCall(
            pool.swap,
            (
                address(panopticPool),
                zeroForOne,
                swapAmount,
                zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                data
            )
        );
        (bool ok, ) = address(pool).call(callData);
        vm.assume(ok);
    }

    // Checks to see that a valid position is minted via simulation
    // asserts that the leg is sufficiently large enough to meet dust threshold requirement
    // also ensures that this is a valid mintable position in uniswap (i.e liquidity amount too much for pool, then fuzz a new positionSize)
    function _assumePositionValidity(
        address caller,
        TokenId _tokenId,
        uint128 positionSize
    ) internal {
        // take a snapshot at this storage state
        uint256 snapshot = vm.snapshot();
        {
            IERC20Partial(token0).approve(address(sfpm), type(uint256).max);
            IERC20Partial(token1).approve(address(sfpm), type(uint256).max);

            // mock mints and burns from the SFPM
            vm.startPrank(address(sfpm));
        }

        int128 itm0;
        int128 itm1;

        uint256 amount0;
        uint256 amount1;

        uint256 maxLoop = _tokenId.countLegs();
        for (uint256 i; i < maxLoop; i++) {
            // basis
            uint256 asset = _tokenId.asset(i);

            // token type we are transacting in
            tokenType = _tokenId.tokenType(i);

            // position bounds
            (legLowerTick, legUpperTick) = _tokenId.asTicks(i);

            // sqrt price of bounds
            sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(legLowerTick);
            sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(legUpperTick);

            if (sqrtRatioAX96 > sqrtRatioBX96)
                (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

            /// get the liquidity
            if (asset == 0) {
                uint256 intermediate = Math.mulDiv96(sqrtRatioAX96, sqrtRatioBX96);
                liquidity = FullMath.mulDiv(
                    positionSize,
                    intermediate,
                    sqrtRatioBX96 - sqrtRatioAX96
                );
            } else {
                liquidity = FullMath.mulDiv(
                    positionSize,
                    FixedPoint96.Q96,
                    sqrtRatioBX96 - sqrtRatioAX96
                );
            }

            // liquidity should be less than 128 bits
            vm.assume(liquidity != 0 && liquidity < type(uint128).max);

            amount0 += LiquidityAmounts.getAmount0ForLiquidity(
                sqrtRatioAX96,
                sqrtRatioBX96,
                uint128(liquidity)
            );

            amount1 += LiquidityAmounts.getAmount1ForLiquidity(
                sqrtRatioAX96,
                sqrtRatioBX96,
                uint128(liquidity)
            );

            vm.assume(amount0 < 2 ** 127 - 1 && amount1 < 2 ** 127 - 1);

            /// assert the notional value is valid
            uint128 contractSize = positionSize * uint128(tokenId.optionRatio(i));

            uint256 notional = asset == 0
                ? PanopticMath.convert0to1(
                    contractSize,
                    TickMath.getSqrtRatioAtTick((legUpperTick + legLowerTick) / 2)
                )
                : PanopticMath.convert1to0(
                    contractSize,
                    TickMath.getSqrtRatioAtTick((legUpperTick + legLowerTick) / 2)
                );
            vm.assume(notional != 0 && notional < type(uint128).max);

            /// simulate mint/burn
            // mint in pool if short
            if (tokenId.isLong(i) == 0) {
                try
                    pool.mint(
                        address(sfpm),
                        legLowerTick,
                        legUpperTick,
                        uint128(liquidity),
                        abi.encode(
                            CallbackData({
                                univ3poolKey: PoolAddress.PoolKey({
                                    token0: pool.token0(),
                                    token1: pool.token1(),
                                    fee: pool.fee()
                                }),
                                payer: address(panopticPool)
                            })
                        )
                    )
                returns (uint256 _amount0, uint256 _amount1) {
                    // assert that it meets the dust threshold requirement
                    vm.assume(
                        (_amount0 > 50 && _amount0 < uint128(type(int128).max)) ||
                            (_amount1 > 50 && _amount1 < uint128(type(int128).max))
                    );

                    if (tokenType == 1) {
                        itm0 += int128(uint128(_amount0));
                    } else {
                        itm1 += int128(uint128(_amount1));
                    }
                } catch {
                    vm.assume(false); // invalid position, discard
                }
            } else {
                pool.burn(legLowerTick, legUpperTick, uint128(liquidity));
            }
        }

        if (itm0 != 0 || itm1 != 0)
            // assert the pool has enough funds to complete the swap if ITM
            _swapITM(itm0, itm1);

        // rollback to the previous storage state
        vm.revertTo(snapshot);

        // revert back to original caller
        vm.startPrank(caller);
    }

    function _verifyBonusAmounts(
        LeftRightUnsigned tokenData,
        LeftRightUnsigned otherTokenData,
        uint160 sqrtPriceX96
    ) internal pure returns (LeftRightSigned bonusAmounts) {
        uint256 token1TotalValue;
        uint256 tokenValue;
        token1TotalValue = (tokenData.rightSlot() * Constants.FP96) / sqrtPriceX96;
        tokenValue = token1TotalValue + Math.mulDiv96(otherTokenData.rightSlot(), sqrtPriceX96);

        uint256 requiredValue;
        requiredValue =
            (tokenData.leftSlot() * Constants.FP96) /
            sqrtPriceX96 +
            Math.mulDiv96(otherTokenData.leftSlot(), sqrtPriceX96);

        uint256 valueRatio1;
        valueRatio1 = (tokenData.rightSlot() * Constants.FP96 * 10_000) / tokenValue / sqrtPriceX96;

        int128 bonus0;
        int128 bonus1;
        bonus0 = int128(
            int256(
                otherTokenData.leftSlot() < otherTokenData.rightSlot()
                    ? ((tokenValue) * (10_000 - valueRatio1) * Constants.FP96) / sqrtPriceX96
                    : ((requiredValue - tokenValue) * (10_000 - valueRatio1) * Constants.FP96) /
                        sqrtPriceX96
            )
        );

        bonus1 = int128(
            int256(
                tokenData.leftSlot() < tokenData.rightSlot()
                    ? Math.mulDiv96((tokenValue) * (valueRatio1), sqrtPriceX96)
                    : Math.mulDiv96((requiredValue - tokenValue) * (valueRatio1), sqrtPriceX96)
            )
        );

        // store bonus amounts as actual amounts by dividing by DECIMALS_128
        bonusAmounts = bonusAmounts.toRightSlot(bonus0 / 10_000).toLeftSlot(bonus1 / 10_000);
    }

    /*//////////////////////////////////////////////////////////////
                    COLLATERAL CHECKER
    //////////////////////////////////////////////////////////////*/
    function _tokensRequired(
        TokenId _tokenId,
        uint128 positionSize,
        int24 atTick,
        uint128 poolUtilization,
        uint256[2] memory checkSingle // flag to check single tokenId index
    ) internal returns (uint128 tokensRequired) {
        uint i;
        uint maxLoop;
        if (checkSingle[0] == 1) {
            i = checkSingle[1];
            maxLoop = checkSingle[1] + 1;
        } else {
            i = 0;
            maxLoop = _tokenId.countLegs();
        }

        for (; i < maxLoop; ++i) {
            uint256 _tokenType = _tokenId.tokenType(i);
            uint256 _isLong = _tokenId.isLong(i);
            int24 _strike = _tokenId.strike(i);
            int24 _width = _tokenId.width(i);

            (int24 rangeDown, int24 rangeUp) = PanopticMath.getRangesFromStrike(
                _width,
                tickSpacing
            );
            (legLowerTick, legUpperTick) = (_strike - rangeDown, _strike + rangeUp);

            {
                LeftRightUnsigned _amountsMoved = PanopticMath.getAmountsMoved(
                    _tokenId,
                    positionSize,
                    i
                );

                notionalMoved = _tokenType == 0
                    ? _amountsMoved.rightSlot()
                    : _amountsMoved.leftSlot();

                utilization = _tokenType == 0
                    ? int64(uint64(poolUtilization))
                    : int64(uint64(poolUtilization >> 64));

                sellCollateralRatio = uint256(
                    int256(collateralToken0.sellCollateralRatio(utilization))
                );
                buyCollateralRatio = uint256(
                    int256(collateralToken0.buyCollateralRatio(utilization))
                );
            }

            if (_isLong == 0) {
                // pos is short
                // base
                tokensRequired = uint128(
                    FullMath.mulDivRoundingUp(notionalMoved, sellCollateralRatio, 10_000)
                );
                // OTM
                if (
                    ((atTick >= (legUpperTick)) && (_tokenType == 1)) ||
                    ((atTick < (legLowerTick)) && (_tokenType == 0))
                ) {} else {
                    uint160 ratio;
                    ratio = _tokenType == 1
                        ? TickMath.getSqrtRatioAtTick(
                            Math.max24(2 * (atTick - _strike), TickMath.MIN_TICK)
                        )
                        : TickMath.getSqrtRatioAtTick(
                            Math.max24(2 * (_strike - atTick), TickMath.MIN_TICK)
                        );

                    // ITM
                    if (
                        ((atTick < (legLowerTick)) && (_tokenType == 1)) ||
                        ((atTick >= (legUpperTick)) && (_tokenType == 0))
                    ) {
                        uint256 c2 = FixedPoint96.Q96 - ratio;

                        tokensRequired += uint128(Math.mulDiv96RoundingUp(notionalMoved, c2));
                    } else {
                        // ATM
                        uint160 scaleFactor = TickMath.getSqrtRatioAtTick(
                            (legUpperTick - _strike) + (_strike - legLowerTick)
                        );

                        uint256 c3 = FullMath.mulDivRoundingUp(
                            notionalMoved,
                            scaleFactor - ratio,
                            scaleFactor + FixedPoint96.Q96
                        );
                        tokensRequired += uint128(c3);
                    }
                }
            } else {
                // pos is long
                // base
                tokensRequired += uint128(
                    FullMath.mulDivRoundingUp(notionalMoved, buyCollateralRatio, 10_000)
                );
            }
        }
    }

    function _spreadTokensRequired(
        TokenId _tokenId,
        uint128 positionSize,
        uint128 poolUtilizations
    ) internal returns (uint128 tokensRequired) {
        uint maxLoop = tokenId.countLegs();

        uint256 _tempTokensRequired;

        for (uint i; i < maxLoop; ++i) {
            partnerIndex = _tokenId.riskPartner(i);
            tokenType = _tokenId.tokenType(i);
            tokenTypeP = _tokenId.tokenType(partnerIndex);
            isLong = _tokenId.isLong(i);
            isLongP = _tokenId.isLong(partnerIndex);

            baseStrike = _tokenId.strike(partnerIndex);
            partnerStrike = _tokenId.strike(i);

            if ((isLong == isLongP) || (tokenType != tokenTypeP)) continue;

            {
                if (isLong == 1) {
                    // spread requirement
                    {
                        amountsMoved = PanopticMath.getAmountsMoved(_tokenId, positionSize, i);

                        amountsMovedPartner = PanopticMath.getAmountsMoved(
                            _tokenId,
                            positionSize,
                            partnerIndex
                        );

                        // amount moved is right slot if tokenType=0, left slot otherwise
                        movedRight = amountsMoved.rightSlot();
                        movedLeft = amountsMoved.leftSlot();

                        // amounts moved for partner
                        movedPartnerRight = amountsMovedPartner.rightSlot();
                        movedPartnerLeft = amountsMovedPartner.leftSlot();

                        uint256 asset = tokenId.asset(i);

                        if (asset != tokenType) {
                            if (tokenType == 0) {
                                _tempTokensRequired = (
                                    movedRight < movedPartnerRight
                                        ? movedPartnerRight - movedRight
                                        : movedRight - movedPartnerRight
                                );
                            } else {
                                _tempTokensRequired = (
                                    movedLeft < movedPartnerLeft
                                        ? movedPartnerLeft - movedLeft
                                        : movedLeft - movedPartnerLeft
                                );
                            }
                        } else {
                            if (tokenType == 1) {
                                _tempTokensRequired = (
                                    movedRight < movedPartnerRight
                                        ? Math.mulDivRoundingUp(
                                            movedPartnerRight - movedRight,
                                            movedLeft,
                                            movedRight
                                        )
                                        : Math.mulDivRoundingUp(
                                            movedRight - movedPartnerRight,
                                            movedLeft,
                                            movedPartnerRight
                                        )
                                );
                            } else {
                                _tempTokensRequired = (
                                    movedLeft < movedPartnerLeft
                                        ? Math.mulDivRoundingUp(
                                            movedPartnerLeft - movedLeft,
                                            movedRight,
                                            movedLeft
                                        )
                                        : Math.mulDivRoundingUp(
                                            movedLeft - movedPartnerLeft,
                                            movedRight,
                                            movedPartnerLeft
                                        )
                                );
                            }
                        }
                    }
                    console2.log("spread req", _tempTokensRequired);
                    console2.log("tokenType", tokenType);
                    console2.log("poolUtilizations", poolUtilizations);
                    _tempTokensRequired = Math.max(
                        uint128(
                            collateralToken0.getRequiredCollateralAtUtilization(
                                uint128(tokenType == 0 ? movedRight : movedLeft),
                                1,
                                tokenType == 0
                                    ? int64(uint64(poolUtilizations))
                                    : int64(uint64(poolUtilizations >> 64))
                            )
                        ),
                        _tempTokensRequired
                    );
                    console2.log(
                        "util req",
                        collateralToken0.getRequiredCollateralAtUtilization(
                            uint128(tokenType == 0 ? movedRight : movedLeft),
                            1,
                            tokenType == 0
                                ? int64(uint64(poolUtilizations))
                                : int64(uint64(poolUtilizations >> 64))
                        )
                    );
                    console2.log(
                        "util req moved",
                        uint128(tokenType == 0 ? movedRight : movedLeft)
                    );
                    console2.log(
                        "util req poolutil",
                        tokenType == 0
                            ? int64(uint64(poolUtilizations))
                            : int64(uint64(poolUtilizations >> 64))
                    );

                    vm.assume(_tempTokensRequired < type(uint128).max);
                    tokensRequired = _tempTokensRequired.toUint128();
                }
            }

            return tokensRequired;
        }
    }

    function _strangleTokensRequired(
        TokenId _tokenId,
        uint128 positionSize,
        uint128 poolUtilization,
        int24 atTick,
        int128 premium0,
        int128 premium1
    ) internal returns (uint128 tokensRequired0, uint128 tokensRequired1) {
        uint maxLoop = tokenId.countLegs();

        uint128 tokensRequired;

        for (uint i; i < maxLoop; ++i) {
            partnerIndex = _tokenId.riskPartner(i);
            tokenType = _tokenId.tokenType(i);
            tokenTypeP = _tokenId.tokenType(partnerIndex);
            isLong = _tokenId.isLong(i);
            isLongP = _tokenId.isLong(partnerIndex);

            if ((isLong != isLongP) || (tokenType == tokenTypeP)) continue;

            amountsMoved = PanopticMath.getAmountsMoved(_tokenId, positionSize, i);

            strike = _tokenId.strike(i);
            width = _tokenId.width(i);

            (, rangeUp0) = PanopticMath.getRangesFromStrike(width, tickSpacing);

            (legLowerTick, legUpperTick) = _tokenId.asTicks(i);
            notionalMoved = tokenType == 0 ? amountsMoved.rightSlot() : amountsMoved.leftSlot();

            {
                utilization = tokenType == 0
                    ? int64(uint64(poolUtilization))
                    : int64(uint64(poolUtilization >> 64));

                int128 baseCollateralRatio;
                int128 targetPoolUtilization = 5_000;
                int128 saturatedPoolUtilization = 9_000;

                buyCollateralRatio = 1_000;
                sellCollateralRatio = 2_000;

                // if selling
                sellCollateralRatio = utilization != 0
                    ? sellCollateralRatio / 2
                    : sellCollateralRatio; // 2x efficiency (doesn't compound at 0)

                if (utilization < targetPoolUtilization) {
                    baseCollateralRatio = int128(int256(sellCollateralRatio));
                } else if (utilization > saturatedPoolUtilization) {
                    baseCollateralRatio = 10_000;
                } else {
                    baseCollateralRatio =
                        int128(int256(sellCollateralRatio)) +
                        int128(
                            int256(
                                (uint256(int256(10_000 - int128(int256(sellCollateralRatio)))) *
                                    uint256(int256(utilization - targetPoolUtilization))) /
                                    uint256(
                                        int256(saturatedPoolUtilization - targetPoolUtilization)
                                    )
                            )
                        );
                }

                tokensRequired = uint128(
                    FullMath.mulDivRoundingUp(notionalMoved, uint128(baseCollateralRatio), 10_000)
                );

                // OTM
                if (
                    ((atTick >= (legUpperTick)) && (tokenType == 1)) ||
                    ((atTick < (legLowerTick)) && (tokenType == 0))
                ) {
                    tokensRequired = tokensRequired; // base
                } else {
                    uint160 ratio;
                    ratio = tokenType == 1
                        ? TickMath.getSqrtRatioAtTick(
                            Math.max24(2 * (atTick - strike), TickMath.MIN_TICK)
                        )
                        : TickMath.getSqrtRatioAtTick(
                            Math.max24(2 * (strike - atTick), TickMath.MIN_TICK)
                        );

                    // ITM
                    if (
                        ((atTick < (legLowerTick)) && (tokenType == 1)) ||
                        ((atTick >= (legUpperTick)) && (tokenType == 0))
                    ) {
                        uint256 c2 = FixedPoint96.Q96 - ratio;
                        tokensRequired += uint128(Math.mulDiv96RoundingUp(notionalMoved, c2));
                    } else {
                        // ATM
                        uint160 scaleFactor = TickMath.getSqrtRatioAtTick(
                            (legUpperTick - strike) + (strike - legLowerTick)
                        );

                        uint256 c3 = FullMath.mulDivRoundingUp(
                            notionalMoved,
                            scaleFactor - ratio,
                            scaleFactor + FixedPoint96.Q96
                        );
                        tokensRequired += uint128(c3);
                    }
                }
            }

            if (tokenType == 0) {
                tokensRequired0 = premium0 < 0
                    ? tokensRequired += uint128((uint128(10_000) * uint128(-premium0)) / 10_000)
                    : tokensRequired;
                tokensRequired = 0;
            } else {
                tokensRequired1 = premium1 < 0
                    ? tokensRequired += uint128((uint128(10_000) * uint128(-premium1)) / 10_000)
                    : tokensRequired;
                tokensRequired = 0; // reset temp
            }
        }
    }
}
