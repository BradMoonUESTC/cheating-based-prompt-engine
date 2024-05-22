// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../InterestRateModels/IIRM.sol";
import "../interfaces/IPriceOracle.sol";
import {IERC20} from "../EVault/IEVault.sol";

/// @title IRMSynth
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Synthetic asset vaults use a different interest rate model than the standard vaults. The IRMSynth interest
/// rate model is a simple reactive rate model which adjusts the interest rate up when it trades below the targetQuote
/// and down when it trades above or at the targetQuote.
contract IRMSynth is IIRM {
    uint216 internal constant SECONDS_PER_YEAR = 365.2425 * 86400; // Gregorian calendar
    uint216 public constant MAX_RATE = 1e27 * 1.5 / SECONDS_PER_YEAR; // 150% APR
    uint216 public constant BASE_RATE = 1e27 * 0.005 / SECONDS_PER_YEAR; // 0.5% APR
    uint216 public constant ADJUST_FACTOR = 1.1e18; // 10% adjust of last rate per interval
    uint216 public constant ADJUST_ONE = 1.0e18;
    uint216 public constant ADJUST_INTERVAL = 1 hours;

    address public immutable synth;
    address public immutable referenceAsset;
    IPriceOracle public immutable oracle;
    uint256 public immutable targetQuote;
    uint256 public immutable quoteAmount;

    struct IRMData {
        uint40 lastUpdated;
        uint216 lastRate;
    }

    IRMData internal irmStorage;

    error E_ZeroAddress();
    error E_InvalidQuote();

    constructor(address synth_, address referenceAsset_, address oracle_, uint256 targetQuoute_) {
        if (synth_ == address(0) || referenceAsset_ == address(0) || oracle_ == address(0)) {
            revert E_ZeroAddress();
        }

        synth = synth_;
        referenceAsset = referenceAsset_;
        oracle = IPriceOracle(oracle_);
        targetQuote = targetQuoute_;
        quoteAmount = 10 ** IERC20(synth_).decimals();

        // Refusing to proceed with worthless asset
        uint256 testQuote = IPriceOracle(oracle_).getQuote(quoteAmount, synth_, referenceAsset_);
        if (testQuote == 0) {
            revert E_InvalidQuote();
        }

        irmStorage = IRMData({lastUpdated: uint40(block.timestamp), lastRate: BASE_RATE});
    }

    function computeInterestRate(address, uint256, uint256) external override returns (uint256) {
        IRMData memory irmCache = irmStorage;
        (uint216 rate, bool updated) = _computeRate(irmCache);

        if (updated) {
            irmStorage = IRMData({lastUpdated: uint40(block.timestamp), lastRate: rate});
        }

        return rate;
    }

    function computeInterestRateView(address, uint256, uint256) external view override returns (uint256) {
        (uint216 rate,) = _computeRate(irmStorage);
        return rate;
    }

    function _computeRate(IRMData memory irmCache) internal view returns (uint216 rate, bool updated) {
        updated = false;
        rate = irmCache.lastRate;

        // If not time to update yet, return the last rate
        if (block.timestamp < irmCache.lastUpdated + ADJUST_INTERVAL) {
            return (rate, updated);
        }

        uint256 quote = oracle.getQuote(quoteAmount, synth, referenceAsset);

        updated = true;

        if (quote < targetQuote) {
            // If the quote is less than the target, increase the rate
            rate = rate * ADJUST_FACTOR / ADJUST_ONE;
        } else {
            // If the quote is greater than the target, decrease the rate
            rate = rate * ADJUST_ONE / ADJUST_FACTOR;
        }

        // Apply the min and max rates
        if (rate < BASE_RATE) {
            rate = BASE_RATE;
        } else if (rate > MAX_RATE) {
            rate = MAX_RATE;
        }

        return (rate, updated);
    }

    function getIRMData() external view returns (IRMData memory) {
        return irmStorage;
    }
}
