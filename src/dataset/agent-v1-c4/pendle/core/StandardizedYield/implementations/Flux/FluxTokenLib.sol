// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../../../interfaces/Flux/IFluxErc20.sol";
import "../../../../interfaces/Flux/IFluxInterestRateModel.sol";
import "../../../libraries/Errors.sol";

library FluxTokenLib {
    uint256 private constant borrowRateMaxMantissa = 0.0005e16;

    struct ExchangeRateComputationParams {
        uint256 currentBlockNumber;
        uint256 accrualBlockNumberPrior;
        uint256 cashPrior;
        uint256 borrowsPrior;
        uint256 reservesPrior;
        uint256 borrowRateMantissa;
        uint256 timestampDelta;
        uint256 simpleInterestFactor;
        uint256 interestAccumulated;
        uint256 totalBorrowsNew;
        uint256 totalReservesNew;
    }

    function exchangeRateCurrentView(address fToken) internal view returns (uint256) {
        ExchangeRateComputationParams memory params;

        params.currentBlockNumber = block.number;
        params.accrualBlockNumberPrior = IFluxErc20(fToken).accrualBlockNumber();

        if (params.accrualBlockNumberPrior == params.currentBlockNumber) return IFluxErc20(fToken).exchangeRateStored();

        /* Read the previous values out of storage */
        params.cashPrior = IFluxErc20(fToken).getCash();
        params.borrowsPrior = IFluxErc20(fToken).totalBorrows();
        params.reservesPrior = IFluxErc20(fToken).totalReserves();

        /* Calculate the current borrow interest rate */
        params.borrowRateMantissa = IFluxInterestRateModel(IFluxErc20(fToken).interestRateModel()).getBorrowRate(
            params.cashPrior,
            params.borrowsPrior,
            params.reservesPrior
        );

        assert(params.borrowRateMantissa <= borrowRateMaxMantissa);

        params.timestampDelta = params.currentBlockNumber - params.accrualBlockNumberPrior;
        params.simpleInterestFactor = params.borrowRateMantissa * params.timestampDelta;
        params.interestAccumulated = (params.simpleInterestFactor * params.borrowsPrior) / 1e18;
        params.totalBorrowsNew = params.interestAccumulated + params.borrowsPrior;

        params.totalReservesNew =
            (IFluxErc20(fToken).reserveFactorMantissa() * params.interestAccumulated) /
            1e18 +
            params.reservesPrior;

        return
            _calcExchangeRate(
                IFluxErc20(fToken).totalSupply(),
                params.cashPrior,
                params.totalBorrowsNew,
                params.totalReservesNew
            );
    }

    function _calcExchangeRate(
        uint256 totalSupply,
        uint256 totalCash,
        uint256 totalBorrows,
        uint256 totalReserves
    ) private pure returns (uint256) {
        uint256 cashPlusBorrowsMinusReserves;
        uint256 exchangeRate;

        cashPlusBorrowsMinusReserves = totalCash + totalBorrows - totalReserves;
        exchangeRate = (cashPlusBorrowsMinusReserves * 1e18) / totalSupply;

        return exchangeRate;
    }
}
