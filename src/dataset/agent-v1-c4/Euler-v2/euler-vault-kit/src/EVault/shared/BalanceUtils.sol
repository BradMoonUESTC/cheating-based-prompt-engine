// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Base} from "./Base.sol";

import "./types/Types.sol";

/// @title BalanceUtils
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Utilities for tracking share balances and allowances
abstract contract BalanceUtils is Base {
    // Balances

    function increaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        Shares amount,
        Assets assets
    ) internal virtual {
        if (account == address(0)) revert E_BadSharesReceiver();
        UserStorage storage user = vaultStorage.users[account];

        (Shares origBalance, bool balanceForwarderEnabled) = user.getBalanceAndBalanceForwarder();
        Shares newBalance = origBalance + amount;

        user.setBalance(newBalance);
        vaultStorage.totalShares = vaultCache.totalShares = vaultCache.totalShares + amount;

        if (balanceForwarderEnabled) {
            balanceTracker.balanceTrackerHook(account, newBalance.toUint(), false);
        }

        emit Transfer(address(0), account, amount.toUint());
        emit Deposit(sender, account, assets.toUint(), amount.toUint());
    }

    function decreaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        address receiver,
        Shares amount,
        Assets assets
    ) internal virtual {
        UserStorage storage user = vaultStorage.users[account];
        (Shares origBalance, bool balanceForwarderEnabled) = user.getBalanceAndBalanceForwarder();
        if (origBalance < amount) revert E_InsufficientBalance();

        Shares newBalance = origBalance.subUnchecked(amount);

        user.setBalance(newBalance);
        vaultStorage.totalShares = vaultCache.totalShares = vaultCache.totalShares - amount;

        if (balanceForwarderEnabled) {
            // if the balance is decreased as a part of the collateral transfer during liquidation,
            // which is indicated by the EVC with a collateral control in progress flag,
            // instruct the balance tracker to forfeit rewards due to the liquidated account, in order to
            // limit gas consumption, which could potentially be abused by violators to prevent liquidations.
            balanceTracker.balanceTrackerHook(account, newBalance.toUint(), isControlCollateralInProgress());
        }

        emit Transfer(account, address(0), amount.toUint());
        emit Withdraw(sender, receiver, account, assets.toUint(), amount.toUint());
    }

    function transferBalance(address from, address to, Shares amount) internal virtual {
        if (to == address(0)) revert E_BadSharesReceiver();

        if (!amount.isZero()) {
            // update from

            UserStorage storage user = vaultStorage.users[from];

            (Shares origFromBalance, bool fromBalanceForwarderEnabled) = user.getBalanceAndBalanceForwarder();
            if (origFromBalance < amount) revert E_InsufficientBalance();

            Shares newFromBalance = origFromBalance.subUnchecked(amount);
            user.setBalance(newFromBalance);

            // update to

            user = vaultStorage.users[to];

            (Shares origToBalance, bool toBalanceForwarderEnabled) = user.getBalanceAndBalanceForwarder();

            Shares newToBalance = origToBalance + amount;
            user.setBalance(newToBalance);

            if (fromBalanceForwarderEnabled) {
                balanceTracker.balanceTrackerHook(from, newFromBalance.toUint(), isControlCollateralInProgress());
            }

            if (toBalanceForwarderEnabled && from != to) {
                balanceTracker.balanceTrackerHook(to, newToBalance.toUint(), false);
            }
        }

        emit Transfer(from, to, amount.toUint());
    }

    // Allowance

    function setAllowance(address owner, address spender, uint256 amount) internal {
        if (spender == owner) revert E_SelfApproval();

        vaultStorage.users[owner].eTokenAllowance[spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /// @dev As gas saving optimization, consuming allowance doesn't emit the Approval event.
    function decreaseAllowance(address owner, address spender, Shares amount) internal virtual {
        if (amount.isZero() || owner == spender) return;
        UserStorage storage user = vaultStorage.users[owner];

        uint256 allowance = user.eTokenAllowance[spender];
        if (allowance != type(uint256).max) {
            if (allowance < amount.toUint()) revert E_InsufficientAllowance();
            unchecked {
                allowance -= amount.toUint();
            }
            user.eTokenAllowance[spender] = allowance;
        }
    }
}
