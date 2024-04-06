// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
// Foundry

import "forge-std/Test.sol";
// Internal
import {LeftRightHarness} from "./harnesses/LeftRightHarness.sol";
import {LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";
import {Errors} from "@libraries/Errors.sol";
import {Math} from "@libraries/Math.sol";

/**
 * Test the LeftRight word packing library using Foundry and Fuzzing.
 *
 * @author Axicon Labs Limited
 */
contract LeftRightTest is Test {
    // harness
    LeftRightHarness harness;

    function setUp() public {
        harness = new LeftRightHarness();
    }

    // RIGHT SLOT
    function test_Success_RightSlot_Uint128_In_Uint256(uint128 y) public {
        LeftRightUnsigned x = LeftRightUnsigned.wrap(0);
        x = harness.toRightSlot(x, y);
        assertEq(uint128(harness.leftSlot(x)), 0);
        assertEq(uint128(harness.rightSlot(x)), y);
    }

    function test_Success_RightSlot_Uint128_In_Uint256_noLeaking(
        LeftRightUnsigned x,
        uint128 y
    ) public {
        uint128 originalLeft = harness.leftSlot(x);
        x = harness.toRightSlot(x, y);
        assertEq(harness.leftSlot(x), originalLeft, "Right slot input overflowed into left slot");
    }

    function test_Success_RightSlot_Int128_In_Int256(int128 y) public {
        LeftRightSigned x = LeftRightSigned.wrap(0);
        x = harness.toRightSlot(x, y);
        assertEq(int128(harness.leftSlot(x)), 0);
        assertEq(int128(harness.rightSlot(x)), y);
    }

    function test_Success_RightSlot_int128_In_Int256_noLeaking(LeftRightSigned x, int128 y) public {
        int128 originalLeft = harness.leftSlot(x);
        x = harness.toRightSlot(x, y);
        assertEq(
            int128(harness.leftSlot(x)),
            originalLeft,
            "Right slot input overflowed into left slot"
        );
    }

    // LEFT SLOT
    function test_Success_LeftSlot_Uint128_In_Uint256(uint128 y) public {
        LeftRightUnsigned x = LeftRightUnsigned.wrap(0);
        x = harness.toLeftSlot(x, y);
        assertEq(uint128(harness.leftSlot(x)), y);
        assertEq(uint128(harness.rightSlot(x)), 0);
    }

    function test_Success_LeftSlot_Int128_In_Int256(int128 y) public {
        LeftRightSigned x = LeftRightSigned.wrap(0);
        x = harness.toLeftSlot(x, y);
        assertEq(int128(harness.leftSlot(x)), y);
        assertEq(int128(harness.rightSlot(x)), 0);
    }

    // BOTH
    function test_Success_BothSlots_uint256(uint128 y, uint128 z) public {
        LeftRightUnsigned x = LeftRightUnsigned.wrap(0);
        x = harness.toLeftSlot(x, y);
        x = harness.toRightSlot(x, z);

        assertEq(uint128(harness.leftSlot(x)), y);
        assertEq(uint128(harness.rightSlot(x)), z);
    }

    function test_Success_BothSlots_int256(int128 y, int128 z) public {
        LeftRightSigned x = LeftRightSigned.wrap(0);
        x = harness.toLeftSlot(x, y);
        x = harness.toRightSlot(x, z);

        assertEq(int128(harness.leftSlot(x)), y);
        assertEq(int128(harness.rightSlot(x)), z);
    }

    // MATH
    function test_Success_AddUints(uint128 y, uint128 z, uint128 u, uint128 v) public {
        LeftRightUnsigned x = LeftRightUnsigned.wrap(0);
        x = harness.toLeftSlot(x, y);
        x = harness.toRightSlot(x, z);
        assertEq(uint128(harness.leftSlot(x)), y);
        assertEq(uint128(harness.rightSlot(x)), z);

        // try swapping order
        x = LeftRightUnsigned.wrap(0);
        x = harness.toRightSlot(x, y);
        x = harness.toLeftSlot(x, z);
        assertEq(uint128(harness.leftSlot(x)), z);
        assertEq(uint128(harness.rightSlot(x)), y);

        x = LeftRightUnsigned.wrap(0);
        x = harness.toLeftSlot(x, y);
        x = harness.toRightSlot(x, z);
        assertEq(uint128(harness.leftSlot(x)), y);
        assertEq(uint128(harness.rightSlot(x)), z);

        LeftRightUnsigned xx = LeftRightUnsigned.wrap(0);
        xx = harness.toLeftSlot(xx, u);
        xx = harness.toRightSlot(xx, v);

        // now test add
        if (uint128(uint256(y) + uint256(u)) < y) {
            // under/overflow
            vm.expectRevert(Errors.UnderOverFlow.selector);
            harness.add(x, xx);
        } else if (uint128(uint256(z) + uint256(v)) < z) {
            // under/overflow
            vm.expectRevert(Errors.UnderOverFlow.selector);
            harness.add(x, xx);
        } else {
            // normal case
            LeftRightUnsigned other = harness.add(x, xx);
            assertEq(uint128(harness.leftSlot(other)), y + u);
            assertEq(uint128(harness.rightSlot(other)), z + v);
        }
    }

    function test_Success_AddUintInt(uint128 y, uint128 z, int128 u, int128 v) public {
        LeftRightUnsigned x = LeftRightUnsigned.wrap(0);
        x = harness.toLeftSlot(x, y);
        x = harness.toRightSlot(x, z);
        assertEq(uint128(harness.leftSlot(x)), y);
        assertEq(uint128(harness.rightSlot(x)), z);

        LeftRightSigned xx = LeftRightSigned.wrap(0);
        xx = harness.toLeftSlot(xx, u);
        xx = harness.toRightSlot(xx, v);

        // now test add
        unchecked {
            if (
                (int256(uint256(y)) + u < int256(uint256(y)) && u > 0) ||
                (int256(uint256(y)) + u > int256(uint256(y)) && u < 0)
            ) {
                // under/overflow
                vm.expectRevert(Errors.UnderOverFlow.selector);
                harness.add(x, xx);
            } else if (
                (int256(uint256(z)) + v < int256(uint256(z)) && (v > 0)) ||
                (int256(uint256(z)) + v > int256(uint256(z)) && (v < 0))
            ) {
                // under/overflow
                vm.expectRevert(Errors.UnderOverFlow.selector);
                harness.add(x, xx);
            } else if (
                int256(uint256(y)) + u > type(int128).max ||
                int256(uint256(z)) + v > type(int128).max
            ) {
                // under/overflow
                vm.expectRevert(Errors.UnderOverFlow.selector);
                harness.add(x, xx);
            } else {
                // normal case
                LeftRightSigned other = harness.add(x, xx);
                assertEq(uint128(harness.leftSlot(other)), uint128(int128(y) + u));
                assertEq(uint128(harness.rightSlot(other)), uint128(int128(z) + v));
            }
        }
    }

    function test_Success_SubUints(uint128 y, uint128 z, uint128 u, uint128 v) public {
        LeftRightUnsigned x = LeftRightUnsigned.wrap(0);
        x = harness.toLeftSlot(x, y);
        x = harness.toRightSlot(x, z);

        assertEq(uint128(harness.leftSlot(x)), y);
        assertEq(uint128(harness.rightSlot(x)), z);

        LeftRightUnsigned xx = LeftRightUnsigned.wrap(0);
        xx = harness.toRightSlot(xx, v);
        xx = harness.toLeftSlot(xx, u);

        assertEq(uint128(harness.leftSlot(xx)), u);
        assertEq(uint128(harness.rightSlot(xx)), v);

        // now test sub
        unchecked {
            // needed b/c we are checking for under/overflow cases to actually happen
            if (y - u > y) {
                // under/overflow
                vm.expectRevert(Errors.UnderOverFlow.selector);
                harness.sub(x, xx);
            } else if (z - v > z) {
                // under/overflow
                vm.expectRevert(Errors.UnderOverFlow.selector);
                harness.sub(x, xx);
            } else {
                // normal case
                LeftRightUnsigned other = harness.sub(x, xx);
                assertEq(uint128(harness.leftSlot(other)), y - u);
                assertEq(uint128(harness.rightSlot(other)), z - v);
            }
        }
    }

    // MATH for ints
    function test_Success_AddInts(int128 y, int128 z, int128 u, int128 v) public {
        LeftRightSigned x = LeftRightSigned.wrap(0);
        x = harness.toLeftSlot(x, y);
        x = harness.toRightSlot(x, z);
        assertEq(int128(harness.leftSlot(x)), y);
        assertEq(int128(harness.rightSlot(x)), z);

        // try swapping order
        x = LeftRightSigned.wrap(0);
        x = harness.toRightSlot(x, y);
        x = harness.toLeftSlot(x, z);
        assertEq(int128(harness.leftSlot(x)), z);
        assertEq(int128(harness.rightSlot(x)), y);

        x = LeftRightSigned.wrap(0);
        x = harness.toLeftSlot(x, y);
        x = harness.toRightSlot(x, z);
        assertEq(int128(harness.leftSlot(x)), y);
        assertEq(int128(harness.rightSlot(x)), z);

        LeftRightSigned xx = LeftRightSigned.wrap(0);
        xx = harness.toLeftSlot(xx, u);
        xx = harness.toRightSlot(xx, v);

        // now test add
        unchecked {
            if ((y + u < y && u > 0) || (y + u > y && u < 0)) {
                // under/overflow
                vm.expectRevert(Errors.UnderOverFlow.selector);
                harness.add(x, xx);
            } else if ((z + v < z && v > 0) || (z + v > z && v < 0)) {
                // under/overflow
                vm.expectRevert(Errors.UnderOverFlow.selector);
                harness.add(x, xx);
            } else {
                // normal case
                LeftRightSigned other = harness.add(x, xx);
                assertEq(int128(harness.leftSlot(other)), y + u);
                assertEq(int128(harness.rightSlot(other)), z + v);
            }
        }
    }

    function test_Success_SubInts(int128 y, int128 z, int128 u, int128 v) public {
        LeftRightSigned x = LeftRightSigned.wrap(0);
        x = harness.toLeftSlot(x, y);
        x = harness.toRightSlot(x, z);
        assertEq(int128(harness.leftSlot(x)), y);
        assertEq(int128(harness.rightSlot(x)), z);

        // try swapping order
        x = LeftRightSigned.wrap(0);
        x = harness.toRightSlot(x, y);
        x = harness.toLeftSlot(x, z);
        assertEq(int128(harness.leftSlot(x)), z);
        assertEq(int128(harness.rightSlot(x)), y);

        x = LeftRightSigned.wrap(0);
        x = harness.toLeftSlot(x, y);
        x = harness.toRightSlot(x, z);
        assertEq(int128(harness.leftSlot(x)), y);
        assertEq(int128(harness.rightSlot(x)), z);

        LeftRightSigned xx = LeftRightSigned.wrap(0);
        xx = harness.toLeftSlot(xx, u);
        xx = harness.toRightSlot(xx, v);

        // now test add
        unchecked {
            if ((y - u > y && u > 0) || (y - u < y && u < 0)) {
                // under/overflow
                vm.expectRevert(Errors.UnderOverFlow.selector);
                harness.sub(x, xx);
            } else if ((z - v > z && v > 0) || (z - v < z && v < 0)) {
                // under/overflow
                vm.expectRevert(Errors.UnderOverFlow.selector);
                harness.sub(x, xx);
            } else {
                // normal case
                LeftRightSigned other = harness.sub(x, xx);
                assertEq(int128(harness.leftSlot(other)), y - u);
                assertEq(int128(harness.rightSlot(other)), z - v);
            }
        }
    }

    function test_Success_SubRectInts(int128 y, int128 z, int128 u, int128 v) public {
        LeftRightSigned x = LeftRightSigned.wrap(0);

        x = harness.toLeftSlot(x, y);
        x = harness.toRightSlot(x, z);

        LeftRightSigned xx = LeftRightSigned.wrap(0);
        xx = harness.toLeftSlot(xx, u);
        xx = harness.toRightSlot(xx, v);

        // now test add
        unchecked {
            if ((y - u > y && u > 0) || (y - u < y && u < 0)) {
                // under/overflow
                vm.expectRevert(Errors.UnderOverFlow.selector);
                harness.subRect(x, xx);
            } else if ((z - v > z && v > 0) || (z - v < z && v < 0)) {
                // under/overflow
                vm.expectRevert(Errors.UnderOverFlow.selector);
                harness.subRect(x, xx);
            } else {
                // normal case
                LeftRightSigned other = harness.subRect(x, xx);
                assertEq(int128(harness.leftSlot(other)), y - u > 0 ? y - u : int128(0));
                assertEq(int128(harness.rightSlot(other)), z - v > 0 ? z - v : int128(0));
            }
        }
    }

    function test_Success_AddCapped_NoCap(
        LeftRightUnsigned x,
        LeftRightUnsigned dx,
        LeftRightUnsigned y,
        LeftRightUnsigned dy
    ) public {
        vm.assume(
            uint256(x.rightSlot()) + dx.rightSlot() < type(uint128).max &&
                uint256(y.rightSlot()) + dy.rightSlot() < type(uint128).max
        );
        vm.assume(
            uint256(x.leftSlot()) + dx.leftSlot() < type(uint128).max &&
                uint256(y.leftSlot()) + dy.leftSlot() < type(uint128).max
        );
        (LeftRightUnsigned r_x, LeftRightUnsigned r_y) = harness.addCapped(x, dx, y, dy);

        LeftRightUnsigned e_x = harness.add(x, dx);
        LeftRightUnsigned e_y = harness.add(y, dy);

        assertEq(LeftRightUnsigned.unwrap(r_x), LeftRightUnsigned.unwrap(e_x));
        assertEq(LeftRightUnsigned.unwrap(r_y), LeftRightUnsigned.unwrap(e_y));
    }

    // Accumulation should be frozen on right slot only
    function test_Success_AddCapped_CapRight(
        LeftRightUnsigned x,
        LeftRightUnsigned dx,
        LeftRightUnsigned y,
        LeftRightUnsigned dy
    ) public {
        vm.assume(
            uint256(x.rightSlot()) + dx.rightSlot() >= type(uint128).max ||
                uint256(y.rightSlot()) + dy.rightSlot() >= type(uint128).max
        );
        vm.assume(
            !(uint256(x.leftSlot()) + dx.leftSlot() >= type(uint128).max ||
                uint256(y.leftSlot()) + dy.leftSlot() >= type(uint128).max)
        );
        (LeftRightUnsigned r_x, LeftRightUnsigned r_y) = harness.addCapped(x, dx, y, dy);

        assertEq(r_x.rightSlot(), x.rightSlot());
        assertEq(r_x.leftSlot(), x.leftSlot() + dx.leftSlot());
        assertEq(r_y.rightSlot(), y.rightSlot());
        assertEq(r_y.leftSlot(), y.leftSlot() + dy.leftSlot());
    }

    // Accumulation should be frozen on left slot only
    function test_Success_AddCapped_CapLeft(
        LeftRightUnsigned x,
        LeftRightUnsigned dx,
        LeftRightUnsigned y,
        LeftRightUnsigned dy
    ) public {
        vm.assume(
            uint256(x.leftSlot()) + dx.leftSlot() >= type(uint128).max ||
                uint256(y.leftSlot()) + dy.leftSlot() >= type(uint128).max
        );
        vm.assume(
            !(uint256(x.rightSlot()) + dx.rightSlot() >= type(uint128).max ||
                uint256(y.rightSlot()) + dy.rightSlot() >= type(uint128).max)
        );
        (LeftRightUnsigned r_x, LeftRightUnsigned r_y) = harness.addCapped(x, dx, y, dy);

        assertEq(r_x.rightSlot(), x.rightSlot() + dx.rightSlot());
        assertEq(r_x.leftSlot(), x.leftSlot());
        assertEq(r_y.rightSlot(), y.rightSlot() + dy.rightSlot());
        assertEq(r_y.leftSlot(), y.leftSlot());
    }

    // Accumulation should be frozen on both slots
    function test_Success_AddCapped_CapBoth(
        LeftRightUnsigned x,
        LeftRightUnsigned dx,
        LeftRightUnsigned y,
        LeftRightUnsigned dy
    ) public {
        vm.assume(
            uint256(x.rightSlot()) + dx.rightSlot() >= type(uint128).max ||
                uint256(y.rightSlot()) + dy.rightSlot() >= type(uint128).max
        );
        vm.assume(
            uint256(x.leftSlot()) + dx.leftSlot() >= type(uint128).max ||
                uint256(y.leftSlot()) + dy.leftSlot() >= type(uint128).max
        );
        (LeftRightUnsigned r_x, LeftRightUnsigned r_y) = harness.addCapped(x, dx, y, dy);

        assertEq(r_x.rightSlot(), x.rightSlot());
        assertEq(r_x.leftSlot(), x.leftSlot());
        assertEq(r_y.rightSlot(), y.rightSlot());
        assertEq(r_y.leftSlot(), y.leftSlot());
    }

    // combined test version for unlimited runs
    function test_Success_AddCapped(
        LeftRightUnsigned x,
        LeftRightUnsigned dx,
        LeftRightUnsigned y,
        LeftRightUnsigned dy
    ) public {
        (LeftRightUnsigned r_x, LeftRightUnsigned r_y) = harness.addCapped(x, dx, y, dy);

        if (
            (uint256(x.rightSlot()) + dx.rightSlot() >= type(uint128).max ||
                uint256(y.rightSlot()) + dy.rightSlot() >= type(uint128).max) &&
            (uint256(x.leftSlot()) + dx.leftSlot() >= type(uint128).max ||
                uint256(y.leftSlot()) + dy.leftSlot() >= type(uint128).max)
        ) {
            assertEq(r_x.rightSlot(), x.rightSlot());
            assertEq(r_x.leftSlot(), x.leftSlot());
            assertEq(r_y.rightSlot(), y.rightSlot());
            assertEq(r_y.leftSlot(), y.leftSlot());
        } else if (
            uint256(x.rightSlot()) + dx.rightSlot() >= type(uint128).max ||
            uint256(y.rightSlot()) + dy.rightSlot() >= type(uint128).max
        ) {
            assertEq(r_x.rightSlot(), x.rightSlot());
            assertEq(r_x.leftSlot(), x.leftSlot() + dx.leftSlot());
            assertEq(r_y.rightSlot(), y.rightSlot());
            assertEq(r_y.leftSlot(), y.leftSlot() + dy.leftSlot());
        } else if (
            uint256(x.leftSlot()) + dx.leftSlot() >= type(uint128).max ||
            uint256(y.leftSlot()) + dy.leftSlot() >= type(uint128).max
        ) {
            assertEq(r_x.rightSlot(), x.rightSlot() + dx.rightSlot());
            assertEq(r_x.leftSlot(), x.leftSlot());
            assertEq(r_y.rightSlot(), y.rightSlot() + dy.rightSlot());
            assertEq(r_y.leftSlot(), y.leftSlot());
        } else {
            assertEq(LeftRightUnsigned.unwrap(r_x), LeftRightUnsigned.unwrap(harness.add(x, dx)));
            assertEq(LeftRightUnsigned.unwrap(r_y), LeftRightUnsigned.unwrap(harness.add(y, dy)));
        }
    }
}
