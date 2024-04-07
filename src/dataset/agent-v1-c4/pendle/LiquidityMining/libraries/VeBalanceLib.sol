// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../core/libraries/math/PMath.sol";
import "../../core/libraries/Errors.sol";

struct VeBalance {
    uint128 bias;
    uint128 slope;
}

struct LockedPosition {
    uint128 amount;
    uint128 expiry;
}

library VeBalanceLib {
    using PMath for uint256;
    uint128 internal constant MAX_LOCK_TIME = 104 weeks;
    uint256 internal constant USER_VOTE_MAX_WEIGHT = 10 ** 18;

    function add(VeBalance memory a, VeBalance memory b) internal pure returns (VeBalance memory res) {
        res.bias = a.bias + b.bias;
        res.slope = a.slope + b.slope;
    }

    function sub(VeBalance memory a, VeBalance memory b) internal pure returns (VeBalance memory res) {
        res.bias = a.bias - b.bias;
        res.slope = a.slope - b.slope;
    }

    function sub(VeBalance memory a, uint128 slope, uint128 expiry) internal pure returns (VeBalance memory res) {
        res.slope = a.slope - slope;
        res.bias = a.bias - slope * expiry;
    }

    function isExpired(VeBalance memory a) internal view returns (bool) {
        return a.slope * uint128(block.timestamp) >= a.bias;
    }

    function getCurrentValue(VeBalance memory a) internal view returns (uint128) {
        if (isExpired(a)) return 0;
        return getValueAt(a, uint128(block.timestamp));
    }

    function getValueAt(VeBalance memory a, uint128 t) internal pure returns (uint128) {
        if (a.slope * t > a.bias) {
            return 0;
        }
        return a.bias - a.slope * t;
    }

    function getExpiry(VeBalance memory a) internal pure returns (uint128) {
        if (a.slope == 0) revert Errors.VEZeroSlope(a.bias, a.slope);
        return a.bias / a.slope;
    }

    function convertToVeBalance(LockedPosition memory position) internal pure returns (VeBalance memory res) {
        res.slope = position.amount / MAX_LOCK_TIME;
        res.bias = res.slope * position.expiry;
    }

    function convertToVeBalance(
        LockedPosition memory position,
        uint256 weight
    ) internal pure returns (VeBalance memory res) {
        res.slope = ((position.amount * weight) / MAX_LOCK_TIME / USER_VOTE_MAX_WEIGHT).Uint128();
        res.bias = res.slope * position.expiry;
    }

    function convertToVeBalance(uint128 amount, uint128 expiry) internal pure returns (uint128, uint128) {
        VeBalance memory balance = convertToVeBalance(LockedPosition(amount, expiry));
        return (balance.bias, balance.slope);
    }
}
