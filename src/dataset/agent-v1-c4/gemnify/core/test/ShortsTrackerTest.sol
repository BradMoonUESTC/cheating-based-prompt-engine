// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../ShortsTracker.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract ShortsTrackerTest is ShortsTracker {
    using Math for uint256;

    // function initialize(address _vault) external initializer {
    //     initialize(_vault);
    // }

    // constructor(address _vault) {
    //     initialize(_vault);
    // }

    function getNextGlobalShortDataWithRealisedPnl(
        address _indexToken,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        int256 _realisedPnl,
        bool _isIncrease
    ) public view returns (uint256, uint256) {
        uint256 averagePrice = globalShortAveragePrices[_indexToken];
        uint256 priceDelta = averagePrice > _nextPrice
            ? averagePrice - _nextPrice
            : _nextPrice - averagePrice;

        uint256 nextSize;
        uint256 delta;
        // avoid stack to deep
        {
            (, , , , uint256 size, , ) = IVault(vault).getPoolInfo(_indexToken);
            //uint256 size = vault.globalShortSizes(_indexToken);
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
            _realisedPnl
        );

        return (nextSize, nextAveragePrice);
    }

    function setGlobalShortAveragePrice(
        address _token,
        uint256 _averagePrice
    ) public {
        globalShortAveragePrices[_token] = _averagePrice;
    }
}
