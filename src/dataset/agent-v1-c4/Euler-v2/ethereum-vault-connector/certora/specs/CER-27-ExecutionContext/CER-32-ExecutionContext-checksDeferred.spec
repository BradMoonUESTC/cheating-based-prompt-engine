// CER-32: Execution Context MUST keep track of whether the Checks are deferred
// with a boolean flag. The flag MUST be set  when a Checks-deferrable Call
// starts and MUST be cleared at the end of it, but only when the flag was not
// set before the call.
import "../utils/IsChecksDeferredFunction.spec";

methods {
    function areChecksDeferred() external returns (bool) envfree;
    function getExecutionContextAreChecksDeferred() external returns (bool) envfree;
}

rule restoreChecksDeferred (method f) filtered { f ->
    isChecksDeferredFunction(f)
}{
    env e;
    calldataarg args;
    bool checksDeferredBefore = getExecutionContextAreChecksDeferred();
    f(e, args);
    bool checksDeferredAfter = getExecutionContextAreChecksDeferred();
    assert checksDeferredAfter == checksDeferredBefore;
}