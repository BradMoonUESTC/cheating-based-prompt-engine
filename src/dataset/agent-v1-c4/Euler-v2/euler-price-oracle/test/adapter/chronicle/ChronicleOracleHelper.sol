// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {AdapterHelper} from "test/adapter/AdapterHelper.sol";
import {boundAddr, distinct} from "test/utils/TestUtils.sol";
import {IChronicle} from "src/adapter/chronicle/IChronicle.sol";
import {ChronicleOracle} from "src/adapter/chronicle/ChronicleOracle.sol";

contract ChronicleOracleHelper is AdapterHelper {
    uint256 internal constant MAX_STALENESS_LOWER_BOUND = 1 minutes;
    uint256 internal constant MAX_STALENESS_UPPER_BOUND = 72 hours;

    struct Bounds {
        uint8 minBaseDecimals;
        uint8 maxBaseDecimals;
        uint8 minQuoteDecimals;
        uint8 maxQuoteDecimals;
        uint8 minFeedDecimals;
        uint8 maxFeedDecimals;
        uint256 minInAmount;
        uint256 maxInAmount;
        uint256 minValue;
        uint256 maxValue;
    }

    Bounds internal DEFAULT_BOUNDS = Bounds({
        minBaseDecimals: 0,
        maxBaseDecimals: 18,
        minQuoteDecimals: 0,
        maxQuoteDecimals: 18,
        minFeedDecimals: 8,
        maxFeedDecimals: 18,
        minInAmount: 0,
        maxInAmount: type(uint128).max,
        minValue: 1,
        maxValue: 1e27
    });

    Bounds internal bounds = DEFAULT_BOUNDS;

    function setBounds(Bounds memory _bounds) internal {
        bounds = _bounds;
    }

    struct FuzzableState {
        // Config
        address base;
        address quote;
        address feed;
        uint256 maxStaleness;
        uint8 baseDecimals;
        uint8 quoteDecimals;
        uint8 feedDecimals;
        // Answer
        uint256 value;
        uint256 age;
        // Environment
        uint256 timestamp;
        uint256 inAmount;
    }

    function setUpState(FuzzableState memory s) internal {
        s.base = boundAddr(s.base);
        s.quote = boundAddr(s.quote);
        s.feed = boundAddr(s.feed);
        vm.assume(distinct(s.base, s.quote, s.feed));

        if (behaviors[Behavior.Constructor_MaxStalenessTooLow]) {
            s.maxStaleness = bound(s.maxStaleness, 0, MAX_STALENESS_LOWER_BOUND - 1);
        } else if (behaviors[Behavior.Constructor_MaxStalenessTooHigh]) {
            s.maxStaleness = bound(s.maxStaleness, MAX_STALENESS_UPPER_BOUND + 1, type(uint128).max);
        } else {
            s.maxStaleness = bound(s.maxStaleness, MAX_STALENESS_LOWER_BOUND, MAX_STALENESS_UPPER_BOUND);
        }

        s.baseDecimals = uint8(bound(s.baseDecimals, bounds.minBaseDecimals, bounds.maxBaseDecimals));
        s.quoteDecimals = uint8(bound(s.quoteDecimals, bounds.minQuoteDecimals, bounds.maxQuoteDecimals));
        s.feedDecimals = uint8(bound(s.feedDecimals, bounds.minFeedDecimals, bounds.maxFeedDecimals));

        vm.mockCall(s.base, abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(s.baseDecimals));
        vm.mockCall(s.quote, abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(s.quoteDecimals));
        vm.mockCall(s.feed, abi.encodeWithSelector(IChronicle.decimals.selector), abi.encode(s.feedDecimals));

        oracle = address(new ChronicleOracle(s.base, s.quote, s.feed, s.maxStaleness));

        s.value = bound(s.value, bounds.minValue, bounds.maxValue);

        s.age = bound(s.age, 0, type(uint128).max);
        if (behaviors[Behavior.FeedReturnsStalePrice]) {
            s.timestamp = bound(s.timestamp, s.age + s.maxStaleness + 1, type(uint256).max);
        } else {
            s.timestamp = bound(s.timestamp, s.age, s.age + s.maxStaleness);
        }

        s.inAmount = bound(s.inAmount, bounds.minInAmount, bounds.maxInAmount);

        if (behaviors[Behavior.FeedReverts]) {
            vm.mockCallRevert(s.feed, abi.encodeWithSelector(IChronicle.readWithAge.selector), "oops");
        } else {
            vm.mockCall(s.feed, abi.encodeWithSelector(IChronicle.readWithAge.selector), abi.encode(s.value, s.age));
        }

        vm.warp(s.timestamp);
    }

    function calcOutAmount(FuzzableState memory s) internal pure returns (uint256) {
        return FixedPointMathLib.fullMulDiv(
            s.inAmount, uint256(s.value) * 10 ** s.quoteDecimals, 10 ** (s.feedDecimals + s.baseDecimals)
        );
    }

    function calcOutAmountInverse(FuzzableState memory s) internal pure returns (uint256) {
        return FixedPointMathLib.fullMulDiv(
            s.inAmount, 10 ** (s.feedDecimals + s.baseDecimals), (uint256(s.value) * 10 ** s.quoteDecimals)
        );
    }
}
