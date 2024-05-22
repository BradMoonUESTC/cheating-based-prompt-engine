// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {BaseAdapter, Errors, IPriceOracle} from "src/adapter/BaseAdapter.sol";
import {IChronicle} from "src/adapter/chronicle/IChronicle.sol";
import {ScaleUtils, Scale} from "src/lib/ScaleUtils.sol";

/// @title ChronicleOracle
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice PriceOracle adapter for Chronicle push-based price feeds.
/// @dev Note: Chronicle price feeds currently have a caller whitelist.
/// To be able read price data, the caller (this contract) must be explicitly authorized.
contract ChronicleOracle is BaseAdapter {
    /// @inheritdoc IPriceOracle
    string public constant name = "ChronicleOracle";
    /// @notice The minimum permitted value for `maxStaleness`.
    uint256 internal constant MAX_STALENESS_LOWER_BOUND = 1 minutes;
    /// @notice The maximum permitted value for `maxStaleness`.
    uint256 internal constant MAX_STALENESS_UPPER_BOUND = 72 hours;
    /// @notice The address of the base asset corresponding to the feed.
    address public immutable base;
    /// @notice The address of the quote asset corresponding to the feed
    address public immutable quote;
    /// @notice The address of the Chronicle price feed.
    /// @dev https://chroniclelabs.org/dashboard/oracles
    address public immutable feed;
    /// @notice The maximum allowed age of the price.
    /// @dev Reverts if `block.timestamp - age > maxStaleness`.
    uint256 public immutable maxStaleness;
    /// @notice The scale factors used for decimal conversions.
    Scale internal immutable scale;

    /// @notice Deploy a ChronicleOracle.
    /// @param _base The address of the base asset corresponding to the feed.
    /// @param _quote The address of the quote asset corresponding to the feed.
    /// @param _feed The address of the Chronicle price feed.
    /// @param _maxStaleness The maximum allowed age of the price.
    constructor(address _base, address _quote, address _feed, uint256 _maxStaleness) {
        if (_maxStaleness < MAX_STALENESS_LOWER_BOUND || _maxStaleness > MAX_STALENESS_UPPER_BOUND) {
            revert Errors.PriceOracle_InvalidConfiguration();
        }

        base = _base;
        quote = _quote;
        feed = _feed;
        maxStaleness = _maxStaleness;

        // The scale factor is used to correctly convert decimals.
        uint8 baseDecimals = _getDecimals(base);
        uint8 quoteDecimals = _getDecimals(quote);
        uint8 feedDecimals = IChronicle(feed).decimals();
        scale = ScaleUtils.calcScale(baseDecimals, quoteDecimals, feedDecimals);
    }

    /// @notice Get the quote from the Chronicle feed.
    /// @param inAmount The amount of `base` to convert.
    /// @param _base The token that is being priced.
    /// @param _quote The token that is the unit of account.
    /// @return The converted amount using the Chronicle feed.
    function _getQuote(uint256 inAmount, address _base, address _quote) internal view override returns (uint256) {
        bool inverse = ScaleUtils.getDirectionOrRevert(_base, base, _quote, quote);

        // Note: `readWithAge` will revert if `price == 0`.
        (uint256 price, uint256 age) = IChronicle(feed).readWithAge();
        uint256 staleness = block.timestamp - age;
        if (staleness > maxStaleness) revert Errors.PriceOracle_TooStale(staleness, maxStaleness);

        return ScaleUtils.calcOutAmount(inAmount, price, scale, inverse);
    }
}
