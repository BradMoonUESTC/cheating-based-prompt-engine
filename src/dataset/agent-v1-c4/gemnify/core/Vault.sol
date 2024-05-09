// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IVault} from "./interfaces/IVault.sol";

import {SwapLogic} from "./libraries/logic/SwapLogic.sol";
import {SupplyLogic} from "./libraries/logic/SupplyLogic.sol";
import {PositionLogic} from "./libraries/logic/PositionLogic.sol";
import {GenericLogic} from "./libraries/logic/GenericLogic.sol";
import {ConfigureLogic} from "./libraries/logic/ConfigureLogic.sol";
import {BorrowingFeeLogic} from "./libraries/logic/BorrowingFeeLogic.sol";
import {NftLogic} from "./libraries/logic/NftLogic.sol";
import {FundingFeeLogic} from "./libraries/logic/FundingFeeLogic.sol";
import {StorageSlot} from "./libraries/logic/StorageSlot.sol";
import {IVaultPriceFeed} from "./interfaces/IVaultPriceFeed.sol";

import {DataTypes} from "./libraries/types/DataTypes.sol";
import {Constants} from "./libraries/helpers/Constants.sol";

import {IWETH} from "../tokens/interfaces/IWETH.sol";

contract Vault is OwnableUpgradeable, ReentrancyGuardUpgradeable, IVault {
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    receive() external payable {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        require(msg.sender == addrs.stargateRouter, "Vault: invalid sender");
        if (msg.value != 0) {
            IWETH(addrs.weth).deposit{value: msg.value}();
        }
    }

    function initialize() external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    function setPermissionParams(
        bool _inManagerMode,
        bool _inPrivateLiquidationMode,
        bool _isSwapEnabled,
        bool _isLeverageEnabled
    ) external onlyOwner {
        ConfigureLogic.setPermissionParams(
            _inManagerMode,
            _inPrivateLiquidationMode,
            _isSwapEnabled,
            _isLeverageEnabled
        );
    }

    function getPermissionParams()
        external
        view
        returns (bool, bool, bool, bool)
    {
        DataTypes.PermissionStorage storage ps = StorageSlot
            .getVaultPermissionStorage();
        return (
            ps.inManagerMode,
            ps.inPrivateLiquidationMode,
            ps.isSwapEnabled,
            ps.isLeverageEnabled
        );
    }

    function setManager(address _manager, bool _isManager) external onlyOwner {
        ConfigureLogic.setManager(_manager, _isManager);
    }

    function isManager(address _manager) external view returns (bool) {
        DataTypes.PermissionStorage storage ps = StorageSlot
            .getVaultPermissionStorage();
        return ps.isManager[_manager];
    }

    function setLiquidator(
        address _liquidator,
        bool _isActive
    ) external onlyOwner {
        ConfigureLogic.setLiquidator(_liquidator, _isActive);
    }

    function isLiquidator(address _liquidator) external view returns (bool) {
        DataTypes.PermissionStorage storage ps = StorageSlot
            .getVaultPermissionStorage();
        return ps.isLiquidator[_liquidator];
    }

    function setSwaper(address _swaper, bool _isActive) external onlyOwner {
        ConfigureLogic.setSwaper(_swaper, _isActive);
    }

    function isSwaper(address _swaper) external view returns (bool) {
        DataTypes.PermissionStorage storage ps = StorageSlot
            .getVaultPermissionStorage();
        return ps.isSwaper[_swaper];
    }

    function setMaxGasPrice(uint256 _maxGasPrice) external onlyOwner {
        ConfigureLogic.setMaxGasPrice(_maxGasPrice);
    }

    function getMaxGasPrice() external view returns (uint256) {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        return ps.maxGasPrice;
    }

    function setAddresses(
        DataTypes.SetAddressesParams memory params
    ) external onlyOwner {
        ConfigureLogic.setAddresses(params);
    }

    function getAddresses()
        external
        view
        returns (DataTypes.AddressStorage memory)
    {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();

        DataTypes.AddressStorage memory addrsT;
        addrsT.weth = addrs.weth;
        addrsT.router = addrs.router;
        addrsT.priceFeed = addrs.priceFeed;
        addrsT.ethg = addrs.ethg;
        addrsT.bendOracle = addrs.bendOracle;
        addrsT.refinance = addrs.refinance;
        addrsT.stargateRouter = addrs.stargateRouter;
        return addrsT;
    }

    function setMaxLeverage(uint256 _maxLeverage) external onlyOwner {
        ConfigureLogic.setMaxLeverage(_maxLeverage);
    }

    function getMaxLeverage() external view returns (uint256) {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        return ps.maxLeverage;
    }

    function setBufferAmount(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        ConfigureLogic.setBufferAmount(_token, _amount);
    }

    function setMaxGlobalShortSize(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        ConfigureLogic.setMaxGlobalShortSize(_token, _amount);
    }

    function getGlobalShortSizeAndPrice(
        address _token
    ) external view returns (uint256, uint256, uint256) {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        return (
            ps.maxGlobalShortSizes[_token],
            ps.globalShortSizes[_token],
            ps.globalShortAveragePrices[_token]
        );
    }

    function setFees(DataTypes.SetFeesParams memory params) external onlyOwner {
        ConfigureLogic.setFees(params);
    }

    function getFees()
        external
        view
        override
        returns (DataTypes.SetFeesParams memory)
    {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        DataTypes.SetFeesParams memory fee;
        fee.taxBasisPoints = fs.taxBasisPoints;
        fee.stableTaxBasisPoints = fs.stableTaxBasisPoints;
        fee.mintBurnFeeBasisPoints = fs.mintBurnFeeBasisPoints;
        fee.swapFeeBasisPoints = fs.swapFeeBasisPoints;
        fee.stableSwapFeeBasisPoints = fs.stableSwapFeeBasisPoints;
        fee.marginFeeBasisPoints = fs.marginFeeBasisPoints;
        fee.liquidationFeeEth = fs.liquidationFeeEth;
        fee.minProfitTime = fs.minProfitTime;
        fee.hasDynamicFees = fs.hasDynamicFees;
        return fee;
    }

    function setBorrowingRate(
        uint256 _borrowingInterval,
        uint256 _borrowingRateFactor,
        uint256 _stableBorrowingRateFactor
    ) external onlyOwner {
        ConfigureLogic.setBorrowingRate(
            _borrowingInterval,
            _borrowingRateFactor,
            _stableBorrowingRateFactor
        );
    }

    function getBorrowingRate()
        external
        view
        override
        returns (uint256, uint256, uint256)
    {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        return (
            fs.borrowingInterval,
            fs.borrowingRateFactor,
            fs.stableBorrowingRateFactor
        );
    }

    function setTokenConfig(
        address _token,
        uint256 _tokenDecimals,
        uint256 _tokenWeight,
        uint256 _minProfitBps,
        uint256 _maxEthgAmount,
        bool _isStable,
        bool _isShortable,
        bool _isNft
    ) external onlyOwner {
        ConfigureLogic.setTokenConfig(
            DataTypes.SetTokenConfigParams({
                token: _token,
                tokenDecimals: _tokenDecimals,
                tokenWeight: _tokenWeight,
                minProfitBps: _minProfitBps,
                maxEthgAmount: _maxEthgAmount,
                isStable: _isStable,
                isShortable: _isShortable,
                isNft: _isNft
            })
        );
    }

    function getTokenConfig(
        address _token
    ) external view returns (DataTypes.SetTokenConfigParams memory) {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();

        DataTypes.SetTokenConfigParams memory tokenConfig;
        tokenConfig.token = _token;
        tokenConfig.tokenDecimals = ts.tokenDecimals[_token];
        tokenConfig.tokenWeight = ts.tokenWeights[_token];
        tokenConfig.minProfitBps = ts.minProfitBasisPoints[_token];
        tokenConfig.maxEthgAmount = ts.maxEthgAmounts[_token];
        tokenConfig.isStable = ts.stableTokens[_token];
        tokenConfig.isShortable = ts.shortableTokens[_token];
        tokenConfig.isNft = ts.nftTokens[_token];
        return tokenConfig;
    }

    function getTokenDecimal(
        address _token
    ) external view override returns (uint256) {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        return 10 ** ts.tokenDecimals[_token];
    }

    function clearTokenConfig(address _token) external onlyOwner {
        ConfigureLogic.clearTokenConfig(_token);
    }

    function withdrawFees(
        address _token,
        address _receiver
    ) external onlyOwner returns (uint256) {
        return GenericLogic.withdrawFees(_token, _receiver);
    }

    function addRouter(address _router) external {
        ConfigureLogic.addRouter(_router);
    }

    function removeRouter(address _router) external {
        ConfigureLogic.removeRouter(_router);
    }

    function setEthgAmount(address _token, uint256 _amount) external onlyOwner {
        ConfigureLogic.setEthgAmount(_token, _amount);
    }

    function setNftInfos(
        address[] memory _nfts,
        address[] memory _certiNfts,
        uint256[] memory _nftLtvs
    ) external onlyOwner {
        ConfigureLogic.setNftInfos(_nfts, _certiNfts, _nftLtvs);
    }

    function setFundingFactor(
        address[] memory _tokens,
        uint256[] memory _fundingFactors,
        uint256[] memory _fundingExponentFactors
    ) external onlyOwner {
        ConfigureLogic.setFundingFactor(
            _tokens,
            _fundingFactors,
            _fundingExponentFactors
        );
    }

    function getFundingFactor(
        address _token
    ) external view override returns (uint256, uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();

        return (fs.fundingFactors[_token], fs.fundingExponentFactors[_token]);
    }

    function setPriceImpactFactor(
        address[] memory _tokens,
        uint256[] memory _swapPositiveImpactFactors,
        uint256[] memory _swapNegativeImpactFactors,
        uint256[] memory _swapImpactExponentFactors,
        uint256[] memory _positionPositiveImpactFactors,
        uint256[] memory _positionNegativeImpactFactors,
        uint256[] memory _positionImpactExponentFactors
    ) external onlyOwner {
        ConfigureLogic.setPriceImpactFactor(
            _tokens,
            _swapPositiveImpactFactors,
            _swapNegativeImpactFactors,
            _swapImpactExponentFactors,
            _positionPositiveImpactFactors,
            _positionNegativeImpactFactors,
            _positionImpactExponentFactors
        );
    }

    function upgradeVault(
        address _newVault,
        address _token,
        uint256 _amount
    ) external onlyOwner {
        IERC20Upgradeable(_token).safeTransfer(_newVault, _amount);
    }

    // deposit into the pool without minting ETHG tokens
    // useful in allowing the pool to become over-collaterised
    function directPoolDeposit(address _token) external override nonReentrant {
        SupplyLogic.directPoolDeposit(_token);
    }

    function buyETHG(
        address _token,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        return SupplyLogic.ExecuteBuyETHG(_token, _receiver);
    }

    function sellETHG(
        address _token,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        return SupplyLogic.ExecuteSellETHG(_token, _receiver);
    }

    function swap(
        address _tokenIn,
        address _tokenOut,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        uint256 amountIn = GenericLogic.transferIn(_tokenIn);
        return SwapLogic.ExecuteSwap(_tokenIn, _tokenOut, amountIn, _receiver);
    }

    function increasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong
    ) external override nonReentrant {
        PositionLogic.increasePosition(
            DataTypes.IncreasePositionParams({
                account: _account,
                collateralToken: _collateralToken,
                indexToken: _indexToken,
                sizeDelta: _sizeDelta,
                isLong: _isLong
            })
        );
    }

    function decreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        return
            PositionLogic.decreasePosition(
                DataTypes.DecreasePositionParams({
                    account: _account,
                    collateralToken: _collateralToken,
                    indexToken: _indexToken,
                    collateralDelta: _collateralDelta,
                    sizeDelta: _sizeDelta,
                    isLong: _isLong,
                    receiver: _receiver
                })
            );
    }

    function liquidatePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        address _feeReceiver
    ) external override nonReentrant {
        return
            PositionLogic.liquidatePosition(
                DataTypes.LiquidatePositionParams({
                    account: _account,
                    collateralToken: _collateralToken,
                    indexToken: _indexToken,
                    isLong: _isLong,
                    feeReceiver: _feeReceiver
                })
            );
    }

    function validateLiquidation(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        bool _raise
    ) external view returns (uint256, uint256) {
        return
            PositionLogic.validateLiquidation(
                _account,
                _collateralToken,
                _indexToken,
                _isLong,
                _raise
            );
    }

    function updateCumulativeBorrowingRate(
        address _collateralToken,
        address _indexToken
    ) external nonReentrant {
        BorrowingFeeLogic.updateCumulativeBorrowingRate(
            _collateralToken,
            _indexToken
        );
    }

    function getCumulativeBorrowingRates(
        address _token
    ) external view returns (uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        return fs.cumulativeBorrowingRates[_token];
    }

    function getMaxPrice(
        address _token
    ) public view override returns (uint256) {
        return GenericLogic.getMaxPrice(_token);
    }

    function getMinPrice(
        address _token
    ) external view override returns (uint256) {
        return GenericLogic.getMinPrice(_token);
    }

    function getPoolInfo(
        address _token
    )
        external
        view
        override
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        return GenericLogic.getPoolInfo(_token);
    }

    function getWhitelistedToken()
        external
        view
        override
        returns (uint256, address[] memory)
    {
        return GenericLogic.getWhitelistedToken();
    }

    function getTokenInfo(
        address _token
    ) external view override returns (DataTypes.TokenInfo memory) {
        return GenericLogic.getTokenInfo(_token);
    }

    function getFeeReserves(address _token) external view returns (uint256) {
        DataTypes.FeeStorage storage fs = StorageSlot.getVaultFeeStorage();
        return fs.feeReserves[_token];
    }

    function getRedemptionCollateral(
        address _token
    ) public view returns (uint256, uint256) {
        return GenericLogic.getRedemptionCollateral(_token);
    }

    function getUtilisation(address _token) public view returns (uint256) {
        return GenericLogic.getUtilisation(_token);
    }

    function getPositionLeverage(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public view returns (uint256) {
        return
            PositionLogic.getPositionLeverage(
                _account,
                _collateralToken,
                _indexToken,
                _isLong
            );
    }

    function getGlobalShortDelta(
        address _token
    ) public view returns (bool, uint256) {
        return PositionLogic.getGlobalShortDelta(_token);
    }

    function getPositionDelta(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (bool, uint256) {
        return
            PositionLogic.getPositionDelta(
                _account,
                _collateralToken,
                _indexToken,
                _isLong
            );
    }

    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _lastIncreasedTime
    ) public view returns (bool, uint256) {
        return
            PositionLogic.getDelta(
                _indexToken,
                _size,
                _averagePrice,
                _isLong,
                _lastIncreasedTime
            );
    }

    function getPosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public view override returns (DataTypes.Position memory) {
        return
            PositionLogic.getPosition(
                _account,
                _collateralToken,
                _indexToken,
                _isLong
            );
    }

    function getRedemptionAmount(
        address _token,
        uint256 _ethgAmount
    ) external view override returns (uint256) {
        return GenericLogic.getRedemptionAmount(_token, _ethgAmount);
    }

    function getTargetEthgAmount(
        address _token
    ) external view returns (uint256) {
        return GenericLogic.getTargetEthgAmount(_token);
    }

    function getFeeBasisPoints(
        address _token,
        uint256 _ethgDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) external view override returns (uint256) {
        return
            GenericLogic.getFeeBasisPoints(
                _token,
                _ethgDelta,
                _feeBasisPoints,
                _taxBasisPoints,
                _increment
            );
    }

    function tokenToUsdMin(
        address _token,
        uint256 _tokenAmount
    ) public view override returns (uint256) {
        return GenericLogic.tokenToUsdMin(_token, _tokenAmount);
    }

    function mintCNft(
        address _cNft,
        address _to,
        uint256 _tokenId,
        uint256 _ltv
    ) external {
        NftLogic.mintCNft(_cNft, _to, _tokenId, _ltv);
    }

    function burnCNft(address _cNft, uint256 _tokenId) external {
        NftLogic.burnCNft(_cNft, _tokenId);
    }

    function mintNToken(address _nToken, uint256 _amount) external {
        NftLogic.mintNToken(_nToken, _amount);
    }

    function burnNToken(address _nToken, uint256 _amount) external {
        NftLogic.burnNToken(_nToken, _amount);
    }

    function getBendDAOAssetPrice(
        address _nft
    ) external view override returns (uint256) {
        return GenericLogic.getBendDAOAssetPrice(_nft);
    }

    function addNftToUser(
        address _user,
        address _nft,
        uint256 _tokenId
    ) external {
        NftLogic.addNftToUser(_user, _nft, _tokenId);
    }

    function removeNftFromUser(
        address _user,
        address _nft,
        uint256 _tokenId
    ) external {
        NftLogic.removeNftFromUser(_user, _nft, _tokenId);
    }

    function isNftDepsoitedForUser(
        address _user,
        address _nft,
        uint256 _tokenId
    ) external view override returns (bool) {
        return NftLogic.isNftDepsoitedForUser(_user, _nft, _tokenId);
    }

    function getETHGAmountWhenRedeemNft(
        address _nft,
        uint256 _tokenId,
        uint256 _ethAmount
    ) external view override returns (uint256, uint256) {
        return
            SupplyLogic.getETHGAmountWhenRedeemNft(_nft, _tokenId, _ethAmount);
    }

    function updateNftRefinanceStatus(
        address _user,
        address _nft,
        uint256 _tokenId
    ) external {
        NftLogic.updateNftRefinanceStatus(_user, _nft, _tokenId);
    }

    function nftUsersLength() external view override returns (uint256) {
        DataTypes.NftStorage storage ns = StorageSlot.getVaultNftStorage();
        return ns.nftUsers.length;
    }

    function getUserTokenIds(
        address _user,
        address _nft
    ) external view override returns (DataTypes.NftStatus[] memory) {
        DataTypes.NftStorage storage ns = StorageSlot.getVaultNftStorage();
        return ns.nftStatus[_user][_nft];
    }

    function getNftInfo(
        address _nft
    ) external view override returns (address, uint256) {
        DataTypes.NftStorage storage ns = StorageSlot.getVaultNftStorage();
        return (ns.nftInfos[_nft].certiNft, ns.nftInfos[_nft].nftLtv);
    }

    function nftUsers(uint256 i) external view returns (address) {
        DataTypes.NftStorage storage ns = StorageSlot.getVaultNftStorage();
        return ns.nftUsers[i];
    }

    function getFundingFeeAmount(
        address _account
    ) external view returns (uint256) {
        return FundingFeeLogic.getFundingFeeAmount(_account);
    }

    function claimFundingFees(
        address _account,
        address _receiver
    ) external returns (uint256) {
        return FundingFeeLogic.claimFundingFees(_account, _receiver);
    }

    function getDepositWithdrawPriceImpactFee(
        address _token,
        uint256 _tokenAmount,
        bool _isDeposit
    ) external view returns (int256) {
        return
            SupplyLogic.getDepositWithdrawPriceImpactFee(
                _token,
                _tokenAmount,
                _isDeposit
            );
    }

    function getSwapPriceImpactFee(
        address _tokenIn,
        address _tokenOut,
        uint256 _tokenAmount
    ) external view returns (int256) {
        return
            SwapLogic.getSwapPriceImpactFee(_tokenIn, _tokenOut, _tokenAmount);
    }

    function getExecutionPriceForIncrease(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong
    ) external view returns (int256, int256, uint256) {
        DataTypes.Position memory position = getPosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        return
            PositionLogic.getExecutionPriceForIncrease(
                DataTypes.IncreasePositionParams({
                    account: _account,
                    collateralToken: _collateralToken,
                    indexToken: _indexToken,
                    sizeDelta: _sizeDelta,
                    isLong: _isLong
                }),
                GenericLogic.getMaxPrice(_indexToken),
                GenericLogic.getMinPrice(_indexToken),
                position.averagePrice,
                ps.reservedAmounts[_indexToken]
            );
    }

    function getExecutionPriceForDecrease(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong
    ) external view returns (int256, uint256) {
        DataTypes.Position memory position = getPosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        return
            PositionLogic.getExecutionPriceForDecrease(
                DataTypes.DecreasePositionParams({
                    account: _account,
                    collateralToken: _collateralToken,
                    indexToken: _indexToken,
                    collateralDelta: _collateralDelta,
                    sizeDelta: _sizeDelta,
                    isLong: _isLong,
                    receiver: _account
                }),
                GenericLogic.getMaxPrice(_indexToken),
                GenericLogic.getMinPrice(_indexToken),
                position.averagePrice,
                ps.reservedAmounts[_indexToken]
            );
    }
}
