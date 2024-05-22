// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {FunctionOverrides} from "./FunctionOverrides.sol";

import {Base} from "../../../../src/EVault/shared/Base.sol";
import {BalanceUtils} from "../../../../src/EVault/shared/BalanceUtils.sol";
import {BorrowUtils} from "../../../../src/EVault/shared/BorrowUtils.sol";

import {Initialize} from "../../../../src/EVault/modules/Initialize.sol";
import {Token} from "../../../../src/EVault/modules/Token.sol";
import {Vault} from "../../../../src/EVault/modules/Vault.sol";
import {Borrowing} from "../../../../src/EVault/modules/Borrowing.sol";
import {Liquidation} from "../../../../src/EVault/modules/Liquidation.sol";
import {BalanceForwarder} from "../../../../src/EVault/modules/BalanceForwarder.sol";
import {Governance} from "../../../../src/EVault/modules/Governance.sol";
import {RiskManager} from "../../../../src/EVault/modules/RiskManager.sol";

import "../../../../src/EVault/shared/types/Types.sol";

// Modules and EVault overrides.
contract BalanceForwarderExtended is BalanceForwarder, FunctionOverrides {
    constructor(Integrations memory integrations) BalanceForwarder(integrations) {}

    function initOperation(uint32 operation, address accountToCheck)
        internal
        override (Base, FunctionOverrides)
        returns (VaultCache memory vaultCache, address account)
    {
        return FunctionOverrides.initOperation(operation, accountToCheck);
    }
}

contract BorrowingExtended is Borrowing, FunctionOverrides {
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

contract GovernanceExtended is Governance, FunctionOverrides {
    constructor(Integrations memory integrations) Governance(integrations) {}

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

contract InitializeExtended is Initialize, FunctionOverrides {
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

contract LiquidationExtended is Liquidation, FunctionOverrides {
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

contract RiskManagerExtended is RiskManager, FunctionOverrides {
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

contract TokenExtended is Token, FunctionOverrides {
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

contract VaultExtended is Vault, FunctionOverrides {
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
