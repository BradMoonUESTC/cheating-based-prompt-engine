// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DataTypes} from "../types/DataTypes.sol";
import {Errors} from "../helpers/Errors.sol";
import {Calc} from "../math/Calc.sol";
import {Precision} from "../math/Precision.sol";
import {StorageSlot} from "./StorageSlot.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {Constants} from "../helpers/Constants.sol";

struct PositionType {
    uint256 long;
    uint256 short;
}

struct GetNextFundingAmountPerSizeResult {
    bool longsPayShorts;
    uint256 fundingFactorPerSecond;
    int256 nextSavedFundingFactorPerSecond;
    PositionType fundingFeeAmountPerSizeDelta;
    PositionType claimableFundingAmountPerSizeDelta;
}

struct GetNextFundingAmountPerSizeCache {
    uint256 longOpenInterest;
    uint256 shortOpenInterest;
    uint256 durationInSeconds;
    uint256 sizeOfLargerSide;
    uint256 fundingUsd;
}

struct GetNextFundingFactorPerSecondCache {
    uint256 diffUsd;
    uint256 totalOpenInterest;
    uint256 fundingFactor;
    uint256 fundingExponentFactor;
    uint256 diffUsdAfterExponent;
    uint256 diffUsdToOpenInterestFactor;
}

library FundingFeeLogic {
    event ClaimFundingFee(
        address indexed account,
        address token,
        uint256 amount
    );

    function getFundingFees(
        address _indexToken,
        bool _isLong,
        DataTypes.Position memory position
    ) internal view returns (DataTypes.PositionFundingFees memory) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        DataTypes.PositionFundingFees memory positionFundingFees;

        positionFundingFees.latestFundingFeeAmountPerSize = fs
            .fundingFeeAmountPerSizes[_indexToken][_isLong];
        positionFundingFees.latestClaimableFundingAmountPerSize = fs
            .claimableFundingAmountPerSizes[_indexToken][_isLong];

        positionFundingFees.fundingFeeAmount = getFundingAmount(
            positionFundingFees.latestFundingFeeAmountPerSize,
            position.fundingFeeAmountPerSize,
            position.size,
            true // roundUpMagnitude
        );

        positionFundingFees.claimableAmount = getFundingAmount(
            positionFundingFees.latestClaimableFundingAmountPerSize,
            position.claimableFundingAmountPerSize,
            position.size,
            false // roundUpMagnitude
        );

        return positionFundingFees;
    }

    function updateFundingState(address _indexToken) internal {
        DataTypes.FeeStorage storage fee = StorageSlot.getVaultFeeStorage();

        GetNextFundingAmountPerSizeResult
            memory result = getNextFundingAmountPerSize(_indexToken);

        fee.fundingFeeAmountPerSizes[_indexToken][true] += result
            .fundingFeeAmountPerSizeDelta
            .long;
        fee.fundingFeeAmountPerSizes[_indexToken][false] += result
            .fundingFeeAmountPerSizeDelta
            .short;
        fee.claimableFundingAmountPerSizes[_indexToken][true] += result
            .claimableFundingAmountPerSizeDelta
            .long;
        fee.claimableFundingAmountPerSizes[_indexToken][false] += result
            .claimableFundingAmountPerSizeDelta
            .short;

        fee.lastFundingTimes[_indexToken] = block.timestamp;
    }

    function getNextFundingAmountPerSize(
        address _indexToken
    ) internal view returns (GetNextFundingAmountPerSizeResult memory) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();

        GetNextFundingAmountPerSizeResult memory result;
        GetNextFundingAmountPerSizeCache memory cache;
        cache.longOpenInterest = getOpenInterest(_indexToken, true);
        cache.shortOpenInterest = getOpenInterest(_indexToken, false);
        if (cache.longOpenInterest == 0 || cache.shortOpenInterest == 0) {
            return result;
        }
        cache.durationInSeconds =
            block.timestamp -
            fs.lastFundingTimes[_indexToken];

        cache.sizeOfLargerSide = cache.longOpenInterest >
            cache.shortOpenInterest
            ? cache.longOpenInterest
            : cache.shortOpenInterest;

        (
            result.fundingFactorPerSecond,
            result.longsPayShorts
        ) = getNextFundingFactorPerSecond(
            _indexToken,
            cache.longOpenInterest,
            cache.shortOpenInterest
        );
        cache.fundingUsd = Precision.applyFactor(
            cache.sizeOfLargerSide,
            cache.durationInSeconds * result.fundingFactorPerSecond
        );
        uint256 indexTokenPrice = GenericLogic.getMaxPrice(_indexToken);
        uint256 shortTokenPrice = Constants.PRICE_PRECISION;
        if (result.longsPayShorts) {
            result
                .fundingFeeAmountPerSizeDelta
                .long = getFundingAmountPerSizeDelta(
                cache.fundingUsd,
                cache.longOpenInterest,
                indexTokenPrice,
                true // roundUpMagnitude
            );

            result
                .claimableFundingAmountPerSizeDelta
                .short = getFundingAmountPerSizeDelta(
                cache.fundingUsd,
                cache.shortOpenInterest,
                indexTokenPrice,
                false // roundUpMagnitude
            );
        } else {
            result
                .fundingFeeAmountPerSizeDelta
                .short = getFundingAmountPerSizeDelta(
                cache.fundingUsd,
                cache.shortOpenInterest,
                shortTokenPrice,
                true // roundUpMagnitude
            );

            result
                .claimableFundingAmountPerSizeDelta
                .long = getFundingAmountPerSizeDelta(
                cache.fundingUsd,
                cache.longOpenInterest,
                shortTokenPrice,
                false // roundUpMagnitude
            );
        }

        return result;
    }

    // @dev get the next funding factor per second
    // @return nextFundingFactorPerSecond, longsPayShorts
    function getNextFundingFactorPerSecond(
        address _indexToken,
        uint256 _longOpenInterest,
        uint256 _shortOpenInterest
    ) internal view returns (uint256, bool) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();

        GetNextFundingFactorPerSecondCache memory cache;

        cache.diffUsd = Calc.diff(_longOpenInterest, _shortOpenInterest);
        cache.totalOpenInterest = _longOpenInterest + _shortOpenInterest;
        if (cache.diffUsd == 0) {
            return (0, true);
        }

        require(cache.totalOpenInterest > 0, Errors.EMPTY_OPEN_INTEREST);

        cache.fundingExponentFactor = fs.fundingExponentFactors[_indexToken];
        cache.diffUsdAfterExponent = Precision.applyExponentFactor(
            cache.diffUsd,
            cache.fundingExponentFactor
        );
        cache.diffUsdToOpenInterestFactor = Precision.toFactor(
            cache.diffUsdAfterExponent,
            cache.totalOpenInterest
        );
        cache.fundingFactor = fs.fundingFactors[_indexToken];

        return (
            Precision.applyFactor(
                cache.diffUsdToOpenInterestFactor,
                cache.fundingFactor
            ),
            _longOpenInterest > _shortOpenInterest
        );
    }

    // store funding values as token amount per (Precision.FLOAT_PRECISION_SQRT / Precision.FLOAT_PRECISION) of USD size
    function getFundingAmountPerSizeDelta(
        uint256 fundingUsd,
        uint256 openInterest,
        uint256 tokenPrice,
        bool roundUpMagnitude
    ) internal pure returns (uint256) {
        if (fundingUsd == 0 || openInterest == 0) {
            return 0;
        }

        uint256 fundingUsdPerSize = Precision.mulDiv(
            fundingUsd,
            Precision.FLOAT_PRECISION * Precision.FLOAT_PRECISION_SQRT,
            openInterest,
            roundUpMagnitude
        );

        if (roundUpMagnitude) {
            return Calc.roundUpDivision(fundingUsdPerSize, tokenPrice);
        } else {
            return fundingUsdPerSize / tokenPrice;
        }
    }

    function getOpenInterest(
        address _indexToken,
        bool _isLong
    ) internal view returns (uint256) {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();

        if (_isLong) {
            DataTypes.TokenInfo memory tokenInfo = GenericLogic.getTokenInfo(
                _indexToken
            );
            uint256 price = GenericLogic.getMaxPrice(_indexToken);
            uint256 reserveAmount = ps.reservedAmounts[_indexToken];
            return (reserveAmount * price) / 10 ** tokenInfo.tokenDecimal;
        } else {
            return ps.globalShortSizes[_indexToken];
        }
    }

    // @dev get the funding amount to be deducted or distributed
    //
    // @param latestFundingAmountPerSize the latest funding amount per size
    // @param positionFundingAmountPerSize the funding amount per size for the position
    // @param positionSizeInUsd the position size in USD
    // @param roundUpMagnitude whether the round up the result
    //
    // @return fundingAmount
    function getFundingAmount(
        uint256 latestFundingAmountPerSize,
        uint256 positionFundingAmountPerSize,
        uint256 positionSizeInUsd,
        bool roundUpMagnitude
    ) internal pure returns (uint256) {
        uint256 fundingDiffFactor = (latestFundingAmountPerSize -
            positionFundingAmountPerSize);

        // a user could avoid paying funding fees by continually updating the position
        // before the funding fee becomes large enough to be chargeable
        // to avoid this, funding fee amounts should be rounded up
        //
        // this could lead to large additional charges if the token has a low number of decimals
        // or if the token's value is very high, so care should be taken to inform users of this
        //
        // if the calculation is for the claimable amount, the amount should be rounded down instead

        // divide the result by Precision.FLOAT_PRECISION * Precision.FLOAT_PRECISION_SQRT as the fundingAmountPerSize values
        // are stored based on FLOAT_PRECISION_SQRT values
        return
            Precision.mulDiv(
                positionSizeInUsd,
                fundingDiffFactor,
                Precision.FLOAT_PRECISION * Precision.FLOAT_PRECISION_SQRT,
                roundUpMagnitude
            );
    }

    function incrementClaimableFundingAmount(
        address _account,
        address _token,
        DataTypes.PositionFundingFees memory positionFundingFees
    ) internal {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        // if the position has negative funding fees, distribute it to allow it to be claimable
        if (positionFundingFees.claimableAmount > 0) {
            fs.claimableFundingAmount[_account][_token] += positionFundingFees
                .claimableAmount;
        }
    }

    function getFundingFeeAmount(
        address _account
    ) external view returns (uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();

        (uint256 length, address[] memory allWhitelistedTokens) = GenericLogic
            .getWhitelistedToken();

        uint256 totalClaimableFundingAmount;
        for (uint256 i = 0; i < length; i++) {
            address token = allWhitelistedTokens[i];
            DataTypes.TokenInfo memory tokenInfo = GenericLogic.getTokenInfo(
                token
            );

            if (!tokenInfo.isWhitelistedToken) {
                continue;
            }
            uint256 claimableFundingAmount = fs.claimableFundingAmount[
                _account
            ][token];
            if (tokenInfo.isNftToken) {
                uint256 price = GenericLogic.getMinPrice(token);
                claimableFundingAmount =
                    (claimableFundingAmount * price) /
                    Constants.PRICE_PRECISION;
            }
            totalClaimableFundingAmount += claimableFundingAmount;
        }
        return totalClaimableFundingAmount;
    }

    function claimFundingFees(
        address _account,
        address _receiver
    ) external returns (uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();

        (uint256 length, address[] memory allWhitelistedTokens) = GenericLogic
            .getWhitelistedToken();

        uint256 totalClaimableFundingAmount;

        for (uint256 i = 0; i < length; i++) {
            address token = allWhitelistedTokens[i];
            DataTypes.TokenInfo memory tokenInfo = GenericLogic.getTokenInfo(
                token
            );

            if (!tokenInfo.isWhitelistedToken) {
                continue;
            }
            uint256 claimableFundingAmount = fs.claimableFundingAmount[
                _account
            ][token];

            if (tokenInfo.isNftToken) {
                claimableFundingAmount =
                    (claimableFundingAmount * GenericLogic.getMinPrice(token)) /
                    GenericLogic.getMaxPrice(addrs.weth);
                claimableFundingAmount = GenericLogic.adjustForDecimals(
                    claimableFundingAmount,
                    token,
                    addrs.weth
                );
                totalClaimableFundingAmount += claimableFundingAmount;
                fs.claimableFundingAmount[_account][token] = 0;
            }
        }
        if (totalClaimableFundingAmount > 0) {
            GenericLogic.transferOut(
                addrs.weth,
                totalClaimableFundingAmount,
                _receiver
            );
            emit ClaimFundingFee(
                _account,
                addrs.weth,
                totalClaimableFundingAmount
            );
        }
        return totalClaimableFundingAmount;
    }
}
