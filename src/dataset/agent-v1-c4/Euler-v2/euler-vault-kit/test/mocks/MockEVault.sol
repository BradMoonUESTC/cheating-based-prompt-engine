// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

contract MockEVault {
    constructor(address factory_, address evc_) {}

    function initialize(address) external {}

    function implementation() external pure returns (string memory) {
        return "TRANSPARENT";
    }

    function UNPACK() internal pure returns (address vaultAsset) {
        assembly {
            vaultAsset := shr(96, calldataload(sub(calldatasize(), 20)))
        }
    }

    function arbitraryFunction(string calldata arg) external view returns (string memory, address, address) {
        (address vaultAsset) = UNPACK();
        return (arg, msg.sender, vaultAsset);
    }

    function payMe() external payable {}
}
