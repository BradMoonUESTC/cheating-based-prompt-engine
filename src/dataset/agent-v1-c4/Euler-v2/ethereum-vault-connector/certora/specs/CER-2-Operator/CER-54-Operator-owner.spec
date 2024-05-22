import "../utils/IsMustRevertFunction.spec";
import "CER-68-Operator-authorization.spec";

methods {
    function getOwnerOf(bytes19) external returns (address) envfree;
    function getOperator(bytes19, address) external returns (uint256) envfree;
    function getAddressPrefix(address) external returns (bytes19) envfree;
    function haveCommonOwner(address account, address otherAccount) external returns (bool) envfree;
}

// CER-54: Account Operator address MUST NOT belong to the Account Owner of the 
// Account for which the Operator being is authorized
rule account_operator_owner() {
    env e;
    address account;
    address operator;

    // call the setAccountOperator method.
    setAccountOperator(e, account, operator, true);
    // Check that since this did not revert, the account and operator
    // must not have the same owner.
    assert !haveCommonOwner(account, operator);
}

rule setOperator_owner() {
    env e;

    bytes19 addressPrefix;
    address operator;
    uint256 operatorBitField;

    // call the setOperator() method.
    setOperator(e, addressPrefix, operator, operatorBitField);
    // For any address "addr" with prefix "addressPrefix"
    address addr;
    require getAddressPrefix(addr) == addressPrefix;
    // Since we did not revert, no such "addr" can have a common owner 
    // with operator
    assert !haveCommonOwner(addr, operator);
}