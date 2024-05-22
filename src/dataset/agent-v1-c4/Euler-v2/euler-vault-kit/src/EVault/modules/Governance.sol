// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {IGovernance} from "../IEVault.sol";
import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";
import {IHookTarget} from "../../interfaces/IHookTarget.sol";
import {Base} from "../shared/Base.sol";
import {BalanceUtils} from "../shared/BalanceUtils.sol";
import {LTVUtils} from "../shared/LTVUtils.sol";
import {BorrowUtils} from "../shared/BorrowUtils.sol";
import {ProxyUtils} from "../shared/lib/ProxyUtils.sol";

import "../shared/types/Types.sol";

/// @title GovernanceModule
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice An EVault module handling governance, including configuration and fees
abstract contract GovernanceModule is IGovernance, BalanceUtils, BorrowUtils, LTVUtils {
    using TypesLib for uint16;

    // Protocol guarantees for the governor

    // Governor is guaranteed that the protocol fee share will not exceed this value
    uint16 internal constant MAX_PROTOCOL_FEE_SHARE = 0.5e4;
    // Governor is guaranteed to be able to set the interest fee to a value within a certain range.
    // Outside this range, the interest fee must be approved by ProtocolConfig.
    // Lower bound of the guaranteed range
    uint16 internal constant GUARANTEED_INTEREST_FEE_MIN = 0.1e4;
    // Higher bound of the guaranteed range
    uint16 internal constant GUARANTEED_INTEREST_FEE_MAX = 1e4;

    /// @notice Set a governor address for the EVault
    /// @param newGovernorAdmin Address of the new governor
    event GovSetGovernorAdmin(address indexed newGovernorAdmin);

    /// @notice Set a fee receiver address
    /// @param newFeeReceiver Address of the new fee receiver
    event GovSetFeeReceiver(address indexed newFeeReceiver);

    /// @notice Set new LTV configuration for a collateral
    /// @param collateral Address of the collateral
    /// @param borrowLTV The new LTV for the collateral, used to determine health of the account during regular
    /// operations, in 1e4 scale
    /// @param liquidationLTV The new LTV for the collateral, used to determine health of the account during
    /// liquidations, in 1e4 scale
    /// @param initialLiquidationLTV The previous liquidation LTV at the moment a new configuration was set
    /// @param targetTimestamp If the LTV is lowered, the timestamp when the ramped liquidation LTV will merge with the
    /// `targetLTV`
    /// @param rampDuration If the LTV is lowered, duration in seconds, during which the liquidation LTV will be merging
    /// with `targetLTV`
    event GovSetLTV(
        address indexed collateral,
        uint16 borrowLTV,
        uint16 liquidationLTV,
        uint16 initialLiquidationLTV,
        uint48 targetTimestamp,
        uint32 rampDuration,
        bool initialized
    );
    /// @notice Set an interest rate model contract address
    /// @param newInterestRateModel Address of the new IRM
    event GovSetInterestRateModel(address newInterestRateModel);

    /// @notice Set a maximum liquidation discount
    /// @param newDiscount The new maximum liquidation discount in 1e4 scale
    event GovSetMaxLiquidationDiscount(uint16 newDiscount);

    /// @notice Set a new liquidation cool off time, which must elapse after successful account status check, before
    /// account can be liquidated
    /// @param newCoolOffTime The new liquidation cool off time in seconds
    event GovSetLiquidationCoolOffTime(uint16 newCoolOffTime);

    /// @notice Set new hooks configuration
    /// @param newHookTarget Address of the new hook target contract
    /// @param newHookedOps A bitfield of operations to be hooked. See Constants.sol for a list of operations
    event GovSetHookConfig(address indexed newHookTarget, uint32 newHookedOps);

    /// @notice Set new configuration flags
    /// @param newConfigFlags New configuration flags. See Constants.sol for a list of configuration flags
    event GovSetConfigFlags(uint32 newConfigFlags);

    /// @notice Set new caps
    /// @param newSupplyCap New supply cap in AmountCap format
    /// @param newBorrowCap New borrow cap in AmountCap format
    event GovSetCaps(uint16 newSupplyCap, uint16 newBorrowCap);

    /// @notice Set new interest fee
    /// @param newFee New interest fee as percentage in 1e4 scale
    event GovSetInterestFee(uint16 newFee);

    modifier governorOnly() {
        if (vaultStorage.governorAdmin != EVCAuthenticateGovernor()) revert E_Unauthorized();
        _;
    }

    /// @inheritdoc IGovernance
    function governorAdmin() public view virtual reentrantOK returns (address) {
        return vaultStorage.governorAdmin;
    }

    /// @inheritdoc IGovernance
    function feeReceiver() public view virtual reentrantOK returns (address) {
        return vaultStorage.feeReceiver;
    }

    /// @inheritdoc IGovernance
    function interestFee() public view virtual reentrantOK returns (uint16) {
        return vaultStorage.interestFee.toUint16();
    }

    /// @inheritdoc IGovernance
    function interestRateModel() public view virtual reentrantOK returns (address) {
        return vaultStorage.interestRateModel;
    }

    /// @inheritdoc IGovernance
    function protocolConfigAddress() public view virtual reentrantOK returns (address) {
        return address(protocolConfig);
    }

    /// @inheritdoc IGovernance
    function protocolFeeShare() public view virtual reentrantOK returns (uint256) {
        (, uint256 protocolShare) = protocolConfig.protocolFeeConfig(address(this));
        return protocolShare;
    }

    /// @inheritdoc IGovernance
    function protocolFeeReceiver() public view virtual reentrantOK returns (address) {
        (address protocolReceiver,) = protocolConfig.protocolFeeConfig(address(this));
        return protocolReceiver;
    }

    /// @inheritdoc IGovernance
    function caps() public view virtual reentrantOK returns (uint16, uint16) {
        return (vaultStorage.supplyCap.toRawUint16(), vaultStorage.borrowCap.toRawUint16());
    }

    /// @inheritdoc IGovernance
    function LTVBorrow(address collateral) public view virtual reentrantOK returns (uint16) {
        return getLTV(collateral, false).toUint16();
    }

    /// @inheritdoc IGovernance
    function LTVLiquidation(address collateral) public view virtual reentrantOK returns (uint16) {
        return getLTV(collateral, true).toUint16();
    }

    /// @inheritdoc IGovernance
    function LTVFull(address collateral)
        public
        view
        virtual
        reentrantOK
        returns (uint16, uint16, uint16, uint48, uint32)
    {
        LTVConfig memory ltv = vaultStorage.ltvLookup[collateral];
        return (
            ltv.borrowLTV.toUint16(),
            ltv.liquidationLTV.toUint16(),
            ltv.initialLiquidationLTV.toUint16(),
            ltv.targetTimestamp,
            ltv.rampDuration
        );
    }

    /// @inheritdoc IGovernance
    function LTVList() public view virtual reentrantOK returns (address[] memory) {
        return vaultStorage.ltvList;
    }

    /// @inheritdoc IGovernance
    function maxLiquidationDiscount() public view virtual reentrantOK returns (uint16) {
        return vaultStorage.maxLiquidationDiscount.toUint16();
    }

    /// @inheritdoc IGovernance
    function liquidationCoolOffTime() public view virtual reentrantOK returns (uint16) {
        return vaultStorage.liquidationCoolOffTime;
    }

    /// @inheritdoc IGovernance
    function hookConfig() public view virtual reentrantOK returns (address, uint32) {
        return (vaultStorage.hookTarget, vaultStorage.hookedOps.toUint32());
    }

    /// @inheritdoc IGovernance
    function configFlags() public view virtual reentrantOK returns (uint32) {
        return vaultStorage.configFlags.toUint32();
    }

    /// @inheritdoc IGovernance
    function EVC() public view virtual reentrantOK returns (address) {
        return address(evc);
    }

    /// @inheritdoc IGovernance
    function unitOfAccount() public view virtual reentrantOK returns (address) {
        (,, address _unitOfAccount) = ProxyUtils.metadata();
        return _unitOfAccount;
    }

    /// @inheritdoc IGovernance
    function oracle() public view virtual reentrantOK returns (address) {
        (, IPriceOracle _oracle,) = ProxyUtils.metadata();
        return address(_oracle);
    }

    /// @inheritdoc IGovernance
    function permit2Address() public view virtual reentrantOK returns (address) {
        return permit2;
    }

    /// @inheritdoc IGovernance
    function convertFees() public virtual nonReentrant {
        (VaultCache memory vaultCache, address account) = initOperation(OP_CONVERT_FEES, CHECKACCOUNT_NONE);

        if (vaultCache.accumulatedFees.isZero()) return;

        (address protocolReceiver, uint16 protocolFee) = protocolConfig.protocolFeeConfig(address(this));
        address governorReceiver = vaultStorage.feeReceiver;

        if (governorReceiver == address(0)) {
            protocolFee = CONFIG_SCALE; // governor forfeits fees
        } else if (protocolFee > MAX_PROTOCOL_FEE_SHARE) {
            protocolFee = MAX_PROTOCOL_FEE_SHARE;
        }

        Shares governorShares = vaultCache.accumulatedFees.mulDiv(CONFIG_SCALE - protocolFee, CONFIG_SCALE);
        Shares protocolShares = vaultCache.accumulatedFees - governorShares;

        // Decrease totalShares because increaseBalance will increase it by that total amount
        vaultStorage.totalShares = vaultCache.totalShares = vaultCache.totalShares - vaultCache.accumulatedFees;

        vaultStorage.accumulatedFees = vaultCache.accumulatedFees = Shares.wrap(0);

        // For the Deposit events in increaseBalance the assets amount is zero - the shares are covered with the accrued
        // interest
        if (!governorShares.isZero()) {
            increaseBalance(vaultCache, governorReceiver, address(0), governorShares, Assets.wrap(0));
        }

        if (!protocolShares.isZero()) {
            increaseBalance(vaultCache, protocolReceiver, address(0), protocolShares, Assets.wrap(0));
        }

        emit ConvertFees(account, protocolReceiver, governorReceiver, protocolShares.toUint(), governorShares.toUint());
    }

    /// @inheritdoc IGovernance
    function setGovernorAdmin(address newGovernorAdmin) public virtual nonReentrant governorOnly {
        vaultStorage.governorAdmin = newGovernorAdmin;
        emit GovSetGovernorAdmin(newGovernorAdmin);
    }

    /// @inheritdoc IGovernance
    function setFeeReceiver(address newFeeReceiver) public virtual nonReentrant governorOnly {
        vaultStorage.feeReceiver = newFeeReceiver;
        emit GovSetFeeReceiver(newFeeReceiver);
    }

    /// @inheritdoc IGovernance
    /// @dev When the collateral asset is no longer deemed suitable to sustain debt (and not because of code issues, see
    /// `clearLTV`), its LTV setting can be set to 0. Setting a zero liquidation LTV also enforces a zero borrowing LTV
    /// (`newBorrowLTV <= newLiquidationLTV`). In such cases, the collateral becomes immediately ineffective for new
    /// borrows. However, for liquidation purposes, the LTV can be ramped down over a period of time (`rampDuration`).
    /// This ramping helps users avoid hard liquidations with maximum discounts and gives them a chance to close their
    /// positions in an orderly fashion. The choice of `rampDuration` depends on market conditions assessed by the
    /// governor. They may decide to forgo the ramp entirely by setting the duration to zero, presumably in light of
    /// extreme market conditions, where ramping would pose a threat to the vault's solvency. In any case, when the
    /// liquidation LTV reaches its target of 0, this asset will no longer support the debt, but it will still be
    /// possible to liquidate it at a discount and use the proceeds to repay an unhealthy loan.
    function setLTV(address collateral, uint16 borrowLTV, uint16 liquidationLTV, uint32 rampDuration)
        public
        virtual
        nonReentrant
        governorOnly
    {
        // self-collateralization is not allowed
        if (collateral == address(this)) revert E_InvalidLTVAsset();

        ConfigAmount newBorrowLTV = borrowLTV.toConfigAmount();
        ConfigAmount newLiquidationLTV = liquidationLTV.toConfigAmount();

        // The borrow LTV must be lower than or equal to the the converged liquidation LTV
        if (newBorrowLTV > newLiquidationLTV) revert E_LTVBorrow();

        LTVConfig memory currentLTV = vaultStorage.ltvLookup[collateral];

        // If new LTV is higher or equal to current, as per ramping configuration, it should take effect immediately
        if (newLiquidationLTV >= currentLTV.getLTV(true) && rampDuration > 0) revert E_LTVLiquidation();

        LTVConfig memory newLTV = currentLTV.setLTV(newBorrowLTV, newLiquidationLTV, rampDuration);

        vaultStorage.ltvLookup[collateral] = newLTV;

        if (!currentLTV.initialized) vaultStorage.ltvList.push(collateral);

        emit GovSetLTV(
            collateral,
            newLTV.borrowLTV.toUint16(),
            newLTV.liquidationLTV.toUint16(),
            newLTV.initialLiquidationLTV.toUint16(),
            newLTV.targetTimestamp,
            newLTV.rampDuration,
            !currentLTV.initialized
        );
    }

    /// @inheritdoc IGovernance
    /// @dev When LTV configuration is cleared, attempt to liquidate the collateral will revert.
    /// Clearing should only be executed when the collateral is found to be unsafe to liquidate,
    /// because e.g. it does external calls on transfer, which would be a critical security threat.
    function clearLTV(address collateral) public virtual nonReentrant governorOnly {
        uint16 originalLTV = getLTV(collateral, true).toUint16();
        vaultStorage.ltvLookup[collateral].clear();

        emit GovSetLTV(collateral, 0, 0, originalLTV, 0, 0, false);
    }

    /// @inheritdoc IGovernance
    function setMaxLiquidationDiscount(uint16 newDiscount) public virtual nonReentrant governorOnly {
        vaultStorage.maxLiquidationDiscount = newDiscount.toConfigAmount();
        emit GovSetMaxLiquidationDiscount(newDiscount);
    }

    /// @inheritdoc IGovernance
    function setLiquidationCoolOffTime(uint16 newCoolOffTime) public virtual nonReentrant governorOnly {
        vaultStorage.liquidationCoolOffTime = newCoolOffTime;
        emit GovSetLiquidationCoolOffTime(newCoolOffTime);
    }

    /// @inheritdoc IGovernance
    function setInterestRateModel(address newModel) public virtual nonReentrant governorOnly {
        VaultCache memory vaultCache = updateVault();

        vaultStorage.interestRateModel = newModel;
        vaultStorage.interestRate = 0;

        uint256 newInterestRate = computeInterestRate(vaultCache);

        logVaultStatus(vaultCache, newInterestRate);

        emit GovSetInterestRateModel(newModel);
    }

    /// @inheritdoc IGovernance
    function setHookConfig(address newHookTarget, uint32 newHookedOps) public virtual nonReentrant governorOnly {
        if (
            newHookTarget != address(0)
                && IHookTarget(newHookTarget).isHookTarget() != IHookTarget.isHookTarget.selector
        ) revert E_NotHookTarget();

        if (newHookedOps >= OP_MAX_VALUE) revert E_NotSupported();

        vaultStorage.hookTarget = newHookTarget;
        vaultStorage.hookedOps = Flags.wrap(newHookedOps);
        emit GovSetHookConfig(newHookTarget, newHookedOps);
    }

    /// @inheritdoc IGovernance
    function setConfigFlags(uint32 newConfigFlags) public virtual nonReentrant governorOnly {
        if (newConfigFlags >= CFG_MAX_VALUE) revert E_NotSupported();

        vaultStorage.configFlags = Flags.wrap(newConfigFlags);
        emit GovSetConfigFlags(newConfigFlags);
    }

    /// @inheritdoc IGovernance
    function setCaps(uint16 supplyCap, uint16 borrowCap) public virtual nonReentrant governorOnly {
        AmountCap _supplyCap = AmountCap.wrap(supplyCap);
        // The raw uint16 cap amount == 0 is a special value. See comments in AmountCap.sol
        // Max total assets is a sum of max pool size and max total debt, both Assets type
        if (supplyCap != 0 && _supplyCap.resolve() > 2 * MAX_SANE_AMOUNT) revert E_BadSupplyCap();

        AmountCap _borrowCap = AmountCap.wrap(borrowCap);
        if (borrowCap != 0 && _borrowCap.resolve() > MAX_SANE_AMOUNT) revert E_BadBorrowCap();

        vaultStorage.supplyCap = _supplyCap;
        vaultStorage.borrowCap = _borrowCap;

        emit GovSetCaps(supplyCap, borrowCap);
    }

    /// @inheritdoc IGovernance
    function setInterestFee(uint16 newInterestFee) public virtual nonReentrant governorOnly {
        // Update vault to apply the current interest fee to the pending interest
        VaultCache memory vaultCache = updateVault();
        logVaultStatus(vaultCache, vaultStorage.interestRate);

        // Interest fees in guaranteed range are always allowed, otherwise ask protocolConfig
        if (newInterestFee < GUARANTEED_INTEREST_FEE_MIN || newInterestFee > GUARANTEED_INTEREST_FEE_MAX) {
            if (!protocolConfig.isValidInterestFee(address(this), newInterestFee)) revert E_BadFee();
        }

        vaultStorage.interestFee = newInterestFee.toConfigAmount();

        emit GovSetInterestFee(newInterestFee);
    }
}

/// @dev Deployable module contract
contract Governance is GovernanceModule {
    constructor(Integrations memory integrations) Base(integrations) {}
}
