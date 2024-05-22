// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

/// @dev Represents the maximum number of elements that can be stored in the set.
/// Must not exceed 255 due to the uint8 data type limit.
uint8 constant SET_MAX_ELEMENTS = 10;

/// @title ElementStorage
/// @notice This struct is used to store the value and stamp of an element.
/// @dev The stamp field is used to keep the storage slot non-zero when the element is removed.
/// @dev It allows for cheaper SSTORE when an element is inserted.
struct ElementStorage {
    /// @notice The value of the element.
    address value;
    /// @notice The stamp of the element.
    uint96 stamp;
}

/// @title SetStorage
/// @notice This struct is used to store the set data.
/// @dev To optimize the gas consumption, firstElement is stored in the same storage slot as the numElements
/// @dev so that for sets with one element, only one storage slot has to be read/written. To keep the elements
/// @dev array indexing consistent and because the first element is stored outside of the array, the elements[0]
/// @dev is not utilized. The stamp field is used to keep the storage slot non-zero when the element is removed.
/// @dev It allows for cheaper SSTORE when an element is inserted.
struct SetStorage {
    /// @notice The number of elements in the set.
    uint8 numElements;
    /// @notice The first element in the set.
    address firstElement;
    /// @notice The metadata of the set.
    uint80 metadata;
    /// @notice The stamp of the set.
    uint8 stamp;
    /// @notice The array of elements in the set. Stores the elements starting from index 1.
    ElementStorage[SET_MAX_ELEMENTS] elements;
}

/// @title Set
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This library provides functions for managing sets of addresses.
/// @dev The maximum number of elements in the set is defined by the constant SET_MAX_ELEMENTS.
library Set {
    error TooManyElements();
    error InvalidIndex();

    uint8 internal constant EMPTY_ELEMENT_OFFSET = 1; // must be 1
    uint8 internal constant DUMMY_STAMP = 1;

    /// @notice Initializes the set by setting the stamp field of the SetStorage and the stamp field of elements to
    /// DUMMY_STAMP.
    /// @dev The stamp field is used to keep the storage slot non-zero when the element is removed. It allows for
    /// cheaper SSTORE when an element is inserted.
    /// @param setStorage The set storage whose stamp fields will be initialized.
    function initialize(SetStorage storage setStorage) internal {
        setStorage.stamp = DUMMY_STAMP;

        for (uint256 i = EMPTY_ELEMENT_OFFSET; i < SET_MAX_ELEMENTS; ++i) {
            setStorage.elements[i].stamp = DUMMY_STAMP;
        }
    }

    /// @notice Inserts an element and returns information whether the element was inserted or not.
    /// @dev Reverts if the set is full but the element is not in the set storage.
    /// @param setStorage The set storage to which the element will be inserted.
    /// @param element The element to be inserted.
    /// @return A boolean value that indicates whether the element was inserted or not. If the element was already in
    /// the set storage, it returns false.
    function insert(SetStorage storage setStorage, address element) internal returns (bool) {
        address firstElement = setStorage.firstElement;
        uint256 numElements = setStorage.numElements;
        uint80 metadata = setStorage.metadata;

        if (numElements == 0) {
            // gas optimization:
            // on the first element insertion, set the stamp to non-zero value to keep the storage slot non-zero when
            // the element is removed. when a new element is inserted after the removal, it should be cheaper
            setStorage.numElements = 1;
            setStorage.firstElement = element;
            setStorage.metadata = metadata;
            setStorage.stamp = DUMMY_STAMP;
            return true;
        }

        if (firstElement == element) return false;

        for (uint256 i = EMPTY_ELEMENT_OFFSET; i < numElements; ++i) {
            if (setStorage.elements[i].value == element) return false;
        }

        if (numElements == SET_MAX_ELEMENTS) revert TooManyElements();

        setStorage.elements[numElements].value = element;

        unchecked {
            setStorage.numElements = uint8(numElements + 1);
        }

        return true;
    }

    /// @notice Removes an element and returns information whether the element was removed or not.
    /// @dev This operation may affect the order of elements in the array of elements obtained using get() function.
    /// @param setStorage The set storage from which the element will be removed.
    /// @param element The element to be removed.
    /// @return A boolean value that indicates whether the element was removed or not. If the element was not in the set
    /// storage, it returns false.
    function remove(SetStorage storage setStorage, address element) internal returns (bool) {
        address firstElement = setStorage.firstElement;
        uint256 numElements = setStorage.numElements;
        uint80 metadata = setStorage.metadata;

        if (numElements == 0) return false;

        uint256 searchIndex;
        if (firstElement != element) {
            for (searchIndex = EMPTY_ELEMENT_OFFSET; searchIndex < numElements; ++searchIndex) {
                if (setStorage.elements[searchIndex].value == element) break;
            }

            if (searchIndex == numElements) return false;
        }

        // write full slot at once to avoid SLOAD and bit masking
        if (numElements == 1) {
            setStorage.numElements = 0;
            setStorage.firstElement = address(0);
            setStorage.metadata = metadata;
            setStorage.stamp = DUMMY_STAMP;
            return true;
        }

        uint256 lastIndex;
        unchecked {
            lastIndex = numElements - 1;
        }

        // set numElements for every execution path to avoid SSTORE and bit masking when the element removed is
        // firstElement
        ElementStorage storage lastElement = setStorage.elements[lastIndex];
        if (searchIndex != lastIndex) {
            if (searchIndex == 0) {
                setStorage.firstElement = lastElement.value;
                setStorage.numElements = uint8(lastIndex);
                setStorage.metadata = metadata;
                setStorage.stamp = DUMMY_STAMP;
            } else {
                setStorage.elements[searchIndex].value = lastElement.value;

                setStorage.firstElement = firstElement;
                setStorage.numElements = uint8(lastIndex);
                setStorage.metadata = metadata;
                setStorage.stamp = DUMMY_STAMP;
            }
        } else {
            setStorage.firstElement = firstElement;
            setStorage.numElements = uint8(lastIndex);
            setStorage.metadata = metadata;
            setStorage.stamp = DUMMY_STAMP;
        }

        lastElement.value = address(0);

        return true;
    }

    /// @notice Swaps the position of two elements so that they appear switched in the array of elements obtained using
    /// get() function.
    /// @dev The first index must not be greater than or equal to the second index. Indices must not be out of bounds.
    /// The function will revert if the indices are invalid.
    /// @param setStorage The set storage for which the elements will be swapped.
    /// @param index1 The index of the first element to be swapped.
    /// @param index2 The index of the second element to be swapped.
    function reorder(SetStorage storage setStorage, uint8 index1, uint8 index2) internal {
        address firstElement = setStorage.firstElement;
        uint256 numElements = setStorage.numElements;

        if (index1 >= index2 || index2 >= numElements) {
            revert InvalidIndex();
        }

        if (index1 == 0) {
            (setStorage.firstElement, setStorage.elements[index2].value) =
                (setStorage.elements[index2].value, firstElement);
        } else {
            (setStorage.elements[index1].value, setStorage.elements[index2].value) =
                (setStorage.elements[index2].value, setStorage.elements[index1].value);
        }
    }

    /// @notice Sets the metadata for the set storage.
    /// @param setStorage The storage structure where metadata will be set.
    /// @param metadata The metadata value to set.
    function setMetadata(SetStorage storage setStorage, uint80 metadata) internal {
        setStorage.metadata = metadata;
    }

    /// @notice Returns an array of elements contained in the storage.
    /// @dev The order of the elements in the array may be affected by performing operations on the set.
    /// @param setStorage The set storage to be processed.
    /// @return An array that contains the same elements as the set storage.
    function get(SetStorage storage setStorage) internal view returns (address[] memory) {
        address firstElement = setStorage.firstElement;
        uint256 numElements = setStorage.numElements;
        address[] memory output = new address[](numElements);

        if (numElements == 0) return output;

        output[0] = firstElement;

        for (uint256 i = EMPTY_ELEMENT_OFFSET; i < numElements; ++i) {
            output[i] = setStorage.elements[i].value;
        }

        return output;
    }

    /// @notice Retrieves the metadata from the set storage.
    /// @param setStorage The storage structure from which metadata is retrieved.
    /// @return The metadata value.
    function getMetadata(SetStorage storage setStorage) internal view returns (uint80) {
        return setStorage.metadata;
    }

    /// @notice Checks if the set storage contains a given element and returns a boolean value that indicates the
    /// result.
    /// @param setStorage The set storage to be searched.
    /// @param element The element to be searched for.
    /// @return A boolean value that indicates whether the set storage includes the element or not.
    function contains(SetStorage storage setStorage, address element) internal view returns (bool) {
        address firstElement = setStorage.firstElement;
        uint256 numElements = setStorage.numElements;

        if (numElements == 0) return false;
        if (firstElement == element) return true;

        for (uint256 i = EMPTY_ELEMENT_OFFSET; i < numElements; ++i) {
            if (setStorage.elements[i].value == element) return true;
        }

        return false;
    }

    /// @notice Iterates over each element in the set and applies the callback function to it.
    /// @dev The set is cleared as a result of this call. Considering that this function does not follow the
    /// Checks-Effects-Interactions pattern, the function using it must prevent re-entrancy.
    /// @param setStorage The set storage to be processed.
    /// @param callback The function to be applied to each element.
    function forEachAndClear(SetStorage storage setStorage, function(address) callback) internal {
        uint256 numElements = setStorage.numElements;
        address firstElement = setStorage.firstElement;
        uint80 metadata = setStorage.metadata;

        if (numElements == 0) return;

        setStorage.numElements = 0;
        setStorage.firstElement = address(0);
        setStorage.metadata = metadata;
        setStorage.stamp = DUMMY_STAMP;

        callback(firstElement);

        for (uint256 i = EMPTY_ELEMENT_OFFSET; i < numElements; ++i) {
            address element = setStorage.elements[i].value;
            setStorage.elements[i] = ElementStorage({value: address(0), stamp: DUMMY_STAMP});

            callback(element);
        }
    }

    /// @notice Iterates over each element in the set and applies the callback function to it, returning the array of
    /// callback results.
    /// @dev The set is cleared as a result of this call. Considering that this function does not follow the
    /// Checks-Effects-Interactions pattern, the function using it must prevent re-entrancy.
    /// @param setStorage The set storage to be processed.
    /// @param callback The function to be applied to each element.
    /// @return result An array of encoded bytes that are the addresses passed to the callback function and results of
    /// calling it.
    function forEachAndClearWithResult(
        SetStorage storage setStorage,
        function(address) returns (bool, bytes memory) callback
    ) internal returns (bytes[] memory) {
        uint256 numElements = setStorage.numElements;
        address firstElement = setStorage.firstElement;
        uint80 metadata = setStorage.metadata;
        bytes[] memory results = new bytes[](numElements);

        if (numElements == 0) return results;

        setStorage.numElements = 0;
        setStorage.firstElement = address(0);
        setStorage.metadata = metadata;
        setStorage.stamp = DUMMY_STAMP;

        (bool success, bytes memory result) = callback(firstElement);
        results[0] = abi.encode(firstElement, success, result);

        for (uint256 i = EMPTY_ELEMENT_OFFSET; i < numElements; ++i) {
            address element = setStorage.elements[i].value;
            setStorage.elements[i] = ElementStorage({value: address(0), stamp: DUMMY_STAMP});

            (success, result) = callback(element);
            results[i] = abi.encode(element, success, result);
        }

        return results;
    }
}
