// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

// there is a known issue with prb-math v3.x releases
// https://github.com/PaulRBerg/prb-math/issues/178
// due to this, either prb-math v2.x or v4.x versions should be used instead
import "prb-math/contracts/PRBMathUD60x18.sol";

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./Calc.sol";

/**
 * @title Precision
 * @dev Library for precision values and conversions
 */
library Precision {
    using SafeCast for uint256;
    using SignedMath for int256;

    uint256 public constant FLOAT_PRECISION = 10 ** 30;
    uint256 public constant FLOAT_PRECISION_SQRT = 10 ** 15;

    uint256 public constant WEI_PRECISION = 10 ** 18;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    uint256 public constant FLOAT_TO_WEI_DIVISOR = 10 ** 12;

    /**
     * Applies the given factor to the given value and returns the result.
     *
     * @param value The value to apply the factor to.
     * @param factor The factor to apply.
     * @return The result of applying the factor to the value.
     */
    function applyFactor(uint256 value, uint256 factor) internal pure returns (uint256) {
        return mulDiv(value, factor, FLOAT_PRECISION);
    }

    /**
     * Applies the given factor to the given value and returns the result.
     *
     * @param value The value to apply the factor to.
     * @param factor The factor to apply.
     * @return The result of applying the factor to the value.
     */
    function applyFactor(uint256 value, int256 factor) internal pure returns (int256) {
        return mulDiv(value, factor, FLOAT_PRECISION);
    }

    function applyFactor(uint256 value, int256 factor, bool roundUpMagnitude) internal pure returns (int256) {
        return mulDiv(value, factor, FLOAT_PRECISION, roundUpMagnitude);
    }

    function mulDiv(uint256 value, uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        return Math.mulDiv(value, numerator, denominator);
    }

    function mulDiv(int256 value, uint256 numerator, uint256 denominator) internal pure returns (int256) {
        return mulDiv(numerator, value, denominator);
    }

    function mulDiv(uint256 value, int256 numerator, uint256 denominator) internal pure returns (int256) {
        uint256 result = mulDiv(value, numerator.abs(), denominator);
        return numerator > 0 ? result.toInt256() : -result.toInt256();
    }

    function mulDiv(uint256 value, int256 numerator, uint256 denominator, bool roundUpMagnitude) internal pure returns (int256) {
        uint256 result = mulDiv(value, numerator.abs(), denominator, roundUpMagnitude);
        return numerator > 0 ? result.toInt256() : -result.toInt256();
    }

    function mulDiv(uint256 value, uint256 numerator, uint256 denominator, bool roundUpMagnitude) internal pure returns (uint256) {
        if (roundUpMagnitude) {
            return Math.mulDiv(value, numerator, denominator, Math.Rounding.Up);
        }

        return Math.mulDiv(value, numerator, denominator);
    }

    function applyExponentFactor(
        uint256 floatValue,
        uint256 exponentFactor
    ) internal pure returns (uint256) {
        // `PRBMathUD60x18.pow` doesn't work for `x` less than one
        if (floatValue < FLOAT_PRECISION) {
            return 0;
        }

        if (exponentFactor == FLOAT_PRECISION) {
            return floatValue;
        }

        // `PRBMathUD60x18.pow` accepts 2 fixed point numbers 60x18
        // we need to convert float (30 decimals) to 60x18 (18 decimals) and then back to 30 decimals
        uint256 weiValue = PRBMathUD60x18.pow(
            floatToWei(floatValue),
            floatToWei(exponentFactor)
        );

        return weiToFloat(weiValue);
    }

    function toFactor(uint256 value, uint256 divisor, bool roundUpMagnitude) internal pure returns (uint256) {
        if (value == 0) { return 0; }

        if (roundUpMagnitude) {
            return Math.mulDiv(value, FLOAT_PRECISION, divisor, Math.Rounding.Up);
        }

        return Math.mulDiv(value, FLOAT_PRECISION, divisor);
    }

    function toFactor(uint256 value, uint256 divisor) internal pure returns (uint256) {
        return toFactor(value, divisor, false);
    }

    function toFactor(int256 value, uint256 divisor) internal pure returns (int256) {
        uint256 result = toFactor(value.abs(), divisor);
        return value > 0 ? result.toInt256() : -result.toInt256();
    }

    /**
     * Converts the given value from float to wei.
     *
     * @param value The value to convert.
     * @return The converted value in wei.
     */
    function floatToWei(uint256 value) internal pure returns (uint256) {
        return value / FLOAT_TO_WEI_DIVISOR;
    }

    /**
     * Converts the given value from wei to float.
     *
     * @param value The value to convert.
     * @return The converted value in float.
     */
    function weiToFloat(uint256 value) internal pure returns (uint256) {
        return value * FLOAT_TO_WEI_DIVISOR;
    }

    /**
     * Converts the given number of basis points to float.
     *
     * @param basisPoints The number of basis points to convert.
     * @return The converted value in float.
     */
    function basisPointsToFloat(uint256 basisPoints) internal pure returns (uint256) {
        return basisPoints * FLOAT_PRECISION / BASIS_POINTS_DIVISOR;
    }
}
