// While in the context of a permit, it is not possible to spoof the
// onBehalfOfAddress by making a callback that supplies a different argument for
// onBehalfOfAddress. The permit will only use the onBehalfOfAddress value
// stored in the context.

// Show that if we are within the context of a permit
// with onBehalfOfAccount == victim in the execution context,
// and an adversary attempts to execute a call with a different
// onbehalf of address, the call will revert
rule cannot_spoof_onBehalfOfAccount_call() {
    env e;
    address victim; // the real onBehalfOfAccount
    address adversary; // a spoofed, nonzero onBehalfOfAccount
    require victim != adversary;
    require adversary != 0;

    // Setup the context of a permit with onBehalfOfAccount == victim
    require e.msg.sender == currentContract;
    require getExecutionContextOnBehalfOfAccount(e) == victim;

    // Attempt a call with a different nonzero onBehalfOfAccount
    uint256 value;
    bytes data;
    call@withrevert(e, currentContract, adversary, value, data);
    assert lastReverted;
}

rule cannot_spoof_onBehalfOfAccount_batch() {
    env e;
    address victim; // the real onBehalfOfAccount
    address adversary; // a spoofed, nonzero onBehalfOfAccount
    require victim != adversary;
    require adversary != 0;

    // Setup the context of a permit with onBehalfOfAccount == victim
    require e.msg.sender == currentContract;
    require getExecutionContextOnBehalfOfAccount(e) == victim;

    // Execute a batch() where one of the arguments is a
    // BatchItem with a spoofed onBehalfOfAccount
    IEVC.BatchItem[] items;
    uint256 i;
    require 0 <= i;
    require i < items.length;
    require items[i].onBehalfOfAccount == adversary;
    require items[i].targetContract == currentContract;
    batch@withrevert(e, items);
    assert lastReverted;

}