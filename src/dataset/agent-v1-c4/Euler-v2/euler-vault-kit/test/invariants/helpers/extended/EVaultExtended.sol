// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// Function Overrides
import {FunctionOverrides} from "./FunctionOverrides.sol";

// Contracts
import {Base} from "../../../../src/EVault/shared/Base.sol";
import {BalanceUtils} from "../../../../src/EVault/shared/BalanceUtils.sol";
import {BorrowUtils} from "../../../../src/EVault/shared/BorrowUtils.sol";
import {EVault} from "../../../../src/EVault/EVault.sol";

// Types
import "../../../../src/EVault/shared/types/Types.sol";

contract EVaultExtended is EVault {
    constructor(Integrations memory integrations, DeployedModules memory modules) EVault(integrations, modules) {}

    function getReentrancyLock() external view returns (bool) {
        return vaultStorage.reentrancyLocked;
    }

    function getSnapshot() external view returns (Snapshot memory) {
        return snapshot;
    }

    function getLastInterestAccumulatorUpdate() external view returns (uint256) {
        return vaultStorage.lastInterestAccumulatorUpdate;
    }

    function getUserInterestAccumulator(address user) external view returns (uint256) {
        return vaultStorage.users[user].interestAccumulator;
    }

    function isFlagSet(uint32 bitMask) external view returns (bool) {
        return vaultStorage.configFlags.isSet(bitMask);
    }
    /* 
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
    }*/
}
