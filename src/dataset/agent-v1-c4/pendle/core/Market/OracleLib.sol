// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../libraries/Errors.sol";

/// Adapted from UniswapV3's Oracle

library OracleLib {
    struct Observation {
        uint32 blockTimestamp;
        uint216 lnImpliedRateCumulative;
        bool initialized;
        // 1 SLOT = 256 bits
    }

    function transform(
        Observation memory last,
        uint32 blockTimestamp,
        uint96 lnImpliedRate
    ) public pure returns (Observation memory) {
        return
            Observation({
                blockTimestamp: blockTimestamp,
                lnImpliedRateCumulative: last.lnImpliedRateCumulative +
                    uint216(lnImpliedRate) *
                    (blockTimestamp - last.blockTimestamp),
                initialized: true
            });
    }

    function initialize(
        Observation[65535] storage self,
        uint32 time
    ) public returns (uint16 cardinality, uint16 cardinalityNext) {
        self[0] = Observation({blockTimestamp: time, lnImpliedRateCumulative: 0, initialized: true});
        return (1, 1);
    }

    function write(
        Observation[65535] storage self,
        uint16 index,
        uint32 blockTimestamp,
        uint96 lnImpliedRate,
        uint16 cardinality,
        uint16 cardinalityNext
    ) public returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
        Observation memory last = self[index];

        // early return if we've already written an observation this block
        if (last.blockTimestamp == blockTimestamp) return (index, cardinality);

        // if the conditions are right, we can bump the cardinality
        if (cardinalityNext > cardinality && index == (cardinality - 1)) {
            cardinalityUpdated = cardinalityNext;
        } else {
            cardinalityUpdated = cardinality;
        }

        indexUpdated = (index + 1) % cardinalityUpdated;
        self[indexUpdated] = transform(last, blockTimestamp, lnImpliedRate);
    }

    function grow(Observation[65535] storage self, uint16 current, uint16 next) public returns (uint16) {
        if (current == 0) revert Errors.OracleUninitialized();
        // no-op if the passed next value isn't greater than the current next value
        if (next <= current) return current;
        // store in each slot to prevent fresh SSTOREs in swaps
        // this data will not be used because the initialized boolean is still false
        for (uint16 i = current; i != next; ) {
            self[i].blockTimestamp = 1;
            unchecked {
                ++i;
            }
        }
        return next;
    }

    function binarySearch(
        Observation[65535] storage self,
        uint32 target,
        uint16 index,
        uint16 cardinality
    ) public view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        uint256 l = (index + 1) % cardinality; // oldest observation
        uint256 r = l + cardinality - 1; // newest observation
        uint256 i;
        while (true) {
            i = (l + r) / 2;

            beforeOrAt = self[i % cardinality];

            // we've landed on an uninitialized observation, keep searching higher (more recently)
            if (!beforeOrAt.initialized) {
                l = i + 1;
                continue;
            }

            atOrAfter = self[(i + 1) % cardinality];

            bool targetAtOrAfter = beforeOrAt.blockTimestamp <= target;

            // check if we've found the answer!
            if (targetAtOrAfter && target <= atOrAfter.blockTimestamp) break;

            if (!targetAtOrAfter) r = i - 1;
            else l = i + 1;
        }
    }

    function getSurroundingObservations(
        Observation[65535] storage self,
        uint32 target,
        uint96 lnImpliedRate,
        uint16 index,
        uint16 cardinality
    ) public view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        // optimistically set before to the newest observation
        beforeOrAt = self[index];

        // if the target is chronologically at or after the newest observation, we can early return
        if (beforeOrAt.blockTimestamp <= target) {
            if (beforeOrAt.blockTimestamp == target) {
                // if newest observation equals target, we're in the same block, so we can ignore atOrAfter
                return (beforeOrAt, atOrAfter);
            } else {
                // otherwise, we need to transform
                return (beforeOrAt, transform(beforeOrAt, target, lnImpliedRate));
            }
        }

        // now, set beforeOrAt to the oldest observation
        beforeOrAt = self[(index + 1) % cardinality];
        if (!beforeOrAt.initialized) beforeOrAt = self[0];

        // ensure that the target is chronologically at or after the oldest observation
        if (target < beforeOrAt.blockTimestamp) revert Errors.OracleTargetTooOld(target, beforeOrAt.blockTimestamp);

        // if we've reached this point, we have to binary search
        return binarySearch(self, target, index, cardinality);
    }

    function observeSingle(
        Observation[65535] storage self,
        uint32 time,
        uint32 secondsAgo,
        uint96 lnImpliedRate,
        uint16 index,
        uint16 cardinality
    ) public view returns (uint216 lnImpliedRateCumulative) {
        if (secondsAgo == 0) {
            Observation memory last = self[index];
            if (last.blockTimestamp != time) {
                return transform(last, time, lnImpliedRate).lnImpliedRateCumulative;
            }
            return last.lnImpliedRateCumulative;
        }

        uint32 target = time - secondsAgo;

        (Observation memory beforeOrAt, Observation memory atOrAfter) = getSurroundingObservations(
            self,
            target,
            lnImpliedRate,
            index,
            cardinality
        );

        if (target == beforeOrAt.blockTimestamp) {
            // we're at the left boundary
            return beforeOrAt.lnImpliedRateCumulative;
        } else if (target == atOrAfter.blockTimestamp) {
            // we're at the right boundary
            return atOrAfter.lnImpliedRateCumulative;
        } else {
            // we're in the middle
            return (beforeOrAt.lnImpliedRateCumulative +
                uint216(
                    (uint256(atOrAfter.lnImpliedRateCumulative - beforeOrAt.lnImpliedRateCumulative) *
                        (target - beforeOrAt.blockTimestamp)) / (atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp)
                ));
        }
    }

    function observe(
        Observation[65535] storage self,
        uint32 time,
        uint32[] memory secondsAgos,
        uint96 lnImpliedRate,
        uint16 index,
        uint16 cardinality
    ) public view returns (uint216[] memory lnImpliedRateCumulative) {
        if (cardinality == 0) revert Errors.OracleZeroCardinality();

        lnImpliedRateCumulative = new uint216[](secondsAgos.length);
        for (uint256 i = 0; i < lnImpliedRateCumulative.length; ++i) {
            lnImpliedRateCumulative[i] = observeSingle(self, time, secondsAgos[i], lnImpliedRate, index, cardinality);
        }
    }
}
