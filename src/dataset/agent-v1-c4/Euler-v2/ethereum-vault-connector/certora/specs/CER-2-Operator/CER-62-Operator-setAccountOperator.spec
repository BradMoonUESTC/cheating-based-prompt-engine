
/**
 * Calling setAccountOperator does not affect the state for any operator
 * other than the target of the function call.
 */
methods {
    function getOperator(bytes19, address) external returns (uint256) envfree;
    function getAddressPrefix(address) external returns (bytes19) envfree;
}

rule setAccountOperatorSandboxed(address account, address operator, bool authorized) {
    address otherAccount;
    address otherOperator;
    env e;

    bytes19 addressPrefix = getAddressPrefix(otherAccount);
    // either otherAccount is from another prefix, or the operator is different
    require(getAddressPrefix(account) != addressPrefix || operator != otherOperator);

    uint256 operatorBefore = getOperator(addressPrefix, otherOperator);
    setAccountOperator(e, account, operator, authorized);
    uint256 operatorAfter = getOperator(addressPrefix, otherOperator);

    // the bitmask for a different account or different operator was not changed
    assert(operatorBefore == operatorAfter);
}