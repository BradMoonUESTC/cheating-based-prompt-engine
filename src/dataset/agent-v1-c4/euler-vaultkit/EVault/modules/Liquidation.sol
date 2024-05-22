// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {ILiquidation} from "../IEVault.sol";
import {Base} from "../shared/Base.sol";
import {BalanceUtils} from "../shared/BalanceUtils.sol";
import {LiquidityUtils} from "../shared/LiquidityUtils.sol";

import "../shared/types/Types.sol";

/// @title LiquidationModule
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice An EVault module handling liquidations of unhealthy accounts
abstract contract LiquidationModule is ILiquidation, BalanceUtils, LiquidityUtils {
    using TypesLib for uint256;

    struct LiquidationCache {
        address liquidator;
        address violator;
        address collateral;
        address[] collaterals;
        Assets liability;
        Assets repay;
        uint256 yieldBalance;
    }

    /// @inheritdoc ILiquidation
    /// @dev The function will not revert if the account is healthy and return (0, 0)
    function checkLiquidation(address liquidator, address violator, address collateral)
        public
        view
        virtual
        nonReentrantView
        returns (uint256 maxRepay, uint256 maxYield)
    {
        LiquidationCache memory liqCache =
            calculateLiquidation(loadVault(), liquidator, violator, collateral, type(uint256).max);

        maxRepay = liqCache.repay.toUint();
        maxYield = liqCache.yieldBalance;
    }

    /// @inheritdoc ILiquidation
    function liquidate(address violator, address collateral, uint256 repayAssets, uint256 minYieldBalance)
        public
        virtual
        nonReentrant
    {
        (VaultCache memory vaultCache, address liquidator) = initOperation(OP_LIQUIDATE, CHECKACCOUNT_CALLER);

        LiquidationCache memory liqCache =
            calculateLiquidation(vaultCache, liquidator, violator, collateral, repayAssets);

        executeLiquidation(vaultCache, liqCache, minYieldBalance);
    }

    function calculateLiquidation(
        VaultCache memory vaultCache,
        address liquidator,
        address violator,
        address collateral,
        uint256 desiredRepay
    ) private view returns (LiquidationCache memory liqCache) {
        // Init cache

        liqCache.liquidator = liquidator;
        liqCache.violator = violator;
        liqCache.collateral = collateral;

        liqCache.repay = Assets.wrap(0);
        liqCache.yieldBalance = 0;
        liqCache.liability = getCurrentOwed(vaultCache, violator).toAssetsUp();
        liqCache.collaterals = getCollaterals(violator);

        // Checks

        // Same account self-liquidation is not allowed
        if (liqCache.violator == liqCache.liquidator) revert E_SelfLiquidation();
        // Only liquidate trusted collaterals to make sure yield transfer has no side effects.
        if (!isRecognizedCollateral(liqCache.collateral)) revert E_BadCollateral();
        // Verify this vault is the controller for the violator
        validateController(liqCache.violator);
        // Violator must have enabled the collateral to be transferred to the liquidator
        if (!isCollateralEnabled(liqCache.violator, liqCache.collateral)) revert E_CollateralDisabled();
        // Violator's health check must not be deferred, meaning no prior operations on violator's account
        // would possibly be forgiven after the enforced collateral transfer to the liquidator
        if (isAccountStatusCheckDeferred(violator)) revert E_ViolatorLiquidityDeferred();
        // A cool off time must elapse since successful account status check in order to mitigate self-liquidaition
        // attacks
        if (isInLiquidationCoolOff(violator)) revert E_LiquidationCoolOff();

        // Violator has no liabilities, liquidation is a no-op
        if (liqCache.liability.isZero()) return liqCache;

        // Calculate max yield and repay

        liqCache = calculateMaxLiquidation(liqCache, vaultCache);

        // Adjust for desired repay

        if (desiredRepay != type(uint256).max) {
            uint256 maxRepay = liqCache.repay.toUint();
            if (desiredRepay > maxRepay) revert E_ExcessiveRepayAmount();

            if (maxRepay > 0) {
                liqCache.yieldBalance = desiredRepay * liqCache.yieldBalance / maxRepay;
                liqCache.repay = desiredRepay.toAssets();
            }
        }
    }

    function calculateMaxLiquidation(LiquidationCache memory liqCache, VaultCache memory vaultCache)
        private
        view
        returns (LiquidationCache memory)
    {
        // Check account health

        (uint256 collateralAdjustedValue, uint256 liabilityValue) =
            calculateLiquidity(vaultCache, liqCache.violator, liqCache.collaterals, true);

        // no violation
        if (collateralAdjustedValue > liabilityValue) return liqCache;

        // Compute discount

        // discountFactor = health score = 1 - discount
        uint256 discountFactor = collateralAdjustedValue * 1e18 / liabilityValue;
        {
            uint256 minDiscountFactor;
            unchecked {
                // discount <= config scale, so discount factor >= 0
                minDiscountFactor = 1e18 - uint256(1e18) * vaultStorage.maxLiquidationDiscount.toUint16() / CONFIG_SCALE;
            }
            if (discountFactor < minDiscountFactor) discountFactor = minDiscountFactor;
        }

        // Compute maximum yield using mid-point prices

        uint256 collateralBalance = IERC20(liqCache.collateral).balanceOf(liqCache.violator);
        uint256 collateralValue =
            vaultCache.oracle.getQuote(collateralBalance, liqCache.collateral, vaultCache.unitOfAccount);

        if (collateralValue == 0) {
            // Worthless collateral can be claimed with no repay. The collateral can be actually worthless, or the
            // amount of available collateral could be non-representable in the unit of account (rounded down to zero
            // during conversion). In this case the liquidator is able to claim the collateral without repaying any
            // debt. Note that it's not profitable as long as liquidation gas costs are larger than the value of a
            // single wei of the reference asset. Care should be taken though when selecting unit of account and
            // collateral assets.
            liqCache.yieldBalance = collateralBalance;
            return liqCache;
        }

        uint256 maxRepayValue = liabilityValue;
        uint256 maxYieldValue = maxRepayValue * 1e18 / discountFactor;

        // Limit yield to borrower's available collateral, and reduce repay if necessary. This can happen when borrower
        // has multiple collaterals and seizing all of this one won't bring the violator back to solvency

        if (collateralValue < maxYieldValue) {
            maxRepayValue = collateralValue * discountFactor / 1e18;
            maxYieldValue = collateralValue;
        }

        liqCache.repay = (maxRepayValue * liqCache.liability.toUint() / liabilityValue).toAssets();
        liqCache.yieldBalance = maxYieldValue * collateralBalance / collateralValue;

        return liqCache;
    }

    function executeLiquidation(VaultCache memory vaultCache, LiquidationCache memory liqCache, uint256 minYieldBalance)
        private
    {
        // Check minimum yield.

        if (minYieldBalance > liqCache.yieldBalance) revert E_MinYield();

        // Handle repay: liquidator takes on violator's debt:

        if (liqCache.repay.toUint() > 0) {
            transferBorrow(vaultCache, liqCache.violator, liqCache.liquidator, liqCache.repay);
        }

        // Handle yield: liquidator receives violator's collateral

        // Impersonate violator on the EVC to seize collateral. The yield transfer will trigger a health check on the
        // violator's account, which should be forgiven, because the violator's account is not guaranteed to be healthy
        // after liquidation. This operation is safe, because:
        // 1. `liquidate` function is enforcing that the violator is not in deferred checks state,
        //    therefore there were no prior batch operations that could have registered a health check,
        //    and if the check is present now, it must have been triggered by the enforced transfer.
        // 2. Only collaterals with initialized LTV settings can be liquidated and they are assumed to be audited
        //    to have safe transfer methods, which make no external calls. In other words, yield transfer will not
        //    have any side effects, which would be wrongly forgiven.
        // 3. Any additional operations on violator's account in a batch will register the health check again, and it
        //    will be executed normally at the end of the batch.

        if (liqCache.yieldBalance > 0) {
            enforceCollateralTransfer(
                liqCache.collateral, liqCache.yieldBalance, liqCache.violator, liqCache.liquidator
            );

            forgiveAccountStatusCheck(liqCache.violator);
        }

        // Handle debt socialization

        if (
            vaultCache.configFlags.isNotSet(CFG_DONT_SOCIALIZE_DEBT) && liqCache.liability > liqCache.repay
                && checkNoCollateral(liqCache.violator, liqCache.collaterals)
        ) {
            Assets owedRemaining = liqCache.liability.subUnchecked(liqCache.repay);
            decreaseBorrow(vaultCache, liqCache.violator, owedRemaining);

            // decreaseBorrow emits Repay without any assets entering the vault. Emit Withdraw from and to zero address
            // to cover the missing amount for offchain trackers.
            emit Withdraw(liqCache.liquidator, address(0), address(0), owedRemaining.toUint(), 0);
            emit DebtSocialized(liqCache.violator, owedRemaining.toUint());
        }

        emit Liquidate(
            liqCache.liquidator, liqCache.violator, liqCache.collateral, liqCache.repay.toUint(), liqCache.yieldBalance
        );
    }

    function isInLiquidationCoolOff(address account) private view returns (bool) {
        unchecked {
            return block.timestamp < getLastAccountStatusCheckTimestamp(account) + vaultStorage.liquidationCoolOffTime;
        }
    }
}

/// @dev Deployable module contract
contract Liquidation is LiquidationModule {
    constructor(Integrations memory integrations) Base(integrations) {}
}
