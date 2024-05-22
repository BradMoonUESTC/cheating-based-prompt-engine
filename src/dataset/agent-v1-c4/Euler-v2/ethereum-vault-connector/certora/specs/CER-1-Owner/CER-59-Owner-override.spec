// CER-59: EVC MUST NOT override the already stored Owner for a 
// given addressPrefix
import "../utils/IsMustRevertFunction.spec";

persistent ghost bool overwroteOwner {
    init_state axiom overwroteOwner == false;
}

hook Sstore currentContract.ownerLookup[KEY bytes19 address_prefix].owner address newValue (address oldValue) {
    if (oldValue != 0 && newValue != oldValue) {
        overwroteOwner = true;
    }
}

rule neverOverwriteOwner (method f) filtered {f ->
    !isMustRevertFunction(f) 
}{
    env e;
    calldataarg args;
    require !overwroteOwner;
    f(e, args);
    assert !overwroteOwner;
}