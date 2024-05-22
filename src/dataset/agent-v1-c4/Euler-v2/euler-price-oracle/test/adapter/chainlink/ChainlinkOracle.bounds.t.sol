// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {ChainlinkOracleHelper} from "test/adapter/chainlink/ChainlinkOracleHelper.sol";
import {ChainlinkOracle} from "src/adapter/chainlink/ChainlinkOracle.sol";

contract ChainlinkOracleBoundsTest is ChainlinkOracleHelper {
    function test_Bounds_UsdOrBtcPair(FuzzableState memory s) public {
        setBounds(
            Bounds({
                minBaseDecimals: 0,
                maxBaseDecimals: 18,
                minQuoteDecimals: 0,
                maxQuoteDecimals: 18,
                minFeedDecimals: 8,
                maxFeedDecimals: 8,
                minInAmount: 0,
                maxInAmount: type(uint128).max,
                minAnswer: 1, // $0.00000001
                maxAnswer: 1e12 * 1e8 // $1,000,000,000,000.00 (One trillion)
            })
        );
        setUpState(s);

        uint256 outAmount = ChainlinkOracle(oracle).getQuote(s.inAmount, s.base, s.quote);
        assertEq(outAmount, calcOutAmount(s));

        uint256 outAmountInverse = ChainlinkOracle(oracle).getQuote(s.inAmount, s.quote, s.base);
        assertEq(outAmountInverse, calcOutAmountInverse(s));
    }

    function test_Bounds_EthPair(FuzzableState memory s) public {
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
                minAnswer: 1, // 1 wei
                maxAnswer: 1e9 * 1e18 // 1,000,000,000 ETH
            })
        );
        setUpState(s);

        uint256 outAmount = ChainlinkOracle(oracle).getQuote(s.inAmount, s.base, s.quote);
        assertEq(outAmount, calcOutAmount(s));

        uint256 outAmountInverse = ChainlinkOracle(oracle).getQuote(s.inAmount, s.quote, s.base);
        assertEq(outAmountInverse, calcOutAmountInverse(s));
    }
}
