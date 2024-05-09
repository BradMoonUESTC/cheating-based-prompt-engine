// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IShortsTracker} from "./interfaces/IShortsTracker.sol";
import {IVault} from "./interfaces/IVault.sol";

import {Constants} from "./libraries/helpers/Constants.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";

contract ShortsTracker is OwnableUpgradeable, IShortsTracker {
    using MathUpgradeable for uint256;

    event GlobalShortDataUpdated(
        address indexed token,
        uint256 globalShortSize,
        uint256 globalShortAveragePrice
    );

    IVault public vault;

    mapping(address => bool) public isHandler;
    mapping(bytes32 => bytes32) public data;

    mapping(address => uint256) public override globalShortAveragePrices;
    bool public override isGlobalShortDataReady;

    modifier onlyHandler() {
        require(isHandler[msg.sender], "ShortsTracker: forbidden");
        _;
    }

    function initialize(address _vault) external initializer {
        __Ownable_init();

        vault = IVault(_vault);
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        require(_handler != address(0), "ShortsTracker: invalid _handler");
        isHandler[_handler] = _isActive;
    }

    function _setGlobalShortAveragePrice(
        address _token,
        uint256 _averagePrice
    ) internal {
        globalShortAveragePrices[_token] = _averagePrice;
    }

    function setIsGlobalShortDataReady(bool value) external override onlyOwner {
        isGlobalShortDataReady = value;
    }

    function updateGlobalShortData(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _markPrice,
        bool _isIncrease
    ) external override onlyHandler {
        if (_isLong || _sizeDelta == 0) {
            return;
        }

        if (!isGlobalShortDataReady) {
            return;
        }

        (
            uint256 globalShortSize,
            uint256 globalShortAveragePrice
        ) = getNextGlobalShortData(
                _account,
                _collateralToken,
                _indexToken,
                _markPrice,
                _sizeDelta,
                _isIncrease
            );
        _setGlobalShortAveragePrice(_indexToken, globalShortAveragePrice);

        emit GlobalShortDataUpdated(
            _indexToken,
            globalShortSize,
            globalShortAveragePrice
        );
    }

    function getGlobalShortDelta(
        address _token
    ) public view returns (bool, uint256) {
        (, , , , uint256 size, , ) = IVault(vault).getPoolInfo(_token);
        uint256 averagePrice = globalShortAveragePrices[_token];
        if (size == 0) {
            return (false, 0);
        }

        uint256 nextPrice = IVault(vault).getMaxPrice(_token);
        uint256 priceDelta = averagePrice > nextPrice
            ? averagePrice - nextPrice
            : nextPrice - averagePrice;
        uint256 delta = (size * priceDelta) / averagePrice;
        bool hasProfit = averagePrice > nextPrice;

        return (hasProfit, delta);
    }

    function setInitData(
        address[] calldata _tokens,
        uint256[] calldata _averagePrices
    ) external override onlyOwner {
        require(!isGlobalShortDataReady, "ShortsTracker: already migrated");

        for (uint256 i = 0; i < _tokens.length; i++) {
            globalShortAveragePrices[_tokens[i]] = _averagePrices[i];
        }
        isGlobalShortDataReady = true;
    }

    function getNextGlobalShortData(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        bool _isIncrease
    ) public view override returns (uint256, uint256) {
        int256 realisedPnl = getRealisedPnl(
            _account,
            _collateralToken,
            _indexToken,
            _sizeDelta,
            _isIncrease
        );
        uint256 averagePrice = globalShortAveragePrices[_indexToken];
        uint256 priceDelta = averagePrice > _nextPrice
            ? averagePrice - _nextPrice
            : _nextPrice - averagePrice;

        uint256 nextSize;
        uint256 delta;
        // avoid stack to deep
        {
            (, , , , uint256 size, , ) = IVault(vault).getPoolInfo(_indexToken);
            nextSize = _isIncrease ? size + _sizeDelta : size - _sizeDelta;

            if (nextSize == 0) {
                return (0, 0);
            }

            if (averagePrice == 0) {
                return (nextSize, _nextPrice);
            }

            delta = (size * priceDelta) / averagePrice;
        }

        uint256 nextAveragePrice = _getNextGlobalAveragePrice(
            averagePrice,
            _nextPrice,
            nextSize,
            delta,
            realisedPnl
        );

        return (nextSize, nextAveragePrice);
    }

    function getRealisedPnl(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isIncrease
    ) public view returns (int256) {
        if (_isIncrease) {
            return 0;
        }

        IVault _vault = vault;
        DataTypes.Position memory position = _vault.getPosition(
            _account,
            _collateralToken,
            _indexToken,
            false
        );

        (bool hasProfit, uint256 delta) = _vault.getDelta(
            _indexToken,
            position.size,
            position.averagePrice,
            false,
            position.lastIncreasedTime
        );
        // get the proportional change in pnl
        uint256 adjustedDelta = (_sizeDelta * delta) / position.size;
        require(
            adjustedDelta < Constants.MAX_INT256,
            "ShortsTracker: overflow"
        );
        return hasProfit ? int256(adjustedDelta) : -int256(adjustedDelta);
    }

    function _getNextGlobalAveragePrice(
        uint256 _averagePrice,
        uint256 _nextPrice,
        uint256 _nextSize,
        uint256 _delta,
        int256 _realisedPnl
    ) public pure returns (uint256) {
        (bool hasProfit, uint256 nextDelta) = _getNextDelta(
            _delta,
            _averagePrice,
            _nextPrice,
            _realisedPnl
        );

        uint256 nextAveragePrice = (_nextPrice * _nextSize) /
            (hasProfit ? _nextSize - nextDelta : _nextSize + nextDelta);

        return nextAveragePrice;
    }

    function _getNextDelta(
        uint256 _delta,
        uint256 _averagePrice,
        uint256 _nextPrice,
        int256 _realisedPnl
    ) internal pure returns (bool, uint256) {
        // global delta 10000, realised pnl 1000 => new pnl 9000
        // global delta 10000, realised pnl -1000 => new pnl 11000
        // global delta -10000, realised pnl 1000 => new pnl -11000
        // global delta -10000, realised pnl -1000 => new pnl -9000
        // global delta 10000, realised pnl 11000 => new pnl -1000 (flips sign)
        // global delta -10000, realised pnl -11000 => new pnl 1000 (flips sign)

        bool hasProfit = _averagePrice > _nextPrice;
        if (hasProfit) {
            // global shorts pnl is positive
            if (_realisedPnl > 0) {
                if (uint256(_realisedPnl) > _delta) {
                    _delta = uint256(_realisedPnl) - _delta;
                    hasProfit = false;
                } else {
                    _delta = _delta - uint256(_realisedPnl);
                }
            } else {
                _delta = _delta + uint256(-_realisedPnl);
            }

            return (hasProfit, _delta);
        }

        if (_realisedPnl > 0) {
            _delta = _delta + uint256(_realisedPnl);
        } else {
            if (uint256(-_realisedPnl) > _delta) {
                _delta = uint256(-_realisedPnl) - _delta;
                hasProfit = true;
            } else {
                _delta = _delta - uint256(-_realisedPnl);
            }
        }
        return (hasProfit, _delta);
    }
}
