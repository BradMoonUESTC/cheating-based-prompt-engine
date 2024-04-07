// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../../../interfaces/IQiToken.sol";
import "../../../libraries/Errors.sol";

contract PendleQiTokenHelper {
    IQiToken private immutable qiToken;
    uint256 private immutable initialExchangeRateMantissa;
    uint256 private constant borrowRateMaxMantissa = 0.0005e16;

    constructor(address _qiToken, uint256 _initialExchangeRateMantissa) {
        qiToken = IQiToken(_qiToken);
        initialExchangeRateMantissa = _initialExchangeRateMantissa;
    }

    function _exchangeRateCurrentView() internal view returns (uint256) {
        uint256 currentBlockTimestamp = block.timestamp;

        uint256 accrualBlockTimestampPrior = qiToken.accrualBlockTimestamp();

        if (accrualBlockTimestampPrior == currentBlockTimestamp) return qiToken.exchangeRateStored();

        /* Read the previous values out of storage */
        uint256 cashPrior = qiToken.getCash();
        uint256 borrowsPrior = qiToken.totalBorrows();
        uint256 reservesPrior = qiToken.totalReserves();

        /* Calculate the current borrow interest rate */
        uint256 borrowRateMantissa = qiToken.interestRateModel().getBorrowRate(cashPrior, borrowsPrior, reservesPrior);

        if (borrowRateMantissa > borrowRateMaxMantissa)
            revert Errors.SYQiTokenBorrowRateTooHigh(borrowRateMantissa, borrowRateMaxMantissa);

        uint256 timestampDelta = currentBlockTimestamp - accrualBlockTimestampPrior;

        uint256 simpleInterestFactor = borrowRateMantissa * timestampDelta;

        uint256 interestAccumulated = (simpleInterestFactor * borrowsPrior) / 1e18;

        uint256 totalBorrowsNew = interestAccumulated + borrowsPrior;

        uint256 totalReservesNew = (qiToken.reserveFactorMantissa() * interestAccumulated) / 1e18 + reservesPrior;

        return _calcExchangeRate(qiToken.totalSupply(), cashPrior, totalBorrowsNew, totalReservesNew);
    }

    function _calcExchangeRate(
        uint256 totalSupply,
        uint256 totalCash,
        uint256 totalBorrows,
        uint256 totalReserves
    ) private view returns (uint256) {
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            return initialExchangeRateMantissa;
        } else {
            uint256 cashPlusBorrowsMinusReserves;
            uint256 exchangeRate;

            cashPlusBorrowsMinusReserves = totalCash + totalBorrows - totalReserves;

            exchangeRate = (cashPlusBorrowsMinusReserves * 1e18) / _totalSupply;

            return exchangeRate;
        }
    }
}
