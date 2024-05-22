// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {IUniswapV3PoolDerivedState} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {AdapterHelper} from "test/adapter/AdapterHelper.sol";
import {boundAddr, distinct} from "test/utils/TestUtils.sol";
import {UniswapV3Oracle} from "src/adapter/uniswap/UniswapV3Oracle.sol";

contract UniswapV3OracleHelper is AdapterHelper {
    struct FuzzableState {
        // Config
        address tokenA;
        address tokenB;
        uint24 fee;
        uint32 twapWindow;
        address uniswapV3Factory;
        address pool;
        // Pool Oracle
        int56 tickCumulative0; // larger value
        int56 tickCumulative1;
        // Environment
        uint256 inAmount;
    }

    function setUpState(FuzzableState memory s) internal {
        s.tokenA = boundAddr(s.tokenA);
        s.tokenB = boundAddr(s.tokenB);
        s.uniswapV3Factory = boundAddr(s.uniswapV3Factory);

        if (behaviors[Behavior.Constructor_NoPool]) {
            s.pool = address(0);
        } else {
            s.pool = boundAddr(s.pool);
        }
        vm.assume(distinct(s.tokenA, s.tokenB, s.uniswapV3Factory, s.pool));

        vm.mockCall(
            s.uniswapV3Factory,
            abi.encodeWithSelector(IUniswapV3Factory.getPool.selector, s.tokenA, s.tokenB, s.fee),
            abi.encode(s.pool)
        );

        if (behaviors[Behavior.Constructor_TwapWindowTooShort]) {
            s.twapWindow = uint32(bound(s.twapWindow, 1, 5 minutes - 1));
        } else if (behaviors[Behavior.Constructor_TwapWindowTooLong]) {
            s.twapWindow = uint32(bound(s.twapWindow, uint32(type(int32).max) + 1, type(uint32).max));
        } else {
            s.twapWindow = uint32(bound(s.twapWindow, 5 minutes + 1, 9 days));
        }

        oracle = address(new UniswapV3Oracle(s.tokenA, s.tokenB, s.fee, s.twapWindow, s.uniswapV3Factory));

        s.tickCumulative0 = int56(bound(s.tickCumulative0, type(int56).min, type(int56).max));
        s.tickCumulative1 = int56(bound(s.tickCumulative1, s.tickCumulative0, type(int56).max));
        unchecked {
            int256 diff = int256(s.tickCumulative1) - int256(s.tickCumulative0);
            vm.assume(diff >= type(int56).min && diff <= type(int56).max);
        }
        int24 tick = int24((s.tickCumulative1 - s.tickCumulative0) / int32(s.twapWindow));
        vm.assume(tick > -887272 && tick < 887272);

        if (behaviors[Behavior.Quote_ObserveReverts]) {
            vm.mockCallRevert(s.pool, abi.encodeWithSelector(IUniswapV3PoolDerivedState.observe.selector), "oops");
        } else {
            int56[] memory tickCumulatives = new int56[](2);
            tickCumulatives[0] = s.tickCumulative0;
            tickCumulatives[1] = s.tickCumulative1;
            uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);
            vm.mockCall(
                s.pool,
                abi.encodeWithSelector(IUniswapV3PoolDerivedState.observe.selector),
                abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
            );
        }

        if (behaviors[Behavior.Quote_InAmountTooLarge]) {
            s.inAmount = bound(s.inAmount, uint256(type(uint128).max) + 1, type(uint256).max);
        } else {
            s.inAmount = bound(s.inAmount, 0, type(uint128).max);
        }
    }
}
