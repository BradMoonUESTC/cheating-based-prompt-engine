// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {BasePositionManager, Constants, IShortsTracker, IRouter, IVault, IOrderBook, MathUpgradeable, IERC20Upgradeable, SafeERC20Upgradeable} from "./BasePositionManager.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";

contract PositionManager is BasePositionManager {
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address public orderBook;

    bool public shouldValidateIncreaseOrder;

    mapping(address => bool) public isOrderKeeper;
    mapping(address => bool) public isLiquidator;

    event SetOrderKeeper(address indexed account, bool isActive);
    event SetLiquidator(address indexed account, bool isActive);
    event SetShouldValidateIncreaseOrder(bool shouldValidateIncreaseOrder);

    modifier onlyOrderKeeper() {
        require(isOrderKeeper[msg.sender], "PositionManager: forbidden");
        _;
    }

    modifier onlyLiquidator() {
        require(isLiquidator[msg.sender], "PositionManager: forbidden");
        _;
    }

    function initialize(
        address _vault,
        address _router,
        address _shortsTracker,
        address _weth,
        uint256 _depositFee,
        address _orderBook
    ) external initializer {
        shouldValidateIncreaseOrder = true;

        __BasePositionManager_init(
            _vault,
            _router,
            _shortsTracker,
            _weth,
            _depositFee
        );

        orderBook = _orderBook;
    }

    function setOrderKeeper(
        address _account,
        bool _isActive
    ) external onlyAdmin {
        isOrderKeeper[_account] = _isActive;
        emit SetOrderKeeper(_account, _isActive);
    }

    function setLiquidator(
        address _account,
        bool _isActive
    ) external onlyAdmin {
        isLiquidator[_account] = _isActive;
        emit SetLiquidator(_account, _isActive);
    }

    function setShouldValidateIncreaseOrder(
        bool _shouldValidateIncreaseOrder
    ) external onlyAdmin {
        shouldValidateIncreaseOrder = _shouldValidateIncreaseOrder;
        emit SetShouldValidateIncreaseOrder(_shouldValidateIncreaseOrder);
    }

    function liquidatePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        address _feeReceiver
    ) external nonReentrant onlyLiquidator {
        address _vault = vault;
        DataTypes.Position memory position = IVault(vault).getPosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );

        uint256 markPrice = _isLong
            ? IVault(_vault).getMinPrice(_indexToken)
            : IVault(_vault).getMaxPrice(_indexToken);
        // should be called strictly before position is updated in Vault
        IShortsTracker(shortsTracker).updateGlobalShortData(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            position.size,
            markPrice,
            false
        );

        IVault(_vault).liquidatePosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            _feeReceiver
        );
    }

    function executeIncreaseOrder(
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external onlyOrderKeeper {
        _validateIncreaseOrder(_account, _orderIndex);

        address _vault = vault;

        (
            ,
            ,
            /*address purchaseToken*/ /*uint256 purchaseTokenAmount*/ address collateralToken,
            address indexToken,
            uint256 sizeDelta,
            bool isLong /*uint256 triggerPrice*/ /*bool triggerAboveThreshold*/ /*uint256 executionFee*/,
            ,
            ,

        ) = IOrderBook(orderBook).getIncreaseOrder(_account, _orderIndex);

        uint256 markPrice = isLong
            ? IVault(_vault).getMaxPrice(indexToken)
            : IVault(_vault).getMinPrice(indexToken);
        // should be called strictly before position is updated in Vault
        IShortsTracker(shortsTracker).updateGlobalShortData(
            _account,
            collateralToken,
            indexToken,
            isLong,
            sizeDelta,
            markPrice,
            true
        );

        IOrderBook(orderBook).executeIncreaseOrder(
            _account,
            _orderIndex,
            _feeReceiver
        );

        _emitIncreasePositionReferral(_account, sizeDelta);
    }

    function executeDecreaseOrder(
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external onlyOrderKeeper {
        address _vault = vault;

        (
            address collateralToken,
            ,
            /*uint256 collateralDelta*/ address indexToken,
            uint256 sizeDelta,
            bool isLong /*uint256 triggerPrice*/ /*bool triggerAboveThreshold*/ /*uint256 executionFee*/,
            ,
            ,

        ) = IOrderBook(orderBook).getDecreaseOrder(_account, _orderIndex);

        uint256 markPrice = isLong
            ? IVault(_vault).getMinPrice(indexToken)
            : IVault(_vault).getMaxPrice(indexToken);
        // should be called strictly before position is updated in Vault
        IShortsTracker(shortsTracker).updateGlobalShortData(
            _account,
            collateralToken,
            indexToken,
            isLong,
            sizeDelta,
            markPrice,
            false
        );

        IOrderBook(orderBook).executeDecreaseOrder(
            _account,
            _orderIndex,
            _feeReceiver
        );

        _emitDecreasePositionReferral(_account, sizeDelta);
    }

    function _validateIncreaseOrder(
        address _account,
        uint256 _orderIndex
    ) internal view {
        (
            address _purchaseToken,
            uint256 _purchaseTokenAmount,
            address _collateralToken,
            address _indexToken,
            uint256 _sizeDelta,
            bool _isLong, // triggerPrice // triggerAboveThreshold // executionFee
            ,
            ,

        ) = IOrderBook(orderBook).getIncreaseOrder(_account, _orderIndex);

        _validateMaxGlobalSize(_indexToken, _isLong, _sizeDelta);

        if (!shouldValidateIncreaseOrder) {
            return;
        }

        // shorts are okay
        if (!_isLong) {
            return;
        }

        // if the position size is not increasing, this is a collateral deposit
        require(_sizeDelta > 0, "PositionManager: long deposit");

        IVault _vault = IVault(vault);
        DataTypes.Position memory position = _vault.getPosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );

        // if there is no existing position, do not charge a fee
        if (position.size == 0) {
            return;
        }

        uint256 nextSize = position.size + _sizeDelta;
        uint256 collateralDelta = _vault.tokenToUsdMin(
            _purchaseToken,
            _purchaseTokenAmount
        );
        uint256 nextCollateral = position.collateral + collateralDelta;

        uint256 prevLeverage = (position.size * Constants.PERCENTAGE_FACTOR) /
            position.collateral;
        // allow for a maximum of a increasePositionBufferBps decrease since there might be some swap fees taken from the collateral
        uint256 nextLeverageWithBuffer = (nextSize *
            (Constants.PERCENTAGE_FACTOR + increasePositionBufferBps)) /
            (nextCollateral);

        require(
            nextLeverageWithBuffer >= prevLeverage,
            "PositionManager: long leverage decrease"
        );
    }
}
