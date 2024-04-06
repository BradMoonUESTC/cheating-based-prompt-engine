// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {CallbackLib} from "@libraries/CallbackLib.sol";
import {CallbackLibHarness} from "./harnesses/CallbackLibHarness.sol";
import {Errors} from "@libraries/Errors.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";

/**
 * Test the CallbackLib functionality with Foundry and Fuzzing.
 *
 * @author Axicon Labs Limited
 */
contract CallbackLibTest is Test {
    IUniswapV3Factory constant factory =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    uint24[] availablePoolFees = [100, 500, 3000, 10000];

    CallbackLibHarness callbackLib = new CallbackLibHarness();

    function test_Success_validateCallback(address tokenA, address tokenB, uint256 fee) public {
        // order tokens correctly
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);

        // ensure pool can be created
        vm.assume(tokenA != tokenB);
        vm.assume(tokenA > address(0));

        // pick a valid pool fee from those available on the factory
        fee = availablePoolFees[bound(fee, 0, 3)];

        // make sure such a pool does not somehow already exist, if it does skip creation
        // create the Uniswap pool (tokens are random do not actually need to exist for the purposes of this test)
        address pool = factory.getPool(tokenA, tokenB, uint24(fee));
        pool = pool == address(0) ? factory.createPool(tokenA, tokenB, uint24(fee)) : pool;

        // now, check if the computed address of the pool from the claimed features is correct
        callbackLib.validateCallback(
            pool,
            factory,
            CallbackLib.PoolFeatures({token0: tokenA, token1: tokenB, fee: uint24(fee)})
        );
    }

    function test_Fail_validateCallback(
        address pool,
        address tokenA,
        address tokenB,
        uint24 fee
    ) public {
        // order tokens correctly
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);

        // ensure pool can be created
        vm.assume(tokenA != tokenB);
        vm.assume(tokenA > address(0));

        // ensure pool does not match with parameters
        vm.assume(pool != factory.getPool(tokenA, tokenB, fee));

        vm.expectRevert(Errors.InvalidUniswapCallback.selector);
        callbackLib.validateCallback(
            pool,
            factory,
            CallbackLib.PoolFeatures({token0: tokenA, token1: tokenB, fee: uint24(fee)})
        );
    }

    function test_Fail_validateCallback_Targeted(
        address wrongPool,
        address tokenA,
        address tokenB,
        uint24 fee
    ) public {
        // order tokens correctly
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);

        // ensure pool can be created
        vm.assume(tokenA != tokenB);
        vm.assume(tokenA > address(0));

        // pick a valid pool fee from those available on the factory
        fee = availablePoolFees[bound(fee, 0, 3)];

        // make sure such a pool does not somehow already exist, if it does skip creation
        // create the Uniswap pool (tokens are random do not actually need to exist for the purposes of this test)
        address pool = factory.getPool(tokenA, tokenB, fee);
        pool = pool == address(0) ? factory.createPool(tokenA, tokenB, fee) : pool;

        // ensure we are validating an incorrect pool address
        vm.assume(wrongPool != pool);

        vm.expectRevert(Errors.InvalidUniswapCallback.selector);
        callbackLib.validateCallback(
            wrongPool,
            factory,
            CallbackLib.PoolFeatures({token0: tokenA, token1: tokenB, fee: fee})
        );
    }
}
