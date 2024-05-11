// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IVaultPriceFeed} from "./interfaces/IVaultPriceFeed.sol";
import {IPriceFeed} from "../oracle/interfaces/IPriceFeed.sol";
import {ISecondaryPriceFeed} from "../oracle/interfaces/ISecondaryPriceFeed.sol";
import {IChainlinkFlags} from "../oracle/interfaces/IChainlinkFlags.sol";

import {Constants} from "./libraries/helpers/Constants.sol";

contract VaultPriceFeed is OwnableUpgradeable, IVaultPriceFeed {
    using MathUpgradeable for uint256;

    // Identifier of the Sequencer offline flag on the Flags contract
    address private constant FLAG_ARBITRUM_SEQ_OFFLINE =
        address(
            bytes20(
                bytes32(
                    uint256(keccak256("chainlink.flags.arbitrum-seq-offline")) -
                        1
                )
            )
        );
    address public chainlinkFlags;

    bool public isSecondaryPriceEnabled;
    bool public useV2Pricing;
    bool public favorPrimaryPrice;
    uint256 public priceSampleSpace;
    uint256 public maxStrictPriceDeviation;
    address public secondaryPriceFeed;
    uint256 public spreadThresholdBasisPoints;

    mapping(address => address) public priceFeeds;
    mapping(address => uint256) public priceDecimals;
    mapping(address => uint256) public spreadBasisPoints;
    // Chainlink can return prices for stablecoins
    // that differs from 1 USD by a larger percentage than stableSwapFeeBasisPoints
    // we use strictStableTokens to cap the price to 1 USD
    // this allows us to configure stablecoins like DAI as being a stableToken
    // while not being a strictStableToken
    mapping(address => bool) public strictStableTokens;

    mapping(address => uint256) public override adjustmentBasisPoints;
    mapping(address => bool) public override isAdjustmentAdditive;
    mapping(address => uint256) public lastAdjustmentTimings;

    function initialize() external initializer {
        __Ownable_init();

        isSecondaryPriceEnabled = true;
        useV2Pricing = false;
        favorPrimaryPrice = false;
    }

    function setChainlinkFlags(address _chainlinkFlags) external onlyOwner {
        chainlinkFlags = _chainlinkFlags;
    }

    function setAdjustment(
        address _token,
        bool _isAdditive,
        uint256 _adjustmentBps
    ) external override onlyOwner {
        require(
            lastAdjustmentTimings[_token] + Constants.MAX_ADJUSTMENT_INTERVAL <
                block.timestamp,
            "VaultPriceFeed: adjustment frequency exceeded"
        );
        require(
            _adjustmentBps <= Constants.MAX_ADJUSTMENT_BASIS_POINTS,
            "invalid _adjustmentBps"
        );
        isAdjustmentAdditive[_token] = _isAdditive;
        adjustmentBasisPoints[_token] = _adjustmentBps;
        lastAdjustmentTimings[_token] = block.timestamp;
    }

    function setUseV2Pricing(bool _useV2Pricing) external override onlyOwner {
        useV2Pricing = _useV2Pricing;
    }

    function setIsSecondaryPriceEnabled(
        bool _isEnabled
    ) external override onlyOwner {
        isSecondaryPriceEnabled = _isEnabled;
    }

    function setSecondaryPriceFeed(
        address _secondaryPriceFeed
    ) external onlyOwner {
        secondaryPriceFeed = _secondaryPriceFeed;
    }

    function setSpreadBasisPoints(
        address _token,
        uint256 _spreadBasisPoints
    ) external override onlyOwner {
        require(
            _spreadBasisPoints <= Constants.MAX_SPREAD_BASIS_POINTS,
            "VaultPriceFeed: invalid _spreadBasisPoints"
        );
        spreadBasisPoints[_token] = _spreadBasisPoints;
    }

    function setSpreadThresholdBasisPoints(
        uint256 _spreadThresholdBasisPoints
    ) external override onlyOwner {
        spreadThresholdBasisPoints = _spreadThresholdBasisPoints;
    }

    function setFavorPrimaryPrice(
        bool _favorPrimaryPrice
    ) external override onlyOwner {
        favorPrimaryPrice = _favorPrimaryPrice;
    }

    function setPriceSampleSpace(
        uint256 _priceSampleSpace
    ) external override onlyOwner {
        require(
            _priceSampleSpace > 0,
            "VaultPriceFeed: invalid _priceSampleSpace"
        );
        priceSampleSpace = _priceSampleSpace;
    }

    function setMaxStrictPriceDeviation(
        uint256 _maxStrictPriceDeviation
    ) external override onlyOwner {
        maxStrictPriceDeviation = _maxStrictPriceDeviation;
    }

    function setTokenConfig(
        address _token,
        address _priceFeed,
        uint256 _priceDecimals,
        bool _isStrictStable
    ) external override onlyOwner {
        priceFeeds[_token] = _priceFeed;
        priceDecimals[_token] = _priceDecimals;
        strictStableTokens[_token] = _isStrictStable;
    }

    function getPrice(
        address _token,
        bool _maximise
    ) public view override returns (uint256) {
        uint256 price = useV2Pricing
            ? getPriceV2(_token, _maximise)
            : getPriceV1(_token, _maximise);

        uint256 adjustmentBps = adjustmentBasisPoints[_token];
        if (adjustmentBps > 0) {
            bool isAdditive = isAdjustmentAdditive[_token];
            if (isAdditive) {
                price =
                    (price * (Constants.PERCENTAGE_FACTOR + adjustmentBps)) /
                    Constants.PERCENTAGE_FACTOR;
            } else {
                price =
                    (price * (Constants.PERCENTAGE_FACTOR - adjustmentBps)) /
                    Constants.PERCENTAGE_FACTOR;
            }
        }

        return price;
    }

    function getPriceV1(
        address _token,
        bool _maximise
    ) public view returns (uint256) {
        uint256 price = getPrimaryPrice(_token, _maximise);

        if (isSecondaryPriceEnabled) {
            price = getSecondaryPrice(_token, price, _maximise);
        }

        if (strictStableTokens[_token]) {
            uint256 delta = price > Constants.ONE_ETH
                ? price - Constants.ONE_ETH
                : Constants.ONE_ETH - price;
            if (delta <= maxStrictPriceDeviation) {
                return Constants.ONE_ETH;
            }

            // if _maximise and price is e.g. 1.02, return 1.02
            if (_maximise && price > Constants.ONE_ETH) {
                return price;
            }

            // if !_maximise and price is e.g. 0.98, return 0.98
            if (!_maximise && price < Constants.ONE_ETH) {
                return price;
            }

            return Constants.ONE_ETH;
        }

        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return
                (price * (Constants.PERCENTAGE_FACTOR + _spreadBasisPoints)) /
                Constants.PERCENTAGE_FACTOR;
        }

        return
            (price * (Constants.PERCENTAGE_FACTOR - _spreadBasisPoints)) /
            Constants.PERCENTAGE_FACTOR;
    }

    function getPriceV2(
        address _token,
        bool _maximise
    ) public view returns (uint256) {
        uint256 price = getPrimaryPrice(_token, _maximise);

        if (isSecondaryPriceEnabled) {
            price = getSecondaryPrice(_token, price, _maximise);
        }

        if (strictStableTokens[_token]) {
            uint256 delta = price > Constants.ONE_ETH
                ? price - Constants.ONE_ETH
                : Constants.ONE_ETH - price;
            if (delta <= maxStrictPriceDeviation) {
                return Constants.ONE_ETH;
            }

            // if _maximise and price is e.g. 1.02, return 1.02
            if (_maximise && price > Constants.ONE_ETH) {
                return price;
            }

            // if !_maximise and price is e.g. 0.98, return 0.98
            if (!_maximise && price < Constants.ONE_ETH) {
                return price;
            }

            return Constants.ONE_ETH;
        }

        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return
                (price * (Constants.PERCENTAGE_FACTOR + _spreadBasisPoints)) /
                Constants.PERCENTAGE_FACTOR;
        }

        return
            (price * (Constants.PERCENTAGE_FACTOR - _spreadBasisPoints)) /
            Constants.PERCENTAGE_FACTOR;
    }

    function getLatestPrimaryPrice(
        address _token
    ) public view override returns (uint256) {
        address priceFeedAddress = priceFeeds[_token];
        require(
            priceFeedAddress != address(0),
            "VaultPriceFeed: invalid price feed"
        );

        IPriceFeed priceFeed = IPriceFeed(priceFeedAddress);

        int256 price = priceFeed.latestAnswer();
        require(price > 0, "VaultPriceFeed: invalid price");

        return uint256(price);
    }

    function getPrimaryPrice(
        address _token,
        bool _maximise
    ) public view override returns (uint256) {
        address priceFeedAddress = priceFeeds[_token];
        require(
            priceFeedAddress != address(0),
            "VaultPriceFeed: invalid price feed"
        );

        if (chainlinkFlags != address(0)) {
            bool isRaised = IChainlinkFlags(chainlinkFlags).getFlag(
                FLAG_ARBITRUM_SEQ_OFFLINE
            );
            if (isRaised) {
                // If flag is raised we shouldn't perform any critical operations
                revert("Chainlink feeds are not being updated");
            }
        }

        IPriceFeed priceFeed = IPriceFeed(priceFeedAddress);

        uint256 price = 0;
        uint80 roundId = priceFeed.latestRound();

        for (uint80 i = 0; i < priceSampleSpace; i++) {
            if (roundId <= i) {
                break;
            }
            uint256 p;

            if (i == 0) {
                int256 _p = priceFeed.latestAnswer();
                require(_p > 0, "VaultPriceFeed: invalid price");
                p = uint256(_p);
            } else {
                (, int256 _p, , , ) = priceFeed.getRoundData(roundId - i);
                require(_p > 0, "VaultPriceFeed: invalid price");
                p = uint256(_p);
            }

            if (price == 0) {
                price = p;
                continue;
            }

            if (_maximise && p > price) {
                price = p;
                continue;
            }

            if (!_maximise && p < price) {
                price = p;
            }
        }

        require(price > 0, "VaultPriceFeed: could not fetch price");
        // normalise price precision
        uint256 _priceDecimals = priceDecimals[_token];
        return (price * Constants.PRICE_PRECISION) / 10 ** _priceDecimals;
    }

    function getSecondaryPrice(
        address _token,
        uint256 _referencePrice,
        bool _maximise
    ) public view returns (uint256) {
        if (secondaryPriceFeed == address(0)) {
            return _referencePrice;
        }
        return
            ISecondaryPriceFeed(secondaryPriceFeed).getPrice(
                _token,
                _referencePrice,
                _maximise
            );
    }
}
