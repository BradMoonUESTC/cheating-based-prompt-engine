import "../utils/IsMustRevertFunction.spec";
import "CER-68-Operator-authorization.spec";

methods {
    function getOwnerOf(bytes19) external returns (address) envfree;
    function getOperator(bytes19, address) external returns (uint256) envfree;
    function getAddressPrefix(address) external returns (bytes19) envfree;
    function haveCommonOwner(address account, address otherAccount) external returns (bool) envfree;
}

// CER-52 Account Operator that is authorized to operate on behalf the Account MUST only be allowed to be deauthorized by:
// - the Account Owner, or
// - the Account Operator itself (one Account Operator MUST NOT be able to deauthorize the other Account Operator)
rule operatorDeauthorization (method f) filtered { f -> 
    !isMustRevertFunction(f) && 
    f.selector != sig:batch(IEVC.BatchItem[] calldata).selector && 
    f.selector != sig:call(address, address, uint256, bytes calldata).selector
}{
    env e;
    calldataarg args;
    address operator;
    bytes19 addressPrefix;
    address caller = actualCaller(e);
    address account;
    require addressPrefix == getAddressPrefix(account);
    address owner = haveCommonOwner(account, caller) ? caller : getAccountOwner(e, account);
    uint256 operatorBefore = getOperator(addressPrefix, operator);
    f(e,args);
    uint256 operatorAfter = getOperator(addressPrefix, operator);
    assert (operatorBefore != operatorAfter) => 
        (caller == operator || caller == owner);
}


rule operatorDeauthorizationSetOperator {
    env e;

    bytes19 addressPrefix;
    address operator;
    uint256 operatorBitField;

    address caller = actualCaller(e);

    // call the setOperator() method giving 0 as the bit field to deauthorize
    setOperator(e, addressPrefix, operator, 0);
    // since the function did not revert the caller must be the owner
    assert caller != operator;
    assert caller == getOwnerOf(addressPrefix);
    assert getOperator(e, addressPrefix, operator) == 0;
}

rule operatorDeauthorizationSetAccountOperator() {
    env e;
    address account;
    address operator;

    address caller = actualCaller(e);
    address owner = haveCommonOwner(account, caller) ? caller : getAccountOwner(e, account);

    // call the setAccountOperator method giving false 
    // as last parameter to deauthorize
    setAccountOperator(e, account, operator, false);


    // Since setAccountOperator did not revert, the actualCaller
    // must either be the owner or operator being deauthorized
    assert caller == owner || caller == operator;

}
