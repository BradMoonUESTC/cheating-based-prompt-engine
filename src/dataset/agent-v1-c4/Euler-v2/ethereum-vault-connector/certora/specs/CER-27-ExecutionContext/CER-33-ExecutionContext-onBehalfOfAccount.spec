// CER-33: Execution Context MUST keep track of the Account on behalf of which
// the current low-level external call is being performed.
import "../utils/IsLowLevelCallFunction.spec";

methods {
    function getExecutionContextOnBehalfOfAccount() external returns (address) envfree;
    // There is another callback in checkAccountStatusInternal with
    // an external vault contract as the target. We want to exclude
    // this low-level CALL from these rules, and this is the point
    // of the following summary, which excludes the CALL but models
    // an arbitrary implementation of this function. Similar for
    // checkVaultStatusInternal
    // CER-76 checks properties of EVC's handling of checkAccountStatus
    function EthereumVaultConnector.requireAccountStatusCheckInternal(address account) internal => NONDET;
    // CER-77 checks properties of EVC's handling of checkVaultStatus
    function EthereumVaultConnector.requireVaultStatusCheckInternal(address vault) internal => NONDET;
    function EthereumVaultConnector.checkStatusAll(TransientStorage.SetType setType) internal => NONDET;
}

persistent ghost bool onBehalfOfCorrect;
persistent ghost address savedOnBehalfOfAccount;

hook CALL(uint g, address addr, uint value, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc
{
    if(addr != currentContract) {
        onBehalfOfCorrect = onBehalfOfCorrect &&
            (savedOnBehalfOfAccount == getExecutionContextOnBehalfOfAccount());
    }
}

hook DELEGATECALL(uint g, address addr, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc
{
    if(addr != currentContract) {
        onBehalfOfCorrect = onBehalfOfCorrect &&
            (savedOnBehalfOfAccount == getExecutionContextOnBehalfOfAccount());
    }
}

// Note: these rules are not parametric because we need
// to initialize savedOnBehalfOfAccount to that parameter
rule execution_context_tracks_account_for_call {
    env e;
    address targetContract;
    address onBehalfOfAccount;
    uint256 value;
    bytes data;
    // We prove this is true aside from in the context of permit
    // with CER-51
    require e.msg.sender != currentContract;
    // initialize ghosts
    require savedOnBehalfOfAccount == onBehalfOfAccount;
    require onBehalfOfCorrect;
    call(e, targetContract, onBehalfOfAccount, value, data);
    assert onBehalfOfCorrect;
}

rule execution_context_tracks_account_for_batch{
    env e;
    IEVC.BatchItem[] items;
    // We prove this is true aside from in the context of permit
    // with CER-51
    require e.msg.sender != currentContract;
    // initialize ghosts
    require items.length == 1;
    require savedOnBehalfOfAccount == items[0].onBehalfOfAccount;
    require onBehalfOfCorrect;
    batch(e, items);
    assert onBehalfOfCorrect;
}

rule execution_context_tracks_account_for_controlCollateral {
    env e;
    address targetCollateral;
    address onBehalfOfAccount;
    uint256 value;
    bytes data;
    // We prove this is true aside from in the context of permit
    // with CER-51
    require e.msg.sender != currentContract;
    // initialize ghosts
    require savedOnBehalfOfAccount == onBehalfOfAccount;
    require onBehalfOfCorrect;
    controlCollateral(e, targetCollateral, onBehalfOfAccount, value, data);
    assert onBehalfOfCorrect;
}