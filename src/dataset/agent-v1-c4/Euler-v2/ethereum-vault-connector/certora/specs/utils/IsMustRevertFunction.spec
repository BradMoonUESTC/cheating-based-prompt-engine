/**
 * This utility function identifies methods that are expected to always revert.
 * These functions are `batchSimulation` and `batchRevert`.
 * They usually need to be excluded from explicit sanity rules, as well as
 * generic rules or invariants if automatic sanity checks are enabled.
 */
definition isMustRevertFunction(method f) returns bool =
    f.selector == sig:EthereumVaultConnectorHarness.batchRevert(IEVC.BatchItem[]).selector;
