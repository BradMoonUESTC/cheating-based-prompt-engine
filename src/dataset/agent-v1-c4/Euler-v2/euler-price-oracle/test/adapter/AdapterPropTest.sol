// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";

contract AdapterPropTest is Test {
    address adapter;
    address base;
    address quote;

    struct Prop_Bidirectional {
        uint256 _dummy;
    }

    /// @dev Adapter supports (A/B) and (B/A).
    function checkProp(Prop_Bidirectional memory p) internal view {
        (bool successBQ,) = _tryGetQuote(1, base, quote);
        (bool successQB,) = _tryGetQuote(1, quote, base);
        assertTrue(successBQ);
        assertTrue(successQB);
        p._dummy;
    }

    struct Prop_NoOtherPaths {
        uint256 inAmount;
        address tokenA;
        address tokenB;
    }

    /// @dev Adapter supports no extra pairs.
    function checkProp(Prop_NoOtherPaths memory p) internal view {
        vm.assume(!((p.tokenA == base && p.tokenB == quote) || (p.tokenA == quote && p.tokenB == base)));
        (bool success,) = _tryGetQuote(1, p.tokenA, p.tokenB);
        assertFalse(success);
    }

    struct Prop_IdempotentQuoteAndQuotes {
        uint256 inAmount;
    }

    /// @dev getQuotes(in,b,q) returns (getQuote(in,b,q), getQuote(in,b,q))
    /// Their domains and codomains are exactly the same.
    function checkProp(Prop_IdempotentQuoteAndQuotes memory p) internal view {
        (bool successBQ, uint256 outAmount) = _tryGetQuote(p.inAmount, base, quote);
        (bool successBQs, uint256 bidOutAmount, uint256 askOutAmount) = _tryGetQuotes(p.inAmount, base, quote);
        assertEq(successBQs, successBQ);
        assertEq(bidOutAmount, outAmount);
        assertEq(askOutAmount, outAmount);

        (bool successQB, uint256 outAmountQB) = _tryGetQuote(p.inAmount, quote, base);
        (bool successQBs, uint256 bidOutAmountQBs, uint256 askOutAmountQBs) = _tryGetQuotes(p.inAmount, quote, base);
        assertEq(successQB, successQBs);
        assertEq(bidOutAmountQBs, outAmountQB);
        assertEq(askOutAmountQBs, outAmountQB);
    }

    struct Prop_SupportsZero {
        uint256 _dummy;
    }

    /// @dev Adapter supports inAmount = 0 and returns 0.
    function checkProp(Prop_SupportsZero memory p) internal view {
        bool success;
        uint256 outAmount;
        uint256 bidOutAmount;
        uint256 askOutAmount;

        (success, outAmount) = _tryGetQuote(0, base, quote);
        assertTrue(success);
        assertEq(outAmount, 0);

        (success, outAmount) = _tryGetQuote(0, quote, base);
        assertTrue(success);
        assertEq(outAmount, 0);

        (success, bidOutAmount, askOutAmount) = _tryGetQuotes(0, base, quote);
        assertTrue(success);
        assertEq(bidOutAmount, 0);
        assertEq(askOutAmount, 0);

        (success, bidOutAmount, askOutAmount) = _tryGetQuotes(0, quote, base);
        assertTrue(success);
        assertEq(bidOutAmount, 0);
        assertEq(askOutAmount, 0);

        p._dummy;
    }

    struct Prop_ContinuousDomain {
        uint256 in0;
        uint256 in1;
        uint256 in2;
    }

    /// @dev The range of accepted inAmount is continuous.
    /// This property sets up values for inAmount in0 < in1 < in2.
    /// If in0 and in2 are supported then in1 must be supported as well.
    function checkProp(Prop_ContinuousDomain memory p) internal view {
        // in0 < in1 < in2
        p.in0 = bound(p.in0, 0, type(uint256).max - 2);
        p.in1 = bound(p.in1, p.in0 + 1, type(uint256).max - 1);
        p.in2 = bound(p.in2, p.in1 + 1, type(uint256).max);

        (bool success0,) = _tryGetQuote(p.in0, base, quote);
        (bool success1,) = _tryGetQuote(p.in1, base, quote);
        (bool success2,) = _tryGetQuote(p.in2, base, quote);

        if (success0 == success2) assertEq(success1, success2);
    }

    struct Prop_OutAmountIncreasing {
        uint256 in0;
        uint256 in1;
    }

    /// @dev outAmount is weakly increasing with respect to inAmount.
    function checkProp(Prop_OutAmountIncreasing memory p) internal view {
        // in0 < in1
        p.in0 = bound(p.in0, 0, type(uint256).max - 2);
        p.in1 = bound(p.in1, p.in0, type(uint256).max - 1);

        (bool success0, uint256 outAmount0) = _tryGetQuote(p.in0, base, quote);
        (bool success1, uint256 outAmount1) = _tryGetQuote(p.in1, base, quote);
        if (success0 && success1) assertLe(outAmount0, outAmount1);

        (success0, outAmount0) = _tryGetQuote(p.in0, quote, base);
        (success1, outAmount1) = _tryGetQuote(p.in1, quote, base);
        if (success0 && success1) assertLe(outAmount0, outAmount1);
    }

    function _tryGetQuote(uint256 inAmount, address _base, address _quote) internal view returns (bool, uint256) {
        bytes memory data = abi.encodeCall(IPriceOracle.getQuote, (inAmount, _base, _quote));
        (bool success, bytes memory returnData) = adapter.staticcall(data);
        uint256 outAmount = success ? abi.decode(returnData, (uint256)) : 0;
        return (success, outAmount);
    }

    function _tryGetQuotes(uint256 inAmount, address _base, address _quote)
        internal
        view
        returns (bool, uint256, uint256)
    {
        bytes memory data = abi.encodeCall(IPriceOracle.getQuotes, (inAmount, _base, _quote));
        (bool success, bytes memory returnData) = adapter.staticcall(data);
        (uint256 bidOutAmount, uint256 askOutAmount) = success ? abi.decode(returnData, (uint256, uint256)) : (0, 0);
        return (success, bidOutAmount, askOutAmount);
    }
}
