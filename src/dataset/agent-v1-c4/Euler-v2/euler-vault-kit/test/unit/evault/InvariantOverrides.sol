// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVault} from "../../../src/EVault/EVault.sol";
import "../../../src/EVault/modules/BalanceForwarder.sol";
import "../../../src/EVault/modules/Borrowing.sol";
import "../../../src/EVault/modules/Governance.sol";
import "../../../src/EVault/modules/Initialize.sol";
import "../../../src/EVault/modules/Liquidation.sol";
import "../../../src/EVault/modules/RiskManager.sol";
import "../../../src/EVault/modules/Token.sol";
import "../../../src/EVault/modules/Vault.sol";
import "forge-std/console.sol";

// Abstract contract to override functions and check invariants.
abstract contract FunctionOverrides is BalanceUtils, BorrowUtils {
    bool public initOperationFlag;

    error EVault_Panic();

    function checkInvariants(address checkedAccount, address controllerEnabled) internal view {
        if (!initOperationFlag) {
            console.log("EVault Panic on InitOperation");
            revert EVault_Panic();
        }

        if (!evc.isVaultStatusCheckDeferred(address(this))) {
            console.log("EVault Panic on VaultStatusCheckDeferred");
            revert EVault_Panic();
        }

        if (checkedAccount != address(0) && !evc.isAccountStatusCheckDeferred(checkedAccount)) {
            console.log("EVault Panic on AccountStatusCheckDeferred");
            revert EVault_Panic();
        }

        if (controllerEnabled != address(0) && !evc.isControllerEnabled(controllerEnabled, address(this))) {
            console.log("EVault Panic on ControllerEnabled");
            revert EVault_Panic();
        }
    }

    function initOperation(uint32 operation, address accountToCheck)
        internal
        virtual
        override
        returns (VaultCache memory vaultCache, address account)
    {
        (vaultCache, account) = super.initOperation(operation, accountToCheck);
        initOperationFlag = true;
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

// Modules and EVault overrides.
contract BalanceForwarderOverride is BalanceForwarder, FunctionOverrides {
    constructor(Integrations memory integrations) BalanceForwarder(integrations) {}

    function initOperation(uint32 operation, address accountToCheck)
        internal
        override (Base, FunctionOverrides)
        returns (VaultCache memory vaultCache, address account)
    {
        return FunctionOverrides.initOperation(operation, accountToCheck);
    }
}

contract BorrowingOverride is Borrowing, FunctionOverrides {
    constructor(Integrations memory integrations) Borrowing(integrations) {}

    function initOperation(uint32 operation, address accountToCheck)
        internal
        override (Base, FunctionOverrides)
        returns (VaultCache memory vaultCache, address account)
    {
        return FunctionOverrides.initOperation(operation, accountToCheck);
    }

    function increaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        Shares amount,
        Assets assets
    ) internal override (BalanceUtils, FunctionOverrides) {
        FunctionOverrides.increaseBalance(vaultCache, account, sender, amount, assets);
    }

    function decreaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        address receiver,
        Shares amount,
        Assets assets
    ) internal override (BalanceUtils, FunctionOverrides) {
        FunctionOverrides.decreaseBalance(vaultCache, account, sender, receiver, amount, assets);
    }

    function transferBalance(address from, address to, Shares amount)
        internal
        override (BalanceUtils, FunctionOverrides)
    {
        FunctionOverrides.transferBalance(from, to, amount);
    }

    function increaseBorrow(VaultCache memory vaultCache, address account, Assets assets)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.increaseBorrow(vaultCache, account, assets);
    }

    function decreaseBorrow(VaultCache memory vaultCache, address account, Assets amount)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.decreaseBorrow(vaultCache, account, amount);
    }

    function transferBorrow(VaultCache memory vaultCache, address from, address to, Assets assets)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.transferBorrow(vaultCache, from, to, assets);
    }
}

contract GovernanceOverride is Governance, FunctionOverrides {
    constructor(Integrations memory integrations) Governance(integrations) {}

    function resetInitOperationFlag() public governorOnly {
        initOperationFlag = false;
    }

    function initOperation(uint32 operation, address accountToCheck)
        internal
        override (Base, FunctionOverrides)
        returns (VaultCache memory vaultCache, address account)
    {
        return FunctionOverrides.initOperation(operation, accountToCheck);
    }

    function increaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        Shares amount,
        Assets assets
    ) internal override (BalanceUtils, FunctionOverrides) {
        FunctionOverrides.increaseBalance(vaultCache, account, sender, amount, assets);
    }

    function decreaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        address receiver,
        Shares amount,
        Assets assets
    ) internal override (BalanceUtils, FunctionOverrides) {
        FunctionOverrides.decreaseBalance(vaultCache, account, sender, receiver, amount, assets);
    }

    function transferBalance(address from, address to, Shares amount)
        internal
        override (BalanceUtils, FunctionOverrides)
    {
        FunctionOverrides.transferBalance(from, to, amount);
    }

    function increaseBorrow(VaultCache memory vaultCache, address account, Assets assets)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.increaseBorrow(vaultCache, account, assets);
    }

    function decreaseBorrow(VaultCache memory vaultCache, address account, Assets amount)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.decreaseBorrow(vaultCache, account, amount);
    }

    function transferBorrow(VaultCache memory vaultCache, address from, address to, Assets assets)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.transferBorrow(vaultCache, from, to, assets);
    }
}

contract InitializeOverride is Initialize, FunctionOverrides {
    constructor(Integrations memory integrations) Initialize(integrations) {}

    function initOperation(uint32 operation, address accountToCheck)
        internal
        override (Base, FunctionOverrides)
        returns (VaultCache memory vaultCache, address account)
    {
        return FunctionOverrides.initOperation(operation, accountToCheck);
    }

    function increaseBorrow(VaultCache memory vaultCache, address account, Assets assets)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.increaseBorrow(vaultCache, account, assets);
    }

    function decreaseBorrow(VaultCache memory vaultCache, address account, Assets amount)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.decreaseBorrow(vaultCache, account, amount);
    }

    function transferBorrow(VaultCache memory vaultCache, address from, address to, Assets assets)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.transferBorrow(vaultCache, from, to, assets);
    }
}

contract LiquidationOverride is Liquidation, FunctionOverrides {
    constructor(Integrations memory integrations) Liquidation(integrations) {}

    function initOperation(uint32 operation, address accountToCheck)
        internal
        override (Base, FunctionOverrides)
        returns (VaultCache memory vaultCache, address account)
    {
        return FunctionOverrides.initOperation(operation, accountToCheck);
    }

    function increaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        Shares amount,
        Assets assets
    ) internal override (BalanceUtils, FunctionOverrides) {
        FunctionOverrides.increaseBalance(vaultCache, account, sender, amount, assets);
    }

    function decreaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        address receiver,
        Shares amount,
        Assets assets
    ) internal override (BalanceUtils, FunctionOverrides) {
        FunctionOverrides.decreaseBalance(vaultCache, account, sender, receiver, amount, assets);
    }

    function transferBalance(address from, address to, Shares amount)
        internal
        override (BalanceUtils, FunctionOverrides)
    {
        FunctionOverrides.transferBalance(from, to, amount);
    }

    function increaseBorrow(VaultCache memory vaultCache, address account, Assets assets)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.increaseBorrow(vaultCache, account, assets);
    }

    function decreaseBorrow(VaultCache memory vaultCache, address account, Assets amount)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.decreaseBorrow(vaultCache, account, amount);
    }

    function transferBorrow(VaultCache memory vaultCache, address from, address to, Assets assets)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.transferBorrow(vaultCache, from, to, assets);
    }
}

contract RiskManagerOverride is RiskManager, FunctionOverrides {
    constructor(Integrations memory integrations) RiskManager(integrations) {}

    function initOperation(uint32 operation, address accountToCheck)
        internal
        override (Base, FunctionOverrides)
        returns (VaultCache memory vaultCache, address account)
    {
        return FunctionOverrides.initOperation(operation, accountToCheck);
    }

    function increaseBorrow(VaultCache memory vaultCache, address account, Assets assets)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.increaseBorrow(vaultCache, account, assets);
    }

    function decreaseBorrow(VaultCache memory vaultCache, address account, Assets amount)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.decreaseBorrow(vaultCache, account, amount);
    }

    function transferBorrow(VaultCache memory vaultCache, address from, address to, Assets assets)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.transferBorrow(vaultCache, from, to, assets);
    }
}

contract TokenOverride is Token, FunctionOverrides {
    constructor(Integrations memory integrations) Token(integrations) {}

    function initOperation(uint32 operation, address accountToCheck)
        internal
        override (Base, FunctionOverrides)
        returns (VaultCache memory vaultCache, address account)
    {
        return FunctionOverrides.initOperation(operation, accountToCheck);
    }

    function increaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        Shares amount,
        Assets assets
    ) internal override (BalanceUtils, FunctionOverrides) {
        FunctionOverrides.increaseBalance(vaultCache, account, sender, amount, assets);
    }

    function decreaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        address receiver,
        Shares amount,
        Assets assets
    ) internal override (BalanceUtils, FunctionOverrides) {
        FunctionOverrides.decreaseBalance(vaultCache, account, sender, receiver, amount, assets);
    }

    function transferBalance(address from, address to, Shares amount)
        internal
        override (BalanceUtils, FunctionOverrides)
    {
        FunctionOverrides.transferBalance(from, to, amount);
    }
}

contract VaultOverride is Vault, FunctionOverrides {
    constructor(Integrations memory integrations) Vault(integrations) {}

    function initOperation(uint32 operation, address accountToCheck)
        internal
        override (Base, FunctionOverrides)
        returns (VaultCache memory vaultCache, address account)
    {
        return FunctionOverrides.initOperation(operation, accountToCheck);
    }

    function increaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        Shares amount,
        Assets assets
    ) internal override (BalanceUtils, FunctionOverrides) {
        FunctionOverrides.increaseBalance(vaultCache, account, sender, amount, assets);
    }

    function decreaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        address receiver,
        Shares amount,
        Assets assets
    ) internal override (BalanceUtils, FunctionOverrides) {
        FunctionOverrides.decreaseBalance(vaultCache, account, sender, receiver, amount, assets);
    }

    function transferBalance(address from, address to, Shares amount)
        internal
        override (BalanceUtils, FunctionOverrides)
    {
        FunctionOverrides.transferBalance(from, to, amount);
    }
}

contract EVaultOverride is EVault, FunctionOverrides {
    constructor(Integrations memory integrations, DeployedModules memory modules) EVault(integrations, modules) {}

    function initOperation(uint32 operation, address accountToCheck)
        internal
        override (Base, FunctionOverrides)
        returns (VaultCache memory vaultCache, address account)
    {
        return FunctionOverrides.initOperation(operation, accountToCheck);
    }

    function increaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        Shares amount,
        Assets assets
    ) internal override (BalanceUtils, FunctionOverrides) {
        FunctionOverrides.increaseBalance(vaultCache, account, sender, amount, assets);
    }

    function decreaseBalance(
        VaultCache memory vaultCache,
        address account,
        address sender,
        address receiver,
        Shares amount,
        Assets assets
    ) internal override (BalanceUtils, FunctionOverrides) {
        FunctionOverrides.decreaseBalance(vaultCache, account, sender, receiver, amount, assets);
    }

    function transferBalance(address from, address to, Shares amount)
        internal
        override (BalanceUtils, FunctionOverrides)
    {
        FunctionOverrides.transferBalance(from, to, amount);
    }

    function increaseBorrow(VaultCache memory vaultCache, address account, Assets assets)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.increaseBorrow(vaultCache, account, assets);
    }

    function decreaseBorrow(VaultCache memory vaultCache, address account, Assets amount)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.decreaseBorrow(vaultCache, account, amount);
    }

    function transferBorrow(VaultCache memory vaultCache, address from, address to, Assets assets)
        internal
        override (BorrowUtils, FunctionOverrides)
    {
        FunctionOverrides.transferBorrow(vaultCache, from, to, assets);
    }
}
