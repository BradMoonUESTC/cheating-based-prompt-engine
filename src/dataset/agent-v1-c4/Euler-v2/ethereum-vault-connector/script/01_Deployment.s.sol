// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/EthereumVaultConnector.sol";

/// @title DeployEthereumVaultConnector
/// @notice This script is used for deterministically deploying the EthereumVaultConnector contract accross different
/// chains.
/// @dev Run this script with the following command:
///      forge script script/01_Deployment.s.sol:Deployment \
///      --rpc-url <your_rpc_url> --etherscan-api-key <your_etherscan_api_key> \
///      --broadcast --verify -vvvv
/// It requires the PRIVATE_KEY to be set as environment variable.
contract Deployment is Script {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        // Setting a zero bytes32 salt for deterministic deployment.
        // It can also be the version number.
        bytes32 versionSalt = bytes32(0);

        vm.startBroadcast(privateKey);
        new EthereumVaultConnector{salt: versionSalt}();

        vm.stopBroadcast();
    }
}
