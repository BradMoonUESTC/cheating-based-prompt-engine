import "../utils/IsMustRevertFunction.spec";

//Tests for a set of functions that have at least one input for which the function MUST not revert.
rule nonRevertFunctions(method f) filtered {f -> !isMustRevertFunction(f)} {
    env e; calldataarg args;

    f(e,args);
    satisfy true, "The function always reverts.";
}

//Tests for the set of functions that MUST revert for all inputs.
rule mustRevertFunctions(method f) filtered {f -> isMustRevertFunction(f)} {
    env e; calldataarg args;

    f@withrevert(e,args);
    assert lastReverted == true, "The function didn't revert for all input.";
}
