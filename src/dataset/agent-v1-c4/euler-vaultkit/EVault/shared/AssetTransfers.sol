// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {SafeERC20Lib} from "./lib/SafeERC20Lib.sol";
import {Base} from "./Base.sol";

import "./types/Types.sol";

/// @title AssetTransfers
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Transfer assets into and out of the vault
abstract contract AssetTransfers is Base {
    using TypesLib for uint256;
    using SafeERC20Lib for IERC20;

    function pullAssets(VaultCache memory vaultCache, address from, Assets amount) internal virtual {
        vaultCache.asset.safeTransferFrom(from, address(this), amount.toUint(), permit2);
        vaultStorage.cash = vaultCache.cash = vaultCache.cash + amount;
    }

    /// @dev If the `CFG_EVC_COMPATIBLE_ASSET` flag is set, the function will protect users from mistakenly sending
    /// funds to the EVC sub-accounts. Functions that push tokens out (`withdraw`, `redeem`, `borrow`) accept a
    /// `receiver` argument. If the user sets one of their sub-accounts (not the owner) as the receiver, funds would be
    /// lost because a regular asset doesn't support the EVC's sub-accounts. The private key to a sub-account (not the
    /// owner) is not known, so the user would not be able to move the funds out. The function will make a best effort
    /// to prevent this by checking if the receiver of the token is recognized by EVC as a non-owner sub-account. In
    /// other words, if there is an account registered in EVC as the owner for the intended receiver, the transfer will
    /// be prevented. However, there is no guarantee that EVC will have the owner registered. If the asset itself is
    /// compatible with EVC, it is safe to not set the flag and send the asset to a non-owner sub-account.
    function pushAssets(VaultCache memory vaultCache, address to, Assets amount) internal virtual {
        if (
            to == address(0)
                || (vaultCache.configFlags.isNotSet(CFG_EVC_COMPATIBLE_ASSET) && isKnownNonOwnerAccount(to))
        ) {
            revert E_BadAssetReceiver();
        }

        vaultStorage.cash = vaultCache.cash = vaultCache.cash - amount;
        vaultCache.asset.safeTransfer(to, amount.toUint());
    }
}
