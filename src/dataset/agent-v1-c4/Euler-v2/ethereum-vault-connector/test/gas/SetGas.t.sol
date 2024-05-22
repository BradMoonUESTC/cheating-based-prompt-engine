// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/Set.sol";

contract SetGasTest is Test {
    using Set for SetStorage;

    address constant ELEMENT_1 = address(1);
    address constant ELEMENT_2 = address(2);
    address constant ELEMENT_19 = address(19);
    address constant ELEMENT_10 = address(10);
    address constant ELEMENT_11 = address(11);
    address constant ELEMENT_NOT_FOUND = address(99);

    SetStorage size00;
    SetStorage size01;
    SetStorage size02;
    SetStorage size05;
    SetStorage size10;

    function setUp() public {
        size01.insert(ELEMENT_1);

        size02.insert(ELEMENT_1);
        size02.insert(ELEMENT_2);

        for (uint160 i = 1; i <= 10; ++i) {
            size10.insert(address(i));
        }

        for (uint160 i = 1; i <= 5; ++i) {
            size05.insert(address(i));
        }
    }

    /**
     *
     */
    /**
     * insert    *
     */
    /**
     *
     */
    function testGas_insert_size00() public {
        size00.insert(ELEMENT_1);
    }

    function testGas_insert_size01() public {
        size01.insert(ELEMENT_2);
    }

    function testGas_insert_size01_duplicateOfFirst() public {
        size01.insert(ELEMENT_1);
    }

    function testGas_insert_size02() public {
        size02.insert(ELEMENT_2);
    }

    function testGas_insert_size02_duplicateOfFirst() public {
        size02.insert(ELEMENT_1);
    }

    function testGas_insert_size02_duplicateOfSecond() public {
        size02.insert(ELEMENT_2);
    }

    function testGas_insert_size05() public {
        size05.insert(ELEMENT_10);
    }

    function testGas_insert_size05_duplicateOfFirst() public {
        size05.insert(ELEMENT_1);
    }

    function testGas_insert_size05_duplicateOfSecond() public {
        size05.insert(ELEMENT_2);
    }

    function testGas_insert_size05_duplicateOfLast() public {
        size05.insert(ELEMENT_19);
    }

    function testGas_insert_siz10_reverts() public {
        vm.expectRevert();
        size10.insert(ELEMENT_11);
    }

    function testGas_insert_size10_duplicateOfFirst() public {
        size10.insert(ELEMENT_1);
    }

    function testGas_insert_size10_duplicateOfSecond() public {
        size10.insert(ELEMENT_2);
    }

    function testGas_insert_size10_duplicateOfLast() public {
        size10.insert(ELEMENT_10);
    }

    /**
     *
     */
    /**
     * contains   *
     */
    /**
     *
     */
    function testGas_contains_size00_notFound() public view {
        size00.contains(ELEMENT_1);
    }

    function testGas_contains_size01_notFound() public view {
        size01.contains(ELEMENT_NOT_FOUND);
    }

    function testGas_contains_size01_foundAtFirst() public view {
        size01.contains(ELEMENT_1);
    }

    function testGas_contains_size02_notFound() public view {
        size02.contains(ELEMENT_NOT_FOUND);
    }

    function testGas_contains_size02_foundAtFirst() public view {
        size02.contains(ELEMENT_1);
    }

    function testGas_contains_size02_foundAtIndex1() public view {
        size02.contains(ELEMENT_2);
    }

    function testGas_contains_size05_notFound() public view {
        size05.contains(ELEMENT_NOT_FOUND);
    }

    function testGas_contains_size05_foundAtFirst() public view {
        size05.contains(ELEMENT_1);
    }

    function testGas_contains_size05_foundAtIndex1() public view {
        size05.contains(ELEMENT_2);
    }

    function testGas_contains_size05_foundAtLastIndex() public view {
        size05.contains(ELEMENT_19);
    }

    function testGas_contains_size10_notFound() public view {
        size10.contains(ELEMENT_NOT_FOUND);
    }

    function testGas_contains_size10_foundAtFirst() public view {
        size10.contains(ELEMENT_1);
    }

    function testGas_contains_size10_foundAtIndex1() public view {
        size10.contains(ELEMENT_2);
    }

    function testGas_contains_size10_foundAtLastIndex() public view {
        size10.contains(ELEMENT_10);
    }

    /**
     *
     */
    /**
     * remove    *
     */
    /**
     *
     */
    function testGas_remove_size00_notFound() public {
        size00.remove(ELEMENT_1);
    }

    function testGas_remove_size01_notFound() public {
        size01.remove(ELEMENT_NOT_FOUND);
    }

    function testGas_remove_size01_foundAtFirst() public {
        size01.remove(ELEMENT_1);
    }

    function testGas_remove_size02_notFound() public {
        size02.remove(ELEMENT_NOT_FOUND);
    }

    function testGas_remove_size02_foundAtFirst() public {
        size02.remove(ELEMENT_1);
    }

    function testGas_remove_size02_foundAtIndex1() public {
        size02.remove(ELEMENT_2);
    }

    function testGas_remove_size05_notFound() public {
        size05.remove(ELEMENT_NOT_FOUND);
    }

    function testGas_remove_size05_foundAtFirst() public {
        size05.remove(ELEMENT_1);
    }

    function testGas_remove_size05_foundAtIndex1() public {
        size05.remove(ELEMENT_2);
    }

    function testGas_remove_size05_foundAtLastIndex() public {
        size05.remove(ELEMENT_19);
    }

    function testGas_remove_size10_notFound() public {
        size10.remove(ELEMENT_NOT_FOUND);
    }

    function testGas_remove_size10_foundAtFirst() public {
        size10.remove(ELEMENT_1);
    }

    function testGas_remove_size10_foundAtIndex1() public {
        size10.remove(ELEMENT_2);
    }

    function testGas_remove_size10_foundAtLastIndex() public {
        size10.remove(ELEMENT_10);
    }
}
