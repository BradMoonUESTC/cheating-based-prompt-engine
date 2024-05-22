/**
 * Verification of:
 *   Each external call, that the EVC performs, restores the value of the
 *   execution context so that it’s equal to the value just before the external
 *   call was performed.
 **/

import "../utils/IsMustRevertFunction.spec";
import "../utils/CallOpSanity.spec";

methods {
    function getRawExecutionContext() external returns (uint256) envfree;
    function getExecutionContextDefault() external returns (uint256) envfree;
    function areAccountStatusChecksEmpty() external returns (bool) envfree;
    function areVaultStatusChecksEmpty() external returns (bool) envfree;
    function getCurrentOnBehalfOfAccount(address) external returns (address,bool) envfree;
}

/**
 * Verify that any functions restores the execution context to whatever it was
 * beforehand.
 */
rule noFunctionChangesExecutionContext(method f) filtered {f -> !isMustRevertFunction(f)} 
{
    env e;
    calldataarg args;

    uint256 preEC = getRawExecutionContext();
    f(e, args);
    assert(preEC == getRawExecutionContext());
}

/**
 * Verify that after any function call, both account and
 * vault status checks are empty, and the execution context is set back to its
 * default value.
 * We ignore must-revert functions to avoid sanity issues. Additionally, we
 * ignore getCurrentOnBehalfOfAccount() as it always reverts.
 */
invariant topLevelFunctionDontChangeTransientStorage()
    areAccountStatusChecksEmpty() && areVaultStatusChecksEmpty() &&
    getRawExecutionContext() == getExecutionContextDefault()
    filtered { f ->
        !isMustRevertFunction(f) &&
        !f.isFallback &&            // certora plans to deprecate certora tool-generated function from sanity checks
        f.selector != sig:getCurrentOnBehalfOfAccount(address).selector
    }

/**
 * Check that `getCurrentOnBehalfOfAccount` always reverts in case the invariant holds.
 * This justifies the filter applied to the invariant above. 
 */
rule getCurrentOnBehalfOfAccountAlwaysReverts() {
    requireInvariant topLevelFunctionDontChangeTransientStorage();
    env e;
    address controllerToCheck;
    getCurrentOnBehalfOfAccount@withrevert(controllerToCheck);
    assert(lastReverted);
}
