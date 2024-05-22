// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {UniswapV3OracleHelper} from "test/adapter/uniswap/UniswapV3OracleHelper.sol";
import {boundAddr} from "test/utils/TestUtils.sol";
import {UniswapV3Oracle} from "src/adapter/uniswap/UniswapV3Oracle.sol";
import {Errors} from "src/lib/Errors.sol";

contract UniswapV3OracleTest is UniswapV3OracleHelper {
    function test_Constructor_Integrity(FuzzableState memory s) public {
        setUpState(s);
        assertEq(UniswapV3Oracle(oracle).tokenA(), s.tokenA);
        assertEq(UniswapV3Oracle(oracle).tokenB(), s.tokenB);
        assertEq(UniswapV3Oracle(oracle).fee(), s.fee);
        assertEq(UniswapV3Oracle(oracle).twapWindow(), s.twapWindow);
    }

    function test_Constructor_RevertsWhen_Constructor_TwapWindowTooShort(FuzzableState memory s) public {
        setBehavior(Behavior.Constructor_TwapWindowTooShort, true);
        vm.expectRevert();
        setUpState(s);
    }

    function test_Constructor_RevertsWhen_Constructor_TwapWindowTooLong(FuzzableState memory s) public {
        setBehavior(Behavior.Constructor_TwapWindowTooLong, true);
        vm.expectRevert();
        setUpState(s);
    }

    function test_Constructor_RevertsWhen_PoolAddressZero(FuzzableState memory s) public {
        setBehavior(Behavior.Constructor_NoPool, true);
        vm.expectRevert();
        setUpState(s);
    }

    function test_Quote_RevertsWhen_InvalidTokens(FuzzableState memory s, address otherA, address otherB) public {
        setUpState(s);
        otherA = boundAddr(otherA);
        otherB = boundAddr(otherB);
        vm.assume(otherA != s.tokenA && otherA != s.tokenB);
        vm.assume(otherB != s.tokenA && otherB != s.tokenB);
        expectNotSupported(s.inAmount, s.tokenA, s.tokenA);
        expectNotSupported(s.inAmount, s.tokenB, s.tokenB);
        expectNotSupported(s.inAmount, s.tokenA, otherA);
        expectNotSupported(s.inAmount, otherA, s.tokenA);
        expectNotSupported(s.inAmount, s.tokenB, otherA);
        expectNotSupported(s.inAmount, otherA, s.tokenB);
        expectNotSupported(s.inAmount, otherA, otherA);
        expectNotSupported(s.inAmount, otherA, otherB);
    }

    function test_Quote_RevertsWhen_InAmountGtUint128(FuzzableState memory s) public {
        setBehavior(Behavior.Quote_InAmountTooLarge, true);
        setUpState(s);
        bytes memory err = abi.encodeWithSelector(Errors.PriceOracle_Overflow.selector);
        expectRevertForAllQuotePermutations(s.inAmount, s.tokenA, s.tokenB, err);
    }

    function test_Quote_RevertsWhen_Quote_ObserveReverts(FuzzableState memory s) public {
        setBehavior(Behavior.Quote_ObserveReverts, true);
        setUpState(s);
        bytes memory err = abi.encodePacked("oops");
        expectRevertForAllQuotePermutations(s.inAmount, s.tokenA, s.tokenB, err);
    }

    function test_Quote_Integrity(FuzzableState memory s) public {
        setUpState(s);

        int24 tick = int24((s.tickCumulative1 - s.tickCumulative0) / int32(s.twapWindow));
        uint256 expectedOutAmount = OracleLibrary.getQuoteAtTick(tick, uint128(s.inAmount), s.tokenA, s.tokenB);

        uint256 outAmount = UniswapV3Oracle(oracle).getQuote(s.inAmount, s.tokenA, s.tokenB);
        assertEq(outAmount, expectedOutAmount);

        (uint256 bidOutAmount, uint256 askOutAmount) = UniswapV3Oracle(oracle).getQuotes(s.inAmount, s.tokenA, s.tokenB);
        assertEq(bidOutAmount, expectedOutAmount);
        assertEq(askOutAmount, expectedOutAmount);
    }

    function test_Quote_Integrity_Inverse(FuzzableState memory s) public {
        setUpState(s);

        int24 tick = int24((s.tickCumulative1 - s.tickCumulative0) / int32(s.twapWindow));
        uint256 expectedOutAmount = OracleLibrary.getQuoteAtTick(tick, uint128(s.inAmount), s.tokenB, s.tokenA);

        uint256 outAmount = UniswapV3Oracle(oracle).getQuote(s.inAmount, s.tokenB, s.tokenA);
        assertEq(outAmount, expectedOutAmount);

        (uint256 bidOutAmount, uint256 askOutAmount) = UniswapV3Oracle(oracle).getQuotes(s.inAmount, s.tokenB, s.tokenA);
        assertEq(bidOutAmount, expectedOutAmount);
        assertEq(askOutAmount, expectedOutAmount);
    }
}
