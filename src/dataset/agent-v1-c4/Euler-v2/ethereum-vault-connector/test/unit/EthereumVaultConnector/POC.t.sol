// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {EthereumVaultConnector} from "../../../src/EthereumVaultConnector.sol";

contract POC_Test is Test {
    EthereumVaultConnector internal evc;

    function setUp() public {
        evc = new EthereumVaultConnector();
    }

    function test_POC() external {}
}
