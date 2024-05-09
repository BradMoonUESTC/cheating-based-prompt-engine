// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DataTypes} from "../types/DataTypes.sol";
import {StorageSlot} from "./StorageSlot.sol";
import {Constants} from "../helpers/Constants.sol";

library BorrowingFeeLogic {
    event UpdateBorrowingRate(address token, uint256 borrowngRate);

    function getBorrowingFee(
        address /* _account */,
        address _collateralToken,
        address /* _indexToken */,
        bool /* _isLong */,
        uint256 _size,
        uint256 _entryBorrowingRate
    ) internal view returns (uint256) {
        if (_size == 0) {
            return 0;
        }
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        uint256 borrowingRate = fs.cumulativeBorrowingRates[_collateralToken] -
            _entryBorrowingRate;
        if (borrowingRate == 0) {
            return 0;
        }

        return (_size * borrowingRate) / Constants.BORROWING_RATE_PRECISION;
    }

    function updateCumulativeBorrowingRate(
        address _collateralToken,
        address /*_indexToken*/
    ) internal {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        if (fs.lastBorrowingTimes[_collateralToken] == 0) {
            fs.lastBorrowingTimes[_collateralToken] =
                (block.timestamp / fs.borrowingInterval) *
                fs.borrowingInterval;
            return;
        }

        if (
            fs.lastBorrowingTimes[_collateralToken] + fs.borrowingInterval >
            block.timestamp
        ) {
            return;
        }

        uint256 borrowingRate = getNextBorrowingRate(_collateralToken);
        fs.cumulativeBorrowingRates[_collateralToken] =
            fs.cumulativeBorrowingRates[_collateralToken] +
            borrowingRate;
        fs.lastBorrowingTimes[_collateralToken] =
            (block.timestamp / fs.borrowingInterval) *
            fs.borrowingInterval;

        emit UpdateBorrowingRate(
            _collateralToken,
            fs.cumulativeBorrowingRates[_collateralToken]
        );
    }

    function getNextBorrowingRate(
        address _token
    ) internal view returns (uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        if (
            fs.lastBorrowingTimes[_token] + fs.borrowingInterval >
            block.timestamp
        ) {
            return 0;
        }

        uint256 intervals = (block.timestamp - fs.lastBorrowingTimes[_token]) /
            (fs.borrowingInterval);
        uint256 poolAmount = ps.poolAmounts[_token];
        if (poolAmount == 0) {
            return 0;
        }

        uint256 _borrowingRateFactor = ts.stableTokens[_token]
            ? fs.stableBorrowingRateFactor
            : fs.borrowingRateFactor;
        return
            (_borrowingRateFactor * ps.reservedAmounts[_token] * intervals) /
            poolAmount;
    }
}
