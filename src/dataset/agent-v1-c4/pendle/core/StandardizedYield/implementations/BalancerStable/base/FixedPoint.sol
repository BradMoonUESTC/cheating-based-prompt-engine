// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/* solhint-disable private-vars-leading-underscore */

/**
 * @dev forked from https://etherscan.io/token/0x8e85e97ed19c0fa13b2549309965291fbbc0048b#code
 * with omitted overflow checks given solidity version
 */

library FixedPoint {
    uint256 internal constant ONE = 1e18; // 18 decimal places
    uint256 internal constant TWO = 2 * ONE;
    uint256 internal constant FOUR = 4 * ONE;

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / ONE;
    }

    function mulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 product = a * b;
        if (product == 0) {
            return 0;
        } else {
            unchecked {
                return ((product - 1) / ONE) + 1;
            }
        }
    }

    function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "Zero division");

        if (a == 0) {
            return 0;
        } else {
            uint256 aInflated = a * ONE;
            return aInflated / b;
        }
    }

    function divUp(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "Zero division");

        if (a == 0) {
            return 0;
        } else {
            uint256 aInflated = a * ONE;
            unchecked {
                return ((aInflated - 1) / b) + 1;
            }
        }
    }

    function complement(uint256 x) internal pure returns (uint256) {
        unchecked {
            return (x < ONE) ? (ONE - x) : 0;
        }
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x > y ? x : y);
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x < y ? x : y);
    }
}
