// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.24;

address constant VM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
address constant CONSOLE = 0x000000000000000000636F6e736F6c652e6c6f67;
address constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
address constant DEFAULT_TEST_CONTRACT = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;
address constant MULTICALL3_ADDRESS = 0xcA11bde05977b3631167028862bE2a173976CA11;
address constant FIRST_DEPLOYED_CONTRACT = 0x2e234DAe75C793f67A35089C9d99245E1C58470b;

/// @dev Exclude Foundry precompiles, predeploys and addresses with already deployed code.
/// These addresses can make certain test cases that call/mockCall to them fail.
/// List of Foundry precompiles: https://book.getfoundry.sh/misc/precompile-registry
function boundAddr(address addr) view returns (address) {
    if (
        uint160(addr) < 10 || addr == VM_ADDRESS || addr == CONSOLE || addr == CREATE2_FACTORY
            || addr == DEFAULT_TEST_CONTRACT || addr == MULTICALL3_ADDRESS || addr == FIRST_DEPLOYED_CONTRACT
            || addr.code.length != 0
    ) {
        return address(uint160(addr) + 10);
    }

    return addr;
}
