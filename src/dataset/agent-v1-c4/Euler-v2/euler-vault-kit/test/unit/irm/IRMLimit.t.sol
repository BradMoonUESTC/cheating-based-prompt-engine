// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "../../../src/EVault/shared/lib/RPow.sol";
import "../../../src/EVault/shared/Constants.sol";

contract IRMLimit is Test {
    function test_IRMLimit_sanity() public pure {
        // 500% APY:
        //   floor(((5 + 1)**(1/(86400*365.2425)) - 1) * 1e27)
        uint256 ir = 56778598899375661056;

        // After 1 year accumulator multiplies by just slightly under 6 (a 500% increase)
        (uint256 accum, bool overflow) = RPow.rpow(uint256(ir) + 1e27, SECONDS_PER_YEAR, 1e27);
        assertFalse(overflow);
        assertTrue(accum < 6e27);
        assertApproxEqAbs(accum, 6e27, 0.000000000000001e27);

        // One second later, it exceeds 6:
        (accum, overflow) = RPow.rpow(uint256(ir) + 1e27, SECONDS_PER_YEAR + 1, 1e27);
        assertFalse(overflow);
        assertTrue(accum > 6e27);
        assertApproxEqAbs(accum, 6e27, 0.000001e27);
    }

    function test_IRMLimit_rpow() public pure {
        // 1,000,000% APY is an accumulator of 10,000 + 1 after a year:

        {
            (uint256 accum, bool overflow) = RPow.rpow(MAX_ALLOWED_INTEREST_RATE + 1e27, SECONDS_PER_YEAR, 1e27);
            assertFalse(overflow);
            assertApproxEqAbs(accum, 10001e27, 0.000000000000001e27);
        }

        // rpow can handle a sustained 1,000,000% APY for 5 years without overflowing:

        {
            (uint256 accum, bool overflow) = RPow.rpow(MAX_ALLOWED_INTEREST_RATE + 1e27, SECONDS_PER_YEAR * 5, 1e27);
            assertFalse(overflow);
            assertApproxEqAbs(accum, 10001 ** 5 * 1e27, 1e29);
        }
    }

    function test_IRMLimit_accum_max() public pure {
        // With sustained 1,000,000% APY, computing the accumulator will not overflow for 5 years:

        uint256 accum = 1e27;
        (uint256 accumMul, bool overflow) = RPow.rpow(MAX_ALLOWED_INTEREST_RATE + 1e27, SECONDS_PER_YEAR, 1e27);
        assertFalse(overflow);

        for (uint256 i; i < 5; ++i) {
            // Checked math ensures no overflow on the following multiply:
            accum = accum * accumMul / 1e27;
        }
    }

    function test_IRMLimit_accum_50() public pure {
        uint256 ir = 12848677781048055591; // 50% APY

        uint256 accum = 1e27;
        (uint256 accumMul, bool overflow) = RPow.rpow(ir + 1e27, SECONDS_PER_YEAR, 1e27);
        assertFalse(overflow);

        for (uint256 i; i < 130; ++i) {
            accum = accum * accumMul / 1e27;
        }
    }

    function test_IRMLimit_accum_500() public pure {
        uint256 ir = 56778597287471077714; // 500% APY

        uint256 accum = 1e27;
        (uint256 accumMul, bool overflow) = RPow.rpow(ir + 1e27, SECONDS_PER_YEAR, 1e27);
        assertFalse(overflow);

        for (uint256 i; i < 29; ++i) {
            accum = accum * accumMul / 1e27;
        }
    }
}
