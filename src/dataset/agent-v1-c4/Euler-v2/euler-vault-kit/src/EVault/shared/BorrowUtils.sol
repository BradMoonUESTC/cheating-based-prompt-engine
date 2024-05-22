// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Base} from "./Base.sol";
import {DToken} from "../DToken.sol";
import {IIRM} from "../../InterestRateModels/IIRM.sol";

import "./types/Types.sol";

/// @title BorrowUtils
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Utilities for tracking debt and interest rates
abstract contract BorrowUtils is Base {
    function getCurrentOwed(VaultCache memory vaultCache, address account, Owed owed) internal view returns (Owed) {
        // Don't bother loading the user's accumulator
        if (owed.isZero()) return Owed.wrap(0);

        // Can't divide by 0 here: If owed is non-zero, we must've initialized the user's interestAccumulator
        return owed.mulDiv(vaultCache.interestAccumulator, vaultStorage.users[account].interestAccumulator);
    }

    function getCurrentOwed(VaultCache memory vaultCache, address account) internal view returns (Owed) {
        return getCurrentOwed(vaultCache, account, vaultStorage.users[account].getOwed());
    }

    function loadUserBorrow(VaultCache memory vaultCache, address account)
        private
        view
        returns (Owed newOwed, Owed prevOwed)
    {
        prevOwed = vaultStorage.users[account].getOwed();
        newOwed = getCurrentOwed(vaultCache, account, prevOwed);
    }

    function setUserBorrow(VaultCache memory vaultCache, address account, Owed newOwed) private {
        UserStorage storage user = vaultStorage.users[account];

        user.setOwed(newOwed);
        user.interestAccumulator = vaultCache.interestAccumulator;
    }

    function increaseBorrow(VaultCache memory vaultCache, address account, Assets assets) internal virtual {
        (Owed owed, Owed prevOwed) = loadUserBorrow(vaultCache, account);

        Owed amount = assets.toOwed();
        owed = owed + amount;

        setUserBorrow(vaultCache, account, owed);
        vaultStorage.totalBorrows = vaultCache.totalBorrows = vaultCache.totalBorrows + amount;

        logBorrow(account, assets, prevOwed.toAssetsUp(), owed.toAssetsUp());
    }

    /// @dev Contrary to `increaseBorrow` and `transferBorrow` this function does the accounting in Assets
    /// by first rounding up the user's debt. The rounding is an additional cost to the user and is recorded
    /// both in user's account and in `totalBorrows`
    function decreaseBorrow(VaultCache memory vaultCache, address account, Assets assets) internal virtual {
        (Owed owedExact, Owed prevOwed) = loadUserBorrow(vaultCache, account);
        Assets owed = owedExact.toAssetsUp();

        if (assets > owed) revert E_RepayTooMuch();

        Owed owedRemaining = owed.subUnchecked(assets).toOwed();

        setUserBorrow(vaultCache, account, owedRemaining);
        vaultStorage.totalBorrows = vaultCache.totalBorrows = vaultCache.totalBorrows > owedExact
            ? vaultCache.totalBorrows.subUnchecked(owedExact).addUnchecked(owedRemaining)
            : owedRemaining;

        logRepay(account, assets, prevOwed.toAssetsUp(), owedRemaining.toAssetsUp());
    }

    function transferBorrow(VaultCache memory vaultCache, address from, address to, Assets assets) internal virtual {
        Owed amount = assets.toOwed();

        (Owed fromOwed, Owed fromOwedPrev) = loadUserBorrow(vaultCache, from);

        // If amount was rounded up, or dust is left over, transfer exact amount owed
        if (
            (amount > fromOwed && amount.subUnchecked(fromOwed).isDust())
                || (amount < fromOwed && fromOwed.subUnchecked(amount).isDust())
        ) {
            amount = fromOwed;
        }

        if (amount > fromOwed) revert E_InsufficientDebt();

        fromOwed = fromOwed.subUnchecked(amount);
        setUserBorrow(vaultCache, from, fromOwed);

        (Owed toOwed, Owed toOwedPrev) = loadUserBorrow(vaultCache, to);

        toOwed = toOwed + amount;
        setUserBorrow(vaultCache, to, toOwed);

        logRepay(from, assets, fromOwedPrev.toAssetsUp(), fromOwed.toAssetsUp());

        // with small fractional debt amounts the interest calculation could be negative in `logBorrow`
        Assets toPrevAssets = toOwedPrev.toAssetsUp();
        Assets toAssets = toOwed.toAssetsUp();
        if (assets + toPrevAssets > toAssets) assets = toAssets - toPrevAssets;
        logBorrow(to, assets, toPrevAssets, toAssets);
    }

    function computeInterestRate(VaultCache memory vaultCache) internal virtual returns (uint256) {
        // single sload
        address irm = vaultStorage.interestRateModel;
        uint256 newInterestRate = vaultStorage.interestRate;

        if (irm != address(0)) {
            (bool success, bytes memory data) = irm.call(
                abi.encodeCall(
                    IIRM.computeInterestRate,
                    (address(this), vaultCache.cash.toUint(), vaultCache.totalBorrows.toAssetsUp().toUint())
                )
            );

            if (success && data.length >= 32) {
                newInterestRate = abi.decode(data, (uint256));
                if (newInterestRate > MAX_ALLOWED_INTEREST_RATE) newInterestRate = MAX_ALLOWED_INTEREST_RATE;
                vaultStorage.interestRate = uint72(newInterestRate);
            }
        }

        return newInterestRate;
    }

    function computeInterestRateView(VaultCache memory vaultCache) internal view virtual returns (uint256) {
        // single sload
        address irm = vaultStorage.interestRateModel;
        uint256 newInterestRate = vaultStorage.interestRate;

        if (irm != address(0) && isVaultStatusCheckDeferred()) {
            (bool success, bytes memory data) = irm.staticcall(
                abi.encodeCall(
                    IIRM.computeInterestRateView,
                    (address(this), vaultCache.cash.toUint(), vaultCache.totalBorrows.toAssetsUp().toUint())
                )
            );

            if (success && data.length >= 32) {
                newInterestRate = abi.decode(data, (uint256));
                if (newInterestRate > MAX_ALLOWED_INTEREST_RATE) newInterestRate = MAX_ALLOWED_INTEREST_RATE;
            }
        }

        return newInterestRate;
    }

    function calculateDTokenAddress() internal view virtual returns (address dToken) {
        // inspired by:
        // https://github.com/Vectorized/solady/blob/229c18cfcdcd474f95c30ad31b0f7d428ee8a31a/src/utils/CREATE3.sol#L82-L90
        assembly ("memory-safe") {
            mstore(0x14, address())
            // 0xd6 = 0xc0 (short RLP prefix) + 0x16 (length of: 0x94 ++ address(this) ++ 0x01).
            // 0x94 = 0x80 + 0x14 (0x14 = the length of an address, 20 bytes, in hex).
            mstore(0x00, 0xd694)
            // Nonce of the contract when DToken was deployed (1).
            mstore8(0x34, 0x01)

            dToken := keccak256(0x1e, 0x17)
        }
    }

    function logBorrow(address account, Assets amount, Assets prevOwed, Assets owed) private {
        Assets interest = owed.subUnchecked(prevOwed).subUnchecked(amount);
        if (!interest.isZero()) emit InterestAccrued(account, interest.toUint());
        if (!amount.isZero()) emit Borrow(account, amount.toUint());
        logDToken(account, prevOwed, owed);
    }

    function logRepay(address account, Assets amount, Assets prevOwed, Assets owed) private {
        Assets interest = owed.addUnchecked(amount).subUnchecked(prevOwed);
        if (!interest.isZero()) emit InterestAccrued(account, interest.toUint());
        if (!amount.isZero()) emit Repay(account, amount.toUint());
        logDToken(account, prevOwed, owed);
    }

    function logDToken(address account, Assets prevOwed, Assets owed) private {
        address dTokenAddress = calculateDTokenAddress();

        if (owed > prevOwed) {
            uint256 change = owed.subUnchecked(prevOwed).toUint();
            DToken(dTokenAddress).emitTransfer(address(0), account, change);
        } else if (prevOwed > owed) {
            uint256 change = prevOwed.subUnchecked(owed).toUint();
            DToken(dTokenAddress).emitTransfer(account, address(0), change);
        }
    }
}
