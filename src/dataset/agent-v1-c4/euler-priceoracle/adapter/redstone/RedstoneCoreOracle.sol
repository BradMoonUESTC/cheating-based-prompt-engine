// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {RedstoneDefaultsLib} from "@redstone/evm-connector/core/RedstoneDefaultsLib.sol";
import {PrimaryProdDataServiceConsumerBase} from
    "@redstone/evm-connector/data-services/PrimaryProdDataServiceConsumerBase.sol";
import {BaseAdapter, Errors, IPriceOracle} from "src/adapter/BaseAdapter.sol";
import {ScaleUtils, Scale} from "src/lib/ScaleUtils.sol";

/// @title RedstoneCoreOracle
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Adapter for Redstone pull-based price feeds.
contract RedstoneCoreOracle is PrimaryProdDataServiceConsumerBase, BaseAdapter {
    /// @notice Struct holding information about the latest price.
    struct Cache {
        /// @notice The Redstone price.
        uint208 price;
        /// @notice The timestamp contained within the price data packages.
        uint48 priceTimestamp;
    }

    /// @notice The maximum permitted value for `maxStaleness`.
    uint256 internal constant MAX_STALENESS_UPPER_BOUND = 5 minutes;
    /// @inheritdoc IPriceOracle
    string public constant name = "RedstoneCoreOracle";
    /// @notice The address of the base asset corresponding to the feed.
    address public immutable base;
    /// @notice The address of the quote asset corresponding to the feed.
    address public immutable quote;
    /// @notice The identifier of the price feed.
    /// @dev See https://app.redstone.finance/#/app/data-services/redstone-primary-prod
    bytes32 public immutable feedId;
    /// @notice The decimals of the Redstone price feed.
    /// @dev Redstone price feeds have 8 decimals by default, however certain exceptions exist.
    uint8 public immutable feedDecimals;
    /// @notice The maximum allowed age of the Redstone price.
    /// @dev Compares `block.timestamp` against the timestamp of the Redstone data package.
    uint256 public immutable maxStaleness;
    /// @notice The scale factors used for decimal conversions.
    Scale internal immutable scale;
    /// @notice The last updated Redstone price and its timestamp.
    /// @dev The cache is updated in `updatePrice`.
    Cache public cache;

    /// @notice The cache timestamp was updated.
    /// @param price The Redstone price.
    /// @param priceTimestamp The timestamp contained within the price data packages.
    event CacheUpdated(uint256 price, uint256 priceTimestamp);

    /// @notice Deploy a RedstoneCoreOracle.
    /// @param _base The address of the base asset corresponding to the feed.
    /// @param _quote The address of the quote asset corresponding to the feed.
    /// @param _feedId The identifier of the price feed.
    /// @param _feedDecimals The decimals of the price feed.
    /// @param _maxStaleness The maximum allowed age of the Redstone price in `updatePrice`.
    /// @dev Since Redstone prices are verified locally, callers can pass data up to `maxStaleness` seconds old.
    /// If `maxStaleness` is too short, the update transaction may revert.
    constructor(address _base, address _quote, bytes32 _feedId, uint8 _feedDecimals, uint256 _maxStaleness) {
        if (_maxStaleness > MAX_STALENESS_UPPER_BOUND) revert Errors.PriceOracle_InvalidConfiguration();

        base = _base;
        quote = _quote;
        feedId = _feedId;
        feedDecimals = _feedDecimals;
        maxStaleness = _maxStaleness;
        uint8 baseDecimals = _getDecimals(base);
        uint8 quoteDecimals = _getDecimals(quote);
        scale = ScaleUtils.calcScale(baseDecimals, quoteDecimals, _feedDecimals);
    }

    /// @notice Ingest a Redstone payload, decode and verify it, and cache the price in storage.
    /// @param timestamp The expected timestamp of the Redstone payload. All data packages must have this timestamp.
    /// @dev Redstone payload must be appended at the end of the abi-encoded calldata to this function.
    /// Decoding and validation inherited from `PrimaryProdDataServiceConsumerBase`.
    /// The price timestamp must lie in the defined acceptance range relative to `block.timestamp`.
    /// Note: The Redstone SDK allows the price timestamp to be up to 1 minute in the future.
    function updatePrice(uint48 timestamp) external {
        // The cache can only be updated if it has a more recent timestamp.
        Cache memory _cache = cache;
        if (timestamp <= _cache.priceTimestamp) return; // Do not revert to avoid DoS attacks.

        if (block.timestamp > timestamp) {
            // Verify that the timestamp is not too stale.
            uint256 staleness = block.timestamp - timestamp;
            if (staleness > maxStaleness) {
                revert Errors.PriceOracle_TooStale(staleness, maxStaleness);
            }
        } else if (timestamp - block.timestamp > RedstoneDefaultsLib.DEFAULT_MAX_DATA_TIMESTAMP_AHEAD_SECONDS) {
            // Verify that the timestamp is not too long in the future (1 min). Redstone SDK explicitly allows this.
            revert Errors.PriceOracle_InvalidAnswer();
        }

        // Optimistically update the price timestamp.
        cache = Cache({price: _cache.price, priceTimestamp: timestamp});

        // Calls `validateTimestamp` for every package, comparing the extracted timestamp against the price timestamp.
        uint256 price = getOracleNumericValueFromTxMsg(feedId);
        if (price == 0) revert Errors.PriceOracle_InvalidAnswer();
        if (price > type(uint208).max) revert Errors.PriceOracle_Overflow();
        cache = Cache({price: uint208(price), priceTimestamp: timestamp});
        emit CacheUpdated(price, timestamp);
    }

    /// @notice Validate the timestamp of a Redstone signed price data package.
    /// @param timestampMillis Data package timestamp in milliseconds.
    /// @dev Internally called in `updatePrice` for every signed data package in the payload.
    function validateTimestamp(uint256 timestampMillis) public view virtual override {
        uint256 timestamp = timestampMillis / 1000;
        if (timestamp != cache.priceTimestamp) revert Errors.PriceOracle_InvalidAnswer();
    }

    /// @notice Get the quote from the Redstone feed.
    /// @param inAmount The amount of `base` to convert.
    /// @param _base The token that is being priced.
    /// @param _quote The token that is the unit of account.
    /// @return The converted amount using the Redstone feed.
    function _getQuote(uint256 inAmount, address _base, address _quote) internal view override returns (uint256) {
        bool inverse = ScaleUtils.getDirectionOrRevert(_base, base, _quote, quote);

        Cache memory _cache = cache;
        if (block.timestamp > _cache.priceTimestamp) {
            // No need to check price timestamps in the future as they can only get more recent with time.
            uint256 priceStaleness = block.timestamp - _cache.priceTimestamp;
            if (priceStaleness > maxStaleness) {
                revert Errors.PriceOracle_TooStale(priceStaleness, maxStaleness);
            }
        }
        return ScaleUtils.calcOutAmount(inAmount, _cache.price, scale, inverse);
    }
}
