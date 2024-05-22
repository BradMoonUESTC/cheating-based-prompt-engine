// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import {ExecutionContext, EC} from "./ExecutionContext.sol";
import {Set, SetStorage} from "./Set.sol";

/// @title TransientStorage
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This contract provides transient storage for the Ethereum Vault Connector.
/// @dev All the variables in this contract are considered transient meaning that their state does not change between
/// transactions.
abstract contract TransientStorage {
    using ExecutionContext for EC;
    using Set for SetStorage;

    enum SetType {
        Account,
        Vault
    }

    EC internal executionContext;
    SetStorage internal accountStatusChecks;
    SetStorage internal vaultStatusChecks;

    constructor() {
        // set the execution context to non-zero value to always keep the storage slot in non-zero state.
        // it allows for cheaper SSTOREs when the execution context is in its default state
        executionContext = EC.wrap(1 << ExecutionContext.STAMP_OFFSET);

        // there are two types of data that are stored using SetStorage type:
        // - the data that is transient in nature (accountStatusChecks and vaultStatusChecks)
        // - the data that is permanent (accountControllers and accountCollaterals from the EthereumVaultConnector
        // contract)

        // for the permanent data, there's no need to care that much about optimizations. each account has its two sets.
        // usually, an address inserted to either of them won't be removed within the same transaction. the only
        // optimization applied (directly in the Set contract) is that on the first element insertion, the stamp is set
        // to non-zero value to always keep that storage slot in non-zero state. it allows for cheaper SSTORE when an
        // element is inserted again after clearing the set.

        // for the transient data, an address insertion should be as cheap as possible. hence on construction, we store
        // dummy values for all the storage slots where the elements will be stored later on. it is important
        // considering that both accountStatusChecks and vaultStatusChecks are always cleared at the end of the
        // transaction. with dummy values set, the transition from zero to non-zero and back to zero will be
        // significantly cheaper than it would be otherwise
        accountStatusChecks.initialize();
        vaultStatusChecks.initialize();
    }
}
