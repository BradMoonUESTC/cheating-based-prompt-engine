// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {GenericLogic} from "../GenericLogic.sol";
import {DataTypes} from "../../types/DataTypes.sol";
import {StorageSlot} from "../StorageSlot.sol";
import {Errors} from "../../helpers/Errors.sol";
import {Constants} from "../../helpers/Constants.sol";
import {Calc} from "../../math/Calc.sol";
import {PricingUtils} from "./PricingUtils.sol";
import {Precision} from "../../math/Precision.sol";

library SwapPriceImpactLogic {
    using SignedMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    struct GetSupplyPriceImpactUsdParams {
        address token;
        uint256 price;
        int256 usdDelta;
    }

    // @dev PoolParams struct to contain pool values
    // @param poolUsd the USD value of token in the pool
    // @param nextPoolUsd the next USD value of token in the pool
    struct PoolParams {
        uint256 poolUsdForToken;
        uint256 nextPoolUsdForToken;
    }

    function getSupplyPriceImpactUsd(
        GetSupplyPriceImpactUsdParams memory params
    ) internal view returns (int256) {
        PoolParams memory poolParamsToken = getNextPoolAmountsUsd(
            params.token,
            params.price,
            params.usdDelta
        );

        int256 priceImpact = _getPriceImpactUsd(params.token, poolParamsToken);

        return priceImpact;
    }

    // @dev get the price impact in USD
    // @param token the trading token
    // @param poolParams PoolParams
    // @return the price impact in USD
    function _getPriceImpactUsd(
        address token,
        PoolParams memory poolParams
    ) internal view returns (int256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        // Calculate the diff between token and the target weight
        uint256 targetAmountToken = (GenericLogic.getTargetEthgAmount(token) *
            Precision.FLOAT_PRECISION) / 10 ** Constants.ETHG_DECIMALS;
        uint256 initialDiffUsdToken = Calc.diff(
            poolParams.poolUsdForToken,
            targetAmountToken
        );
        uint256 nextDiffUsdToken = Calc.diff(
            poolParams.nextPoolUsdForToken,
            targetAmountToken
        );

        // check whether an improvement in balance comes from causing the balance to switch sides
        // for example, if there is $2000 of ETH and $1000 of USDC in the pool
        // adding $1999 USDC into the pool will reduce absolute balance from $1000 to $999 but it does not
        // help rebalance the pool much, the isSameSideRebalance value helps avoid gaming using this case
        bool isSameSideRebalance = (poolParams.poolUsdForToken <=
            targetAmountToken) ==
            (poolParams.nextPoolUsdForToken <= targetAmountToken);
        uint256 impactExponentFactor = fs.swapImpactExponentFactors[token];
        if (isSameSideRebalance) {
            bool hasPositiveImpact = nextDiffUsdToken < initialDiffUsdToken;
            uint256 impactFactor = getAdjustedSwapImpactFactor(
                token,
                hasPositiveImpact
            );
            return
                PricingUtils.getPriceImpactUsdForSameSideRebalance(
                    initialDiffUsdToken,
                    nextDiffUsdToken,
                    impactFactor,
                    impactExponentFactor
                );
        } else {
            (
                uint256 positiveImpactFactor,
                uint256 negativeImpactFactor
            ) = getAdjustedSwapImpactFactors(token);

            return
                PricingUtils.getPriceImpactUsdForCrossoverRebalance(
                    initialDiffUsdToken,
                    nextDiffUsdToken,
                    positiveImpactFactor,
                    negativeImpactFactor,
                    impactExponentFactor
                );
        }
    }

    function getNextPoolAmountsUsd(
        address token,
        uint256 price,
        int256 usdDelta
    ) internal view returns (PoolParams memory) {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        uint256 poolAmount = (ps.poolAmounts[token] *
            Precision.FLOAT_PRECISION) / 10 ** ts.tokenDecimals[token];
        return getNextPoolAmountsParams(price, usdDelta, poolAmount);
    }

    function getNextPoolAmountsParams(
        uint256 price,
        int256 usdDelta,
        uint256 poolAmount
    ) internal pure returns (PoolParams memory) {
        uint256 poolUsd = (poolAmount * price) / Constants.PRICE_PRECISION;
        if (usdDelta < 0 && (-usdDelta).toUint256() > poolUsd) {
            revert(Errors.VAULT_POOL_AMOUNT_EXCEEDED);
        }

        uint256 nextPoolUsd = Calc.sumReturnUint256(poolUsd, usdDelta);

        PoolParams memory poolParams = PoolParams(poolUsd, nextPoolUsd);

        return poolParams;
    }

    function getAdjustedSwapImpactFactor(
        address token,
        bool isPositive
    ) internal view returns (uint256) {
        (
            uint256 positiveImpactFactor,
            uint256 negativeImpactFactor
        ) = getAdjustedSwapImpactFactors(token);

        return isPositive ? positiveImpactFactor : negativeImpactFactor;
    }

    function getAdjustedSwapImpactFactors(
        address token
    ) internal view returns (uint256, uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        uint256 positiveImpactFactor = fs.swapImpactFactors[token][true];
        uint256 negativeImpactFactor = fs.swapImpactFactors[token][false];

        // if the positive impact factor is more than the negative impact factor, positions could be opened
        // and closed immediately for a profit if the difference is sufficient to cover the position fees
        if (positiveImpactFactor > negativeImpactFactor) {
            positiveImpactFactor = negativeImpactFactor;
        }

        return (positiveImpactFactor, negativeImpactFactor);
    }

    // @dev update the swap impact pool amount, if it is a positive impact amount
    // cap the impact amount to the amount available in the swap impact pool
    // @param market the market to apply to
    // @param token the token to apply to
    // @param tokenPrice the price of the token
    // @param priceImpactUsd the USD price impact
    function applySwapImpactWithCap(
        address token,
        uint256 tokenPriceMax,
        uint256 tokenPriceMin,
        int256 priceImpactUsd
    ) internal returns (int256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();

        int256 impactAmount = getSwapImpactAmountWithCap(
            token,
            tokenPriceMax,
            tokenPriceMin,
            priceImpactUsd
        );

        // if there is a positive impact, the impact pool amount should be reduced
        // if there is a negative impact, the impact pool amount should be increased
        fs.swapImpactPoolAmounts[token] = Calc.sumReturnUint256(
            fs.swapImpactPoolAmounts[token],
            -impactAmount
        );

        return impactAmount;
    }

    function getSwapImpactAmountWithCap(
        address token,
        uint256 tokenPriceMax,
        uint256 tokenPriceMin,
        int256 priceImpactUsd
    ) internal view returns (int256) {
        int256 impactAmount;

        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();

        if (priceImpactUsd > 0) {
            // positive impact: minimize impactAmount, use tokenPrice.max
            // round positive impactAmount down, this will be deducted from the swap impact pool for the user
            impactAmount =
                (priceImpactUsd * Constants.PRICE_PRECISION.toInt256()) /
                tokenPriceMax.toInt256();

            int256 maxImpactAmount = fs.swapImpactPoolAmounts[token].toInt256();
            if (impactAmount > maxImpactAmount) {
                impactAmount = maxImpactAmount;
            }
        } else {
            // negative impact: maximize impactAmount, use tokenPrice.min
            // round negative impactAmount up, this will be deducted from the user
            impactAmount = Calc.roundUpMagnitudeDivision(
                priceImpactUsd * Constants.PRICE_PRECISION.toInt256(),
                tokenPriceMin
            );
        }

        return impactAmount;
    }
}
