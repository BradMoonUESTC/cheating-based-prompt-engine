// if msg.sender is the currentContract, it means we are within permit() and
// we need to use executionContext.getOnBehalfOfAccount() instead.
function actualCaller(env e) returns address {
    if(e.msg.sender == currentContract) {
        return getExecutionContextOnBehalfOfAccount(e);
    } else {
        return e.msg.sender;
    }
}