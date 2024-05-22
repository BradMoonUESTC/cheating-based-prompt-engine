// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

contract ForkTest is Test {
    uint256 constant ETHEREUM_FORK_BLOCK = 18888888;
    uint256 ethereumFork;

    function _setUpFork() public {
        _setUpFork(ETHEREUM_FORK_BLOCK);
    }

    function _setUpFork(uint256 blockNumber) public {
        _setUpForkLatest();
        vm.rollFork(blockNumber);
    }

    function _setUpForkLatest() public {
        string memory ETHEREUM_RPC_URL = vm.envString("ETHEREUM_RPC_URL");
        ethereumFork = vm.createFork(ETHEREUM_RPC_URL);
        vm.selectFork(ethereumFork);
    }
}
