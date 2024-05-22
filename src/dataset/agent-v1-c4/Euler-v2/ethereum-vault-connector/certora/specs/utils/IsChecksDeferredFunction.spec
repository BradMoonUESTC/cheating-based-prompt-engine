/**
 * This is all the checksDeferred functions (call, controlCollateral, batch)
 * aside from batchRevert which always reverts
 */
definition isChecksDeferredFunction(method f) returns bool =
    f.selector == sig:EthereumVaultConnectorHarness.call(
        address,address,uint256,bytes).selector ||
    f.selector == sig:EthereumVaultConnectorHarness.batch(
        IEVC.BatchItem[]).selector ||
    f.selector == sig:EthereumVaultConnectorHarness.controlCollateral(
        address, address, uint256, bytes).selector;
    