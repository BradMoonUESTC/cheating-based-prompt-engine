// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {SemiFungiblePositionManager} from "@contracts/SemiFungiblePositionManager.sol";
import {PanopticPool} from "@contracts/PanopticPool.sol";
import {CollateralTracker} from "@contracts/CollateralTracker.sol";
import {PanopticFactory} from "@contracts/PanopticFactory.sol";
import {IDonorNFT} from "@tokens/interfaces/IDonorNFT.sol";
import {DonorNFT} from "@periphery/DonorNFT.sol";
import {PanopticHelper} from "@periphery/PanopticHelper.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {ERC20S} from "@scripts/tokens/ERC20S.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {TokenId} from "@types/TokenId.sol";
import {LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";
import {PanopticMath} from "@libraries/PanopticMath.sol";
import {CallbackLib} from "@libraries/CallbackLib.sol";
import {SafeTransferLib} from "@libraries/SafeTransferLib.sol";
import {PositionUtils} from "../testUtils/PositionUtils.sol";
import {Math} from "@libraries/Math.sol";
import {Errors} from "@libraries/Errors.sol";

contract SwapperC {
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        // Decode the swap callback data, checks that the UniswapV3Pool has the correct address.
        CallbackLib.CallbackData memory decoded = abi.decode(data, (CallbackLib.CallbackData));

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

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        // Decode the mint callback data
        CallbackLib.CallbackData memory decoded = abi.decode(data, (CallbackLib.CallbackData));

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

    function mint(IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, uint128 liquidity) public {
        pool.mint(
            address(this),
            tickLower,
            tickUpper,
            liquidity,
            abi.encode(
                CallbackLib.CallbackData({
                    poolFeatures: CallbackLib.PoolFeatures({
                        token0: pool.token0(),
                        token1: pool.token1(),
                        fee: pool.fee()
                    }),
                    payer: msg.sender
                })
            )
        );
    }

    function burn(IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, uint128 liquidity) public {
        pool.burn(tickLower, tickUpper, liquidity);
    }

    function swapTo(IUniswapV3Pool pool, uint160 sqrtPriceX96) public {
        (uint160 sqrtPriceX96Before, , , , , , ) = pool.slot0();

        if (sqrtPriceX96Before == sqrtPriceX96) return;

        pool.swap(
            msg.sender,
            sqrtPriceX96Before > sqrtPriceX96 ? true : false,
            type(int128).max,
            sqrtPriceX96,
            abi.encode(
                CallbackLib.CallbackData({
                    poolFeatures: CallbackLib.PoolFeatures({
                        token0: pool.token0(),
                        token1: pool.token1(),
                        fee: pool.fee()
                    }),
                    payer: msg.sender
                })
            )
        );
    }
}

// mostly just fixed one-off tests/PoC
contract Misctest is Test, PositionUtils {
    // the instance of SFPM we are testing
    SemiFungiblePositionManager sfpm;

    // reference implemenatations used by the factory
    address poolReference;

    address collateralReference;

    // Mainnet factory address - SFPM is dependent on this for several checks and callbacks
    IUniswapV3Factory V3FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    // Mainnet router address - used for swaps to test fees/premia
    ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    PanopticFactory factory;
    PanopticPool pp;
    CollateralTracker ct0;
    CollateralTracker ct1;
    PanopticHelper ph;

    uint256 assetsBefore0;
    uint256 assetsBefore1;

    uint256[] assetsBefore0Arr;
    uint256[] assetsBefore1Arr;

    IUniswapV3Pool uniPool;
    ERC20S token0;
    ERC20S token1;

    address Deployer = address(0x1234);
    address Alice = address(0x123456);
    address Bob = address(0x12345678);
    address Swapper = address(0x123456789);
    address Charlie = address(0x1234567891);
    address Seller = address(0x12345678912);
    address[] Buyers;
    address[] Buyer;
    SwapperC swapperc;

    TokenId[] $setupIdList;
    TokenId[] $posIdList;
    TokenId[][] $posIdLists;
    TokenId[] $tempIdList;

    address[] owners;
    TokenId[] tokenIdsTemp;
    TokenId[][] tokenIds;
    TokenId[][] positionIdLists;
    TokenId[][] collateralIdLists;

    function setUp() public {
        vm.startPrank(Deployer);

        sfpm = new SemiFungiblePositionManager(V3FACTORY);

        ph = new PanopticHelper(sfpm);

        // deploy reference pool and collateral token
        poolReference = address(new PanopticPool(sfpm));
        collateralReference = address(
            new CollateralTracker(10, 2_000, 1_000, -1_024, 5_000, 9_000, 20_000)
        );
        token0 = new ERC20S("token0", "T0", 18);
        token1 = new ERC20S("token1", "T1", 18);
        uniPool = IUniswapV3Pool(V3FACTORY.createPool(address(token0), address(token1), 500));

        swapperc = new SwapperC();
        vm.startPrank(Swapper);
        token0.mint(Swapper, type(uint128).max);
        token1.mint(Swapper, type(uint128).max);
        token0.approve(address(swapperc), type(uint128).max);
        token1.approve(address(swapperc), type(uint128).max);

        // This price causes exactly one unit of liquidity to be minted
        // above here reverts b/c 0 liquidity cannot be minted
        IUniswapV3Pool(uniPool).initialize(2 ** 96);

        IUniswapV3Pool(uniPool).increaseObservationCardinalityNext(100);

        // move back to price=1 while generating 100 observations (min required for pool to function)
        for (uint256 i = 0; i < 100; ++i) {
            vm.warp(block.timestamp + 1);
            vm.roll(block.number + 1);
            swapperc.mint(uniPool, -10, 10, 10 ** 18);
            swapperc.burn(uniPool, -10, 10, 10 ** 18);
        }
        swapperc.mint(uniPool, -887270, 887270, 10 ** 18);

        swapperc.swapTo(uniPool, 10 ** 17 * 2 ** 96);

        swapperc.burn(uniPool, -887270, 887270, 10 ** 18);

        vm.startPrank(Deployer);

        IDonorNFT dNFT = IDonorNFT(address(new DonorNFT()));
        factory = new PanopticFactory(
            address(token1),
            sfpm,
            V3FACTORY,
            dNFT,
            poolReference,
            collateralReference
        );
        factory.initialize(Deployer);

        DonorNFT(address(dNFT)).changeFactory(address(factory));

        token0.mint(Deployer, type(uint104).max);
        token1.mint(Deployer, type(uint104).max);
        token0.approve(address(factory), type(uint104).max);
        token1.approve(address(factory), type(uint104).max);

        pp = PanopticPool(
            address(
                factory.deployNewPool(
                    address(token0),
                    address(token1),
                    500,
                    bytes32(uint256(uint160(Deployer)) << 96)
                )
            )
        );

        vm.startPrank(Swapper);
        swapperc.swapTo(uniPool, 2 ** 96);

        vm.startPrank(Alice);

        token0.mint(Alice, type(uint104).max);
        token1.mint(Alice, type(uint104).max);

        ct0 = pp.collateralToken0();
        ct1 = pp.collateralToken1();

        token0.approve(address(ct0), type(uint104).max);
        token1.approve(address(ct1), type(uint104).max);

        ct0.deposit(type(uint104).max, Alice);
        ct1.deposit(type(uint104).max, Alice);

        vm.startPrank(Bob);

        token0.mint(Bob, type(uint104).max);
        token1.mint(Bob, type(uint104).max);

        token0.approve(address(ct0), type(uint104).max);
        token1.approve(address(ct1), type(uint104).max);

        ct0.deposit(type(uint104).max, Bob);
        ct1.deposit(type(uint104).max, Bob);

        vm.startPrank(Charlie);

        token0.mint(Charlie, type(uint104).max);
        token1.mint(Charlie, type(uint104).max);

        token0.approve(address(ct0), type(uint104).max);
        token1.approve(address(ct1), type(uint104).max);

        ct0.deposit(type(uint104).max, Charlie);
        ct1.deposit(type(uint104).max, Charlie);

        vm.startPrank(Seller);

        token0.mint(Seller, type(uint104).max / 1_000_000);
        token1.mint(Seller, type(uint104).max / 1_000_000);

        token0.approve(address(ct0), type(uint104).max / 1_000_000);
        token1.approve(address(ct1), type(uint104).max / 1_000_000);

        ct0.deposit(type(uint104).max / 1_000_000, Seller);
        ct1.deposit(type(uint104).max / 1_000_000, Seller);

        for (uint256 i = 0; i < 3; i++) {
            Buyers.push(address(uint160(uint256(keccak256(abi.encodePacked(i + 1337))))));

            vm.startPrank(Buyers[i]);

            token0.mint(Buyers[i], type(uint104).max / 1_000_000);
            token1.mint(Buyers[i], type(uint104).max / 1_000_000);

            token0.approve(address(ct0), type(uint104).max / 1_000_000);
            token1.approve(address(ct1), type(uint104).max / 1_000_000);

            ct0.deposit(type(uint104).max / 1_000_000, Buyers[i]);
            ct1.deposit(type(uint104).max / 1_000_000, Buyers[i]);
        }

        // // setup mini-median price array
        // for (uint256 i = 0; i < 8; ++i) {
        //     vm.warp(block.timestamp + 120);
        //     vm.roll(block.number + 1);
        //     pp.pokeMedian();
        // }

        for (uint256 i = 0; i < 20; ++i) {
            $posIdLists.push(new TokenId[](0));
        }
    }

    // these tests are PoCs for rounding issues in the premium distribution
    // to demonstrate the issue log the settled, gross, and owed premia at burn
    function test_settledPremiumDistribution_demoInflatedGross() public {
        swapperc = new SwapperC();
        vm.startPrank(Swapper);
        token0.mint(Swapper, type(uint128).max);
        token1.mint(Swapper, type(uint128).max);
        token0.approve(address(swapperc), type(uint128).max);
        token1.approve(address(swapperc), type(uint128).max);

        // mint OTM position
        $posIdList.push(
            TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(uniPool))).addLeg(
                0,
                1,
                1,
                0,
                0,
                0,
                15,
                1
            )
        );

        $tempIdList = $posIdList;

        vm.startPrank(Bob);

        pp.mintOptions($posIdList, 1_000_000, 0, 0, 0);

        $posIdList.push(
            TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(uniPool))).addLeg(
                0,
                1,
                1,
                1,
                0,
                0,
                15,
                1
            )
        );

        // the collectedAmount will always be a round number, so it's actually not possible to get a greater grossPremium than sum(collected, owed)
        // (owed and gross are both calculated from collectedAmount)
        for (uint256 i = 0; i < 1000; i++) {
            vm.startPrank(Alice);
            $tempIdList[0] = $posIdList[1];
            pp.mintOptions($tempIdList, 250_000, type(uint64).max, 0, 0);

            vm.startPrank(Bob);
            pp.mintOptions($posIdList, 250_000, type(uint64).max, 0, 0);

            vm.startPrank(Swapper);
            swapperc.swapTo(uniPool, Math.getSqrtRatioAtTick(10) + 1);
            // 1998600539
            accruePoolFeesInRange(address(uniPool), (uniPool.liquidity() * 2) / 3, 1, 1);
            swapperc.swapTo(uniPool, 2 ** 96);

            vm.startPrank(Bob);
            $tempIdList[0] = $posIdList[0];
            pp.burnOptions($posIdList[1], $tempIdList, 0, 0);

            vm.startPrank(Alice);
            pp.burnOptions($posIdList[1], new TokenId[](0), 0, 0);
        }

        vm.startPrank(Bob);
        // burn Bob's short option
        pp.burnOptions($posIdList[0], new TokenId[](0), 0, 0);
    }

    function test_settledPremiumDistribution_demoInflatedOwed() public {
        swapperc = new SwapperC();
        vm.startPrank(Swapper);
        token0.mint(Swapper, type(uint128).max);
        token1.mint(Swapper, type(uint128).max);
        token0.approve(address(swapperc), type(uint128).max);
        token1.approve(address(swapperc), type(uint128).max);

        // mint OTM position
        $posIdList.push(
            TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(uniPool))).addLeg(
                0,
                1,
                1,
                0,
                0,
                0,
                15,
                1
            )
        );

        $tempIdList = $posIdList;

        vm.startPrank(Bob);

        pp.mintOptions($posIdList, 1_000_000, 0, 0, 0);

        $posIdList.push(
            TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(uniPool))).addLeg(
                0,
                1,
                1,
                1,
                0,
                0,
                15,
                1
            )
        );

        // only 20 tokens actually settled, but 22 owed... 2 tokens taken from PLPs
        // we may need to redefine availablePremium as max(availablePremium, settledTokens)
        for (uint256 i = 0; i < 10; i++) {
            pp.mintOptions($posIdList, 499_999, type(uint64).max, 0, 0);
            vm.startPrank(Swapper);
            swapperc.swapTo(uniPool, Math.getSqrtRatioAtTick(10) + 1);
            // 1998600539
            accruePoolFeesInRange(address(uniPool), uniPool.liquidity() - 1, 1, 1);
            swapperc.swapTo(uniPool, 2 ** 96);
            vm.startPrank(Bob);
            pp.burnOptions($posIdList[1], $tempIdList, 0, 0);
        }

        // burn Bob's short option
        pp.burnOptions($posIdList[0], new TokenId[](0), 0, 0);
    }

    function test_success_settleLongPremium() public {
        swapperc = new SwapperC();
        vm.startPrank(Swapper);
        token0.mint(Swapper, type(uint128).max);
        token1.mint(Swapper, type(uint128).max);
        token0.approve(address(swapperc), type(uint128).max);
        token1.approve(address(swapperc), type(uint128).max);

        // sell primary chunk
        $posIdLists[0].push(
            TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(uniPool))).addLeg(
                0,
                1,
                1,
                0,
                0,
                0,
                15,
                1
            )
        );

        // mint some amount of liquidity with Alice owning 1/2 and Bob and Charlie owning 1/4 respectively
        // then, remove 9.737% of that liquidity at the same ratio
        // Once this state is in place, accumulate some amount of fees on the existing liquidity in the pool
        // The fees should be immediately available for withdrawal because they have been paid to liquidity already in the pool
        // 8.896% * 1.022x vegoid = +~10% of the fee amount accumulated will be owed by sellers
        vm.startPrank(Alice);

        pp.mintOptions($posIdLists[0], 500_000_000, 0, 0, 0);

        vm.startPrank(Bob);

        pp.mintOptions($posIdLists[0], 250_000_000, 0, 0, 0);

        vm.startPrank(Charlie);

        pp.mintOptions($posIdLists[0], 250_000_000, 0, 0, 0);

        // sell unrelated, non-overlapping, dummy chunk (to buy for match testing)
        vm.startPrank(Seller);

        $posIdLists[1].push(
            TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(uniPool))).addLeg(
                0,
                1,
                1,
                0,
                1,
                0,
                -15,
                1
            )
        );

        pp.mintOptions($posIdLists[1], 1_000_000_000 - 9_884_444 * 3, 0, 0, 0);

        // position type A: 1-leg long primary
        $posIdLists[2].push(
            TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(uniPool))).addLeg(
                0,
                1,
                1,
                1,
                0,
                0,
                15,
                1
            )
        );

        for (uint256 i = 0; i < Buyers.length; ++i) {
            vm.startPrank(Buyers[i]);
            pp.mintOptions($posIdLists[2], 9_884_444, type(uint64).max, 0, 0);
        }

        // position type B: 2-leg long primary and long dummy
        $posIdLists[2].push(
            TokenId
                .wrap(0)
                .addPoolId(PanopticMath.getPoolId(address(uniPool)))
                .addLeg(0, 1, 1, 1, 0, 0, 15, 1)
                .addLeg(1, 1, 1, 1, 1, 1, -15, 1)
        );

        for (uint256 i = 0; i < Buyers.length; ++i) {
            vm.startPrank(Buyers[i]);
            pp.mintOptions($posIdLists[2], 9_884_444, type(uint64).max, 0, 0);
        }

        // position type C: 2-leg long primary and short dummy
        $posIdLists[2].push(
            TokenId
                .wrap(0)
                .addPoolId(PanopticMath.getPoolId(address(uniPool)))
                .addLeg(0, 1, 1, 1, 0, 0, 15, 1)
                .addLeg(1, 1, 1, 0, 1, 1, -15, 1)
        );

        for (uint256 i = 0; i < Buyers.length; ++i) {
            vm.startPrank(Buyers[i]);
            pp.mintOptions($posIdLists[2], 9_884_444, type(uint64).max, 0, 0);
        }

        // position type D: 1-leg long dummy
        $posIdLists[2].push(
            TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(uniPool))).addLeg(
                0,
                1,
                1,
                1,
                1,
                0,
                -15,
                1
            )
        );

        for (uint256 i = 0; i < Buyers.length; ++i) {
            vm.startPrank(Buyers[i]);
            pp.mintOptions($posIdLists[2], 19_768_888, type(uint64).max, 0, 0);
        }

        // populate collateralIdLists with each ending at a different token
        {
            $posIdLists[3] = $posIdLists[2];
            $posIdLists[3][0] = $posIdLists[2][3];
            $posIdLists[3][3] = $posIdLists[2][0];
            collateralIdLists.push($posIdLists[3]);
            $posIdLists[3] = $posIdLists[2];
            $posIdLists[3][1] = $posIdLists[2][3];
            $posIdLists[3][3] = $posIdLists[2][1];
            collateralIdLists.push($posIdLists[3]);
            $posIdLists[3] = $posIdLists[2];
            $posIdLists[3][2] = $posIdLists[2][3];
            $posIdLists[3][3] = $posIdLists[2][2];
            collateralIdLists.push($posIdLists[3]);
            collateralIdLists.push($posIdLists[2]);
        }

        vm.startPrank(Swapper);

        swapperc.swapTo(uniPool, Math.getSqrtRatioAtTick(10) + 1);

        // There are some precision issues with this (1B is not exactly 1B) but close enough to see the effects
        accruePoolFeesInRange(address(uniPool), uniPool.liquidity() - 1, 1_000_000, 1_000_000_000);
        console2.log("liquidity", uniPool.liquidity());

        // accumulate lower order of fees on dummy chunk
        swapperc.swapTo(uniPool, Math.getSqrtRatioAtTick(-10));

        accruePoolFeesInRange(address(uniPool), uniPool.liquidity() - 1, 10_000, 100_000);
        console2.log("liquidity", uniPool.liquidity());

        swapperc.swapTo(uniPool, 2 ** 96);
        {
            (, int24 currentTick, , , , , ) = uniPool.slot0();
            LeftRightUnsigned accountLiquidityPrimary = sfpm.getAccountLiquidity(
                address(uniPool),
                address(pp),
                0,
                10,
                20
            );
            console2.log(
                "accountLiquidityPrimaryShort",
                accountLiquidityPrimary.rightSlot() + accountLiquidityPrimary.leftSlot()
            );
            console2.log("accountLiquidityPrimaryRemoved", accountLiquidityPrimary.leftSlot());

            (uint256 shortPremium0Primary, uint256 shortPremium1Primary) = sfpm.getAccountPremium(
                address(uniPool),
                address(pp),
                0,
                10,
                20,
                currentTick,
                0
            );

            console2.log(
                "shortPremium0Primary",
                (shortPremium0Primary *
                    (accountLiquidityPrimary.rightSlot() + accountLiquidityPrimary.leftSlot())) /
                    2 ** 64
            );
            console2.log(
                "shortPremium1Primary",
                (shortPremium1Primary *
                    (accountLiquidityPrimary.rightSlot() + accountLiquidityPrimary.leftSlot())) /
                    2 ** 64
            );

            (uint256 longPremium0Primary, uint256 longPremium1Primary) = sfpm.getAccountPremium(
                address(uniPool),
                address(pp),
                0,
                10,
                20,
                currentTick,
                1
            );

            console2.log(
                "longPremium0Primary",
                (longPremium0Primary * accountLiquidityPrimary.leftSlot()) / 2 ** 64
            );
            console2.log(
                "longPremium1Primary",
                (longPremium1Primary * accountLiquidityPrimary.leftSlot()) / 2 ** 64
            );
        }

        {
            LeftRightUnsigned accountLiquidityDummy = sfpm.getAccountLiquidity(
                address(uniPool),
                address(pp),
                1,
                -20,
                -10
            );

            console2.log(
                "accountLiquidityDummyShort",
                accountLiquidityDummy.rightSlot() + accountLiquidityDummy.leftSlot()
            );
            console2.log("accountLiquidityDummyRemoved", accountLiquidityDummy.leftSlot());

            (uint256 shortPremium0Dummy, uint256 shortPremium1Dummy) = sfpm.getAccountPremium(
                address(uniPool),
                address(pp),
                1,
                -20,
                -10,
                0,
                0
            );

            console2.log(
                "shortPremium0Dummy",
                (shortPremium0Dummy *
                    (accountLiquidityDummy.rightSlot() + accountLiquidityDummy.leftSlot())) /
                    2 ** 64
            );
            console2.log(
                "shortPremium1Dummy",
                (shortPremium1Dummy *
                    (accountLiquidityDummy.rightSlot() + accountLiquidityDummy.leftSlot())) /
                    2 ** 64
            );

            (uint256 longPremium0Dummy, uint256 longPremium1Dummy) = sfpm.getAccountPremium(
                address(uniPool),
                address(pp),
                1,
                -20,
                -10,
                0,
                1
            );

            console2.log(
                "longPremium0Dummy",
                (longPremium0Dummy * accountLiquidityDummy.leftSlot()) / 2 ** 64
            );
            console2.log(
                "longPremium1Dummy",
                (longPremium1Dummy * accountLiquidityDummy.leftSlot()) / 2 ** 64
            );
        }

        // >>> s1p = 1100030357
        // >>> l1p = 100030357
        // >>> s1c = 1_000_000_000
        // >>> l1p//3
        // 33343452
        // >>> (s1c+l1p/3)*(0.25*s1p)//(s1p)
        // 258335863.0 (Bob)
        // >>> 258335863.0*2
        // 516671726.0 (Alice)

        assetsBefore0 = ct0.convertToAssets(ct0.balanceOf(Buyers[0]));
        assetsBefore1 = ct1.convertToAssets(ct1.balanceOf(Buyers[0]));

        // collect buyer 1's three relevant chunks
        for (uint256 i = 0; i < 3; ++i) {
            pp.settleLongPremium(collateralIdLists[i], Buyers[0], 0);
        }

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Buyers[0])) - assetsBefore0,
            33_342,
            "Incorrect Buyer 1 1st Collect 0"
        );

        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Buyers[0])) - assetsBefore1,
            33_343_452,
            "Incorrect Buyer 1 1st Collect 1"
        );

        vm.startPrank(Bob);

        // burn Bob's position, should get 25% of fees paid (no long fees avail.)
        assetsBefore0 = ct0.convertToAssets(ct0.balanceOf(Bob));
        assetsBefore1 = ct1.convertToAssets(ct1.balanceOf(Bob));

        pp.burnOptions($posIdLists[0][0], new TokenId[](0), 0, 0);

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Bob)) - assetsBefore0,
            258_335,
            "Incorrect Bob Delta 0"
        );
        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Bob)) - assetsBefore1,
            258_335_862,
            "Incorrect Bob Delta 1"
        );

        // sell unrelated, non-overlapping, dummy chunk to replenish removed liquidity
        vm.startPrank(Seller);

        $posIdLists[1].push(
            TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(uniPool))).addLeg(
                0,
                1,
                1,
                0,
                0,
                0,
                15,
                1
            )
        );

        pp.mintOptions($posIdLists[1], 1_000_000_000, 0, 0, 0);

        assetsBefore0Arr.push(ct0.convertToAssets(ct0.balanceOf(Buyers[0])));
        assetsBefore1Arr.push(ct1.convertToAssets(ct1.balanceOf(Buyers[0])));
        assetsBefore0Arr.push(ct0.convertToAssets(ct0.balanceOf(Buyers[1])));
        assetsBefore1Arr.push(ct1.convertToAssets(ct1.balanceOf(Buyers[1])));
        assetsBefore0Arr.push(ct0.convertToAssets(ct0.balanceOf(Buyers[2])));
        assetsBefore1Arr.push(ct1.convertToAssets(ct1.balanceOf(Buyers[2])));

        // now, settle the dummy chunks for all the buyers/positions and see that the settled ratio for primary doesn't change

        for (uint256 i = 0; i < Buyers.length; ++i) {
            pp.settleLongPremium(collateralIdLists[1], Buyers[i], 1);

            pp.settleLongPremium(collateralIdLists[3], Buyers[i], 0);
        }

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Buyers[0])) - assetsBefore0Arr[0],
            333,
            "Incorrect Buyer 1 2nd Collect 0"
        );

        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Buyers[0])) - assetsBefore1Arr[0],
            3_333,
            "Incorrect Buyer 1 2nd Collect 1"
        );

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Buyers[1])) - assetsBefore0Arr[1],
            333,
            "Incorrect Buyer 2 2nd Collect 0"
        );

        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Buyers[1])) - assetsBefore1Arr[1],
            3_333,
            "Incorrect Buyer 2 2nd Collect 1"
        );

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Buyers[2])) - assetsBefore0Arr[2],
            333,
            "Incorrect Buyer 3 2nd Collect 0"
        );

        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Buyers[2])) - assetsBefore1Arr[2],
            3_333,
            "Incorrect Buyer 3 2nd Collect 1"
        );

        vm.startPrank(Alice);

        // burn Alice's position
        assetsBefore0 = ct0.convertToAssets(ct0.balanceOf(Alice));
        assetsBefore1 = ct1.convertToAssets(ct1.balanceOf(Alice));

        pp.burnOptions($posIdLists[0][0], new TokenId[](0), 0, 0);

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Alice)) - assetsBefore0,
            516_671,
            "Incorrect Alice Delta 0"
        );
        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Alice)) - assetsBefore1,
            516_671_726,
            "Incorrect Alice Delta 1"
        );

        // try collecting all the dummy chunks again - see that no additional premium is collected
        assetsBefore0Arr[0] = ct0.convertToAssets(ct0.balanceOf(Buyers[0]));
        assetsBefore1Arr[0] = ct1.convertToAssets(ct1.balanceOf(Buyers[0]));
        assetsBefore0Arr[1] = ct0.convertToAssets(ct0.balanceOf(Buyers[1]));
        assetsBefore1Arr[1] = ct1.convertToAssets(ct1.balanceOf(Buyers[1]));
        assetsBefore0Arr[2] = ct0.convertToAssets(ct0.balanceOf(Buyers[2]));
        assetsBefore1Arr[2] = ct1.convertToAssets(ct1.balanceOf(Buyers[2]));

        for (uint256 i = 0; i < Buyers.length; ++i) {
            pp.settleLongPremium(collateralIdLists[1], Buyers[i], 1);

            pp.settleLongPremium(collateralIdLists[3], Buyers[i], 0);
        }

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Buyers[0])) - assetsBefore0Arr[0],
            0,
            "Incorrect Buyer 1 3rd Collect 0"
        );

        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Buyers[0])) - assetsBefore1Arr[0],
            0,
            "Incorrect Buyer 1 3rd Collect 1"
        );

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Buyers[1])) - assetsBefore0Arr[1],
            0,
            "Incorrect Buyer 2 3rd Collect 0"
        );

        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Buyers[1])) - assetsBefore1Arr[1],
            0,
            "Incorrect Buyer 2 3rd Collect 1"
        );

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Buyers[2])) - assetsBefore0Arr[2],
            0,
            "Incorrect Buyer 3 3rd Collect 0"
        );

        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Buyers[2])) - assetsBefore1Arr[2],
            0,
            "Incorrect Buyer 3 3rd Collect 1"
        );

        // now, collect the rest of the long (primary) legs, premium should be collected from 2nd & 3rd buyers
        assetsBefore0Arr[0] = ct0.convertToAssets(ct0.balanceOf(Buyers[0]));
        assetsBefore1Arr[0] = ct1.convertToAssets(ct1.balanceOf(Buyers[0]));
        assetsBefore0Arr[1] = ct0.convertToAssets(ct0.balanceOf(Buyers[1]));
        assetsBefore1Arr[1] = ct1.convertToAssets(ct1.balanceOf(Buyers[1]));
        assetsBefore0Arr[2] = ct0.convertToAssets(ct0.balanceOf(Buyers[2]));
        assetsBefore1Arr[2] = ct1.convertToAssets(ct1.balanceOf(Buyers[2]));

        for (uint256 i = 0; i < Buyers.length; ++i) {
            pp.settleLongPremium(collateralIdLists[0], Buyers[i], 0);

            pp.settleLongPremium(collateralIdLists[1], Buyers[i], 0);

            pp.settleLongPremium(collateralIdLists[2], Buyers[i], 0);
        }

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Buyers[0])) - assetsBefore0Arr[0],
            0,
            "Incorrect Buyer 1 4th Collect 0"
        );

        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Buyers[0])) - assetsBefore1Arr[0],
            0,
            "Incorrect Buyer 1 4th Collect 1"
        );

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Buyers[1])) - assetsBefore0Arr[1],
            33_342,
            "Incorrect Buyer 2 4th Collect 0"
        );

        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Buyers[1])) - assetsBefore1Arr[1],
            33_343_452,
            "Incorrect Buyer 2 4th Collect 1"
        );

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Buyers[2])) - assetsBefore0Arr[2],
            33_342,
            "Incorrect Buyer 3 4th Collect 0"
        );

        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Buyers[2])) - assetsBefore1Arr[2],
            33_343_452,
            "Incorrect Buyer 3 4th Collect 1"
        );

        vm.startPrank(Charlie);

        // Finally, burn Charlie's position, he should get 27.5% (25% + full 10% long paid (* 25% owned))
        assetsBefore0 = ct0.convertToAssets(ct0.balanceOf(Charlie));
        assetsBefore1 = ct1.convertToAssets(ct1.balanceOf(Charlie));

        pp.burnOptions($posIdLists[0][0], new TokenId[](0), 0, 0);

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Charlie)) - assetsBefore0,
            275_007,
            "Incorrect Charlie Delta 0"
        );
        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Charlie)) - assetsBefore1,
            275_007_589,
            "Incorrect Charlie Delta 1"
        );

        // test long leg validation
        vm.expectRevert(Errors.NotALongLeg.selector);
        pp.settleLongPremium(collateralIdLists[2], Buyers[0], 1);

        // test positionIdList validation
        // snapshot so we don't have to reset changes to collateralIdLists array
        uint256 snap = vm.snapshot();

        collateralIdLists[0].pop();
        vm.expectRevert(Errors.InputListFail.selector);
        pp.settleLongPremium(collateralIdLists[0], Buyers[0], 0);
        vm.revertTo(snap);

        // test collateral checking (basic)
        for (uint256 i = 0; i < 3; ++i) {
            // snapshot so we don't have to reset changes to collateralIdLists array
            snap = vm.snapshot();

            deal(address(ct0), Buyers[i], i ** 15);
            deal(address(ct1), Buyers[i], i ** 15);
            vm.expectRevert(Errors.NotEnoughCollateral.selector);
            pp.settleLongPremium(collateralIdLists[0], Buyers[i], 0);
            vm.revertTo(snap);
        }

        // burn all buyer positions - they should pay 0 premium since it has all been settled already
        for (uint256 i = 0; i < Buyers.length; ++i) {
            assetsBefore0 = ct0.convertToAssets(ct0.balanceOf(Buyers[i]));
            assetsBefore1 = ct1.convertToAssets(ct1.balanceOf(Buyers[i]));
            vm.startPrank(Buyers[i]);
            pp.burnOptions($posIdLists[2], new TokenId[](0), 0, 0);

            // the positive premium is from the dummy short chunk
            // @TODO might have to tweak this if rounding is changed upstream
            assertEq(
                int256(ct0.convertToAssets(ct0.balanceOf(Buyers[i]))) - int256(assetsBefore0),
                i == 0 ? int256(104) : int256(105),
                "Buyer paid premium twice"
            );

            assertEq(
                ct1.convertToAssets(ct1.balanceOf(Buyers[i])) - assetsBefore1,
                1085,
                "Buyer paid premium twice"
            );
        }
    }

    function test_success_settledPremiumDistribution() public {
        swapperc = new SwapperC();
        vm.startPrank(Swapper);
        token0.mint(Swapper, type(uint128).max);
        token1.mint(Swapper, type(uint128).max);
        token0.approve(address(swapperc), type(uint128).max);
        token1.approve(address(swapperc), type(uint128).max);

        // mint OTM position
        $posIdList.push(
            TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(uniPool))).addLeg(
                0,
                1,
                1,
                0,
                0,
                0,
                15,
                1
            )
        );

        // mint some amount of liquidity with Alice owning 1/2 and Bob and Charlie owning 1/4 respectively
        // then, remove 9.737% of that liquidity at the same ratio
        // Once this state is in place, accumulate some amount of fees on the existing liquidity in the pool
        // The fees should be immediately available for withdrawal because they have been paid to liquidity already in the pool
        // 8.896% * 1.022x vegoid = +~10% of the fee amount accumulated will be owed by sellers
        // First close Bob's position; they should receive 25% of the initial amount because no fees were paid on their position
        // Close half (4.4468%) of the removed liquidity
        // Then close Alice's position, they should receive ~53.3% (50%+ 2/3*5%)
        // Close the other half of the removed liquidity (4.4468%)
        // Finally, close Charlie's position, they should receive ~27.5% (25% + 10% * 25%)
        vm.startPrank(Alice);

        pp.mintOptions($posIdList, 500_000, 0, 0, 0);

        vm.startPrank(Bob);

        pp.mintOptions($posIdList, 250_000, 0, 0, 0);

        vm.startPrank(Charlie);

        pp.mintOptions($posIdList, 250_000, 0, 0, 0);

        $posIdList.push(
            TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(uniPool))).addLeg(
                0,
                1,
                1,
                1,
                0,
                0,
                15,
                1
            )
        );

        vm.startPrank(Alice);

        // mint finely tuned amount of long options for Alice so premium paid = 1.1x
        pp.mintOptions($posIdList, 44_468, type(uint64).max, 0, 0);

        vm.startPrank(Bob);

        // mint finely tuned amount of long options for Bob so premium paid = 1.1x
        pp.mintOptions($posIdList, 44_468, type(uint64).max, 0, 0);

        vm.startPrank(Swapper);

        swapperc.swapTo(uniPool, Math.getSqrtRatioAtTick(10) + 1);

        // There are some precision issues with this (1B is not exactly 1B) but close enough to see the effects
        accruePoolFeesInRange(address(uniPool), uniPool.liquidity() - 1, 1_000_000, 1_000_000_000);

        swapperc.swapTo(uniPool, 2 ** 96);

        vm.startPrank(Bob);

        // burn Bob's position, should get 25% of fees paid (no long fees avail.)
        assetsBefore0 = ct0.convertToAssets(ct0.balanceOf(Bob));
        assetsBefore1 = ct1.convertToAssets(ct1.balanceOf(Bob));

        $tempIdList.push($posIdList[1]);

        // burn Bob's short option
        pp.burnOptions($posIdList[0], $tempIdList, 0, 0);

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Bob)) - assetsBefore0,
            250_000,
            "Incorrect Bob Delta 0"
        );
        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Bob)) - assetsBefore1,
            249_999_999,
            "Incorrect Bob Delta 1"
        );

        // re-mint the short option
        $posIdList[1] = $posIdList[0];
        $posIdList[0] = $tempIdList[0];
        pp.mintOptions($posIdList, 1_000_000, 0, 0, 0);

        $tempIdList[0] = $posIdList[1];

        // Burn the long options, adds 1/2 of the removed liq
        // amount of premia paid = 50_000
        pp.burnOptions($posIdList[0], $tempIdList, 0, 0);

        vm.startPrank(Alice);

        // burn Alice's position, should get 53.3̅% of fees paid back (50% + (5% long paid) * (2/3 owned by Alice))
        assetsBefore0 = ct0.convertToAssets(ct0.balanceOf(Alice));
        assetsBefore1 = ct1.convertToAssets(ct1.balanceOf(Alice));

        $tempIdList[0] = $posIdList[0];
        pp.burnOptions($posIdList[1], $tempIdList, 0, 0);

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Alice)) - assetsBefore0,
            533_333,
            "Incorrect Alice Delta 0"
        );
        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Alice)) - assetsBefore1,
            533_333_345,
            "Incorrect Alice Delta 1"
        );

        // Burn other half of the removed liq
        pp.burnOptions($posIdList[0], new TokenId[](0), 0, 0);

        vm.startPrank(Charlie);

        // Finally, burn Charlie's position, he should get 27.5% (25% + full 10% long paid (* 25% owned))
        assetsBefore0 = ct0.convertToAssets(ct0.balanceOf(Charlie));
        assetsBefore1 = ct1.convertToAssets(ct1.balanceOf(Charlie));

        pp.burnOptions($posIdList[1], new TokenId[](0), 0, 0);

        assertEq(
            ct0.convertToAssets(ct0.balanceOf(Charlie)) - assetsBefore0,
            275_000,
            "Incorrect Charlie Delta 0"
        );
        assertEq(
            ct1.convertToAssets(ct1.balanceOf(Charlie)) - assetsBefore1,
            275_000_008,
            "Incorrect Charlie Delta 1"
        );
    }

    function test_success_PremiumRollover() public {
        vm.startPrank(Swapper);
        // JIT a bunch of liquidity so swaps at mint can happen normally
        swapperc.mint(uniPool, -10, 10, 10 ** 18);

        // L = 1
        uniPool.liquidity();

        TokenId tokenId = TokenId
            .wrap(0)
            .addPoolId(PanopticMath.getPoolId(address(uniPool)))
            .addLeg(0, 1, 1, 0, 0, 0, 0, 4094);

        TokenId[] memory posIdList = new TokenId[](1);
        posIdList[0] = tokenId;

        vm.startPrank(Bob);
        // mint 1 liquidity unit of wideish centered position
        pp.mintOptions(posIdList, 3, 0, 0, 0);

        vm.startPrank(Swapper);
        swapperc.burn(uniPool, -10, 10, 10 ** 18);

        // L = 2
        uniPool.liquidity();

        // accumulate the maximum fees per liq SFPM supports
        accruePoolFeesInRange(address(uniPool), 1, 2 ** 64 - 1, 0);

        vm.startPrank(Swapper);
        swapperc.mint(uniPool, -10, 10, 10 ** 18);

        vm.startPrank(Bob);
        // works fine
        pp.burnOptions(tokenId, new TokenId[](0), 0, 0);

        uint256 balanceBefore0 = ct0.convertToAssets(ct0.balanceOf(Alice));
        uint256 balanceBefore1 = ct1.convertToAssets(ct1.balanceOf(Alice));

        vm.startPrank(Alice);

        // lock in almost-overflowed fees per liquidity
        pp.mintOptions(posIdList, 1_000_000_000, 0, 0, 0);

        vm.startPrank(Swapper);
        swapperc.burn(uniPool, -10, 10, 10 ** 18);

        // overflow back to ~1_000_000_000_000 (fees per liq)
        accruePoolFeesInRange(address(uniPool), 412639631, 1_000_000_000_000, 1_000_000_000_000);

        // this should behave like the actual accumulator does and rollover, not revert on overflow
        (uint256 premium0, uint256 premium1) = sfpm.getAccountPremium(
            address(uniPool),
            address(pp),
            0,
            -20470,
            20470,
            0,
            0
        );
        assertEq(premium0, 340282366920938463444927863358058659840);
        assertEq(premium1, 44704247211996718928643);

        vm.startPrank(Swapper);
        swapperc.mint(uniPool, -10, 10, 10 ** 18);
        vm.startPrank(Alice);

        // tough luck... PLPs just stole ~2**64 tokens per liquidity Alice had because of an overflow
        // Alice can be frontrun if her transaction goes to a public mempool (or is otherwise anticipated),
        // so the cost of the attack is just ~2**64 * active liquidity (shown here to be as low as 1 even with initial full-range!)
        // + fee to move price initially (if applicable)
        // The solution is to freeze fee accumulation if one of the token accumulators overflow
        pp.burnOptions(tokenId, new TokenId[](0), 0, 0);

        // make sure Alice earns no fees on token 0 (her delta is slightly negative due to commission fees/precision etc)
        // the accumulator overflowed, so the accumulation was frozen. If she had poked before the accumulator overflowed,
        // she could have still earned some fees, but now the accumulation is frozen forever.
        assertEq(
            int256(ct0.convertToAssets(ct0.balanceOf(Alice))) - int256(balanceBefore0),
            -1244790
        );

        // but she earns all of fees on token 1 since the premium accumulator did not overflow (!)
        assertEq(
            int256(ct1.convertToAssets(ct1.balanceOf(Alice))) - int256(balanceBefore1),
            999_999_999_998
        );
    }
}
