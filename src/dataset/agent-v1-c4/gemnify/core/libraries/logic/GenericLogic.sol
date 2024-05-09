// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import {ValidationLogic} from "./ValidationLogic.sol";
import {StorageSlot} from "./StorageSlot.sol";

import {Constants} from "../helpers/Constants.sol";
import {Errors} from "../helpers/Errors.sol";
import {DataTypes} from "../types/DataTypes.sol";

import {IVaultPriceFeed} from "../../interfaces/IVaultPriceFeed.sol";
import {INFTOracleGetter} from "../../BendDAO/interfaces/INFTOracleGetter.sol";

library GenericLogic {
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event CollectSwapFees(address token, uint256 feeUsd, uint256 feeTokens);
    event IncreasePoolAmount(address token, uint256 amount);
    event DecreasePoolAmount(address token, uint256 amount);
    event IncreaseEthgAmount(address token, uint256 amount);
    event DecreaseEthgAmount(address token, uint256 amount);
    event IncreaseReservedAmount(address token, uint256 amount);
    event DecreaseReservedAmount(address token, uint256 amount);
    event IncreaseGuaranteedEth(address token, uint256 amount);
    event DecreaseGuaranteedEth(address token, uint256 amount);

    function collectSwapFees(
        address _token,
        uint256 _amount,
        uint256 _feeBasisPoints
    ) internal returns (uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        uint256 afterFeeAmount = (_amount *
            (Constants.PERCENTAGE_FACTOR - _feeBasisPoints)) /
            Constants.PERCENTAGE_FACTOR;
        uint256 feeAmount = _amount - afterFeeAmount;
        fs.feeReserves[_token] = fs.feeReserves[_token] + feeAmount;
        emit CollectSwapFees(
            _token,
            tokenToUsdMin(_token, feeAmount),
            feeAmount
        );
        return afterFeeAmount;
    }

    // cases to consider
    // 1. initialAmount is far from targetAmount, action increases balance slightly => high rebate
    // 2. initialAmount is far from targetAmount, action increases balance largely => high rebate
    // 3. initialAmount is close to targetAmount, action increases balance slightly => low rebate
    // 4. initialAmount is far from targetAmount, action reduces balance slightly => high tax
    // 5. initialAmount is far from targetAmount, action reduces balance largely => high tax
    // 6. initialAmount is close to targetAmount, action reduces balance largely => low tax
    // 7. initialAmount is above targetAmount, nextAmount is below targetAmount and vice versa
    // 8. a large swap should have similar fees as the same trade split into multiple smaller swaps
    function getFeeBasisPoints(
        address _token,
        uint256 _ethgDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) internal view returns (uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        if (!fs.hasDynamicFees) {
            return _feeBasisPoints;
        }

        uint256 initialAmount = ps.ethgAmounts[_token];
        uint256 nextAmount = initialAmount + _ethgDelta;
        if (!_increment) {
            nextAmount = _ethgDelta > initialAmount
                ? 0
                : initialAmount - _ethgDelta;
        }

        uint256 targetAmount = getTargetEthgAmount(_token);
        if (targetAmount == 0) {
            return _feeBasisPoints;
        }

        uint256 initialDiff = initialAmount > targetAmount
            ? initialAmount - targetAmount
            : targetAmount - initialAmount;
        uint256 nextDiff = nextAmount > targetAmount
            ? nextAmount - targetAmount
            : targetAmount - nextAmount;

        // action improves relative asset balance
        if (nextDiff < initialDiff) {
            uint256 rebateBps = (_taxBasisPoints * initialDiff) / targetAmount;
            return
                rebateBps > _feeBasisPoints ? 0 : _feeBasisPoints - rebateBps;
        }

        uint256 averageDiff = (initialDiff + nextDiff) / 2;
        if (averageDiff > targetAmount) {
            averageDiff = targetAmount;
        }
        uint256 taxBps = (_taxBasisPoints * averageDiff) / targetAmount;
        return _feeBasisPoints + taxBps;
    }

    function adjustForDecimals(
        uint256 _amount,
        address _tokenDiv,
        address _tokenMul
    ) internal view returns (uint256) {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        uint256 decimalsDiv = _tokenDiv == addrs.ethg
            ? Constants.ETHG_DECIMALS
            : ts.tokenDecimals[_tokenDiv];
        uint256 decimalsMul = _tokenMul == addrs.ethg
            ? Constants.ETHG_DECIMALS
            : ts.tokenDecimals[_tokenMul];
        return (_amount * 10 ** decimalsMul) / 10 ** decimalsDiv;
    }

    function adjustFor30Decimals(
        uint256 _amount,
        address _tokenMul
    ) internal view returns (uint256) {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        uint256 decimalsDiv = Constants.PRICE_PRECISION;
        uint256 decimalsMul = ts.tokenDecimals[_tokenMul];
        return (_amount * 10 ** decimalsMul) / decimalsDiv;
    }

    function getMaxPrice(address _token) internal view returns (uint256) {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        return IVaultPriceFeed(addrs.priceFeed).getPrice(_token, true);
    }

    function getMinPrice(address _token) internal view returns (uint256) {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        return IVaultPriceFeed(addrs.priceFeed).getPrice(_token, false);
    }

    function tokenToUsdMin(
        address _token,
        uint256 _tokenAmount
    ) internal view returns (uint256) {
        if (_tokenAmount == 0) {
            return 0;
        }
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        uint256 price = getMinPrice(_token);
        uint256 decimals = ts.tokenDecimals[_token];
        return (_tokenAmount * price) / 10 ** decimals;
    }

    function usdToTokenMax(
        address _token,
        uint256 _usdAmount
    ) internal view returns (uint256) {
        if (_usdAmount == 0) {
            return 0;
        }
        return usdToToken(_token, _usdAmount, getMinPrice(_token));
    }

    function usdToTokenMin(
        address _token,
        uint256 _usdAmount
    ) internal view returns (uint256) {
        if (_usdAmount == 0) {
            return 0;
        }
        return usdToToken(_token, _usdAmount, getMaxPrice(_token));
    }

    function usdToToken(
        address _token,
        uint256 _usdAmount,
        uint256 _price
    ) internal view returns (uint256) {
        if (_usdAmount == 0) {
            return 0;
        }
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        uint256 decimals = ts.tokenDecimals[_token];
        return (_usdAmount * 10 ** decimals) / _price;
    }

    function getTargetEthgAmount(
        address _token
    ) internal view returns (uint256) {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        uint256 supply = IERC20Upgradeable(addrs.ethg).totalSupply();
        if (supply == 0) {
            return 0;
        }
        uint256 weight = ts.tokenWeights[_token];
        return (weight * supply) / ts.totalTokenWeights;
    }

    function transferIn(address _token) internal returns (uint256) {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        uint256 prevBalance = ps.tokenBalances[_token];
        uint256 nextBalance = IERC20Upgradeable(_token).balanceOf(
            address(this)
        );
        ps.tokenBalances[_token] = nextBalance;

        return nextBalance - prevBalance;
    }

    function transferOut(
        address _token,
        uint256 _amount,
        address _receiver
    ) internal {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        IERC20Upgradeable(_token).safeTransfer(_receiver, _amount);
        ps.tokenBalances[_token] = IERC20Upgradeable(_token).balanceOf(
            address(this)
        );
    }

    function getRedemptionAmount(
        address _token,
        uint256 _ethgAmount
    ) internal view returns (uint256) {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        uint256 price = getMaxPrice(_token);
        uint256 redemptionAmount = (_ethgAmount * Constants.PRICE_PRECISION) /
            price;

        return adjustForDecimals(redemptionAmount, addrs.ethg, _token);
    }

    function increasePoolAmount(address _token, uint256 _amount) internal {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        ps.poolAmounts[_token] += _amount;
        uint256 balance = IERC20Upgradeable(_token).balanceOf(address(this));
        ValidationLogic.validate(
            ps.poolAmounts[_token] <= balance,
            Errors.VAULT_POOL_AMOUNT_EXCEEDED
        );
        emit IncreasePoolAmount(_token, _amount);
    }

    function decreasePoolAmount(address _token, uint256 _amount) internal {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        ValidationLogic.validate(
            ps.poolAmounts[_token] >= _amount,
            Errors.VAULT_POOL_AMOUNT_EXCEEDED
        );
        ps.poolAmounts[_token] -= _amount;
        ValidationLogic.validate(
            ps.reservedAmounts[_token] <= ps.poolAmounts[_token],
            Errors.VAULT_RESERVE_EXCEEDS_POOL
        );
        emit DecreasePoolAmount(_token, _amount);
    }

    function increaseEthgAmount(address _token, uint256 _amount) internal {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        ps.ethgAmounts[_token] = ps.ethgAmounts[_token] + _amount;
        uint256 maxEthgAmount = ts.maxEthgAmounts[_token];
        if (maxEthgAmount != 0) {
            ValidationLogic.validate(
                ps.ethgAmounts[_token] <= maxEthgAmount,
                Errors.VAULT_MAX_ETHG_EXCEEDED
            );
        }
        emit IncreaseEthgAmount(_token, _amount);
    }

    function decreaseEthgAmount(address _token, uint256 _amount) internal {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        uint256 value = ps.ethgAmounts[_token];
        // since ETHG can be minted using multiple assets
        // it is possible for the ETHG debt for a single asset to be less than zero
        // the ETHG debt is capped to zero for this case
        if (value <= _amount) {
            ps.ethgAmounts[_token] = 0;
            emit DecreaseEthgAmount(_token, value);
            return;
        }
        ps.ethgAmounts[_token] = value - _amount;
        emit DecreaseEthgAmount(_token, _amount);
    }

    function increaseReservedAmount(address _token, uint256 _amount) internal {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        ps.reservedAmounts[_token] = ps.reservedAmounts[_token] + _amount;
        ValidationLogic.validate(
            ps.reservedAmounts[_token] <= ps.poolAmounts[_token],
            Errors.VAULT_RESERVE_EXCEEDS_POOL
        );
        emit IncreaseReservedAmount(_token, _amount);
    }

    function decreaseReservedAmount(address _token, uint256 _amount) internal {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        ValidationLogic.validate(
            ps.reservedAmounts[_token] - _amount >= 0,
            Errors.VAULT_INSUFFICIENT_RESERVE
        );
        ps.reservedAmounts[_token] -= _amount;
        emit DecreaseReservedAmount(_token, _amount);
    }

    function increaseGuaranteedEth(
        address _token,
        uint256 _ethAmount
    ) internal {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        ps.guaranteedEth[_token] = ps.guaranteedEth[_token] + _ethAmount;
        emit IncreaseGuaranteedEth(_token, _ethAmount);
    }

    function decreaseGuaranteedEth(
        address _token,
        uint256 _ethAmount
    ) internal {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        ps.guaranteedEth[_token] = ps.guaranteedEth[_token] - _ethAmount;
        emit DecreaseGuaranteedEth(_token, _ethAmount);
    }

    function increaseGlobalShortSize(address _token, uint256 _amount) internal {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        ps.globalShortSizes[_token] = ps.globalShortSizes[_token] + _amount;
        uint256 maxSize = ps.maxGlobalShortSizes[_token];
        if (maxSize != 0) {
            ValidationLogic.validate(
                ps.globalShortSizes[_token] <= maxSize,
                Errors.VAULT_MAX_SHORTS_EXCEEDED
            );
        }
    }

    function decreaseGlobalShortSize(address _token, uint256 _amount) internal {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        uint256 size = ps.globalShortSizes[_token];
        if (_amount > size) {
            ps.globalShortSizes[_token] = 0;
            return;
        }

        ps.globalShortSizes[_token] = size - _amount;
    }

    function updateTokenBalance(address _token) internal {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        uint256 nextBalance = IERC20Upgradeable(_token).balanceOf(
            address(this)
        );
        ps.tokenBalances[_token] = nextBalance;
    }

    function withdrawFees(
        address _token,
        address _receiver
    ) external returns (uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        uint256 amount = fs.feeReserves[_token];
        if (amount == 0) {
            return 0;
        }
        fs.feeReserves[_token] = 0;
        transferOut(_token, amount, _receiver);
        return amount;
    }

    function getPoolInfo(
        address _token
    )
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        address token = _token;
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        return (
            ps.poolAmounts[token],
            ps.reservedAmounts[token],
            ps.bufferAmounts[token],
            ps.guaranteedEth[token],
            ps.globalShortSizes[token],
            ps.globalShortAveragePrices[token],
            ps.ethgAmounts[token]
        );
    }

    function getWhitelistedToken()
        internal
        view
        returns (uint256, address[] memory)
    {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        return (ts.whitelistedTokenCount, ts.allWhitelistedTokens);
    }

    function getTokenInfo(
        address _token
    ) internal view returns (DataTypes.TokenInfo memory) {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();

        return
            DataTypes.TokenInfo({
                tokenDecimal: ts.tokenDecimals[_token],
                isWhitelistedToken: ts.whitelistedTokens[_token],
                isStableToken: ts.stableTokens[_token],
                isNftToken: ts.nftTokens[_token]
            });
    }

    function getBuyEthgFeeBasisPoints(
        address _token,
        uint256 _ethgAmount
    ) internal view returns (uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        return
            getFeeBasisPoints(
                _token,
                _ethgAmount,
                fs.mintBurnFeeBasisPoints,
                fs.taxBasisPoints,
                true
            );
    }

    function getSellEthgFeeBasisPoints(
        address _token,
        uint256 _ethgAmount
    ) internal view returns (uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        return
            getFeeBasisPoints(
                _token,
                _ethgAmount,
                fs.mintBurnFeeBasisPoints,
                fs.taxBasisPoints,
                false
            );
    }

    function getBendDAOAssetPrice(
        address _nft
    ) external view returns (uint256) {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        return INFTOracleGetter(addrs.bendOracle).getAssetPrice(_nft);
    }

    function getRedemptionCollateral(
        address _token
    ) public view returns (uint256, uint256) {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        if (ts.stableTokens[_token]) {
            return (
                ps.poolAmounts[_token],
                tokenToUsdMin(_token, ps.poolAmounts[_token])
            );
        }
        uint256 collateral = usdToTokenMin(_token, ps.guaranteedEth[_token]);
        uint256 amount = collateral +
            ps.poolAmounts[_token] -
            ps.reservedAmounts[_token];
        return (amount, tokenToUsdMin(_token, amount));
    }

    function getUtilisation(address _token) public view returns (uint256) {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        uint256 poolAmount = ps.poolAmounts[_token];
        if (poolAmount == 0) {
            return 0;
        }
        return
            (ps.reservedAmounts[_token] * Constants.BORROWING_RATE_PRECISION) /
            poolAmount;
    }
}
