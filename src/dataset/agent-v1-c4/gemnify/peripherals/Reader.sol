// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IVault} from "../core/interfaces/IVault.sol";
import {Constants} from "../core/libraries/helpers/Constants.sol";
import {StorageSlot} from "../core/libraries/logic/StorageSlot.sol";

import {DataTypes} from "../core/libraries/types/DataTypes.sol";

import {IReader} from "./interfaces/IReader.sol";

contract Reader is OwnableUpgradeable, IReader {
    using MathUpgradeable for uint256;

    IVault public override vault;

    function initialize(address _vault) external initializer {
        __Ownable_init();
        vault = IVault(_vault);
    }

    function setVault(address _vault) external onlyOwner {
        vault = IVault(_vault);
    }

    function getDepositOrWithdrawFeeBasisPoints(
        address _token,
        uint256 _amountIn,
        bool _isDeposit
    ) external view returns (uint256) {
        uint256 price = vault.getMinPrice(_token);
        uint256 tokenInDecimals = vault.getTokenDecimal(_token);

        uint256 ethgAmount = (_amountIn * price) / Constants.PRICE_PRECISION;
        ethgAmount =
            (ethgAmount * (10 ** Constants.ETHG_DECIMALS)) /
            tokenInDecimals;

        bool increment = _isDeposit ? true : false;
        DataTypes.SetFeesParams memory fees = vault.getFees();

        return
            vault.getFeeBasisPoints(
                _token,
                ethgAmount,
                fees.mintBurnFeeBasisPoints,
                fees.taxBasisPoints,
                increment
            );
    }

    function getSwapFeeBasisPoints(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view returns (uint256) {
        uint256 priceIn = vault.getMinPrice(_tokenIn);
        uint256 tokenInDecimals = vault.getTokenDecimal(_tokenIn);

        uint256 ethgAmount = (_amountIn * priceIn) / Constants.PRICE_PRECISION;
        ethgAmount =
            (ethgAmount * (10 ** Constants.ETHG_DECIMALS)) /
            tokenInDecimals;

        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        DataTypes.SetFeesParams memory fees = vault.getFees();
        bool isStableSwap = ts.stableTokens[_tokenIn] &&
            ts.stableTokens[_tokenOut];
        uint256 baseBps = isStableSwap
            ? fees.stableSwapFeeBasisPoints
            : fees.swapFeeBasisPoints;
        uint256 taxBps = isStableSwap
            ? fees.stableTaxBasisPoints
            : fees.taxBasisPoints;
        uint256 feesBasisPoints0 = vault.getFeeBasisPoints(
            _tokenIn,
            ethgAmount,
            baseBps,
            taxBps,
            true
        );
        uint256 feesBasisPoints1 = vault.getFeeBasisPoints(
            _tokenOut,
            ethgAmount,
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

    function getBorrowingRates(
        address[] memory _tokens
    ) public view returns (uint256[] memory) {
        uint256[] memory borrowingRates = new uint256[](_tokens.length);

        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];

            (
                ,
                uint256 borrowingRateFactor,
                uint256 stableBorrowingRateFactor
            ) = vault.getBorrowingRate();

            DataTypes.TokenInfo memory tokenInfo = vault.getTokenInfo(token);

            uint256 factor = tokenInfo.isStableToken
                ? stableBorrowingRateFactor
                : borrowingRateFactor;

            (uint256 poolAmount, uint256 reservedAmount, , , , , ) = vault
                .getPoolInfo(token);

            if (poolAmount > 0) {
                borrowingRates[i] = (factor * reservedAmount) / poolAmount;
            }
        }

        return borrowingRates;
    }
}
