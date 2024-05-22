// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

// Contracts
import {BalanceUtils} from "../../../../src/EVault/shared/BalanceUtils.sol";
import {BorrowUtils} from "../../../../src/EVault/shared/BorrowUtils.sol";
import "../../../../src/EVault/shared/types/Types.sol";

// Utils
import "../../InvariantsSpec.t.sol";
import "../../utils/StdAsserts.sol";

/// @notice Abstract contract to override functions and check internal invariants.
abstract contract FunctionOverrides is BalanceUtils, BorrowUtils, StdAsserts, InvariantsSpec {
    uint32 internal constant INIT_OPERATION_FLAG = 1 << 31;

    /// @notice Internal invariants for low level operations
    /// @dev Similar to Postconditions but checked internally within the transaction
    function checkInvariants(address checkedAccount, address controllerEnabled) internal {
        assertTrue(Flags.unwrap(vaultStorage.hookedOps) & INIT_OPERATION_FLAG != 0, INTERNAL_INVARIANT_A);
        assertTrue(evc.isVaultStatusCheckDeferred(address(this)), INTERNAL_INVARIANT_B);
        assertTrue(
            checkedAccount == address(0) || evc.isAccountStatusCheckDeferred(checkedAccount), INTERNAL_INVARIANT_C
        );
        assertTrue(
            controllerEnabled == address(0) || evc.isControllerEnabled(controllerEnabled, address(this)),
            INTERNAL_INVARIANT_D
        );
    }

    function initOperation(uint32 operation, address accountToCheck)
        internal
        virtual
        override
        returns (VaultCache memory vaultCache, address account)
    {
        (vaultCache, account) = super.initOperation(operation, accountToCheck);
        vaultStorage.hookedOps = Flags.wrap(Flags.unwrap(vaultStorage.hookedOps) | INIT_OPERATION_FLAG);
    }

    function increaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        Shares amount,
        Assets assets
    ) internal virtual override {
        super.increaseBalance(vaultCache, account, sender, amount, assets);
        checkInvariants(address(0), address(0));
    }

    function decreaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        address receiver,
        Shares amount,
        Assets assets
    ) internal virtual override {
        super.decreaseBalance(vaultCache, account, sender, receiver, amount, assets);
        checkInvariants(account, address(0));
    }

    function transferBalance(address from, address to, Shares amount) internal virtual override {
        super.transferBalance(from, to, amount);
        checkInvariants(from, address(0));
    }

    function increaseBorrow(VaultCache memory vaultCache, address account, Assets assets) internal virtual override {
        super.increaseBorrow(vaultCache, account, assets);
        checkInvariants(account, account);
    }

    function decreaseBorrow(VaultCache memory vaultCache, address account, Assets amount) internal virtual override {
        super.decreaseBorrow(vaultCache, account, amount);
        checkInvariants(address(0), account);
    }

    function transferBorrow(VaultCache memory vaultCache, address from, address to, Assets assets)
        internal
        virtual
        override
    {
        super.transferBorrow(vaultCache, from, to, assets);
        checkInvariants(address(0), from);
        checkInvariants(to, to);
    }
}
