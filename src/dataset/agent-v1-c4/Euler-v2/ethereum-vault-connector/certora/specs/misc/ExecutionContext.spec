methods {
    function areChecksDeferred(ExecutionContextHarness.EC context) external returns (bool) envfree;
    function getOnBehalfOfAccount(ExecutionContextHarness.EC context) external returns (address) envfree;
    function setOnBehalfOfAccount(ExecutionContextHarness.EC context, address account) external returns (ExecutionContextHarness.EC) envfree;
    function areChecksInProgress(ExecutionContextHarness.EC context) external returns (bool) envfree;
    function setChecksInProgress(ExecutionContextHarness.EC context) external returns (ExecutionContextHarness.EC) envfree;
    function isOperatorAuthenticated(ExecutionContextHarness.EC context) external returns (bool) envfree;
    function setOperatorAuthenticated(ExecutionContextHarness.EC context) external returns (ExecutionContextHarness.EC) envfree;
    function clearOperatorAuthenticated(ExecutionContextHarness.EC context) external returns (ExecutionContextHarness.EC) envfree;
    function isSimulationInProgress(ExecutionContextHarness.EC context) external returns (bool) envfree;
    function setSimulationInProgress(ExecutionContextHarness.EC context) external returns (ExecutionContextHarness.EC) envfree;
}

/// check basic functionality of getOnBehalfOfAccount and setOnBehalfOfAccount
rule check_on_behalf_of_account(uint ec, address adr) {
    address before = getOnBehalfOfAccount(ec);
    uint newec = setOnBehalfOfAccount(ec, adr);
    assert(getOnBehalfOfAccount(newec) == adr);
    uint resetec = setOnBehalfOfAccount(ec, before);
    assert(resetec == ec);
}
