// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {PythOracleHelper} from "test/adapter/pyth/PythOracleHelper.sol";
import {PythOracle} from "src/adapter/pyth/PythOracle.sol";

contract PythOracleBoundsTest is PythOracleHelper {
    function test_Bounds(FuzzableState memory s) public {
        setBounds(
            Bounds({
                minBaseDecimals: 0,
                maxBaseDecimals: 18,
                minQuoteDecimals: 0,
                maxQuoteDecimals: 18,
                minInAmount: 0,
                maxInAmount: type(uint128).max,
                minPrice: 1,
                maxPrice: 1_000_000_000_000_000,
                minExpo: -20,
                maxExpo: 0
            })
        );
        setUpState(s);

        uint256 outAmount = PythOracle(oracle).getQuote(s.inAmount, s.base, s.quote);
        assertEq(outAmount, calcOutAmount(s));

        uint256 outAmountInverse = PythOracle(oracle).getQuote(s.inAmount, s.quote, s.base);
        assertEq(outAmountInverse, calcOutAmountInverse(s));
    }
}
