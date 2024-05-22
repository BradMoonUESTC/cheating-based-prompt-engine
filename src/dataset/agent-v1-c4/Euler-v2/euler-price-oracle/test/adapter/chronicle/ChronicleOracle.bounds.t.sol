// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {ChronicleOracleHelper} from "test/adapter/chronicle/ChronicleOracleHelper.sol";
import {ChronicleOracle} from "src/adapter/chronicle/ChronicleOracle.sol";

contract ChronicleOracleBoundsTest is ChronicleOracleHelper {
    function test_Bounds_UsdPair(FuzzableState memory s) public {
        setBounds(
            Bounds({
                minBaseDecimals: 0,
                maxBaseDecimals: 18,
                minQuoteDecimals: 0,
                maxQuoteDecimals: 18,
                minFeedDecimals: 18,
                maxFeedDecimals: 18,
                minInAmount: 0,
                maxInAmount: type(uint128).max,
                minValue: 1, // 1e-18 USD
                maxValue: 1e12 * 1e18 // $1,000,000,000,000.00 (One trillion)
            })
        );
        setUpState(s);

        uint256 outAmount = ChronicleOracle(oracle).getQuote(s.inAmount, s.base, s.quote);
        assertEq(outAmount, calcOutAmount(s));

        uint256 outAmountInverse = ChronicleOracle(oracle).getQuote(s.inAmount, s.quote, s.base);
        assertEq(outAmountInverse, calcOutAmountInverse(s));
    }
}
