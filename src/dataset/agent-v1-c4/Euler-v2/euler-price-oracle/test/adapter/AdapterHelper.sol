// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";
import {Errors} from "src/lib/Errors.sol";

contract AdapterHelper is Test {
    address internal oracle;

    enum Behavior {
        FeedReverts,
        FeedReturnsNegativePrice,
        FeedReturnsZeroPrice,
        FeedReturnsTooLargePrice,
        FeedReturnsStalePrice,
        FeedReturnsTooAheadPrice,
        FeedReturnsStaleRate,
        FeedReturnsConfTooWide,
        FeedReturnsExpoTooLow,
        FeedReturnsExpoTooHigh,
        Constructor_NoPool,
        Constructor_TwapWindowTooShort,
        Constructor_TwapWindowTooLong,
        Constructor_MaxConfWidthTooLow,
        Constructor_MaxConfWidthTooHigh,
        Constructor_MaxStalenessTooLow,
        Constructor_MaxStalenessTooHigh,
        Quote_InAmountTooLarge,
        Quote_ObserveReverts,
        CachedPriceStale
    }

    mapping(Behavior => bool) internal behaviors;

    function setBehavior(Behavior behavior, bool _status) internal {
        behaviors[behavior] = _status;
    }

    function expectRevertForAllQuotePermutations(uint256 inAmount, address base, address quote, bytes memory revertData)
        internal
    {
        vm.expectRevert(revertData);
        IPriceOracle(oracle).getQuote(inAmount, base, quote);

        vm.expectRevert(revertData);
        IPriceOracle(oracle).getQuote(inAmount, quote, base);

        vm.expectRevert(revertData);
        IPriceOracle(oracle).getQuotes(inAmount, base, quote);

        vm.expectRevert(revertData);
        IPriceOracle(oracle).getQuotes(inAmount, quote, base);
    }

    function expectNotSupported(uint256 inAmount, address tokenA, address tokenB) internal {
        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracle_NotSupported.selector, tokenA, tokenB));
        IPriceOracle(oracle).getQuote(inAmount, tokenA, tokenB);

        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracle_NotSupported.selector, tokenA, tokenB));
        IPriceOracle(oracle).getQuotes(inAmount, tokenA, tokenB);
    }
}
