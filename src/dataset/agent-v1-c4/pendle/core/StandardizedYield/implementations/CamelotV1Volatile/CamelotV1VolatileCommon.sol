// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../../../../interfaces/Camelot/ICamelotPair.sol";
import "../../../../interfaces/Camelot/ICamelotRouter.sol";
import "../../../../interfaces/Camelot/ICamelotFactory.sol";
import "../../../libraries/TokenHelper.sol";
import "../../../libraries/math/PMath.sol";

contract CamelotV1VolatileCommon {
    struct CamelotPairData {
        address token0;
        address token1;
        address pair;
        uint256 reserve0;
        uint256 reserve1;
        uint256 fee0;
        uint256 fee1;
    }

    uint256 internal constant FEE_DENOMINATOR = 100000;
    uint256 internal constant ONE = 1 * FEE_DENOMINATOR;
    uint256 internal constant TWO = 2 * FEE_DENOMINATOR;
    uint256 internal constant FOUR = 4 * FEE_DENOMINATOR;

    // reference: https://blog.alphaventuredao.io/onesideduniswap/
    function _getZapInSwapAmount(uint256 amountIn, uint256 reserve, uint256 fee) internal pure returns (uint256) {
        return
            (PMath.sqrt(PMath.square((TWO - fee) * reserve) + FOUR * (ONE - fee) * amountIn * reserve) -
                (TWO - fee) *
                reserve) / (2 * (ONE - fee));
    }
}
