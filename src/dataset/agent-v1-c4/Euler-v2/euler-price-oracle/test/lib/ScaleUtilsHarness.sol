// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {ScaleUtils, Scale} from "src/lib/ScaleUtils.sol";

contract ScaleUtilsHarness {
    function from(uint8 priceExponent, uint8 feedExponent) external pure returns (Scale) {
        return ScaleUtils.from(priceExponent, feedExponent);
    }

    function getDirectionOrRevert(address givenBase, address base, address givenQuote, address quote)
        external
        pure
        returns (bool)
    {
        return ScaleUtils.getDirectionOrRevert(givenBase, base, givenQuote, quote);
    }

    function calcScale(uint8 baseDecimals, uint8 quoteDecimals, uint8 feedDecimals) external pure returns (Scale) {
        return ScaleUtils.calcScale(baseDecimals, quoteDecimals, feedDecimals);
    }

    function calcOutAmount(uint256 inAmount, uint256 unitPrice, Scale scale, bool inverse)
        external
        pure
        returns (uint256)
    {
        return ScaleUtils.calcOutAmount(inAmount, unitPrice, scale, inverse);
    }
}
