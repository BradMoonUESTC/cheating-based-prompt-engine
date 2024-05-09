// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Calc} from "../../math/Calc.sol";
import {DataTypes} from "../../types/DataTypes.sol";
import {StorageSlot} from "../StorageSlot.sol";
import {GenericLogic} from "../GenericLogic.sol";
import {PricingUtils} from "./PricingUtils.sol";
import {Precision} from "../../math/Precision.sol";
import {Constants} from "../../helpers/Constants.sol";

library PositionPriceImpactLogic {
    using SignedMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    // @dev GetPriceImpactUsdParams struct used in getPriceImpactUsd to avoid stack
    // too deep errors
    // @param indexToken the indexToken to check
    // @param usdDelta the change in position size in USD
    // @param isLong whether the position is long or short
    struct GetPriceImpactUsdParams {
        address indexToken;
        int256 usdDelta;
        uint256 indexTokenPrice;
        uint256 positionAveragePrice;
        uint256 reservedAmount;
        bool isLong;
    }

    // @dev OpenInterestParams struct to contain open interest values
    // @param longOpenInterest the amount of long open interest
    // @param shortOpenInterest the amount of short open interest
    // @param nextLongOpenInterest the updated amount of long open interest
    // @param nextShortOpenInterest the updated amount of short open interest
    struct OpenInterestParams {
        uint256 longOpenInterest;
        uint256 shortOpenInterest;
        uint256 nextLongOpenInterest;
        uint256 nextShortOpenInterest;
    }

    // @dev get the price impact in USD for a position increase / decrease
    // @param params GetPriceImpactUsdParams
    function getPriceImpactUsd(
        GetPriceImpactUsdParams memory params
    ) internal view returns (int256) {
        OpenInterestParams memory openInterestParams = getNextOpenInterest(
            params
        );

        int256 priceImpactUsd = _getPriceImpactUsd(
            params.indexToken,
            openInterestParams
        );

        return priceImpactUsd;
    }

    // @dev get the price impact in USD for a position increase / decrease
    // @param indexToken the trading indexToken
    // @param openInterestParams OpenInterestParams
    function _getPriceImpactUsd(
        address indexToken,
        OpenInterestParams memory openInterestParams
    ) internal view returns (int256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        uint256 initialDiffUsd = Calc.diff(
            openInterestParams.longOpenInterest,
            openInterestParams.shortOpenInterest
        );
        uint256 nextDiffUsd = Calc.diff(
            openInterestParams.nextLongOpenInterest,
            openInterestParams.nextShortOpenInterest
        );

        // check whether an improvement in balance comes from causing the balance to switch sides
        // for example, if there is $2000 of ETH and $1000 of USDC in the pool
        // adding $1999 USDC into the pool will reduce absolute balance from $1000 to $999 but it does not
        // help rebalance the pool much, the isSameSideRebalance value helps avoid gaming using this case
        bool isSameSideRebalance = openInterestParams.longOpenInterest <=
            openInterestParams.shortOpenInterest ==
            openInterestParams.nextLongOpenInterest <=
            openInterestParams.nextShortOpenInterest;
        uint256 impactExponentFactor = fs.positionImpactExponents[indexToken];

        if (isSameSideRebalance) {
            bool hasPositiveImpact = nextDiffUsd < initialDiffUsd;
            uint256 impactFactor = getAdjustedPositionImpactFactor(
                indexToken,
                hasPositiveImpact
            );

            return
                PricingUtils.getPriceImpactUsdForSameSideRebalance(
                    initialDiffUsd,
                    nextDiffUsd,
                    impactFactor,
                    impactExponentFactor
                );
        } else {
            (
                uint256 positiveImpactFactor,
                uint256 negativeImpactFactor
            ) = getAdjustedPositionImpactFactors(indexToken);

            return
                PricingUtils.getPriceImpactUsdForCrossoverRebalance(
                    initialDiffUsd,
                    nextDiffUsd,
                    positiveImpactFactor,
                    negativeImpactFactor,
                    impactExponentFactor
                );
        }
    }

    // @dev get the next open interest values
    // @param params GetPriceImpactUsdParams
    // @return OpenInterestParams
    function getNextOpenInterest(
        GetPriceImpactUsdParams memory params
    ) internal view returns (OpenInterestParams memory) {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();

        uint256 reserveAmount = (params.reservedAmount *
            Precision.FLOAT_PRECISION) /
            10 ** ts.tokenDecimals[params.indexToken];
        uint256 longOpenInterest = (reserveAmount * params.indexTokenPrice) /
            Constants.PRICE_PRECISION;
        uint256 shortOpenInterest = ps.globalShortSizes[params.indexToken];
        if (ps.globalShortAveragePrices[params.indexToken] > 0) {
            shortOpenInterest =
                (ps.globalShortSizes[params.indexToken] *
                    params.indexTokenPrice) /
                ps.globalShortAveragePrices[params.indexToken];
        }

        return
            getNextOpenInterestParams(
                params,
                longOpenInterest,
                shortOpenInterest
            );
    }

    function getNextOpenInterestParams(
        GetPriceImpactUsdParams memory params,
        uint256 longOpenInterest,
        uint256 shortOpenInterest
    ) internal pure returns (OpenInterestParams memory) {
        uint256 nextLongOpenInterest = longOpenInterest;
        uint256 nextShortOpenInterest = shortOpenInterest;

        int256 delta;
        if (params.positionAveragePrice > 0) {
            if (params.usdDelta < 0) {
                delta = -(((-params.usdDelta).toUint256() *
                    params.indexTokenPrice) / params.positionAveragePrice)
                    .toInt256();
            } else {
                delta = ((params.usdDelta.toUint256() *
                    params.indexTokenPrice) / params.positionAveragePrice)
                    .toInt256();
            }
        } else {
            delta = params.usdDelta;
        }

        if (params.isLong) {
            nextLongOpenInterest = Calc.sumReturnUint256(
                longOpenInterest,
                delta
            );
        } else {
            nextShortOpenInterest = Calc.sumReturnUint256(
                shortOpenInterest,
                delta
            );
        }

        OpenInterestParams memory openInterestParams = OpenInterestParams(
            longOpenInterest,
            shortOpenInterest,
            nextLongOpenInterest,
            nextShortOpenInterest
        );

        return openInterestParams;
    }

    function getAdjustedPositionImpactFactor(
        address indexToken,
        bool isPositive
    ) internal view returns (uint256) {
        (
            uint256 positiveImpactFactor,
            uint256 negativeImpactFactor
        ) = getAdjustedPositionImpactFactors(indexToken);

        return isPositive ? positiveImpactFactor : negativeImpactFactor;
    }

    function getAdjustedPositionImpactFactors(
        address indexToken
    ) internal view returns (uint256, uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        uint256 positiveImpactFactor = fs.positionImpactFactors[indexToken][
            true
        ];
        uint256 negativeImpactFactor = fs.positionImpactFactors[indexToken][
            false
        ];

        // if the positive impact factor is more than the negative impact factor, positions could be opened
        // and closed immediately for a profit if the difference is sufficient to cover the position fees
        if (positiveImpactFactor > negativeImpactFactor) {
            positiveImpactFactor = negativeImpactFactor;
        }

        return (positiveImpactFactor, negativeImpactFactor);
    }

    function getCappedPositionImpactUsd(
        address token,
        uint256 tokenPriceMin,
        int256 priceImpactUsd
    ) internal view returns (int256) {
        if (priceImpactUsd < 0) {
            return priceImpactUsd;
        }

        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();

        uint256 impactPoolAmount = fs.positionImpactPoolAmounts[token];

        int256 maxPriceImpactUsdBasedOnImpactPool = ((impactPoolAmount *
            tokenPriceMin) / Constants.PRICE_PRECISION).toInt256();

        if (priceImpactUsd > maxPriceImpactUsdBasedOnImpactPool) {
            priceImpactUsd = maxPriceImpactUsdBasedOnImpactPool;
        }

        return priceImpactUsd;
    }

    // @dev apply a delta to the position impact pool
    // @param dataStore DataStore
    // @param eventEmitter EventEmitter
    // @param market the market to apply to
    // @param delta the delta amount
    function applyDeltaToPositionImpactPool(
        address _indexToken,
        int256 delta
    ) internal returns (uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();

        uint256 priceImpactPoolAmount = fs.positionImpactPoolAmounts[
            _indexToken
        ];
        if (delta < 0 && (-delta).toUint256() > priceImpactPoolAmount) {
            fs.positionImpactPoolAmounts[_indexToken] = 0;
            return 0;
        }

        uint256 nextPriceImpactPoolAmount = Calc.sumReturnUint256(
            priceImpactPoolAmount,
            delta
        );
        fs.positionImpactPoolAmounts[_indexToken] = nextPriceImpactPoolAmount;
        return nextPriceImpactPoolAmount;
    }
}
