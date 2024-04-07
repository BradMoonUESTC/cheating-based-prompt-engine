// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

library ArrayLib {
    function sum(uint256[] memory input) internal pure returns (uint256) {
        uint256 value = 0;
        for (uint256 i = 0; i < input.length; ) {
            value += input[i];
            unchecked {
                i++;
            }
        }
        return value;
    }

    /// @notice return index of the element if found, else return uint256.max
    function find(address[] memory array, address element) internal pure returns (uint256 index) {
        uint256 length = array.length;
        for (uint256 i = 0; i < length; ) {
            if (array[i] == element) return i;
            unchecked {
                i++;
            }
        }
        return type(uint256).max;
    }

    function append(address[] memory inp, address element) internal pure returns (address[] memory out) {
        uint256 length = inp.length;
        out = new address[](length + 1);
        for (uint256 i = 0; i < length; ) {
            out[i] = inp[i];
            unchecked {
                i++;
            }
        }
        out[length] = element;
    }

    function appendHead(address[] memory inp, address element) internal pure returns (address[] memory out) {
        uint256 length = inp.length;
        out = new address[](length + 1);
        out[0] = element;
        for (uint256 i = 1; i <= length; ) {
            out[i] = inp[i - 1];
            unchecked {
                i++;
            }
        }
    }

    /**
     * @dev This function assumes a and b each contains unidentical elements
     * @param a array of addresses a
     * @param b array of addresses b
     * @return out Concatenation of a and b containing unidentical elements
     */
    function merge(address[] memory a, address[] memory b) internal pure returns (address[] memory out) {
        unchecked {
            uint256 countUnidenticalB = 0;
            bool[] memory isUnidentical = new bool[](b.length);
            for (uint256 i = 0; i < b.length; ++i) {
                if (!contains(a, b[i])) {
                    countUnidenticalB++;
                    isUnidentical[i] = true;
                }
            }

            out = new address[](a.length + countUnidenticalB);
            for (uint256 i = 0; i < a.length; ++i) {
                out[i] = a[i];
            }
            uint256 id = a.length;
            for (uint256 i = 0; i < b.length; ++i) {
                if (isUnidentical[i]) {
                    out[id++] = b[i];
                }
            }
        }
    }

    // various version of contains
    function contains(address[] memory array, address element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i = 0; i < length; ) {
            if (array[i] == element) return true;
            unchecked {
                i++;
            }
        }
        return false;
    }

    function contains(bytes4[] memory array, bytes4 element) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i = 0; i < length; ) {
            if (array[i] == element) return true;
            unchecked {
                i++;
            }
        }
        return false;
    }

    function create(address a) internal pure returns (address[] memory res) {
        res = new address[](1);
        res[0] = a;
    }

    function create(address a, address b) internal pure returns (address[] memory res) {
        res = new address[](2);
        res[0] = a;
        res[1] = b;
    }

    function create(address a, address b, address c) internal pure returns (address[] memory res) {
        res = new address[](3);
        res[0] = a;
        res[1] = b;
        res[2] = c;
    }

    function create(uint256 a) internal pure returns (uint256[] memory res) {
        res = new uint256[](1);
        res[0] = a;
    }
}
