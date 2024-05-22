// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/Set.sol";

contract SetTest is Test {
    using Set for SetStorage;

    SetStorage internal setStorage;
    uint256 internal counter;

    function setUp() public {
        delete setStorage;
        delete expectedElements;
    }

    // ----- AUXILIARY FOR TESTING -----
    SetStorage internal expectedElements;

    function callbackTestNoResult(address element) internal {
        if (expectedElements.contains(element)) {
            expectedElements.remove(element);
        } else {
            revert("callbackTestNoResult");
        }
    }

    function callbackTestWithResult(address element) internal returns (bool, bytes memory) {
        if (expectedElements.contains(element)) {
            expectedElements.remove(element);

            return (uint160(element) % 2 == 0, abi.encode(uint160(element) % 3));
        } else {
            revert("callbackTestWithResult");
        }
    }

    // ----- AUXILIARY FOR TESTING -----

    function test_InsertRemove(address[] memory elements, uint64 seed) public {
        // ------------------ SETUP ----------------------
        delete setStorage;

        // ------------------ INSERTING ------------------
        // make the first two elements identical to exercise an edge case
        if (++counter % 10 == 0 && elements.length >= 2) {
            elements[0] = elements[1];
        }

        // count added elements not to exceed the limit
        uint256 expectedNumElements;
        for (uint256 i = 0; i < elements.length && expectedNumElements < SET_MAX_ELEMENTS; ++i) {
            if (setStorage.insert(elements[i])) ++expectedNumElements;
        }

        // check the number of elements
        address[] memory array = setStorage.get();
        assertEq(array.length, expectedNumElements);

        // check the elements
        uint256 lastExpectedIndex = 0;
        for (uint256 i = 0; i < array.length; ++i) {
            // expected element has to be found as the duplicates are not being inserted
            address expectedElement;
            uint256 seenBeforeCnt;

            do {
                seenBeforeCnt = 0;
                expectedElement = elements[lastExpectedIndex];

                for (uint256 j = 0; j < lastExpectedIndex; ++j) {
                    if (elements[lastExpectedIndex] == elements[j]) {
                        ++seenBeforeCnt;
                    }
                }

                ++lastExpectedIndex;
            } while (seenBeforeCnt != 0);

            assertEq(array[i], expectedElement);
        }

        // ------------------ REMOVING ------------------
        uint256 cnt;
        while (setStorage.get().length > 0) {
            uint256 lengthBeforeRemoval = setStorage.get().length;
            uint256 indexToBeRemoved = seed % lengthBeforeRemoval;
            address elementToBeRemoved = setStorage.get()[indexToBeRemoved];

            // try to remove non-existent element to exercise an edge case
            if (++cnt % 5 == 0) {
                address candidate = address(uint160(cnt));

                if (!setStorage.contains(candidate)) {
                    assertEq(setStorage.remove(candidate), false);
                    assertEq(setStorage.get().length, lengthBeforeRemoval);
                }
            } else {
                assertEq(setStorage.contains(elementToBeRemoved), true);
                assertEq(setStorage.remove(elementToBeRemoved), true);
                assertEq(setStorage.get().length, lengthBeforeRemoval - 1);
            }
        }
    }

    function test_RevertIfTooManyElements_Insert(uint256 seed) public {
        seed = bound(seed, 101, type(uint256).max);
        delete setStorage;

        for (uint256 i = 0; i < SET_MAX_ELEMENTS; ++i) {
            assertEq(setStorage.insert(address(uint160(uint256(bytes32(keccak256(abi.encode(seed, i))))))), true);
        }

        vm.expectRevert(Set.TooManyElements.selector);
        setStorage.insert(address(uint160(uint256(bytes32(keccak256(abi.encode(seed, seed)))))));
    }

    function test_FirstElement_Insert(address element) public {
        bool wasInserted = setStorage.insert(element);

        assertTrue(wasInserted);
        assertEq(setStorage.numElements, 1);
        assertEq(setStorage.firstElement, element);
    }

    function test_SecondElement_Insert(address elementA, address elementB) public {
        vm.assume(elementA != elementB);

        assertTrue(setStorage.insert(elementA));
        assertTrue(setStorage.insert(elementB));
        assertEq(setStorage.numElements, 2);
        assertEq(setStorage.firstElement, elementA);
    }

    function test_FirstElementDuplicate_Insert(address element) public {
        assertTrue(setStorage.insert(element));
        assertFalse(setStorage.insert(element));
        assertEq(setStorage.numElements, 1);
        assertEq(setStorage.firstElement, element);
    }

    function test_ArrayElementDuplicate_Insert(address elementA, address elementB) public {
        vm.assume(elementA != elementB);

        assertTrue(setStorage.insert(elementA));
        assertTrue(setStorage.insert(elementB));
        assertFalse(setStorage.insert(elementB));
        assertEq(setStorage.numElements, 2);
        assertEq(setStorage.firstElement, elementA);
    }

    function test_ContainsMaxElements_Insert() public {
        for (uint256 i = 0; i < SET_MAX_ELEMENTS; i++) {
            address e = address(uint160(uint256(i)));
            address eNext = address(uint160(uint256(i + 1)));
            assertTrue(setStorage.insert(e));
            assertTrue(setStorage.contains(e));
            assertFalse(setStorage.contains(eNext));
        }

        assertEq(setStorage.numElements, SET_MAX_ELEMENTS);
    }

    function test_Reorder(uint8 numberOfElements, address firstElement, uint8 index1, uint8 index2) public {
        numberOfElements = uint8(bound(numberOfElements, 2, SET_MAX_ELEMENTS));
        index1 = uint8(bound(index1, 0, numberOfElements - 2));
        index2 = uint8(bound(index2, index1 + 1, numberOfElements - 1));

        for (uint8 i = 0; i < numberOfElements; ++i) {
            setStorage.insert(address(uint160(uint256(keccak256(abi.encode(i, firstElement))))));
        }

        address[] memory pre = setStorage.get();
        setStorage.reorder(index1, index2);
        address[] memory post = setStorage.get();

        assertEq(pre.length, post.length);
        assertEq(pre[index1], post[index2]);
        assertEq(pre[index2], post[index1]);

        (post[index1], post[index2]) = (post[index2], post[index1]);

        for (uint8 i = 0; i < numberOfElements; ++i) {
            assertEq(pre[i], post[i]);
        }
    }

    function test_RevertIfInvalidIndex_Reorder(
        uint8 numberOfElements,
        address firstElement,
        uint8 index1,
        uint8 index2
    ) public {
        numberOfElements = uint8(bound(numberOfElements, 2, SET_MAX_ELEMENTS));

        for (uint8 i = 0; i < numberOfElements; ++i) {
            setStorage.insert(address(uint160(uint256(keccak256(abi.encode(i, firstElement))))));
        }

        // indices are equal
        index1 = uint8(bound(index1, 0, numberOfElements - 1));
        index2 = index1;

        vm.expectRevert(Set.InvalidIndex.selector);
        setStorage.reorder(index1, index2);

        // index1 is greater than index2
        index1 = uint8(bound(index1, 1, numberOfElements - 1));
        index2 = uint8(bound(index2, 0, index1 - 1));

        vm.expectRevert(Set.InvalidIndex.selector);
        setStorage.reorder(index1, index2);

        // both indices are out of bounds
        index1 = numberOfElements;
        index2 = numberOfElements + 1;

        vm.expectRevert(Set.InvalidIndex.selector);
        setStorage.reorder(index1, index2);

        // index2 is out of bounds
        index1 = uint8(bound(index1, 0, numberOfElements - 1));
        index2 = numberOfElements;

        vm.expectRevert(Set.InvalidIndex.selector);
        setStorage.reorder(index1, index2);
    }

    function test_setMetadata(uint80 metadata) public {
        vm.assume(metadata > 0);
        setStorage.setMetadata(metadata);
        assertEq(setStorage.getMetadata(), metadata);
    }

    function test_Empty_Remove(address e) public {
        assertFalse(setStorage.remove(e));
        assertEq(setStorage.numElements, 0);
    }

    function test_FirstElement_Remove(address e) public {
        setStorage.insert(e);
        assertTrue(setStorage.remove(e));
        assertEq(setStorage.numElements, 0);
    }

    function test_SecondElement_Remove(address elementA, address elementB) public {
        vm.assume(elementA != elementB);
        setStorage.insert(elementA);
        setStorage.insert(elementB);
        assertTrue(setStorage.remove(elementB));
        assertEq(setStorage.numElements, 1);
        assertTrue(setStorage.remove(elementA));
        assertEq(setStorage.numElements, 0);
    }

    function test_Empty_Contains(address e) public {
        assertFalse(setStorage.contains(e));
    }

    function test_FirstElement_Contains(address e) public {
        setStorage.insert(e);
        assertTrue(setStorage.contains(e));
    }

    function test_ForEachAndClear(uint8 numberOfElements, address firstElement) public {
        numberOfElements = uint8(bound(numberOfElements, 2, SET_MAX_ELEMENTS));

        for (uint8 i = 0; i < numberOfElements; ++i) {
            address element = address(uint160(uint256(keccak256(abi.encode(i, firstElement)))));
            setStorage.insert(element);
            expectedElements.insert(element);
        }

        setStorage.forEachAndClear(callbackTestNoResult);

        assertEq(expectedElements.numElements, 0);
        assertEq(setStorage.numElements, 0);
        assertEq(setStorage.firstElement, address(0));

        for (uint8 i = 0; i < SET_MAX_ELEMENTS; ++i) {
            assertEq(setStorage.elements[i].value, address(0));
        }
    }

    function test_ForEachAndClearWithResult(uint8 numberOfElements, address firstElement) public {
        numberOfElements = uint8(bound(numberOfElements, 2, SET_MAX_ELEMENTS));

        for (uint8 i = 0; i < numberOfElements; ++i) {
            address element = address(uint160(uint256(keccak256(abi.encode(i, firstElement)))));
            setStorage.insert(element);
            expectedElements.insert(element);
        }

        address[] memory expectedElementsCache = expectedElements.get();
        bytes[] memory result = setStorage.forEachAndClearWithResult(callbackTestWithResult);

        assertEq(expectedElements.numElements, 0);
        assertEq(setStorage.numElements, 0);
        assertEq(setStorage.firstElement, address(0));

        for (uint8 i = 0; i < SET_MAX_ELEMENTS; ++i) {
            assertEq(setStorage.elements[i].value, address(0));
        }

        for (uint8 i = 0; i < numberOfElements; ++i) {
            (address element, bool success, bytes memory data) = abi.decode(result[i], (address, bool, bytes));

            assertEq(element, expectedElementsCache[i]);
            assertEq(success, uint160(expectedElementsCache[i]) % 2 == 0);
            assertEq(data, abi.encode(uint160(expectedElementsCache[i]) % 3));
        }
    }
}
