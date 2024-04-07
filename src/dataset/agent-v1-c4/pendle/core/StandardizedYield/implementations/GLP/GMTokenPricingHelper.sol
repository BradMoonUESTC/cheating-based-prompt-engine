// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../../../libraries/BoringOwnableUpgradeable.sol";
import {AggregatorV2V3Interface as IChainlinkAggregator} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

interface IGMXV2Oracle {
    function getPriceFeedMultiplier(address dataStore, address token) external view returns (uint256);
}

interface IGMXV2DataStore {
    function getAddress(bytes32 key) external view returns (address);
}

interface IGMXV2Reader {
    struct PriceProps {
        uint256 min;
        uint256 max;
    }
    struct MarketProps {
        address marketToken;
        address indexToken;
        address longToken;
        address shortToken;
    }
    struct MarketPoolValueInfoProps {
        int256 poolValue;
        int256 longPnl;
        int256 shortPnl;
        int256 netPnl;
        uint256 longTokenAmount;
        uint256 shortTokenAmount;
        uint256 longTokenUsd;
        uint256 shortTokenUsd;
        uint256 totalBorrowingFees;
        uint256 borrowingFeePoolFactor;
        uint256 impactPoolAmount;
    }

    function getMarketTokenPrice(
        address dataStore,
        MarketProps memory market,
        PriceProps memory indexTokenPrice,
        PriceProps memory longTokenPrice,
        PriceProps memory shortTokenPrice,
        bytes32 pnlFactorType,
        bool maximize
    ) external view returns (int256, MarketPoolValueInfoProps memory);
}

contract GMTokenPricingHelper is BoringOwnableUpgradeable, UUPSUpgradeable {
    uint256 constant FLOAT_PRECISION = 10 ** 30;
    bytes32 public constant MARKET_TOKEN = keccak256(abi.encode("MARKET_TOKEN"));
    bytes32 public constant INDEX_TOKEN = keccak256(abi.encode("INDEX_TOKEN"));
    bytes32 public constant LONG_TOKEN = keccak256(abi.encode("LONG_TOKEN"));
    bytes32 public constant SHORT_TOKEN = keccak256(abi.encode("SHORT_TOKEN"));
    bytes32 public constant PRICE_FEED = keccak256(abi.encode("PRICE_FEED"));
    bytes32 public constant MAX_PNL_FACTOR_FOR_DEPOSITS = keccak256(abi.encode("MAX_PNL_FACTOR_FOR_DEPOSITS"));

    IGMXV2Oracle constant oracle = IGMXV2Oracle(0xa11B501c2dd83Acd29F6727570f2502FAaa617F2);
    IGMXV2DataStore constant datastore = IGMXV2DataStore(0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8);
    IGMXV2Reader constant reader = IGMXV2Reader(0xf60becbba223EEA9495Da3f606753867eC10d139);

    constructor() initializer {}

    function getPrice(address gm) external view returns (uint256) {
        IGMXV2Reader.MarketProps memory prop = _getMarketProps(datastore, gm);
        (int256 marketPrice, ) = reader.getMarketTokenPrice(
            address(datastore),
            prop,
            _getTokenPrice(prop.indexToken),
            _getTokenPrice(prop.longToken),
            _getTokenPrice(prop.shortToken),
            MAX_PNL_FACTOR_FOR_DEPOSITS,
            true
        );

        // price from gmx is in based 30 when token decimals is 18
        // while GM token should always be 18 decimals
        return uint256(marketPrice) / 10 ** 12;
    }

    function _getTokenPrice(address token) internal view returns (IGMXV2Reader.PriceProps memory price) {
        (, int256 latestAnswer, , , ) = IChainlinkAggregator(datastore.getAddress(_priceFeedKey(token)))
            .latestRoundData();

        uint256 multipler = oracle.getPriceFeedMultiplier(address(datastore), token);
        uint256 adjustedPrice = (uint256(latestAnswer) * multipler) / FLOAT_PRECISION;
        return IGMXV2Reader.PriceProps({min: adjustedPrice, max: adjustedPrice});
    }

    function _getMarketProps(
        IGMXV2DataStore dataStore,
        address key
    ) internal view returns (IGMXV2Reader.MarketProps memory) {
        IGMXV2Reader.MarketProps memory prop;
        prop.marketToken = dataStore.getAddress(keccak256(abi.encode(key, MARKET_TOKEN)));
        prop.indexToken = dataStore.getAddress(keccak256(abi.encode(key, INDEX_TOKEN)));
        prop.longToken = dataStore.getAddress(keccak256(abi.encode(key, LONG_TOKEN)));
        prop.shortToken = dataStore.getAddress(keccak256(abi.encode(key, SHORT_TOKEN)));
        return prop;
    }

    function _priceFeedKey(address token) internal pure returns (bytes32) {
        return keccak256(abi.encode(PRICE_FEED, token));
    }

    /////////////////// UPGRADABLE LOGIC ///////////////////////////
    function initialize() external initializer {
        __BoringOwnable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
