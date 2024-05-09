// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import {ValidationLogic} from "./ValidationLogic.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {StorageSlot} from "./StorageSlot.sol";
import {Errors} from "../helpers/Errors.sol";
import {Constants} from "../helpers/Constants.sol";
import {IVaultPriceFeed} from "../../interfaces/IVaultPriceFeed.sol";

import {DataTypes} from "../types/DataTypes.sol";

library ConfigureLogic {
    function setBorrowingRate(
        uint256 _borrowingInterval,
        uint256 _borrowingRateFactor,
        uint256 _stableBorrowingRateFactor
    ) external {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        ValidationLogic.validate(
            _borrowingInterval >= Constants.MIN_BORROWING_RATE_INTERVAL,
            Errors.VAULT_INVALID_BORROWING_INTERVALE
        );
        ValidationLogic.validate(
            _borrowingRateFactor <= Constants.MAX_BORROWING_RATE_FACTOR,
            Errors.VAULT_INVALID_BORROWING_RATE_FACTOR
        );
        ValidationLogic.validate(
            _stableBorrowingRateFactor <= Constants.MAX_BORROWING_RATE_FACTOR,
            Errors.VAULT_INVALID_STABLE_BORROWING_RATE_FACTOR
        );
        fs.borrowingInterval = _borrowingInterval;
        fs.borrowingRateFactor = _borrowingRateFactor;
        fs.stableBorrowingRateFactor = _stableBorrowingRateFactor;
    }

    function setAddresses(DataTypes.SetAddressesParams memory params) external {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        addrs.weth = params.weth;
        addrs.router = params.router;
        addrs.priceFeed = params.priceFeed;
        addrs.ethg = params.ethg;
        addrs.bendOracle = params.bendOracle;
        addrs.refinance = params.refinance;
        addrs.stargateRouter = params.stargateRouter;
    }

    function setFees(DataTypes.SetFeesParams memory params) external {
        ValidationLogic.validate(
            params.taxBasisPoints <= Constants.MAX_FEE_BASIS_POINTS,
            Errors.VAULT_INVALID_TAX_BASIS_POINTS
        );
        ValidationLogic.validate(
            params.stableTaxBasisPoints <= Constants.MAX_FEE_BASIS_POINTS,
            Errors.VAULT_INVALID_STABLE_TAX_BASIS_POINTS
        );
        ValidationLogic.validate(
            params.mintBurnFeeBasisPoints <= Constants.MAX_FEE_BASIS_POINTS,
            Errors.VAULT_INVALID_MINT_BURN_FEE_BASIS_POINTS
        );
        ValidationLogic.validate(
            params.swapFeeBasisPoints <= Constants.MAX_FEE_BASIS_POINTS,
            Errors.VAULT_INVALID_SWAP_FEE_BASIS_POINTS
        );
        ValidationLogic.validate(
            params.stableSwapFeeBasisPoints <= Constants.MAX_FEE_BASIS_POINTS,
            Errors.VAULT_INVALID_STABLE_SWAP_FEE_BASIS_POINTS
        );
        ValidationLogic.validate(
            params.marginFeeBasisPoints <= Constants.MAX_FEE_BASIS_POINTS,
            Errors.VAULT_INVALID_MARGIN_FEE_BASIS_POINTS
        );
        ValidationLogic.validate(
            params.liquidationFeeEth <= Constants.MAX_LIQUIDATION_FEE_ETH,
            Errors.VAULT_INVALID_LIQUIDATION_FEE_ETH
        );
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        fs.taxBasisPoints = params.taxBasisPoints;
        fs.stableTaxBasisPoints = params.stableTaxBasisPoints;
        fs.mintBurnFeeBasisPoints = params.mintBurnFeeBasisPoints;
        fs.swapFeeBasisPoints = params.swapFeeBasisPoints;
        fs.stableSwapFeeBasisPoints = params.stableSwapFeeBasisPoints;
        fs.marginFeeBasisPoints = params.marginFeeBasisPoints;
        fs.liquidationFeeEth = params.liquidationFeeEth;
        fs.minProfitTime = params.minProfitTime;
        fs.hasDynamicFees = params.hasDynamicFees;
    }

    function addRouter(address _router) external {
        DataTypes.PermissionStorage storage ps = StorageSlot
            .getVaultPermissionStorage();
        ps.approvedRouters[msg.sender][_router] = true;
    }

    function removeRouter(address _router) external {
        DataTypes.PermissionStorage storage ps = StorageSlot
            .getVaultPermissionStorage();
        ps.approvedRouters[msg.sender][_router] = false;
    }

    function setTokenConfig(
        DataTypes.SetTokenConfigParams memory params
    ) external {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        // increment token count for the first time
        if (!ts.whitelistedTokens[params.token]) {
            ts.whitelistedTokenCount = ts.whitelistedTokenCount + 1;
            ts.allWhitelistedTokens.push(params.token);
        }
        uint256 totalTokenWeights = ts.totalTokenWeights;
        totalTokenWeights = totalTokenWeights - ts.tokenWeights[params.token];
        ts.whitelistedTokens[params.token] = true;
        ts.tokenDecimals[params.token] = params.tokenDecimals;
        ts.tokenWeights[params.token] = params.tokenWeight;
        ts.minProfitBasisPoints[params.token] = params.minProfitBps;
        ts.maxEthgAmounts[params.token] = params.maxEthgAmount;
        ts.stableTokens[params.token] = params.isStable;
        ts.shortableTokens[params.token] = params.isShortable;
        ts.nftTokens[params.token] = params.isNft;
        ts.totalTokenWeights = totalTokenWeights + params.tokenWeight;
    }

    function clearTokenConfig(address _token) external {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        ValidationLogic.validate(
            ts.whitelistedTokens[_token],
            Errors.VAULT_TOKEN_NOT_WHITELISTED
        );
        ts.totalTokenWeights = ts.totalTokenWeights - ts.tokenWeights[_token];
        delete ts.whitelistedTokens[_token];
        delete ts.tokenDecimals[_token];
        delete ts.tokenWeights[_token];
        delete ts.minProfitBasisPoints[_token];
        delete ts.maxEthgAmounts[_token];
        delete ts.stableTokens[_token];
        delete ts.shortableTokens[_token];
        delete ts.nftTokens[_token];
        ts.whitelistedTokenCount = ts.whitelistedTokenCount - 1;
    }

    function setEthgAmount(address _token, uint256 _amount) external {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        uint256 ethgAmount = ps.ethgAmounts[_token];
        if (_amount > ethgAmount) {
            GenericLogic.increaseEthgAmount(_token, _amount - ethgAmount);
            return;
        }
        GenericLogic.decreaseEthgAmount(_token, ethgAmount - _amount);
    }

    function setNftInfos(
        address[] memory _nfts,
        address[] memory _certiNfts,
        uint256[] memory _nftLtvs
    ) external {
        require(
            _nfts.length == _certiNfts.length &&
                _nfts.length == _nftLtvs.length,
            "inconsistent length"
        );
        DataTypes.NftStorage storage ns = StorageSlot.getVaultNftStorage();
        for (uint256 i = 0; i < _nfts.length; i++) {
            DataTypes.NftInfo memory nftInfo = DataTypes.NftInfo(
                _certiNfts[i],
                _nftLtvs[i]
            );
            ns.nftInfos[_nfts[i]] = nftInfo;
        }
    }

    function setFundingFactor(
        address[] memory _tokens,
        uint256[] memory _fundingFactors,
        uint256[] memory _fundingExponentFactors
    ) external {
        require(
            _tokens.length == _fundingFactors.length &&
                _tokens.length == _fundingExponentFactors.length,
            "inconsistent length"
        );

        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();

        for (uint256 i = 0; i < _tokens.length; i++) {
            fs.fundingFactors[_tokens[i]] = _fundingFactors[i];
            fs.fundingExponentFactors[_tokens[i]] = _fundingExponentFactors[i];
        }
    }

    function setPriceImpactFactor(
        address[] memory _tokens,
        uint256[] memory _swapPositiveImpactFactors,
        uint256[] memory _swapNegativeImpactFactors,
        uint256[] memory _swapImpactExponentFactors,
        uint256[] memory _positionPositiveImpactFactors,
        uint256[] memory _positionNegativeImpactFactors,
        uint256[] memory _positionImpactExponentFactors
    ) external {
        require(
            _tokens.length == _swapPositiveImpactFactors.length &&
                _tokens.length == _swapNegativeImpactFactors.length &&
                _tokens.length == _swapImpactExponentFactors.length &&
                _tokens.length == _positionPositiveImpactFactors.length &&
                _tokens.length == _positionNegativeImpactFactors.length &&
                _tokens.length == _positionImpactExponentFactors.length,
            "inconsistent length"
        );
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();

        for (uint256 i = 0; i < _tokens.length; i++) {
            fs.swapImpactExponentFactors[
                _tokens[i]
            ] = _swapImpactExponentFactors[i];
            fs.swapImpactFactors[_tokens[i]][true] = _swapPositiveImpactFactors[
                i
            ];
            fs.swapImpactFactors[_tokens[i]][
                false
            ] = _swapNegativeImpactFactors[i];

            fs.positionImpactExponents[
                _tokens[i]
            ] = _positionImpactExponentFactors[i];
            fs.positionImpactFactors[_tokens[i]][
                true
            ] = _positionPositiveImpactFactors[i];
            fs.positionImpactFactors[_tokens[i]][
                false
            ] = _positionNegativeImpactFactors[i];
        }
    }

    function setPermissionParams(
        bool _inManagerMode,
        bool _inPrivateLiquidationMode,
        bool _isSwapEnabled,
        bool _isLeverageEnabled
    ) external {
        DataTypes.PermissionStorage storage ps = StorageSlot
            .getVaultPermissionStorage();
        ps.inManagerMode = _inManagerMode;
        ps.inPrivateLiquidationMode = _inPrivateLiquidationMode;
        ps.isSwapEnabled = _isSwapEnabled;
        ps.isLeverageEnabled = _isLeverageEnabled;
    }

    function setManager(address _manager, bool _isManager) external {
        DataTypes.PermissionStorage storage ps = StorageSlot
            .getVaultPermissionStorage();

        ps.isManager[_manager] = _isManager;
    }

    function setLiquidator(address _liquidator, bool _isActive) external {
        DataTypes.PermissionStorage storage ps = StorageSlot
            .getVaultPermissionStorage();
        ps.isLiquidator[_liquidator] = _isActive;
    }

    function setSwaper(address _swaper, bool _isActive) external {
        DataTypes.PermissionStorage storage ps = StorageSlot
            .getVaultPermissionStorage();
        ps.isSwaper[_swaper] = _isActive;
    }

    function setMaxGasPrice(uint256 _maxGasPrice) external {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        ps.maxGasPrice = _maxGasPrice;
    }

    function setMaxLeverage(uint256 _maxLeverage) external {
        ValidationLogic.validate(
            _maxLeverage > Constants.MIN_LEVERAGE,
            Errors.VAULT_INVALID_MAXLEVERAGE
        );
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        ps.maxLeverage = _maxLeverage;
    }

    function setBufferAmount(address _token, uint256 _amount) external {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        ps.bufferAmounts[_token] = _amount;
    }

    function setMaxGlobalShortSize(address _token, uint256 _amount) external {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        ps.maxGlobalShortSizes[_token] = _amount;
    }
}
