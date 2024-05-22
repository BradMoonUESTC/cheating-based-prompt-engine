import "../utils/IsMustRevertFunction.spec";
import "../utils/ActualCaller.spec";

methods {
    function getOwnerOf(bytes19) external returns (address) envfree;
    function getOperator(bytes19, address) external returns (uint256) envfree;
    function getAddressPrefix(address) external returns (bytes19) envfree;
    function haveCommonOwner(address account, address otherAccount) external returns (bool) envfree;
}

/**
 * Check that `setOperator(addressPrefix, ...)` can only be called if msg.sender
 * is the owner of the address prefix. Technically, we check that
 * - msg.sender is from the prefix itself and thus a plausible owner
 * - msg.sender is stored as the owner after the function call
 * - the owner before the call was either 0 (not set) or msg.sender already
 * - the bitset is set as it should be.
 */
rule onlyOwnerCanCallSetOperator() {
    env e;

    bytes19 addressPrefix;
    address operator;
    uint256 operatorBitField;

    address ownerBefore = getOwnerOf(addressPrefix);

    address caller = actualCaller(e);

    // call the setOperator() method.
    setOperator(e, addressPrefix, operator, operatorBitField);

    // sender is from the prefix itself and thus plausible to be the owner
    assert(getAddressPrefix(caller) == addressPrefix);
    // the owner before the call was either not set or actualCaller already
    assert(ownerBefore == 0 || ownerBefore == caller);
    // sender is stored as the owner of the address prefix
    assert(caller == getOwnerOf(addressPrefix));
    // make sure the right bitfield was set
    assert(getOperator(addressPrefix, operator) == operatorBitField);
}


// a copy of the internal ownerLookup
persistent ghost mapping(bytes19 => address) ownerLookupGhost {
    init_state axiom forall bytes19 prefix. ownerLookupGhost[prefix] == 0;
}
// makes sure the ownerLookupGhost is updated properly
hook Sstore EthereumVaultConnectorHarness.ownerLookup[KEY bytes19 prefix].owner address value {
    ownerLookupGhost[prefix] = value;
}
// makes sure that reads from ownerLookup after havocs are correct
hook Sload address value EthereumVaultConnectorHarness.ownerLookup[KEY bytes19 prefix].owner {
    require(ownerLookupGhost[prefix] == value);
}

// check that an owner of a prefix is always from that prefix
invariant OwnerIsFromPrefix(bytes19 prefix)
    // Assume: In the inductive step, for the precondition,
    // we are assuming that the low-level `CALL`s that are
    // reachable in batch/call will not affect the state of ownerLookup
    ownerLookupGhost[prefix] == 0 || getAddressPrefix(ownerLookupGhost[prefix]) == prefix
    filtered { 
        f -> !isMustRevertFunction(f)
    }

/**
  * Checks a liveness property that the owner of an account
  * can succesfully set an operator (under a few assumptions
  * that are spelled out with the "require" statements).
 */
rule theOwnerCanCallSetOperator() {
    env e;

    bytes19 addressPrefix;
    address operator;
    uint256 operatorBitField;

    address owner = getOwnerOf(addressPrefix);
    requireInvariant OwnerIsFromPrefix(addressPrefix);

    // the actual caller (either msg.sender or the onBehalfOfAccount)
    address caller = actualCaller(e);

    // This is a permit self-call:
    if (e.msg.sender == currentContract) {
        // the owner is already set, not zero and not EVC
        require(owner == caller && owner != 0 && owner != currentContract);
        // the owner has the proper prefix
        require(getAddressPrefix(owner) == addressPrefix);
    // This is the normal case where the caller is msg.sender:
    } else {
        // just a regular call from msg.sender
        // msg.sender is from the proper prefix
        require(getAddressPrefix(e.msg.sender) == addressPrefix);
        // the owner is not set yet (zero) or identical to msg.sender
        require(owner == 0 || owner == e.msg.sender);
    }

    // The function will revert if any of these assumptions do not hold:
    require(e.msg.value < nativeBalances[e.msg.sender]);
    require !(operator == currentContract);
    require !(haveCommonOwner(caller, operator));

    // the operator can not be from the prefix either
    require(getAddressPrefix(operator) != getAddressPrefix(caller));

    // the current bitfield must be different from what we try to set
    require(getOperator(addressPrefix, operator) != operatorBitField);

    // call the setOperator() method.
    setOperator@withrevert(e, addressPrefix, operator, operatorBitField);
    // check that it does not revert under these assumptions
    assert(!lastReverted);
}

// Only the owner of an account can set the operator of that account
// if it is called with authenticated=true
rule onlyOwnerOrOperatorCanCallSetAccountOperator() {
    env e;
    address account;
    address operator;

    address caller = actualCaller(e);

    // call the setAccountOperator method.
    setAccountOperator(e, account, operator, true);

    address owner = haveCommonOwner(account, caller) ? caller : getAccountOwner(e, account);

    // Since setAccountOperator did not revert, the actualCaller
    // must either be the owner
    assert(caller == owner);

}