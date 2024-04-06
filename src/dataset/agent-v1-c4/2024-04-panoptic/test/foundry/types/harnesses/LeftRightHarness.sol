// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {LeftRightLibrary, LeftRightUnsigned, LeftRightSigned} from "@types/LeftRight.sol";

/// @title LeftRightHarness: A harness to expose the LeftRight library for code coverage analysis.
/// @notice Replicates the interface of the LeftRight library, passing through any function calls
/// @author Axicon Labs Limited
contract LeftRightHarness {
    /*//////////////////////////////////////////////////////////////
                              RIGHT SLOT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the "right" slot from a uint256 bit pattern.
     * @param self The uint256 (full 256 bits) to be cut in its right half.
     * @return the right half of self (128 bits).
     */
    function rightSlot(LeftRightUnsigned self) public pure returns (uint128) {
        uint128 r = LeftRightLibrary.rightSlot(self);
        return r;
    }

    /**
     * @notice Get the "right" slot from an int256 bit pattern.
     * @param self The int256 (full 256 bits) to be cut in its right half.
     * @return the right half self (128 bits).
     */
    function rightSlot(LeftRightSigned self) public pure returns (int128) {
        int128 r = LeftRightLibrary.rightSlot(self);
        return r;
    }

    /// @dev All toRightSlot functions add bits to the right slot without clearing it first
    /// @dev Typically, the slot is already clear when writing to it, but if it is not, the bits will be added to the existing bits
    /// @dev Therefore, the assumption must not be made that the bits will be cleared while using these helpers

    /**
     * @notice Write the "right" slot to a uint256.
     * @param self the original full uint256 bit pattern to be written to.
     * @param right the bit pattern to write into the full pattern in the right half.
     * @return self with incoming right added (not overwritten, but added) to its right 128 bits.
     */
    function toRightSlot(
        LeftRightUnsigned self,
        uint128 right
    ) public pure returns (LeftRightUnsigned) {
        LeftRightUnsigned r = LeftRightLibrary.toRightSlot(self, right);
        return r;
    }

    /**
     * @notice Write the "right" slot to an int256.
     * @param self the original full int256 bit pattern to be written to.
     * @param right the bit pattern to write into the full pattern in the right half.
     * @return self with right added to its right 128 bits.
     */
    function toRightSlot(LeftRightSigned self, int128 right) public pure returns (LeftRightSigned) {
        LeftRightSigned r = LeftRightLibrary.toRightSlot(self, right);
        return r;
    }

    /*//////////////////////////////////////////////////////////////
                              LEFT SLOT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the "left" half from a uint256 bit pattern.
     * @param self The uint256 (full 256 bits) to be cut in its left half.
     * @return the left half (128 bits).
     */
    function leftSlot(LeftRightUnsigned self) public pure returns (uint128) {
        uint128 r = LeftRightLibrary.leftSlot(self);
        return r;
    }

    /**
     * @notice Get the "left" half from an int256 bit pattern.
     * @param self The int256 (full 256 bits) to be cut in its left half.
     * @return the left half (128 bits).
     */
    function leftSlot(LeftRightSigned self) public pure returns (int128) {
        int128 r = LeftRightLibrary.leftSlot(self);
        return r;
    }

    /// @dev All toLeftSlot functions add bits to the left slot without clearing it first
    /// @dev Typically, the slot is already clear when writing to it, but if it is not, the bits will be added to the existing bits
    /// @dev Therefore, the assumption must not be made that the bits will be cleared while using these helpers

    /**
     * @notice Write the "left" slot to a uint256 bit pattern.
     * @param self the original full uint256 bit pattern to be written to.
     * @param left the bit pattern to write into the full pattern in the right half.
     * @return self with left added to its left 128 bits.
     */
    function toLeftSlot(
        LeftRightUnsigned self,
        uint128 left
    ) public pure returns (LeftRightUnsigned) {
        LeftRightUnsigned r = LeftRightLibrary.toLeftSlot(self, left);
        return r;
    }

    /**
     * @notice Write the "left" slot to an int256 bit pattern.
     * @param self the original full int256 bit pattern to be written to.
     * @param left the bit pattern to write into the full pattern in the right half.
     * @return self with left added to its left 128 bits.
     */
    function toLeftSlot(LeftRightSigned self, int128 left) public pure returns (LeftRightSigned) {
        LeftRightSigned r = LeftRightLibrary.toLeftSlot(self, left);
        return r;
    }

    /*//////////////////////////////////////////////////////////////
                            MATH HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add two uint256 bit LeftRight-encoded words; revert on overflow or underflow.
     * @param x the augend
     * @param y the addend
     * @return z the sum x + y
     */
    function add(LeftRightUnsigned x, LeftRightUnsigned y) public pure returns (LeftRightUnsigned) {
        LeftRightUnsigned r = LeftRightLibrary.add(x, y);
        return r;
    }

    /**
     * @notice Subtract two uint256 bit LeftRight-encoded words; revert on overflow or underflow.
     * @param x the minuend
     * @param y the subtrahend
     * @return z the difference x - y
     */
    function sub(LeftRightUnsigned x, LeftRightUnsigned y) public pure returns (LeftRightUnsigned) {
        LeftRightUnsigned r = LeftRightLibrary.sub(x, y);
        return r;
    }

    /**
     * @notice Add uint256 to an int256 LeftRight-encoded word; revert on overflow or underflow.
     * @param x the augend
     * @param y the addend
     * @return z (int256) the sum x + y
     */
    function add(LeftRightUnsigned x, LeftRightSigned y) public pure returns (LeftRightSigned) {
        LeftRightSigned r = LeftRightLibrary.add(x, y);
        return r;
    }

    /**
     * @notice Add two int256 bit LeftRight-encoded words; revert on overflow.
     * @param x the augend
     * @param y the addend
     * @return z the sum x + y
     */
    function add(LeftRightSigned x, LeftRightSigned y) public pure returns (LeftRightSigned) {
        LeftRightSigned r = LeftRightLibrary.add(x, y);
        return r;
    }

    /**
     * @notice Subtract two int256 bit LeftRight-encoded words; revert on overflow.
     * @param x the minuend
     * @param y the subtrahend
     * @return z the difference x - y
     */
    function sub(LeftRightSigned x, LeftRightSigned y) public pure returns (LeftRightSigned) {
        LeftRightSigned r = LeftRightLibrary.sub(x, y);
        return r;
    }

    /**
     * @notice Subtract two int256 bit LeftRight-encoded words; rectify to 0 on negative result.
     * @param x the minuend
     * @param y the subtrahend
     * @return z the difference x - y
     */
    function subRect(LeftRightSigned x, LeftRightSigned y) public pure returns (LeftRightSigned) {
        LeftRightSigned r = LeftRightLibrary.subRect(x, y);
        return r;
    }

    function addCapped(
        LeftRightUnsigned x,
        LeftRightUnsigned dx,
        LeftRightUnsigned y,
        LeftRightUnsigned dy
    ) public pure returns (LeftRightUnsigned, LeftRightUnsigned) {
        (LeftRightUnsigned r1, LeftRightUnsigned r2) = LeftRightLibrary.addCapped(x, dx, y, dy);
        return (r1, r2);
    }
}
