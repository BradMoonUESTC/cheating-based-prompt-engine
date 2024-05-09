// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ISecondaryPriceFeed} from "./interfaces/ISecondaryPriceFeed.sol";
import {IFastPriceFeed} from "./interfaces/IFastPriceFeed.sol";
import {IFastPriceEvents} from "./interfaces/IFastPriceEvents.sol";
import {IVaultPriceFeed} from "../core/interfaces/IVaultPriceFeed.sol";
import {IPositionRouter} from "../core/interfaces/IPositionRouter.sol";
import {IPositionManager} from "../core/interfaces/IPositionManager.sol";

import {Constants} from "../core/libraries/helpers/Constants.sol";

contract FastPriceFeed is
    ISecondaryPriceFeed,
    IFastPriceFeed,
    OwnableUpgradeable
{
    using MathUpgradeable for uint256;

    // fit data in a uint256 slot to save gas costs
    struct PriceDataItem {
        uint160 refPrice; // Chainlink price
        uint32 refTime; // last updated at time
        uint32 cumulativeRefDelta; // cumulative Chainlink price delta
        uint32 cumulativeFastDelta; // cumulative fast price delta
    }

    bool public isSpreadEnabled;

    address public vaultPriceFeed;
    address public fastPriceEvents;

    uint256 public override lastUpdatedAt;
    uint256 public override lastUpdatedBlock;

    uint256 public priceDuration;
    uint256 public maxPriceUpdateDelay;
    uint256 public spreadBasisPointsIfInactive;
    uint256 public spreadBasisPointsIfChainError;
    uint256 public minBlockInterval;
    uint256 public maxTimeDeviation;

    uint256 public priceDataInterval;

    // allowed deviation from primary price
    uint256 public maxDeviationBasisPoints;

    uint256 public minAuthorizations;
    uint256 public disableFastPriceVoteCount;

    mapping(address => bool) public isUpdater;
    mapping(address => bool) public isSigner;

    mapping(address => uint256) public prices;
    mapping(address => PriceDataItem) public priceData;
    mapping(address => uint256) public maxCumulativeDeltaDiffs;

    mapping(address => bool) public disableFastPriceVotes;

    // array of tokens used in setCompactedPrices, saves L1 calldata gas costs
    address[] public tokens;
    // array of tokenPrecisions used in setCompactedPrices, saves L1 calldata gas costs
    // if the token price will be sent with 3 decimals, then tokenPrecision for that token
    // should be 10 ** 3
    uint256[] public tokenPrecisions;

    event DisableFastPrice(address signer);
    event EnableFastPrice(address signer);
    event PriceData(
        address token,
        uint256 refPrice,
        uint256 fastPrice,
        uint256 cumulativeRefDelta,
        uint256 cumulativeFastDelta
    );
    event MaxCumulativeDeltaDiffExceeded(
        address token,
        uint256 refPrice,
        uint256 fastPrice,
        uint256 cumulativeRefDelta,
        uint256 cumulativeFastDelta
    );

    modifier onlySigner() {
        require(isSigner[msg.sender], "FastPriceFeed: forbidden");
        _;
    }

    modifier onlyUpdater() {
        require(isUpdater[msg.sender], "FastPriceFeed: forbidden");
        _;
    }

    function initialize(
        uint256 _priceDuration,
        uint256 _maxPriceUpdateDelay,
        uint256 _minBlockInterval,
        uint256 _maxDeviationBasisPoints,
        address _fastPriceEvents,
        uint256 _minAuthorizations,
        address[] memory _updaters,
        address[] memory _signers
    ) external initializer {
        __Ownable_init();
        require(
            _priceDuration <= Constants.MAX_PRICE_DURATION,
            "FastPriceFeed: invalid _priceDuration"
        );

        isSpreadEnabled = false;

        priceDuration = _priceDuration;
        maxPriceUpdateDelay = _maxPriceUpdateDelay;
        minBlockInterval = _minBlockInterval;
        maxDeviationBasisPoints = _maxDeviationBasisPoints;
        fastPriceEvents = _fastPriceEvents;

        minAuthorizations = _minAuthorizations;

        for (uint256 i = 0; i < _updaters.length; i++) {
            address updater = _updaters[i];
            isUpdater[updater] = true;
        }

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            isSigner[signer] = true;
        }
    }

    function setUpdater(
        address _account,
        bool _isActive
    ) external override onlyOwner {
        isUpdater[_account] = _isActive;
    }

    function setSigner(
        address _account,
        bool _isActive
    ) external override onlyOwner {
        isSigner[_account] = _isActive;
    }

    function setFastPriceEvents(address _fastPriceEvents) external onlyOwner {
        fastPriceEvents = _fastPriceEvents;
    }

    function setVaultPriceFeed(
        address _vaultPriceFeed
    ) external override onlyOwner {
        vaultPriceFeed = _vaultPriceFeed;
    }

    function setMaxTimeDeviation(uint256 _maxTimeDeviation) external onlyOwner {
        maxTimeDeviation = _maxTimeDeviation;
    }

    function setPriceDuration(
        uint256 _priceDuration
    ) external override onlyOwner {
        require(
            _priceDuration <= Constants.MAX_PRICE_DURATION,
            "FastPriceFeed: invalid _priceDuration"
        );
        priceDuration = _priceDuration;
    }

    function setMaxPriceUpdateDelay(
        uint256 _maxPriceUpdateDelay
    ) external override onlyOwner {
        maxPriceUpdateDelay = _maxPriceUpdateDelay;
    }

    function setSpreadBasisPointsIfInactive(
        uint256 _spreadBasisPointsIfInactive
    ) external override onlyOwner {
        spreadBasisPointsIfInactive = _spreadBasisPointsIfInactive;
    }

    function setSpreadBasisPointsIfChainError(
        uint256 _spreadBasisPointsIfChainError
    ) external override onlyOwner {
        spreadBasisPointsIfChainError = _spreadBasisPointsIfChainError;
    }

    function setMinBlockInterval(
        uint256 _minBlockInterval
    ) external override onlyOwner {
        minBlockInterval = _minBlockInterval;
    }

    function setIsSpreadEnabled(
        bool _isSpreadEnabled
    ) external override onlyOwner {
        isSpreadEnabled = _isSpreadEnabled;
    }

    function setLastUpdatedAt(uint256 _lastUpdatedAt) external onlyOwner {
        lastUpdatedAt = _lastUpdatedAt;
    }

    function setMaxDeviationBasisPoints(
        uint256 _maxDeviationBasisPoints
    ) external override onlyOwner {
        maxDeviationBasisPoints = _maxDeviationBasisPoints;
    }

    function setMaxCumulativeDeltaDiffs(
        address[] memory _tokens,
        uint256[] memory _maxCumulativeDeltaDiffs
    ) external override onlyOwner {
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            maxCumulativeDeltaDiffs[token] = _maxCumulativeDeltaDiffs[i];
        }
    }

    function setPriceDataInterval(
        uint256 _priceDataInterval
    ) external override onlyOwner {
        priceDataInterval = _priceDataInterval;
    }

    function setMinAuthorizations(
        uint256 _minAuthorizations
    ) external onlyOwner {
        minAuthorizations = _minAuthorizations;
    }

    function setTokens(
        address[] memory _tokens,
        uint256[] memory _tokenPrecisions
    ) external onlyOwner {
        require(
            _tokens.length == _tokenPrecisions.length,
            "FastPriceFeed: invalid lengths"
        );
        tokens = _tokens;
        tokenPrecisions = _tokenPrecisions;
    }

    function setPrices(
        address[] memory _tokens,
        uint256[] memory _prices,
        uint256 _timestamp
    ) external onlyUpdater {
        _setPrices(_tokens, _prices, _timestamp);
    }

    function _setPrices(
        address[] memory _tokens,
        uint256[] memory _prices,
        uint256 _timestamp
    ) private {
        bool shouldUpdate = _setLastUpdatedValues(_timestamp);

        if (shouldUpdate) {
            address _fastPriceEvents = fastPriceEvents;
            address _vaultPriceFeed = vaultPriceFeed;

            for (uint256 i = 0; i < _tokens.length; i++) {
                address token = _tokens[i];
                _setPrice(token, _prices[i], _vaultPriceFeed, _fastPriceEvents);
            }
        }
    }

    function setCompactedPrices(
        uint256[] memory _priceBitArray,
        uint256 _timestamp
    ) external onlyUpdater {
        bool shouldUpdate = _setLastUpdatedValues(_timestamp);

        if (shouldUpdate) {
            address _fastPriceEvents = fastPriceEvents;
            address _vaultPriceFeed = vaultPriceFeed;

            for (uint256 i = 0; i < _priceBitArray.length; i++) {
                uint256 priceBits = _priceBitArray[i];

                for (uint256 j = 0; j < 8; j++) {
                    uint256 index = i * 8 + j;
                    if (index >= tokens.length) {
                        return;
                    }

                    uint256 startBit = 32 * j;
                    uint256 price = (priceBits >> startBit) &
                        Constants.BITMASK_32;

                    address token = tokens[i * 8 + j];
                    uint256 tokenPrecision = tokenPrecisions[i * 8 + j];
                    uint256 adjustedPrice = (price *
                        (Constants.PRICE_PRECISION)) / (tokenPrecision);

                    _setPrice(
                        token,
                        adjustedPrice,
                        _vaultPriceFeed,
                        _fastPriceEvents
                    );
                }
            }
        }
    }

    function setPricesWithBits(
        uint256 _priceBits,
        uint256 _timestamp
    ) external onlyUpdater {
        _setPricesWithBits(_priceBits, _timestamp);
    }

    // market order
    function setPricesWithBitsAndExecute(
        address _positionRouter,
        uint256 _priceBits,
        uint256 _timestamp,
        uint256 _endIndexForIncreasePositions,
        uint256 _endIndexForDecreasePositions,
        uint256 _maxIncreasePositions,
        uint256 _maxDecreasePositions
    ) external onlyUpdater {
        _setPricesWithBits(_priceBits, _timestamp);

        IPositionRouter positionRouter = IPositionRouter(_positionRouter);
        uint256 maxEndIndexForIncrease = positionRouter
            .increasePositionRequestKeysStart() + _maxIncreasePositions;
        uint256 maxEndIndexForDecrease = positionRouter
            .decreasePositionRequestKeysStart() + _maxDecreasePositions;

        if (_endIndexForIncreasePositions > maxEndIndexForIncrease) {
            _endIndexForIncreasePositions = maxEndIndexForIncrease;
        }

        if (_endIndexForDecreasePositions > maxEndIndexForDecrease) {
            _endIndexForDecreasePositions = maxEndIndexForDecrease;
        }

        positionRouter.executeIncreasePositions(
            _endIndexForIncreasePositions,
            payable(msg.sender)
        );
        positionRouter.executeDecreasePositions(
            _endIndexForDecreasePositions,
            payable(msg.sender)
        );
    }

    // market order
    function setPricesAndExecute(
        address _positionRouter,
        address[] memory _tokens,
        uint256[] memory _prices,
        uint256 _timestamp,
        uint256 _endIndexForIncreasePositions,
        uint256 _endIndexForDecreasePositions,
        uint256 _maxIncreasePositions,
        uint256 _maxDecreasePositions
    ) external onlyUpdater {
        _setPrices(_tokens, _prices, _timestamp);

        IPositionRouter positionRouter = IPositionRouter(_positionRouter);
        uint256 maxEndIndexForIncrease = positionRouter
            .increasePositionRequestKeysStart() + _maxIncreasePositions;
        uint256 maxEndIndexForDecrease = positionRouter
            .decreasePositionRequestKeysStart() + _maxDecreasePositions;

        if (_endIndexForIncreasePositions > maxEndIndexForIncrease) {
            _endIndexForIncreasePositions = maxEndIndexForIncrease;
        }

        if (_endIndexForDecreasePositions > maxEndIndexForDecrease) {
            _endIndexForDecreasePositions = maxEndIndexForDecrease;
        }

        positionRouter.executeIncreasePositions(
            _endIndexForIncreasePositions,
            payable(msg.sender)
        );
        positionRouter.executeDecreasePositions(
            _endIndexForDecreasePositions,
            payable(msg.sender)
        );
    }

    // limit order
    function setPricesWithBitsAndExecute(
        address _positionManager,
        uint256 _priceBits,
        uint256 _timestamp,
        address _account,
        uint256 _orderIndex,
        bool _isIncrease
    ) external onlyUpdater {
        _setPricesWithBits(_priceBits, _timestamp);

        IPositionManager positionManager = IPositionManager(_positionManager);

        if (_isIncrease) {
            positionManager.executeIncreaseOrder(
                _account,
                _orderIndex,
                payable(msg.sender)
            );
        } else {
            positionManager.executeDecreaseOrder(
                _account,
                _orderIndex,
                payable(msg.sender)
            );
        }
    }

    // limit order
    function setPricesAndExecute(
        address _positionManager,
        address[] memory _tokens,
        uint256[] memory _prices,
        uint256 _timestamp,
        address _account,
        uint256 _orderIndex,
        bool _isIncrease
    ) external onlyUpdater {
        _setPrices(_tokens, _prices, _timestamp);

        IPositionManager positionManager = IPositionManager(_positionManager);

        if (_isIncrease) {
            positionManager.executeIncreaseOrder(
                _account,
                _orderIndex,
                payable(msg.sender)
            );
        } else {
            positionManager.executeDecreaseOrder(
                _account,
                _orderIndex,
                payable(msg.sender)
            );
        }
    }

    function disableFastPrice() external onlySigner {
        require(
            !disableFastPriceVotes[msg.sender],
            "FastPriceFeed: already voted"
        );
        disableFastPriceVotes[msg.sender] = true;
        disableFastPriceVoteCount = disableFastPriceVoteCount + 1;

        emit DisableFastPrice(msg.sender);
    }

    function enableFastPrice() external onlySigner {
        require(
            disableFastPriceVotes[msg.sender],
            "FastPriceFeed: already enabled"
        );
        disableFastPriceVotes[msg.sender] = false;
        disableFastPriceVoteCount = disableFastPriceVoteCount - 1;

        emit EnableFastPrice(msg.sender);
    }

    // under regular operation, the fastPrice (prices[token]) is returned and there is no spread returned from this function,
    // though VaultPriceFeed might apply its own spread
    //
    // if the fastPrice has not been updated within priceDuration then it is ignored and only _refPrice with a spread is used (spread: spreadBasisPointsIfInactive)
    // in case the fastPrice has not been updated for maxPriceUpdateDelay then the _refPrice with a larger spread is used (spread: spreadBasisPointsIfChainError)
    //
    // there will be a spread from the _refPrice to the fastPrice in the following cases:
    // - in case isSpreadEnabled is set to true
    // - in case the maxDeviationBasisPoints between _refPrice and fastPrice is exceeded
    // - in case watchers flag an issue
    // - in case the cumulativeFastDelta exceeds the cumulativeRefDelta by the maxCumulativeDeltaDiff
    function getPrice(
        address _token,
        uint256 _refPrice,
        bool _maximise
    ) external view override returns (uint256) {
        if (block.timestamp > lastUpdatedAt + (maxPriceUpdateDelay)) {
            if (_maximise) {
                return
                    (_refPrice *
                        (Constants.PERCENTAGE_FACTOR +
                            (spreadBasisPointsIfChainError))) /
                    (Constants.PERCENTAGE_FACTOR);
            }

            return
                (_refPrice *
                    (Constants.PERCENTAGE_FACTOR -
                        (spreadBasisPointsIfChainError))) /
                (Constants.PERCENTAGE_FACTOR);
        }

        if (block.timestamp > lastUpdatedAt + (priceDuration)) {
            if (_maximise) {
                return
                    (_refPrice *
                        (Constants.PERCENTAGE_FACTOR +
                            (spreadBasisPointsIfInactive))) /
                    (Constants.PERCENTAGE_FACTOR);
            }

            return
                (_refPrice *
                    (Constants.PERCENTAGE_FACTOR -
                        (spreadBasisPointsIfInactive))) /
                (Constants.PERCENTAGE_FACTOR);
        }

        uint256 fastPrice = prices[_token];
        if (fastPrice == 0) {
            return _refPrice;
        }

        uint256 diffBasisPoints = _refPrice > fastPrice
            ? _refPrice - (fastPrice)
            : fastPrice - (_refPrice);
        diffBasisPoints =
            (diffBasisPoints * (Constants.PERCENTAGE_FACTOR)) /
            (_refPrice);

        // create a spread between the _refPrice and the fastPrice if the maxDeviationBasisPoints is exceeded
        // or if watchers have flagged an issue with the fast price
        bool hasSpread = !favorFastPrice(_token) ||
            diffBasisPoints > maxDeviationBasisPoints;

        if (hasSpread) {
            // return the higher of the two prices
            if (_maximise) {
                return _refPrice > fastPrice ? _refPrice : fastPrice;
            }

            // return the lower of the two prices
            return _refPrice < fastPrice ? _refPrice : fastPrice;
        }

        return fastPrice;
    }

    function favorFastPrice(address _token) public view returns (bool) {
        if (isSpreadEnabled) {
            return false;
        }

        if (disableFastPriceVoteCount >= minAuthorizations) {
            // force a spread if watchers have flagged an issue with the fast price
            return false;
        }

        (
            ,
            ,
            /* uint256 prevRefPrice */ /* uint256 refTime */ uint256 cumulativeRefDelta,
            uint256 cumulativeFastDelta
        ) = getPriceData(_token);
        if (
            cumulativeFastDelta > cumulativeRefDelta &&
            cumulativeFastDelta - (cumulativeRefDelta) >
            maxCumulativeDeltaDiffs[_token]
        ) {
            // force a spread if the cumulative delta for the fast price feed exceeds the cumulative delta
            // for the Chainlink price feed by the maxCumulativeDeltaDiff allowed
            return false;
        }

        return true;
    }

    function getPriceData(
        address _token
    ) public view returns (uint256, uint256, uint256, uint256) {
        PriceDataItem memory data = priceData[_token];
        return (
            uint256(data.refPrice),
            uint256(data.refTime),
            uint256(data.cumulativeRefDelta),
            uint256(data.cumulativeFastDelta)
        );
    }

    function _setPricesWithBits(
        uint256 _priceBits,
        uint256 _timestamp
    ) private {
        bool shouldUpdate = _setLastUpdatedValues(_timestamp);

        if (shouldUpdate) {
            address _fastPriceEvents = fastPriceEvents;
            address _vaultPriceFeed = vaultPriceFeed;

            for (uint256 j = 0; j < 8; j++) {
                uint256 index = j;
                if (index >= tokens.length) {
                    return;
                }

                uint256 startBit = 32 * j;
                uint256 price = (_priceBits >> startBit) & Constants.BITMASK_32;

                address token = tokens[j];
                uint256 tokenPrecision = tokenPrecisions[j];
                uint256 adjustedPrice = (price * (Constants.PRICE_PRECISION)) /
                    (tokenPrecision);

                _setPrice(
                    token,
                    adjustedPrice,
                    _vaultPriceFeed,
                    _fastPriceEvents
                );
            }
        }
    }

    function _setPrice(
        address _token,
        uint256 _price,
        address _vaultPriceFeed,
        address _fastPriceEvents
    ) private {
        require(_price > 0, "FastPriceFeed: price is 0");
        if (_vaultPriceFeed != address(0)) {
            uint256 refPrice = IVaultPriceFeed(_vaultPriceFeed)
                .getLatestPrimaryPrice(_token);
            uint256 fastPrice = prices[_token];

            (
                uint256 prevRefPrice,
                uint256 refTime,
                uint256 cumulativeRefDelta,
                uint256 cumulativeFastDelta
            ) = getPriceData(_token);

            if (prevRefPrice > 0) {
                uint256 refDeltaAmount = refPrice > prevRefPrice
                    ? refPrice - (prevRefPrice)
                    : prevRefPrice - (refPrice);
                uint256 fastDeltaAmount = fastPrice > _price
                    ? fastPrice - (_price)
                    : _price - (fastPrice);

                // reset cumulative delta values if it is a new time window
                if (
                    refTime / (priceDataInterval) !=
                    block.timestamp / (priceDataInterval)
                ) {
                    cumulativeRefDelta = 0;
                    cumulativeFastDelta = 0;
                }

                cumulativeRefDelta =
                    cumulativeRefDelta +
                    ((refDeltaAmount * (Constants.CUMULATIVE_DELTA_PRECISION)) /
                        (prevRefPrice));
                cumulativeFastDelta =
                    cumulativeFastDelta +
                    ((fastDeltaAmount *
                        (Constants.CUMULATIVE_DELTA_PRECISION)) / (fastPrice));
            }

            if (
                cumulativeFastDelta > cumulativeRefDelta &&
                cumulativeFastDelta - (cumulativeRefDelta) >
                maxCumulativeDeltaDiffs[_token]
            ) {
                emit MaxCumulativeDeltaDiffExceeded(
                    _token,
                    refPrice,
                    fastPrice,
                    cumulativeRefDelta,
                    cumulativeFastDelta
                );
            }

            _setPriceData(
                _token,
                refPrice,
                cumulativeRefDelta,
                cumulativeFastDelta
            );
            emit PriceData(
                _token,
                refPrice,
                fastPrice,
                cumulativeRefDelta,
                cumulativeFastDelta
            );
        }

        prices[_token] = _price;
        _emitPriceEvent(_fastPriceEvents, _token, _price);
    }

    function _setPriceData(
        address _token,
        uint256 _refPrice,
        uint256 _cumulativeRefDelta,
        uint256 _cumulativeFastDelta
    ) private {
        require(
            _refPrice < Constants.MAX_REF_PRICE,
            "FastPriceFeed: invalid refPrice"
        );
        // skip validation of block.timestamp, it should only be out of range after the year 2100
        require(
            _cumulativeRefDelta < Constants.MAX_CUMULATIVE_REF_DELTA,
            "FastPriceFeed: invalid cumulativeRefDelta"
        );
        require(
            _cumulativeFastDelta < Constants.MAX_CUMULATIVE_FAST_DELTA,
            "FastPriceFeed: invalid cumulativeFastDelta"
        );

        priceData[_token] = PriceDataItem(
            uint160(_refPrice),
            uint32(block.timestamp),
            uint32(_cumulativeRefDelta),
            uint32(_cumulativeFastDelta)
        );
    }

    function _emitPriceEvent(
        address _fastPriceEvents,
        address _token,
        uint256 _price
    ) private {
        if (_fastPriceEvents == address(0)) {
            return;
        }

        IFastPriceEvents(_fastPriceEvents).emitPriceEvent(_token, _price);
    }

    function _setLastUpdatedValues(uint256 _timestamp) private returns (bool) {
        if (minBlockInterval > 0) {
            require(
                block.number - (lastUpdatedBlock) >= minBlockInterval,
                "FastPriceFeed: minBlockInterval not yet passed"
            );
        }

        uint256 _maxTimeDeviation = maxTimeDeviation;
        require(
            _timestamp > block.timestamp - (_maxTimeDeviation),
            "FastPriceFeed: _timestamp below allowed range"
        );
        require(
            _timestamp < block.timestamp + (_maxTimeDeviation),
            "FastPriceFeed: _timestamp exceeds allowed range"
        );

        // do not update prices if _timestamp is before the current lastUpdatedAt value
        if (_timestamp < lastUpdatedAt) {
            return false;
        }

        lastUpdatedAt = _timestamp;
        lastUpdatedBlock = block.number;

        return true;
    }
}
