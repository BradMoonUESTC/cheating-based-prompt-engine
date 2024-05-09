// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ValidationLogic} from "./ValidationLogic.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {BorrowingFeeLogic} from "./BorrowingFeeLogic.sol";
import {FundingFeeLogic} from "./FundingFeeLogic.sol";
import {PositionPriceImpactLogic} from "./priceImpact/PositionPriceImpactLogic.sol";
import {StorageSlot} from "./StorageSlot.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {Errors} from "../helpers/Errors.sol";
import {Calc} from "../math/Calc.sol";
import {Precision} from "../math/Precision.sol";

import {DataTypes} from "../types/DataTypes.sol";

import {Constants} from "../helpers/Constants.sol";

library PositionLogic {
    using SafeCast for uint256;
    using SafeCast for int256;

    event CollectMarginFees(address token, uint256 feeUsd, uint256 feeTokens);
    event UpdatePnl(bytes32 key, bool hasProfit, uint256 delta);
    event ClaimFundingFee(
        address indexed account,
        address token,
        uint256 amount
    );
    event IncreasePosition(
        bytes32 key,
        DataTypes.IncreasePositionParams params,
        uint256 collateralDelta,
        uint256 price,
        uint256 fee
    );

    event DecreasePosition(
        bytes32 key,
        DataTypes.DecreasePositionParams params,
        uint256 price,
        uint256 fee
    );

    event LiquidatePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        bool isLong,
        uint256 size,
        uint256 collateral,
        uint256 reserveAmount,
        int256 realisedPnl,
        uint256 markPrice
    );

    event UpdatePosition(
        bytes32 key,
        uint256 size,
        uint256 collateral,
        uint256 averagePrice,
        uint256 entryBorrowingRate,
        uint256 reserveAmount,
        int256 realisedPnl,
        uint256 markPrice
    );
    event ClosePosition(
        bytes32 key,
        uint256 size,
        uint256 collateral,
        uint256 averagePrice,
        uint256 entryBorrowingRate,
        uint256 reserveAmount,
        int256 realisedPnl
    );

    struct CollectMarginFeesParams {
        address account;
        address collateralToken;
        address indexToken;
        bool isLong;
        uint256 sizeDelta;
        DataTypes.Position position;
    }

    struct ReduceCollateralCache {
        uint256 fee;
        bool hasProfit;
        uint256 adjustedDelta;
        uint256 delta;
        uint256 usdOut;
        uint256 usdOutAfterFee;
        DataTypes.PositionFundingFees fundingFees;
    }

    struct IncreasePositionCache {
        int256 priceImpactUsd;
        int256 priceImpactAmount;
        uint256 entryPrice;
        uint256 fee;
        DataTypes.PositionFundingFees fundingFees;
        uint256 collateralDelta;
        uint256 collateralDeltaUsd;
        uint256 reserveDelta;
    }

    struct ExecutionPriceForDecreaseCache {
        int256 priceImpactUsd;
        int256 executionPrice;
    }

    function increasePosition(
        DataTypes.IncreasePositionParams memory params
    ) external {
        IncreasePositionCache memory cache;
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        DataTypes.PermissionStorage storage permission = StorageSlot
            .getVaultPermissionStorage();
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();

        ValidationLogic.validateIncreasePositionParams(
            permission.isLeverageEnabled,
            params.account,
            params.collateralToken,
            params.indexToken,
            params.isLong
        );

        bytes32 key = getPositionKey(
            params.account,
            params.collateralToken,
            params.indexToken,
            params.isLong
        );
        DataTypes.Position storage position = ps.positions[key];

        (
            cache.priceImpactUsd,
            cache.priceImpactAmount,
            cache.entryPrice
        ) = getExecutionPriceForIncrease(
            params,
            GenericLogic.getMaxPrice(params.indexToken),
            GenericLogic.getMinPrice(params.indexToken),
            position.averagePrice,
            ps.reservedAmounts[params.indexToken]
        );

        // if there is a positive impact, the impact pool amount should be reduced
        // if there is a negative impact, the impact pool amount should be increased
        PositionPriceImpactLogic.applyDeltaToPositionImpactPool(
            params.indexToken,
            -cache.priceImpactAmount
        );

        BorrowingFeeLogic.updateCumulativeBorrowingRate(
            params.collateralToken,
            params.indexToken
        );

        FundingFeeLogic.updateFundingState(params.indexToken);

        if (position.size == 0) {
            position.averagePrice = cache.entryPrice;
            position.fundingFeeAmountPerSize = fs.fundingFeeAmountPerSizes[
                params.indexToken
            ][params.isLong];
            position.claimableFundingAmountPerSize = fs
                .claimableFundingAmountPerSizes[params.indexToken][
                    params.isLong
                ];
        }
        if (position.size > 0 && params.sizeDelta > 0) {
            position.averagePrice = getNextAveragePrice(
                params.indexToken,
                position.size,
                position.averagePrice,
                params.isLong,
                cache.entryPrice,
                params.sizeDelta,
                position.lastIncreasedTime
            );
        }
        (cache.fee, cache.fundingFees) = collectMarginFees(
            CollectMarginFeesParams({
                account: params.account,
                collateralToken: params.collateralToken,
                indexToken: params.indexToken,
                isLong: params.isLong,
                sizeDelta: params.sizeDelta,
                position: position
            })
        );
        {
            address fundingToken = params.isLong
                ? addrs.weth
                : params.indexToken;
            FundingFeeLogic.incrementClaimableFundingAmount(
                params.account,
                fundingToken,
                cache.fundingFees
            );
        }

        cache.collateralDelta = GenericLogic.transferIn(params.collateralToken);
        cache.collateralDeltaUsd = GenericLogic.tokenToUsdMin(
            params.collateralToken,
            cache.collateralDelta
        );

        position.fundingFeeAmountPerSize = cache
            .fundingFees
            .latestFundingFeeAmountPerSize;
        position.claimableFundingAmountPerSize = cache
            .fundingFees
            .latestClaimableFundingAmountPerSize;
        position.collateral = position.collateral + cache.collateralDeltaUsd;
        ValidationLogic.validate(
            position.collateral >= cache.fee,
            Errors.VAULT_INSUFFICIENT_COLLATERAL_FOR_FEES
        );
        position.collateral = position.collateral - cache.fee;
        position.entryBorrowingRate = fs.cumulativeBorrowingRates[
            params.collateralToken
        ];
        position.size = position.size + params.sizeDelta;
        position.lastIncreasedTime = block.timestamp;
        ValidationLogic.validate(
            position.size > 0,
            Errors.VAULT_INVALID_POSITION_SIZE
        );

        ValidationLogic.validatePosition(position.size, position.collateral);
        validateLiquidation(
            params.account,
            params.collateralToken,
            params.indexToken,
            params.isLong,
            true
        );

        // reserve tokens to pay profits on the position
        cache.reserveDelta = GenericLogic.usdToTokenMax(
            params.collateralToken,
            params.sizeDelta
        );
        position.reserveAmount = position.reserveAmount + cache.reserveDelta;
        GenericLogic.increaseReservedAmount(
            params.collateralToken,
            cache.reserveDelta
        );

        if (params.isLong) {
            // guaranteedEth stores the sum of (position.size - position.collateral) for all positions
            // if a fee is charged on the collateral then guaranteedEth should be increased by that fee amount
            // since (position.size - position.collateral) would have increased by `fee`
            GenericLogic.increaseGuaranteedEth(
                params.collateralToken,
                params.sizeDelta + cache.fee
            );
            GenericLogic.decreaseGuaranteedEth(
                params.collateralToken,
                cache.collateralDeltaUsd
            );
            // treat the deposited collateral as part of the pool
            GenericLogic.increasePoolAmount(
                params.collateralToken,
                cache.collateralDelta
            );
            // fees need to be deducted from the pool since fees are deducted from position.collateral
            // and collateral is treated as part of the pool
            uint256 usdToTokenMin = GenericLogic.usdToTokenMin(
                params.collateralToken,
                cache.fee
            );
            GenericLogic.decreasePoolAmount(
                params.collateralToken,
                usdToTokenMin
            );
        } else {
            if (ps.globalShortSizes[params.indexToken] == 0) {
                ps.globalShortAveragePrices[params.indexToken] = cache
                    .entryPrice;
            } else {
                ps.globalShortAveragePrices[
                    params.indexToken
                ] = getNextGlobalShortAveragePrice(
                    params.indexToken,
                    cache.entryPrice,
                    params.sizeDelta
                );
            }
            GenericLogic.increaseGlobalShortSize(
                params.indexToken,
                params.sizeDelta
            );
        }

        emit IncreasePosition(
            key,
            params,
            cache.collateralDeltaUsd,
            cache.entryPrice,
            cache.fee
        );
        emit UpdatePosition(
            key,
            position.size,
            position.collateral,
            position.averagePrice,
            position.entryBorrowingRate,
            position.reserveAmount,
            position.realisedPnl,
            cache.entryPrice
        );
    }

    function decreasePosition(
        DataTypes.DecreasePositionParams memory params
    ) external returns (uint256) {
        ValidationLogic.validateDecreasePositionParams(params.account);
        return _decreasePosition(params);
    }

    function _decreasePosition(
        DataTypes.DecreasePositionParams memory params
    ) internal returns (uint256) {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();

        BorrowingFeeLogic.updateCumulativeBorrowingRate(
            params.collateralToken,
            params.indexToken
        );

        FundingFeeLogic.updateFundingState(params.indexToken);

        bytes32 key = getPositionKey(
            params.account,
            params.collateralToken,
            params.indexToken,
            params.isLong
        );
        DataTypes.Position storage position = ps.positions[key];
        ValidationLogic.validate(
            position.size > 0,
            Errors.VAULT_EMPTY_POSITION
        );
        ValidationLogic.validate(
            position.size >= params.sizeDelta,
            Errors.VAULT_POSITION_SIZE_EXCEEDED
        );
        ValidationLogic.validate(
            position.collateral >= params.collateralDelta,
            Errors.VAULT_POSITION_COLLATERAL_EXCEEDED
        );

        uint256 collateral = position.collateral;
        uint256 reservedAmount = ps.reservedAmounts[params.indexToken];
        // scrop variables to avoid stack too deep errors
        {
            uint256 reserveDelta = (position.reserveAmount *
                (params.sizeDelta)) / position.size;
            position.reserveAmount = position.reserveAmount - reserveDelta;
            GenericLogic.decreaseReservedAmount(
                params.collateralToken,
                reserveDelta
            );
        }
        (
            uint256 usdOut,
            uint256 usdOutAfterFee,
            DataTypes.PositionFundingFees memory fundingFees
        ) = reduceCollateral(params, reservedAmount);
        uint256 price = params.isLong
            ? GenericLogic.getMinPrice(params.indexToken)
            : GenericLogic.getMaxPrice(params.indexToken);

        {
            DataTypes.AddressStorage storage addrs = StorageSlot
                .getVaultAddressStorage();

            address fundingToken = params.isLong
                ? addrs.weth
                : params.indexToken;
            FundingFeeLogic.incrementClaimableFundingAmount(
                params.account,
                fundingToken,
                fundingFees
            );
        }

        if (position.size != params.sizeDelta) {
            position.entryBorrowingRate = fs.cumulativeBorrowingRates[
                params.collateralToken
            ];

            position.fundingFeeAmountPerSize = fundingFees
                .latestFundingFeeAmountPerSize;
            position.claimableFundingAmountPerSize = fundingFees
                .latestClaimableFundingAmountPerSize;

            position.size = position.size - params.sizeDelta;

            ValidationLogic.validatePosition(
                position.size,
                position.collateral
            );

            validateLiquidation(
                params.account,
                params.collateralToken,
                params.indexToken,
                params.isLong,
                true
            );

            if (params.isLong) {
                GenericLogic.increaseGuaranteedEth(
                    params.collateralToken,
                    collateral - position.collateral
                );
                GenericLogic.decreaseGuaranteedEth(
                    params.collateralToken,
                    params.sizeDelta
                );
            }

            emit UpdatePosition(
                key,
                position.size,
                position.collateral,
                position.averagePrice,
                position.entryBorrowingRate,
                position.reserveAmount,
                position.realisedPnl,
                price
            );
        } else {
            if (params.isLong) {
                GenericLogic.increaseGuaranteedEth(
                    params.collateralToken,
                    collateral
                );
                GenericLogic.decreaseGuaranteedEth(
                    params.collateralToken,
                    params.sizeDelta
                );
            }
            emit ClosePosition(
                key,
                position.size,
                position.collateral,
                position.averagePrice,
                position.entryBorrowingRate,
                position.reserveAmount,
                position.realisedPnl
            );
            delete ps.positions[key];
        }

        emit DecreasePosition(key, params, price, usdOut - usdOutAfterFee);

        if (!params.isLong) {
            GenericLogic.decreaseGlobalShortSize(
                params.indexToken,
                params.sizeDelta
            );
        }

        if (usdOut > 0) {
            if (params.isLong) {
                uint256 amount = GenericLogic.usdToTokenMin(
                    params.collateralToken,
                    usdOut
                );
                GenericLogic.decreasePoolAmount(params.collateralToken, amount);
            }

            uint256 amountOutAfterFees = GenericLogic.usdToTokenMin(
                params.collateralToken,
                usdOutAfterFee
            );
            GenericLogic.transferOut(
                params.collateralToken,
                amountOutAfterFees,
                params.receiver
            );
            return amountOutAfterFees;
        }

        return 0;
    }

    function liquidatePosition(
        DataTypes.LiquidatePositionParams memory params
    ) external {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        DataTypes.PermissionStorage storage permission = StorageSlot
            .getVaultPermissionStorage();
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        if (permission.inPrivateLiquidationMode) {
            ValidationLogic.validate(
                permission.isLiquidator[msg.sender],
                Errors.VAULT_INVALID_LIQUIDATOR
            );
        }
        uint256 markPrice = params.isLong
            ? GenericLogic.getMinPrice(params.indexToken)
            : GenericLogic.getMaxPrice(params.indexToken);

        BorrowingFeeLogic.updateCumulativeBorrowingRate(
            params.collateralToken,
            params.indexToken
        );
        FundingFeeLogic.updateFundingState(params.indexToken);

        bytes32 key = getPositionKey(
            params.account,
            params.collateralToken,
            params.indexToken,
            params.isLong
        );
        DataTypes.Position storage position = ps.positions[key];
        ValidationLogic.validate(
            position.size > 0,
            Errors.VAULT_EMPTY_POSITION
        );
        (uint256 liquidationState, uint256 marginFees) = validateLiquidation(
            params.account,
            params.collateralToken,
            params.indexToken,
            params.isLong,
            false
        );
        ValidationLogic.validate(
            liquidationState != 0,
            Errors.VAULT_POSITION_CAN_NOT_BE_LIQUIDATED
        );
        if (liquidationState == 2) {
            // max leverage exceeded but there is collateral remaining after deducting losses so decreasePosition instead
            _decreasePosition(
                DataTypes.DecreasePositionParams({
                    account: params.account,
                    collateralToken: params.collateralToken,
                    indexToken: params.indexToken,
                    collateralDelta: 0,
                    sizeDelta: position.size,
                    isLong: params.isLong,
                    receiver: params.account
                })
            );
            return;
        }
        uint256 feeTokens = GenericLogic.usdToTokenMin(
            params.collateralToken,
            marginFees
        );
        fs.feeReserves[params.collateralToken] =
            fs.feeReserves[params.collateralToken] +
            feeTokens;
        emit CollectMarginFees(params.collateralToken, marginFees, feeTokens);
        GenericLogic.decreaseReservedAmount(
            params.collateralToken,
            position.reserveAmount
        );
        if (params.isLong) {
            GenericLogic.decreaseGuaranteedEth(
                params.collateralToken,
                position.size - position.collateral
            );
            GenericLogic.decreasePoolAmount(
                params.collateralToken,
                GenericLogic.usdToTokenMin(params.collateralToken, marginFees)
            );
        }
        emit LiquidatePosition(
            key,
            params.account,
            params.collateralToken,
            params.indexToken,
            params.isLong,
            position.size,
            position.collateral,
            position.reserveAmount,
            position.realisedPnl,
            markPrice
        );
        if (!params.isLong && marginFees < position.collateral) {
            uint256 remainingCollateral = position.collateral - marginFees;
            uint256 amount = GenericLogic.usdToTokenMin(
                params.collateralToken,
                remainingCollateral
            );
            GenericLogic.increasePoolAmount(params.collateralToken, amount);
        }
        if (!params.isLong) {
            GenericLogic.decreaseGlobalShortSize(
                params.indexToken,
                position.size
            );
        }
        delete ps.positions[key];
        // pay the fee receiver using the pool, we assume that in general the liquidated amount should be sufficient to cover
        // the liquidation fees
        GenericLogic.decreasePoolAmount(
            params.collateralToken,
            GenericLogic.usdToTokenMin(
                params.collateralToken,
                fs.liquidationFeeEth
            )
        );
        GenericLogic.transferOut(
            params.collateralToken,
            GenericLogic.usdToTokenMin(
                params.collateralToken,
                fs.liquidationFeeEth
            ),
            params.feeReceiver
        );
    }

    function getPositionKey(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _account,
                    _collateralToken,
                    _indexToken,
                    _isLong
                )
            );
    }

    // for longs has position profit: nextAveragePrice = (nextPrice * nextSize)/ (nextSize + delta)
    // for longs has negative profit: nextAveragePrice = (nextPrice * nextSize)/ (nextSize - delta)
    // for shorts has position profit: nextAveragePrice = (nextPrice * nextSize) / (nextSize - delta)
    // for shorts has negative profit: nextAveragePrice = (nextPrice * nextSize) / (nextSize + delta)
    function getNextAveragePrice(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        uint256 _lastIncreasedTime
    ) internal view returns (uint256) {
        (bool hasProfit, uint256 delta) = getDelta(
            _indexToken,
            _size,
            _averagePrice,
            _isLong,
            _lastIncreasedTime
        );
        uint256 nextSize = _size + _sizeDelta;
        uint256 divisor;
        if (_isLong) {
            divisor = hasProfit ? nextSize + delta : nextSize - delta;
        } else {
            divisor = hasProfit ? nextSize - delta : nextSize + delta;
        }
        return (_nextPrice * nextSize) / divisor;
    }

    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _lastIncreasedTime
    ) internal view returns (bool, uint256) {
        ValidationLogic.validate(
            _averagePrice > 0,
            Errors.VAULT_INVALID_AVERAGE_PRICE
        );
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        uint256 price = _isLong
            ? GenericLogic.getMinPrice(_indexToken)
            : GenericLogic.getMaxPrice(_indexToken);
        uint256 priceDelta = _averagePrice > price
            ? _averagePrice - price
            : price - _averagePrice;
        uint256 delta = (_size * priceDelta) / _averagePrice;

        bool hasProfit;

        if (_isLong) {
            hasProfit = price > _averagePrice;
        } else {
            hasProfit = _averagePrice > price;
        }

        // if the minProfitTime has passed then there will be no min profit threshold
        // the min profit threshold helps to prevent front-running issues
        uint256 minBps = block.timestamp > _lastIncreasedTime + fs.minProfitTime
            ? 0
            : ts.minProfitBasisPoints[_indexToken];
        if (
            hasProfit && delta * Constants.PERCENTAGE_FACTOR <= _size * minBps
        ) {
            delta = 0;
        }

        return (hasProfit, delta);
    }

    function collectMarginFees(
        CollectMarginFeesParams memory params
    ) internal returns (uint256, DataTypes.PositionFundingFees memory) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        uint256 feeUsd = getPositionFee(
            params.account,
            params.collateralToken,
            params.indexToken,
            params.isLong,
            params.sizeDelta
        );

        uint256 borrowingFee = BorrowingFeeLogic.getBorrowingFee(
            params.account,
            params.collateralToken,
            params.indexToken,
            params.isLong,
            params.position.size,
            params.position.entryBorrowingRate
        );

        // funding fee
        DataTypes.PositionFundingFees
            memory positionFundingFees = FundingFeeLogic.getFundingFees(
                params.indexToken,
                params.isLong,
                params.position
            );

        // feeUsd = feeUsd + borrowingFee + positionFundingFees.fundingFeeAmount;
        feeUsd = feeUsd + borrowingFee;

        uint256 feeTokens = GenericLogic.usdToTokenMin(
            params.collateralToken,
            feeUsd
        );
        fs.feeReserves[params.collateralToken] =
            fs.feeReserves[params.collateralToken] +
            feeTokens;

        emit CollectMarginFees(params.collateralToken, feeUsd, feeTokens);
        return (feeUsd, positionFundingFees);
    }

    function getPositionFee(
        address /*_account*/,
        address /*_collateralToken*/,
        address /*_indexToken*/,
        bool /*_isLong*/,
        uint256 _sizeDelta
    ) internal view returns (uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        if (_sizeDelta == 0) {
            return 0;
        }
        uint256 afterFeeUsd = (_sizeDelta *
            (Constants.PERCENTAGE_FACTOR - fs.marginFeeBasisPoints)) /
            Constants.PERCENTAGE_FACTOR;
        return _sizeDelta - afterFeeUsd;
    }

    // validateLiquidation returns (state, fees)
    function validateLiquidation(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        bool _raise
    ) internal view returns (uint256, uint256) {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        DataTypes.Position storage position = ps.positions[key];

        (bool hasProfit, uint256 delta) = getDelta(
            _indexToken,
            position.size,
            position.averagePrice,
            _isLong,
            position.lastIncreasedTime
        );
        uint256 positionFee = getPositionFee(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            position.size
        );

        uint256 borrowingFee = BorrowingFeeLogic.getBorrowingFee(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            position.size,
            position.entryBorrowingRate
        );

        DataTypes.PositionFundingFees
            memory positionFundingFees = FundingFeeLogic.getFundingFees(
                _indexToken,
                _isLong,
                position
            );

        uint256 marginFees = positionFee +
            borrowingFee +
            positionFundingFees.fundingFeeAmount;

        if (!hasProfit && position.collateral < delta) {
            if (_raise) {
                revert("Vault: losses exceed collateral");
            }
            return (1, marginFees);
        }

        uint256 remainingCollateral = position.collateral;
        if (!hasProfit) {
            remainingCollateral = position.collateral - delta;
        }

        if (remainingCollateral < marginFees) {
            if (_raise) {
                revert("Vault: fees exceed collateral");
            }
            // cap the fees to the remainingCollateral
            return (1, remainingCollateral);
        }

        if (remainingCollateral < marginFees + fs.liquidationFeeEth) {
            if (_raise) {
                revert("Vault: liquidation fees exceed collateral");
            }
            return (1, marginFees);
        }

        if (
            remainingCollateral * ps.maxLeverage <
            position.size * Constants.PERCENTAGE_FACTOR
        ) {
            if (_raise) {
                revert("Vault: maxLeverage exceeded");
            }
            return (2, marginFees);
        }

        return (0, marginFees);
    }

    // For traders’ short position has negative profit: nextAveragePrice = (nextPrice * nextSize)/ (nextSize + delta)
    // For traders’ short position has position profit: nextAveragePrice = (nextPrice * nextSize) / (nextSize - delta)
    function getNextGlobalShortAveragePrice(
        address _indexToken,
        uint256 _nextPrice,
        uint256 _sizeDelta
    ) internal view returns (uint256) {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        uint256 size = ps.globalShortSizes[_indexToken];
        uint256 averagePrice = ps.globalShortAveragePrices[_indexToken];
        uint256 priceDelta = averagePrice > _nextPrice
            ? averagePrice - _nextPrice
            : _nextPrice - averagePrice;
        uint256 delta = (size * priceDelta) / averagePrice;
        bool hasProfit = averagePrice > _nextPrice;

        uint256 nextSize = size + _sizeDelta;
        uint256 divisor = hasProfit ? nextSize - delta : nextSize + delta;

        return (_nextPrice * nextSize) / divisor;
    }

    function reduceCollateral(
        DataTypes.DecreasePositionParams memory params,
        uint256 _reservedAmount
    )
        internal
        returns (uint256, uint256, DataTypes.PositionFundingFees memory)
    {
        ReduceCollateralCache memory cache;
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        bytes32 key = getPositionKey(
            params.account,
            params.collateralToken,
            params.indexToken,
            params.isLong
        );
        DataTypes.Position storage position = ps.positions[key];
        (cache.fee, cache.fundingFees) = collectMarginFees(
            CollectMarginFeesParams({
                account: params.account,
                collateralToken: params.collateralToken,
                indexToken: params.indexToken,
                isLong: params.isLong,
                sizeDelta: params.sizeDelta,
                position: position
            })
        );

        (cache.hasProfit, cache.delta) = getDelta(
            params.indexToken,
            position.size,
            position.averagePrice,
            params.isLong,
            position.lastIncreasedTime
        );
        // get the proportional change in pnl
        cache.adjustedDelta = (params.sizeDelta * cache.delta) / position.size;

        // transfer profits out
        if (cache.hasProfit && cache.adjustedDelta > 0) {
            cache.usdOut = cache.adjustedDelta;
            position.realisedPnl =
                position.realisedPnl +
                cache.adjustedDelta.toInt256();

            // pay out realised profits from the pool amount for short positions
            if (!params.isLong) {
                uint256 tokenAmount = GenericLogic.usdToTokenMin(
                    params.collateralToken,
                    cache.adjustedDelta
                );
                GenericLogic.decreasePoolAmount(
                    params.collateralToken,
                    tokenAmount
                );
            }
        }

        if (!cache.hasProfit && cache.adjustedDelta > 0) {
            position.collateral = position.collateral - cache.adjustedDelta;

            // transfer realised losses to the pool for short positions
            // realised losses for long positions are not transferred here as
            // _increasePoolAmount was already called in increasePosition for longs
            if (!params.isLong) {
                uint256 tokenAmount = GenericLogic.usdToTokenMin(
                    params.collateralToken,
                    cache.adjustedDelta
                );
                GenericLogic.increasePoolAmount(
                    params.collateralToken,
                    tokenAmount
                );
            }

            position.realisedPnl =
                position.realisedPnl -
                cache.adjustedDelta.toInt256();
        }

        // reduce the position's collateral by _collateralDelta
        // transfer _collateralDelta out
        if (params.collateralDelta > 0) {
            cache.usdOut += params.collateralDelta;
            position.collateral -= params.collateralDelta;
        }

        // if the position will be closed, then transfer the remaining collateral out
        if (position.size == params.sizeDelta) {
            cache.usdOut += position.collateral;
            position.collateral = 0;
        }

        // if the usdOut is more than the fee then deduct the fee from the usdOut directly
        // else deduct the fee from the position's collateral
        cache.usdOutAfterFee = cache.usdOut;
        if (cache.usdOut > cache.fee) {
            cache.usdOutAfterFee = cache.usdOut - cache.fee;
        } else {
            position.collateral -= cache.fee;
            if (params.isLong) {
                uint256 feeTokens = GenericLogic.usdToTokenMin(
                    params.collateralToken,
                    cache.fee
                );
                GenericLogic.decreasePoolAmount(
                    params.collateralToken,
                    feeTokens
                );
            }
        }

        // price impact
        uint256 priceMax = GenericLogic.getMaxPrice(params.indexToken);
        uint256 priceMin = GenericLogic.getMinPrice(params.indexToken);
        (int256 priceImpactUsd, ) = getExecutionPriceForDecrease(
            params,
            priceMax,
            priceMin,
            position.averagePrice,
            _reservedAmount
        );
        if (priceImpactUsd > 0) {
            cache.usdOutAfterFee += priceImpactUsd.toUint256();
        } else {
            if (cache.usdOutAfterFee > (-priceImpactUsd).toUint256()) {
                cache.usdOutAfterFee -= (-priceImpactUsd).toUint256();
            } else {
                cache.usdOutAfterFee = 0;
            }
        }
        // if there is a positive impact, the impact pool amount should be reduced
        // if there is a negative impact, the impact pool amount should be increased
        PositionPriceImpactLogic.applyDeltaToPositionImpactPool(
            params.indexToken,
            -(priceImpactUsd / priceMin.toInt256())
        );

        emit UpdatePnl(key, cache.hasProfit, cache.adjustedDelta);

        return (cache.usdOut, cache.usdOutAfterFee, cache.fundingFees);
    }

    function getPosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public view returns (DataTypes.Position memory) {
        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        return ps.positions[key];
    }

    function getPositionDelta(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (bool, uint256) {
        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        DataTypes.Position storage position = ps.positions[key];
        return
            getDelta(
                _indexToken,
                position.size,
                position.averagePrice,
                _isLong,
                position.lastIncreasedTime
            );
    }

    function getGlobalShortDelta(
        address _token
    ) public view returns (bool, uint256) {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        uint256 size = ps.globalShortSizes[_token];
        if (size == 0) {
            return (false, 0);
        }
        uint256 nextPrice = GenericLogic.getMaxPrice(_token);
        uint256 averagePrice = ps.globalShortAveragePrices[_token];
        uint256 priceDelta = averagePrice > nextPrice
            ? averagePrice - nextPrice
            : nextPrice - averagePrice;
        uint256 delta = (size * priceDelta) / averagePrice;
        bool hasProfit = averagePrice > nextPrice;
        return (hasProfit, delta);
    }

    function getPositionLeverage(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public view returns (uint256) {
        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        DataTypes.Position storage position = ps.positions[key];
        ValidationLogic.validate(
            position.collateral > 0,
            Errors.VAULT_INVALID_POSITION
        );
        return
            (position.size * Constants.PERCENTAGE_FACTOR) / position.collateral;
    }

    // returns priceImpactUsd, executionPrice
    function getExecutionPriceForIncrease(
        DataTypes.IncreasePositionParams memory params,
        uint256 _priceMax,
        uint256 _priceMin,
        uint256 _positionAveragePrice,
        uint256 _reservedAmount
    ) public view returns (int256, int256, uint256) {
        // note that the executionPrice is not validated against the order.acceptablePrice value
        // if the sizeDeltaUsd is zero
        // for limit orders the order.triggerPrice should still have been validated
        if (params.sizeDelta == 0) {
            // increase order:
            //     - long: use the larger price
            //     - short: use the smaller price
            if (params.isLong) {
                return (0, 0, _priceMax);
            } else {
                return (0, 0, _priceMin);
            }
        }

        int256 priceImpactUsd = PositionPriceImpactLogic.getPriceImpactUsd(
            PositionPriceImpactLogic.GetPriceImpactUsdParams(
                params.indexToken,
                params.sizeDelta.toInt256(),
                _priceMax,
                _positionAveragePrice,
                _reservedAmount,
                params.isLong
            )
        );
        if (priceImpactUsd == 0) {
            if (params.isLong) {
                return (0, 0, _priceMax);
            } else {
                return (0, 0, _priceMin);
            }
        }
        // cap priceImpactUsd based on the amount available in the position impact pool
        priceImpactUsd = PositionPriceImpactLogic.getCappedPositionImpactUsd(
            params.indexToken,
            _priceMin,
            priceImpactUsd
        );
        // for long positions
        //
        // if price impact is positive, the sizeDeltaInTokens would be increased by the priceImpactAmount
        // the priceImpactAmount should be minimized
        //
        // if price impact is negative, the sizeDeltaInTokens would be decreased by the priceImpactAmount
        // the priceImpactAmount should be maximized

        // for short positions
        //
        // if price impact is positive, the sizeDeltaInTokens would be decreased by the priceImpactAmount
        // the priceImpactAmount should be minimized
        //
        // if price impact is negative, the sizeDeltaInTokens would be increased by the priceImpactAmount
        // the priceImpactAmount should be maximized

        int256 priceImpactAmount;

        if (priceImpactUsd > 0) {
            // use indexTokenPrice.max and round down to minimize the priceImpactAmount
            priceImpactAmount =
                (priceImpactUsd * Constants.PRICE_PRECISION.toInt256()) /
                _priceMax.toInt256();
        } else {
            // use indexTokenPrice.min and round up to maximize the priceImpactAmount
            priceImpactAmount = Calc.roundUpMagnitudeDivision(
                priceImpactUsd * Constants.PRICE_PRECISION.toInt256(),
                _priceMin
            );
        }
        uint256 baseSizeDeltaInTokens;
        if (params.isLong) {
            // round the number of tokens for long positions down
            baseSizeDeltaInTokens =
                (params.sizeDelta * Constants.PRICE_PRECISION) /
                _priceMax;
        } else {
            // round the number of tokens for short positions up
            baseSizeDeltaInTokens = Calc.roundUpDivision(
                params.sizeDelta * Constants.PRICE_PRECISION,
                _priceMin
            );
        }
        int256 sizeDeltaInTokens;
        if (params.isLong) {
            sizeDeltaInTokens =
                baseSizeDeltaInTokens.toInt256() +
                priceImpactAmount;
        } else {
            sizeDeltaInTokens =
                baseSizeDeltaInTokens.toInt256() -
                priceImpactAmount;
        }
        if (sizeDeltaInTokens < 0) {
            revert("PriceImpact: PriceImpact Larger Than Order Size");
        }

        // using increase of long positions as an example
        // if price is $2000, sizeDeltaUsd is $5000, priceImpactUsd is -$1000
        // priceImpactAmount = -1000 / 2000 = -0.5
        // baseSizeDeltaInTokens = 5000 / 2000 = 2.5
        // sizeDeltaInTokens = 2.5 - 0.5 = 2
        // executionPrice = 5000 / 2 = $2500
        uint256 executionPrice = (params.sizeDelta *
            Constants.PRICE_PRECISION) / sizeDeltaInTokens.toUint256();

        return (priceImpactUsd, priceImpactAmount, executionPrice);
    }

    // returns priceImpactUsd, priceImpactDiffUsd, executionPrice
    function getExecutionPriceForDecrease(
        DataTypes.DecreasePositionParams memory params,
        uint256 _priceMax,
        uint256 _priceMin,
        uint256 _positionAveragePrice,
        uint256 reservedAmount
    ) public view returns (int256, uint256) {
        ExecutionPriceForDecreaseCache memory cache;
        // note that the executionPrice is not validated against the order.acceptablePrice value
        // if the sizeDeltaUsd is zero
        // for limit orders the order.triggerPrice should still have been validated
        if (params.sizeDelta == 0) {
            // decrease order:
            //     - long: use the smaller price
            //     - short: use the larger price
            if (params.isLong) {
                return (0, _priceMin);
            } else {
                return (0, _priceMax);
            }
        }

        cache.priceImpactUsd = PositionPriceImpactLogic.getPriceImpactUsd(
            PositionPriceImpactLogic.GetPriceImpactUsdParams(
                params.indexToken,
                -params.sizeDelta.toInt256(),
                _priceMax,
                _positionAveragePrice,
                reservedAmount,
                params.isLong
            )
        );
        if (cache.priceImpactUsd == 0) {
            if (params.isLong) {
                return (0, _priceMin);
            } else {
                return (0, _priceMax);
            }
        }

        cache.executionPrice = (params.isLong ? _priceMin : _priceMax)
            .toInt256();
        // cap priceImpactUsd based on the amount available in the position impact pool
        cache.priceImpactUsd = PositionPriceImpactLogic
            .getCappedPositionImpactUsd(
                params.indexToken,
                _priceMin,
                cache.priceImpactUsd
            );
        bytes32 key = getPositionKey(
            params.account,
            params.collateralToken,
            params.indexToken,
            params.isLong
        );
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        DataTypes.Position storage position = ps.positions[key];
        if (params.sizeDelta > 0 && position.size > 0) {
            int256 adjustedPriceImpactUsd = params.isLong
                ? cache.priceImpactUsd
                : -cache.priceImpactUsd;

            if (
                adjustedPriceImpactUsd < 0 &&
                (-adjustedPriceImpactUsd).toUint256() > params.sizeDelta
            ) {
                revert("PriceImpact: PriceImpact Larger Than Order Size");
            }

            int256 adjustment = Precision.mulDiv(
                position.averagePrice,
                adjustedPriceImpactUsd,
                params.sizeDelta
            );
            cache.executionPrice += adjustment;

            if (cache.executionPrice < 0) {
                revert("PriceImpact: negative Execution Price");
            }
        }

        return (cache.priceImpactUsd, cache.executionPrice.toUint256());
    }

    // function getFundingFeeAmount(
    //     address _account
    // ) external view returns (uint256) {
    //     DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();

    //     (uint256 length, address[] memory allWhitelistedTokens) = GenericLogic
    //         .getWhitelistedToken();

    //     uint256 totalClaimableFundingAmount;
    //     for (uint256 i = 0; i < length; i++) {
    //         address token = allWhitelistedTokens[i];
    //         DataTypes.TokenInfo memory tokenInfo = GenericLogic.getTokenInfo(
    //             token
    //         );

    //         if (!tokenInfo.isWhitelistedToken) {
    //             continue;
    //         }
    //         uint256 claimableFundingAmount = fs.claimableFundingAmount[
    //             _account
    //         ][token];
    //         if (tokenInfo.isNftToken) {
    //             uint256 price = GenericLogic.getMinPrice(token);
    //             claimableFundingAmount =
    //                 (claimableFundingAmount * price) /
    //                 Constants.PRICE_PRECISION;
    //         }
    //         totalClaimableFundingAmount += claimableFundingAmount;
    //     }
    //     return totalClaimableFundingAmount;
    // }

    // function claimFundingFees(
    //     address _account,
    //     address _receiver
    // ) external returns (uint256) {
    //     DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
    //     DataTypes.AddressStorage storage addrs = StorageSlot
    //         .getVaultAddressStorage();

    //     (uint256 length, address[] memory allWhitelistedTokens) = GenericLogic
    //         .getWhitelistedToken();

    //     uint256 totalClaimableFundingAmount;

    //     for (uint256 i = 0; i < length; i++) {
    //         address token = allWhitelistedTokens[i];
    //         DataTypes.TokenInfo memory tokenInfo = GenericLogic.getTokenInfo(
    //             token
    //         );

    //         if (!tokenInfo.isWhitelistedToken) {
    //             continue;
    //         }
    //         uint256 claimableFundingAmount = fs.claimableFundingAmount[
    //             _account
    //         ][token];

    //         if (tokenInfo.isNftToken) {
    //             claimableFundingAmount =
    //                 (claimableFundingAmount * GenericLogic.getMinPrice(token)) /
    //                 GenericLogic.getMaxPrice(addrs.weth);
    //             claimableFundingAmount = GenericLogic.adjustForDecimals(
    //                 claimableFundingAmount,
    //                 token,
    //                 addrs.weth
    //             );
    //             totalClaimableFundingAmount += claimableFundingAmount;
    //             fs.claimableFundingAmount[_account][token] = 0;
    //         }
    //     }
    //     if (totalClaimableFundingAmount > 0) {
    //         GenericLogic.transferOut(
    //             addrs.weth,
    //             totalClaimableFundingAmount,
    //             _receiver
    //         );
    //         emit ClaimFundingFee(
    //             _account,
    //             addrs.weth,
    //             totalClaimableFundingAmount
    //         );
    //     }
    //     return totalClaimableFundingAmount;
    // }
}
