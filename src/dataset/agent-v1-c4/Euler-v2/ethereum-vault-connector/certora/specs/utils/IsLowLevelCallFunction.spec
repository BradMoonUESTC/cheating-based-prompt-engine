/**
 * This is all the functions with low-level call operations
 * that do not always revert (e.g. batchRevert is omitted)
 */
definition isLowLevelCallFunction(method f) returns bool =
    f.selector == sig:EthereumVaultConnectorHarness.permit(
        address,address,uint256,uint256,uint256,uint256,bytes,bytes).selector ||
    f.selector == sig:EthereumVaultConnectorHarness.call(
        address,address,uint256,bytes).selector ||
    f.selector == sig:EthereumVaultConnectorHarness.batch(
        IEVC.BatchItem[]).selector ||
    f.selector == sig:EthereumVaultConnectorHarness.controlCollateral(
        address, address, uint256, bytes).selector;
    