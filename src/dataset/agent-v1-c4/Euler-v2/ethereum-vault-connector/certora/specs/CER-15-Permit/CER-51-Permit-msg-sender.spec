import "../utils/IsMustRevertFunction.spec";

/**
 * Check that we don't leak write access to storage to other code.
 */
import "../utils/CallOpSanity.spec";

methods {
    function getAccountController(address account) external returns (address) envfree;
    function isCollateralEnabled(address account, address vault) external returns (bool) envfree;
    function isAccountController(address account, address controller) external returns (bool) envfree;

}

////////////////////////////////////////////////////////////////
//                                                            //
//           Account Controllers (Ghost and Hooks)            //
//                                                            //
////////////////////////////////////////////////////////////////

/* Any load from `firstElement` or `elements`, for either `accountControllers`
 * or `vaultStatusChecks`, MUST be dominated by a store on the same memory first.
 * Thus, requiring `value != currentContract` is safe as we assert it before.
 * We do this to keep the knowledge about `currentContract` not being in any of
 * these sets across HAVOC'd function calls.
 */
// when writing to accountControllers, check that value != currentContract
hook Sstore EthereumVaultConnectorHarness.accountControllers[KEY address user].firstElement address value {
    assert(value != currentContract);
}
hook Sstore EthereumVaultConnectorHarness.accountControllers[KEY address user].elements[INDEX uint256 i].value address value {
    assert(value != currentContract);
}
// when loading from accountControllers, we know that value != currentContract
hook Sload address value EthereumVaultConnectorHarness.accountControllers[KEY address user].firstElement {
    require(value != currentContract);
}
hook Sload address value EthereumVaultConnectorHarness.accountControllers[KEY address user].elements[INDEX uint256 i].value {
    require(value != currentContract);
}

////////////////////////////////////////////////////////////////
//                                                            //
//           Vault Status Checks (Ghost and Hooks)            //
//                                                            //
////////////////////////////////////////////////////////////////

// when writing to vaultStatusChecks, check that value != currentContract
hook Sstore EthereumVaultConnectorHarness.vaultStatusChecks.firstElement address value {
    assert(value != currentContract);
}
hook Sstore EthereumVaultConnectorHarness.vaultStatusChecks.elements[INDEX uint256 i].value address value {
    assert(value != currentContract);
}
// when loading from vaultStatusChecks, we know that value != currentContract
hook Sload address value EthereumVaultConnectorHarness.vaultStatusChecks.firstElement {
    require(value != currentContract);
}
hook Sload address value EthereumVaultConnectorHarness.vaultStatusChecks.elements[INDEX uint256 i].value {
    require(value != currentContract);
}

////////////////////////////////////////////////////////////////
//                                                            //
//                Ghost and Hook for Property                 //
//  EVC can only be msg.sender during the permit() function   //
//                                                            //
////////////////////////////////////////////////////////////////

/**
 * Core property: we never `call` into ourselves (except for `permit`, which we
 * exclude in the rule below). All other possibilities to be called either have
 * `msg.sender != currentContract` (reentrant `call` or `staticcall` or internal
 * `delegatecall`), or have no write access to our storage (reentrant
 * `delegatecall`).
 */
hook CALL(uint g, address addr, uint value, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc
{
    assert(executingContract != currentContract || addr != currentContract);
}

// This rule checks the property of interest "EVC can only be msg.sender during the self-call in the permit() function. Expected to fail on permit() function.
// To prove this for controlCollateral, we need the additionl assumption
// that the EVC can never become an account controller. (See the rule after this one). We also prove this assumption
// CER-80: https://linear.app/euler-labs/issue/CER-80/collaterals-restrictions

rule onlyEVCCanCallCriticalMethod(method f, env e, calldataarg args)
  filtered {f -> 
    !isMustRevertFunction(f) &&
    f.selector != sig:EthereumVaultConnectorHarness.permit(address,uint256,uint256,uint256,uint256,bytes,bytes).selector &&
    f.selector != sig:EthereumVaultConnectorHarness.controlCollateral(address, address, uint256, bytes).selector
  }{
    //Exclude EVC as being the initiator of the call.
    require(e.msg.sender != currentContract);
    f(e,args);

    assert(true);
}

// For onlyController we need the additional assumption that
// the EVC ("currentContract") can never become a collateral for any address.
// NOTE: We will eventually prove this assumption to satisfy
// CER-80: https://linear.app/euler-labs/issue/CER-80/collaterals-restrictions
rule onlyEVCCanCallCriticalMethodOnlyController {
    env e;
    address targetCollateral;
    address onBehalfOfAccount;
    uint256 value;
    bytes data;

    require(e.msg.sender != currentContract);
    require !isCollateralEnabled(onBehalfOfAccount, currentContract);
    controlCollateral(e, targetCollateral, onBehalfOfAccount, value, data);

    assert(true);
}
