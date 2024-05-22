
/*
Verification of Set.sol 
*/

methods {
    function insert(address element) external returns (bool) envfree;
    function remove(address element) external returns (bool) envfree;
    function get(uint8 index) external returns (address) envfree;
    function contains(address element) external returns (bool) envfree;
    function length() external returns (uint8) envfree;
}



// GHOST COPIES:
// For every storage variable we add a ghost field that is kept synchronized by hooks.
// The ghost fields can be accessed by the spec, even inside quantifiers.

/** @title ghost field for the values array - mapping the value to the element number 
 firstElement - is elemnt #1 
 setStorage.elements[1] - is element #2  ghostValues[2]
 ghostLength is the number of elements as stored also in setStorage.numElements
 last element #numElements is stored in currentContract.setStorage.elements[numElements-1] and in ghostValues[ghostLength]
*/
ghost mapping(mathint => address) ghostValues {
    init_state axiom forall mathint i. ghostValues[i] == 0;
}
// ghost field for mapping the set's elements back to their index
ghost mapping(address => mathint) ghostIndexes {
    init_state axiom forall address x. ghostIndexes[x] == 0;
}

ghost mathint ghostLength {
    init_state axiom  ghostLength == 0;
    // assumption: it's infeasible to grow the list to these many elements.
    axiom ghostLength < max_uint256;
}

ghost address ghostFirst {
    init_state axiom ghostFirst == 0; 
}

// Store and load hooks to synchronize ghostValues .
hook Sstore currentContract.setStorage.elements[INDEX uint256 _index].value address newValue (address oldValue) {
    mathint index = to_mathint(_index)+1;
    require ghostValues[index] == oldValue;
    require ghostIndexes[oldValue] == index;

    ghostValues[index] = newValue;
    ghostIndexes[oldValue] = 0;
    ghostIndexes[newValue] = index;
    
}

hook Sload address v currentContract.setStorage.elements[INDEX uint256 index].value {
    require ghostIndexes[v] == to_mathint(index+1);
    require ghostValues[index+1] == v;
}

// Store and load hooks to sync length
hook Sstore currentContract.setStorage.numElements uint8 newValue (uint8 oldValue) {
    // make sure we were mirroring before
    require ghostLength == to_mathint(oldValue);
    ghostLength = to_mathint(newValue);
}

hook Sload uint8 value currentContract.setStorage.numElements {
    require ghostLength == to_mathint(value);
}

// Store and load hooks to sync firstElement
hook Sstore currentContract.setStorage.firstElement address newValue {
    ghostFirst = newValue;
}

hook Sload address value currentContract.setStorage.firstElement {
    require ghostFirst == value;
}

// check for the ghosts and updates 
invariant mirrorIsCorrect(uint8 i) 
    ( i > 1 =>  get(i) == ghostValues[i]) &&
    get(1) == ghostFirst &&
    ghostLength == to_mathint(length());


/** @title Elements are unique in the set.
Proving this is together with proving that each element has a single index 
**/
// CER-93 Set insert: must insert an element into the set unless it's a 
// duplicate or the set is full. This is covered by a combination of
// containsIntegrity() and validSet().
invariant validSet() 
    // inverse
    ( forall mathint i. ( i <= ghostLength && i > 1) => 
        ghostIndexes[ghostValues[i]] == i )
    &&
    ( forall address v. ( ghostIndexes[v]!=0 ) => 
        ghostValues[ghostIndexes[v]] == v )
    &&  
    // uniqueness
    ( forall mathint i.  forall mathint j. 
        ( i <= ghostLength && i > 1 && j <= ghostLength && j > 1 && j != i ) =>
            ( ghostValues[i] != ghostValues[j] )
     ) &&
     ( forall mathint i.  
        ( i <= ghostLength && i > 1 ) =>
         ( ghostValues[i] != ghostFirst)
     )

    { 
                preserved {
                    requireInvariant mirrorIsCorrect(1);
                    uint8 _length = assert_uint8(ghostLength);
                    requireInvariant mirrorIsCorrect(_length); 
                }
        }

invariant containsIntegrity(address v ) 
    v!=0 => ( contains(v) <=> ( v == ghostFirst  || 
                    ( ghostIndexes[v] <= ghostLength && ghostIndexes[v] > 1 ))) 
        {
            preserved {
                requireInvariant validSet();
                requireInvariant mirrorIsCorrect(1);
                uint8 _length = assert_uint8(ghostLength);
                requireInvariant mirrorIsCorrect(_length); 
            }
        }

// CER-86 Set insert: contains must return true if an element is present in 
// the set. (This is specified in combination with validSet/containsIntegrity)
rule contained_if_inserted(address a) {
    env e;
    insert(a);
    assert(contains(a));
}

// CER-91: set library MUST remove an element from the set if it's present
rule not_contained_if_removed(address a) {
    env e;
    requireInvariant validSet();
    requireInvariant mirrorIsCorrect(1);
    uint8 _length = assert_uint8(ghostLength);
    requireInvariant mirrorIsCorrect(_length); 

    remove(a);
    assert(!contains(a));
}

// CER-90: remove must return true if an element was successfully removed from 
// the set.remove must return false if an element was not removed from the set.
// (In other words it returns true if and only if an element is removed).
rule removed_iff_not_contained(address a) {
    env e;
    requireInvariant validSet();
    bool containsBefore = contains(a);
    bool succ = remove(a);
    assert(succ <=> containsBefore);
}

/** @title remove decreases the number of elements by one */
rule removed_then_length_decrease(address a) {
    env e;
    requireInvariant validSet();
    mathint ghostBefore = ghostLength;
    bool succ = remove(a);
    assert(succ => ghostLength == ghostBefore - 1);
}

/** @title every operation is feasible */ 
rule sanity(method f) {
    env e;
    calldataarg args;
    f(e, args);
    satisfy true;
}