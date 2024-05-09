// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {BorrowingFeeLogic} from "./BorrowingFeeLogic.sol";
import {SwapPriceImpactLogic} from "./priceImpact/SwapPriceImpactLogic.sol";
import {ValidationLogic} from "./ValidationLogic.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {StorageSlot} from "./StorageSlot.sol";

import {DataTypes} from "../types/DataTypes.sol";

import {Constants} from "../helpers/Constants.sol";
import {Errors} from "../helpers/Errors.sol";

library SwapLogic {
    using SafeCast for uint256;
    using SafeCast for int256;

    event Swap(
        address indexed account,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 amountOutAfterFees,
        uint256 feeBasisPoints
    );

    struct PriceImpactCache {
        address tokenIn;
        uint256 priceInMax;
        uint256 priceInMin;
        int256 priceImpactUsdTokenIn;
        address tokenOut;
        uint256 priceOutMax;
        uint256 priceOutMin;
        int256 priceImpactUsdTokenOut;
    }

    function ExecuteSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        address _receiver
    ) external returns (uint256) {
        PriceImpactCache memory cache;

        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        DataTypes.PermissionStorage storage ps = StorageSlot
            .getVaultPermissionStorage();
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();

        ValidationLogic.validate(
            ps.isSwaper[msg.sender],
            Errors.VAULT_NOT_SWAPER
        );

        ValidationLogic.validateSwapParams(
            ps.isSwapEnabled,
            _tokenIn,
            _tokenOut,
            _amountIn,
            ts.whitelistedTokens
        );

        BorrowingFeeLogic.updateCumulativeBorrowingRate(_tokenIn, _tokenIn);
        BorrowingFeeLogic.updateCumulativeBorrowingRate(_tokenOut, _tokenOut);

        cache.tokenIn = _tokenIn;
        cache.tokenOut = _tokenOut;
        cache.priceInMax = GenericLogic.getMaxPrice(_tokenIn);
        cache.priceInMin = GenericLogic.getMinPrice(_tokenIn);
        cache.priceOutMax = GenericLogic.getMaxPrice(_tokenOut);
        cache.priceOutMin = GenericLogic.getMinPrice(_tokenOut);

        // adjust ethgAmounts by the same ethgAmount as debt is shifted between the assets
        uint256 ethgAmount = (_amountIn * cache.priceInMin) /
            Constants.PRICE_PRECISION;
        ethgAmount = GenericLogic.adjustForDecimals(
            ethgAmount,
            _tokenIn,
            addrs.ethg
        );

        // price impact tokenIn
        {
            cache.priceImpactUsdTokenIn = SwapPriceImpactLogic
                .getSupplyPriceImpactUsd(
                    SwapPriceImpactLogic.GetSupplyPriceImpactUsdParams({
                        token: cache.tokenIn,
                        price: cache.priceInMax,
                        usdDelta: ((ethgAmount * Constants.PRICE_PRECISION) /
                            10 ** Constants.ETHG_DECIMALS).toInt256()
                    })
                );
            int256 impactAmountTokenIn = SwapPriceImpactLogic
                .applySwapImpactWithCap(
                    cache.tokenIn,
                    cache.priceInMax,
                    cache.priceInMin,
                    cache.priceImpactUsdTokenIn
                );
            if (cache.priceImpactUsdTokenIn > 0) {
                uint256 positiveImpactAmountTokenIn = GenericLogic
                    .adjustFor30Decimals(
                        impactAmountTokenIn.toUint256(),
                        cache.tokenIn
                    );
                _amountIn += positiveImpactAmountTokenIn;
            }

            if (cache.priceImpactUsdTokenIn < 0) {
                uint256 negativeImpactAmount = GenericLogic.adjustFor30Decimals(
                    (-impactAmountTokenIn).toUint256(),
                    cache.tokenIn
                );
                _amountIn -= negativeImpactAmount;
            }
        }

        uint256 amountOut = (_amountIn * cache.priceInMin) / cache.priceOutMax;

        amountOut = GenericLogic.adjustForDecimals(
            amountOut,
            _tokenIn,
            _tokenOut
        );

        uint256 feeBasisPoints = getSwapFeeBasisPoints(
            _tokenIn,
            _tokenOut,
            ethgAmount
        );
        uint256 amountOutAfterFees = GenericLogic.collectSwapFees(
            _tokenOut,
            amountOut,
            feeBasisPoints
        );

        // price impact tokenOut
        {
            cache.priceImpactUsdTokenOut = SwapPriceImpactLogic
                .getSupplyPriceImpactUsd(
                    SwapPriceImpactLogic.GetSupplyPriceImpactUsdParams({
                        token: cache.tokenOut,
                        price: cache.priceOutMax,
                        usdDelta: -(
                            ((ethgAmount * Constants.PRICE_PRECISION) /
                                10 ** Constants.ETHG_DECIMALS).toInt256()
                        )
                    })
                );
            int256 impactAmountOut = SwapPriceImpactLogic
                .applySwapImpactWithCap(
                    cache.tokenOut,
                    cache.priceOutMax,
                    cache.priceOutMin,
                    cache.priceImpactUsdTokenOut
                );
            if (cache.priceImpactUsdTokenOut > 0) {
                uint256 positiveImpactAmount = GenericLogic.adjustFor30Decimals(
                    impactAmountOut.toUint256(),
                    cache.tokenOut
                );
                amountOutAfterFees += positiveImpactAmount;
            }
            if (cache.priceImpactUsdTokenOut < 0) {
                uint256 negativeImpactAmount = GenericLogic.adjustFor30Decimals(
                    (-impactAmountOut).toUint256(),
                    cache.tokenOut
                );
                amountOutAfterFees -= negativeImpactAmount;
            }
        }

        GenericLogic.increaseEthgAmount(_tokenIn, ethgAmount);
        GenericLogic.decreaseEthgAmount(_tokenOut, ethgAmount);

        GenericLogic.increasePoolAmount(_tokenIn, _amountIn);
        GenericLogic.decreasePoolAmount(_tokenOut, amountOut);

        ValidationLogic.validateBufferAmount(_tokenOut);

        GenericLogic.transferOut(_tokenOut, amountOutAfterFees, _receiver);

        emit Swap(
            _receiver,
            _tokenIn,
            _tokenOut,
            _amountIn,
            amountOut,
            amountOutAfterFees,
            feeBasisPoints
        );

        return amountOutAfterFees;
    }

    function getSwapFeeBasisPoints(
        address _tokenIn,
        address _tokenOut,
        uint256 _ethgAmount
    ) internal view returns (uint256) {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        bool isStableSwap = ts.stableTokens[_tokenIn] &&
            ts.stableTokens[_tokenOut];
        uint256 baseBps = isStableSwap
            ? fs.stableSwapFeeBasisPoints
            : fs.swapFeeBasisPoints;
        uint256 taxBps = isStableSwap
            ? fs.stableTaxBasisPoints
            : fs.taxBasisPoints;
        uint256 feesBasisPoints0 = GenericLogic.getFeeBasisPoints(
            _tokenIn,
            _ethgAmount,
            baseBps,
            taxBps,
            true
        );
        uint256 feesBasisPoints1 = GenericLogic.getFeeBasisPoints(
            _tokenOut,
            _ethgAmount,
            baseBps,
            taxBps,
            false
        );
        // use the higher of the two fee basis points
        return
            feesBasisPoints0 > feesBasisPoints1
                ? feesBasisPoints0
                : feesBasisPoints1;
    }

    function getSwapPriceImpactFee(
        address _tokenIn,
        address _tokenOut,
        uint256 _tokenAmount
    ) external view returns (int256) {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        uint256 priceInMax = GenericLogic.getMaxPrice(_tokenIn);
        uint256 priceInMin = GenericLogic.getMinPrice(_tokenIn);
        uint256 priceOutMax = GenericLogic.getMaxPrice(_tokenOut);
        uint256 ethgAmount = (_tokenAmount * priceInMin) /
            Constants.PRICE_PRECISION;
        ethgAmount = GenericLogic.adjustForDecimals(
            ethgAmount,
            _tokenIn,
            addrs.ethg
        );

        int256 priceImpactUsdTokenIn;
        int256 priceImpactUsdTokenOut;
        // price impact tokenIn
        priceImpactUsdTokenIn = SwapPriceImpactLogic.getSupplyPriceImpactUsd(
            SwapPriceImpactLogic.GetSupplyPriceImpactUsdParams({
                token: _tokenIn,
                price: priceInMax,
                usdDelta: ((ethgAmount * Constants.PRICE_PRECISION) /
                    10 ** Constants.ETHG_DECIMALS).toInt256()
            })
        );

        // price impact tokenOut
        priceImpactUsdTokenOut = SwapPriceImpactLogic.getSupplyPriceImpactUsd(
            SwapPriceImpactLogic.GetSupplyPriceImpactUsdParams({
                token: _tokenOut,
                price: priceOutMax,
                usdDelta: -(
                    ((ethgAmount * Constants.PRICE_PRECISION) /
                        10 ** Constants.ETHG_DECIMALS).toInt256()
                )
            })
        );
        return (priceImpactUsdTokenIn + priceImpactUsdTokenOut);
    }
}
