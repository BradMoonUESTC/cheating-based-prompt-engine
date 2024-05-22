// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPyth} from "@pyth/IPyth.sol";
import {PythStructs} from "@pyth/PythStructs.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {AdapterHelper} from "test/adapter/AdapterHelper.sol";
import {StubPyth} from "test/adapter/pyth/StubPyth.sol";
import {boundAddr, distinct} from "test/utils/TestUtils.sol";
import {PythOracle} from "src/adapter/pyth/PythOracle.sol";

contract PythOracleHelper is AdapterHelper {
    uint256 internal constant MAX_STALENESS_UPPER_BOUND = 15 minutes;
    uint256 internal constant MAX_CONF_WIDTH_LOWER_BOUND = 10;
    uint256 internal constant MAX_CONF_WIDTH_UPPER_BOUND = 500;

    struct Bounds {
        uint8 minBaseDecimals;
        uint8 maxBaseDecimals;
        uint8 minQuoteDecimals;
        uint8 maxQuoteDecimals;
        uint256 minInAmount;
        uint256 maxInAmount;
        int64 minPrice;
        int64 maxPrice;
        int32 minExpo;
        int32 maxExpo;
    }

    Bounds internal DEFAULT_BOUNDS = Bounds({
        minBaseDecimals: 0,
        maxBaseDecimals: 18,
        minQuoteDecimals: 0,
        maxQuoteDecimals: 18,
        minInAmount: 0,
        maxInAmount: type(uint128).max,
        minPrice: 1,
        maxPrice: 1_000_000_000_000,
        minExpo: -20,
        maxExpo: 12
    });

    Bounds internal bounds = DEFAULT_BOUNDS;

    function setBounds(Bounds memory _bounds) internal {
        bounds = _bounds;
    }

    address PYTH;

    struct FuzzableState {
        // Config
        address base;
        address quote;
        bytes32 feedId;
        uint256 maxConfWidth;
        uint256 maxStaleness;
        uint8 baseDecimals;
        uint8 quoteDecimals;
        // Answer
        PythStructs.Price p;
        // Environment
        uint256 inAmount;
        uint256 timestamp;
    }

    constructor() {
        PYTH = address(new StubPyth());
    }

    function setUpState(FuzzableState memory s) internal {
        s.base = boundAddr(s.base);
        s.quote = boundAddr(s.quote);
        vm.assume(distinct(s.base, s.quote, PYTH));
        vm.assume(s.feedId != 0);

        if (behaviors[Behavior.Constructor_MaxStalenessTooHigh]) {
            s.maxStaleness = bound(s.maxStaleness, MAX_STALENESS_UPPER_BOUND + 1, type(uint128).max);
        } else {
            s.maxStaleness = bound(s.maxStaleness, 0, MAX_STALENESS_UPPER_BOUND);
        }

        if (behaviors[Behavior.Constructor_MaxConfWidthTooLow]) {
            s.maxConfWidth = bound(s.maxConfWidth, 0, MAX_CONF_WIDTH_LOWER_BOUND - 1);
        } else if (behaviors[Behavior.Constructor_MaxConfWidthTooHigh]) {
            s.maxConfWidth = bound(s.maxConfWidth, MAX_CONF_WIDTH_UPPER_BOUND + 1, type(uint128).max);
        } else {
            s.maxConfWidth = bound(s.maxConfWidth, MAX_CONF_WIDTH_LOWER_BOUND, MAX_CONF_WIDTH_UPPER_BOUND);
        }

        s.baseDecimals = uint8(bound(s.baseDecimals, bounds.minBaseDecimals, bounds.maxBaseDecimals));
        s.quoteDecimals = uint8(bound(s.quoteDecimals, bounds.minQuoteDecimals, bounds.maxQuoteDecimals));

        vm.mockCall(s.base, abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(s.baseDecimals));
        vm.mockCall(s.quote, abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(s.quoteDecimals));

        oracle = address(new PythOracle(PYTH, s.base, s.quote, s.feedId, s.maxStaleness, s.maxConfWidth));

        if (behaviors[Behavior.FeedReturnsNegativePrice]) {
            s.p.price = int64(bound(s.p.price, type(int64).min, -1));
        } else if (behaviors[Behavior.FeedReturnsZeroPrice]) {
            s.p.price = 0;
        } else {
            s.p.price = int64(bound(s.p.price, bounds.minPrice, bounds.maxPrice));
        }

        if (behaviors[Behavior.FeedReturnsConfTooWide]) {
            s.p.conf = uint64(bound(s.p.conf, uint64(s.p.price) * s.maxConfWidth / 10000 + 1, type(uint64).max));
        } else {
            s.p.conf = uint64(bound(s.p.conf, 0, uint64(s.p.price) * s.maxConfWidth / 10000));
        }

        if (behaviors[Behavior.FeedReturnsExpoTooLow]) {
            s.p.expo = int32(bound(s.p.expo, type(int32).min, -21));
        } else if (behaviors[Behavior.FeedReturnsExpoTooHigh]) {
            s.p.expo = int32(bound(s.p.expo, 21, type(int32).max));
        } else {
            s.p.expo = int32(bound(s.p.expo, bounds.minExpo, bounds.maxExpo));
        }

        s.p.publishTime = bound(s.p.publishTime, 1 minutes + 1, type(uint128).max);

        if (behaviors[Behavior.FeedReturnsStalePrice]) {
            s.timestamp = bound(s.timestamp, s.p.publishTime + s.maxStaleness + 1, type(uint144).max);
        } else if (behaviors[Behavior.FeedReturnsTooAheadPrice]) {
            s.timestamp = bound(s.timestamp, 0, s.p.publishTime - 1 minutes - 1);
        } else {
            s.timestamp = bound(s.timestamp, s.p.publishTime - 1 minutes, s.p.publishTime + s.maxStaleness);
        }

        if (behaviors[Behavior.FeedReverts]) {
            StubPyth(PYTH).setRevert(true);
        } else {
            StubPyth(PYTH).setPrice(s.p);
        }

        s.inAmount = bound(s.inAmount, 1, type(uint128).max);
        vm.warp(s.timestamp);
    }

    function calcOutAmount(FuzzableState memory s) internal pure returns (uint256) {
        int8 diff = int8(s.baseDecimals) - int8(s.p.expo);
        if (diff > 0) {
            return FixedPointMathLib.fullMulDiv(
                s.inAmount, uint256(uint64(s.p.price)) * 10 ** s.quoteDecimals, 10 ** (uint8(diff))
            );
        } else {
            return FixedPointMathLib.fullMulDiv(
                s.inAmount, uint256(uint64(s.p.price)) * 10 ** (s.quoteDecimals + uint8(-diff)), 1
            );
        }
    }

    function calcOutAmountInverse(FuzzableState memory s) internal pure returns (uint256) {
        int8 diff = int8(s.baseDecimals) - int8(s.p.expo);
        if (diff > 0) {
            return FixedPointMathLib.fullMulDiv(
                s.inAmount, 10 ** uint8(diff), uint256(uint64(s.p.price)) * 10 ** s.quoteDecimals
            );
        } else {
            return FixedPointMathLib.fullMulDiv(
                s.inAmount, 1, uint256(uint64(s.p.price)) * 10 ** (s.quoteDecimals + uint8(-diff))
            );
        }
    }
}
