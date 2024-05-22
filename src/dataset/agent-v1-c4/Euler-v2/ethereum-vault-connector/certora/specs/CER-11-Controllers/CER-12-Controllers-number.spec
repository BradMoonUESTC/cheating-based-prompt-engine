/**
CER-12:
Each Account can have at most one Controller Vault enabled at a time unless it's a transient state during a Checks-deferrable Call. This is how single-liability-per-account is enforced.
**/

import "../utils/IsMustRevertFunction.spec";

methods {
    function numOfController(address account) external returns(uint8) envfree;
    function getExecutionContextAreChecksDeferred() external returns(bool) envfree;
    function containsStatusCheckFor(address account) external returns(bool) envfree;
}

/**
 * Check that we never have more than one controller.
 *
 * It does not work for batch() or call(), as it requires rather complex reasoning. Some pieces necessary for this reasoning:
 * - the account status checks verifies that there is only a single controller.
 * - the only place that adds a controller issues an account status check for
 *   the respective account, either immediately or by registering it to the set.
 * - whenever the setDeferredChecks bit in `executionContext` is cleared,
 *   we make sure that we run the account status checks for
 *   all accounts registered for a status check.
 * 
 * We prove this separately for enableController as we need to break it into
 * cases (when checks are deferred vs not). This is done in the 3 rules that
 * follow this one.
 */
rule onlyOneController(method f) filtered { f->
    !isMustRevertFunction(f)
    && f.selector != sig:batch(IEVC.BatchItem[] calldata).selector
    && f.selector != sig:call(address, address, uint256, bytes calldata).selector
    && f.selector != sig:enableController(address, address).selector
} {
    env e;
    calldataarg args;
    address a;
    require numOfController(a) <= 1;
    f(e, args);
    assert numOfController(a) <= 1;
}

// For enableController, we can only check this rule directly if 
// account status checks are not deferred. To cover the deferred case,
// we check that when account checks are deferred, the enableController
// call will enqueue a check for the relevant account using the rule
// `enableControllerEnqueuesStatusCheckWhenDeferred`
rule onlyOneControllerEnableController {
    env e;
    address account;
    address vault;
    require !getExecutionContextAreChecksDeferred();
    require numOfController(account) <= 1;
    enableController(e, account, vault);
    assert numOfController(account) <= 1;
}

// This ensures enableController will enqueue a status
// check when status checks are deferred
rule enableControllerEnequeusStatusCheckWhenDeferred {
    env e;
    address account;
    address vault;
    require getExecutionContextAreChecksDeferred();
    enableController(e, account, vault);
    assert containsStatusCheckFor(account) == true;
}

// This directly specifies that checkAccountStatusInternal
// will force numOfController for the checked account to be
// less or equal to one to cover deferred checks.
rule checkAccountStatusForcesNumControllersLEOne {
    env e;
    address account;
    bool status = checkAccountStatus(e, account);
    assert numOfController(account) > 1 => !status;
}