// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ValidationLogic} from "./ValidationLogic.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {BorrowingFeeLogic} from "./BorrowingFeeLogic.sol";
import {SwapPriceImpactLogic} from "./priceImpact/SwapPriceImpactLogic.sol";
import {NftLogic} from "./NftLogic.sol";
import {StorageSlot} from "./StorageSlot.sol";
import {Errors} from "../helpers/Errors.sol";
import {Constants} from "../helpers/Constants.sol";
import {DataTypes} from "../types/DataTypes.sol";

import {IETHG} from "../../../tokens/interfaces/IETHG.sol";
import {INFTOracleGetter} from "../../BendDAO/interfaces/INFTOracleGetter.sol";
import {IVault} from "../../interfaces/IVault.sol";
import {INToken} from "../../interfaces/INToken.sol";

library SupplyLogic {
    using SafeCast for uint256;
    using SafeCast for int256;

    event DirectPoolDeposit(address token, uint256 amount);

    event BuyETHG(
        address account,
        address token,
        uint256 tokenAmount,
        uint256 ethgAmount,
        uint256 feeBasisPoints,
        int256 priceImpactUsd
    );
    event SellETHG(
        address account,
        address token,
        uint256 ethgAmount,
        uint256 tokenAmount,
        uint256 feeBasisPoints,
        int256 priceImpactUsd
    );

    function ExecuteBuyETHG(
        address _token,
        address _receiver
    ) external returns (uint256) {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        ValidationLogic.validateManager();
        ValidationLogic.validateWhitelistedToken(_token);

        uint256 tokenAmount;

        tokenAmount = GenericLogic.transferIn(_token);

        ValidationLogic.validate(
            tokenAmount > 0,
            Errors.VAULT_INVALID_TOKEN_AMOUNT
        );

        BorrowingFeeLogic.updateCumulativeBorrowingRate(_token, _token);

        uint256 price = GenericLogic.getMinPrice(_token);
        if (ts.nftTokens[_token]) {
            uint256 priceBend = INFTOracleGetter(addrs.bendOracle)
                .getAssetPrice(_token);
            price = price < priceBend ? price : priceBend;
        }
        uint256 ethgAmount = (tokenAmount * price) / Constants.PRICE_PRECISION;

        ethgAmount = GenericLogic.adjustForDecimals(
            ethgAmount,
            _token,
            addrs.ethg
        );

        ValidationLogic.validate(
            ethgAmount > 0,
            Errors.VAULT_INVALID_ETHG_AMOUNT
        );

        uint256 feeBasisPoints = GenericLogic.getBuyEthgFeeBasisPoints(
            _token,
            ethgAmount
        );

        uint256 amountAfterFees = GenericLogic.collectSwapFees(
            _token,
            tokenAmount,
            feeBasisPoints
        );

        // price impact
        uint256 priceMax = GenericLogic.getMaxPrice(_token);
        int256 priceImpactUsd = SwapPriceImpactLogic.getSupplyPriceImpactUsd(
            SwapPriceImpactLogic.GetSupplyPriceImpactUsdParams({
                token: _token,
                price: priceMax,
                usdDelta: ((ethgAmount * Constants.PRICE_PRECISION) /
                    10 ** Constants.ETHG_DECIMALS).toInt256()
            })
        );
        int256 impactAmount = SwapPriceImpactLogic.applySwapImpactWithCap(
            _token,
            priceMax,
            price,
            priceImpactUsd
        );
        if (priceImpactUsd > 0) {
            uint256 positiveImpactAmount = GenericLogic.adjustFor30Decimals(
                impactAmount.toUint256(),
                _token
            );
            amountAfterFees += positiveImpactAmount;
        }
        if (priceImpactUsd < 0) {
            uint256 negativeImpactAmount = GenericLogic.adjustFor30Decimals(
                (-impactAmount).toUint256(),
                _token
            );
            amountAfterFees -= negativeImpactAmount;
        }

        uint256 mintAmount = (amountAfterFees * price) /
            Constants.PRICE_PRECISION;
        mintAmount = GenericLogic.adjustForDecimals(
            mintAmount,
            _token,
            addrs.ethg
        );

        GenericLogic.increaseEthgAmount(_token, mintAmount);
        GenericLogic.increasePoolAmount(_token, amountAfterFees);

        IETHG(addrs.ethg).mint(_receiver, mintAmount);

        emit BuyETHG(
            _receiver,
            _token,
            tokenAmount,
            mintAmount,
            feeBasisPoints,
            priceImpactUsd
        );

        return mintAmount;
    }

    function ExecuteSellETHG(
        address _token,
        address _receiver
    ) external returns (uint256) {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        ValidationLogic.validateManager();
        ValidationLogic.validateWhitelistedToken(_token);

        uint256 ethgAmount = GenericLogic.transferIn(addrs.ethg);
        ValidationLogic.validate(
            ethgAmount > 0,
            Errors.VAULT_INVALID_ETHG_AMOUNT
        );

        BorrowingFeeLogic.updateCumulativeBorrowingRate(_token, _token);

        // price impact
        uint256 priceMax = GenericLogic.getMaxPrice(_token);
        uint256 priceMin = GenericLogic.getMinPrice(_token);
        int256 priceImpactUsd = SwapPriceImpactLogic.getSupplyPriceImpactUsd(
            SwapPriceImpactLogic.GetSupplyPriceImpactUsdParams({
                token: _token,
                price: priceMax,
                usdDelta: -(
                    ((ethgAmount * Constants.PRICE_PRECISION) /
                        10 ** Constants.ETHG_DECIMALS).toInt256()
                )
            })
        );
        int256 impactAmount = SwapPriceImpactLogic.applySwapImpactWithCap(
            _token,
            priceMax,
            priceMin,
            priceImpactUsd
        );

        uint256 redemptionAmount = GenericLogic.getRedemptionAmount(
            _token,
            ethgAmount
        );
        ValidationLogic.validate(
            redemptionAmount > 0,
            Errors.VAULT_INVALID_REDEMPTION_AMOUNT
        );
        GenericLogic.decreaseEthgAmount(_token, ethgAmount);
        GenericLogic.decreasePoolAmount(_token, redemptionAmount);

        IETHG(addrs.ethg).burn(address(this), ethgAmount);

        // the _transferIn call increased the value of tokenBalances[ethg]
        // usually decreases in token balances are synced by calling _transferOut
        // however, for ethg, the tokens are burnt, so _updateTokenBalance should
        // be manually called to record the decrease in tokens
        GenericLogic.updateTokenBalance(addrs.ethg);

        uint256 feeBasisPoints = GenericLogic.getSellEthgFeeBasisPoints(
            _token,
            ethgAmount
        );

        uint256 amountOut = GenericLogic.collectSwapFees(
            _token,
            redemptionAmount,
            feeBasisPoints
        );
        if (priceImpactUsd > 0) {
            uint256 positiveImpactAmount = GenericLogic.adjustFor30Decimals(
                impactAmount.toUint256(),
                _token
            );
            amountOut += positiveImpactAmount;
        } else {
            uint256 negativeImpactAmount = GenericLogic.adjustFor30Decimals(
                (-impactAmount).toUint256(),
                _token
            );
            amountOut -= negativeImpactAmount;
        }

        ValidationLogic.validate(
            amountOut > 0,
            Errors.VAULT_INVALID_AMOUNT_OUT
        );
        if (ts.nftTokens[_token]) {
            INToken(_token).burn(address(this), amountOut);
            GenericLogic.updateTokenBalance(_token);
        } else {
            GenericLogic.transferOut(_token, amountOut, _receiver);
        }

        emit SellETHG(
            _receiver,
            _token,
            ethgAmount,
            amountOut,
            feeBasisPoints,
            priceImpactUsd
        );

        return amountOut;
    }

    function directPoolDeposit(address _token) external {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        ValidationLogic.validate(
            ts.whitelistedTokens[_token],
            Errors.VAULT_TOKEN_NOT_WHITELISTED
        );
        uint256 tokenAmount = GenericLogic.transferIn(_token);
        ValidationLogic.validate(
            tokenAmount > 0,
            Errors.VAULT_INVALID_TOKEN_AMOUNT
        );
        GenericLogic.increasePoolAmount(_token, tokenAmount);
        emit DirectPoolDeposit(_token, tokenAmount);
    }

    function getETHGAmountWhenRedeemNft(
        address _nft,
        uint256 _tokenId,
        uint256 _ethAmount
    ) external view returns (uint256, uint256) {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();

        uint256 tokenAmount = ((NftLogic.getNftDepositLtv(_nft, _tokenId) *
            10 ** ts.tokenDecimals[_nft]) / Constants.PERCENTAGE_FACTOR);

        if (tokenAmount == 0) {
            return (0, 0);
        }

        uint256 price = GenericLogic.getMaxPrice(_nft);

        uint256 priceBend = INFTOracleGetter(addrs.bendOracle).getAssetPrice(
            _nft
        );
        price = price < priceBend ? price : priceBend;

        uint256 ethgAmount = (tokenAmount * price) / Constants.PRICE_PRECISION;

        ethgAmount = GenericLogic.adjustForDecimals(
            ethgAmount,
            _nft,
            addrs.ethg
        );

        _ethAmount = GenericLogic.adjustForDecimals(
            _ethAmount,
            addrs.weth,
            addrs.ethg
        );

        if (ethgAmount <= _ethAmount) {
            return (0, 0);
        } else {
            ethgAmount -= _ethAmount;
        }
        // fee
        uint256 feeBasisPoints = GenericLogic.getSellEthgFeeBasisPoints(
            _nft,
            ethgAmount
        );

        uint256 feeAmount = (tokenAmount * feeBasisPoints) /
            Constants.PERCENTAGE_FACTOR;

        uint256 feeEthgAmount = (feeAmount * price) / Constants.PRICE_PRECISION;
        feeEthgAmount = GenericLogic.adjustForDecimals(
            feeEthgAmount,
            _nft,
            addrs.ethg
        );

        return (ethgAmount, feeEthgAmount);
    }

    function getDepositWithdrawPriceImpactFee(
        address _token,
        uint256 _tokenAmount,
        bool _isDeposit
    ) external view returns (int256) {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        uint256 price = GenericLogic.getMinPrice(_token);
        if (ts.nftTokens[_token]) {
            uint256 priceBend = INFTOracleGetter(addrs.bendOracle)
                .getAssetPrice(_token);
            price = price < priceBend ? price : priceBend;
        }
        uint256 ethgAmount = (_tokenAmount * price) / Constants.PRICE_PRECISION;

        ethgAmount = GenericLogic.adjustForDecimals(
            ethgAmount,
            _token,
            addrs.ethg
        );
        // price impact
        uint256 priceMax = GenericLogic.getMaxPrice(_token);
        int256 usdDelta;
        if (_isDeposit) {
            usdDelta = ((ethgAmount * Constants.PRICE_PRECISION) /
                10 ** Constants.ETHG_DECIMALS).toInt256();
        } else {
            usdDelta = -(
                ((ethgAmount * Constants.PRICE_PRECISION) /
                    10 ** Constants.ETHG_DECIMALS).toInt256()
            );
        }
        int256 priceImpactUsd = SwapPriceImpactLogic.getSupplyPriceImpactUsd(
            SwapPriceImpactLogic.GetSupplyPriceImpactUsdParams({
                token: _token,
                price: priceMax,
                usdDelta: usdDelta
            })
        );
        return priceImpactUsd;
    }
}
