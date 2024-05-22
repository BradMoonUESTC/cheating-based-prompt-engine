// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract Proxy is TransparentUpgradeableProxy {
    receive() external payable {}

    constructor(
        address BridgeLogic,
        address admin_,
        bytes memory _data
    ) TransparentUpgradeableProxy(BridgeLogic, admin_, _data) {}
}
