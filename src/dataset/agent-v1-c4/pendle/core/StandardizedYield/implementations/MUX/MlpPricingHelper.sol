// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../../../libraries/BoringOwnableUpgradeable.sol";
import "../../../../interfaces/IPPriceFeed.sol";
import "../../../../interfaces/IPOffchainStorage.sol";

contract MlpPricingHelper is BoringOwnableUpgradeable, UUPSUpgradeable, IPPriceFeed {
    address public immutable pendleStorage;
    bytes32 public constant KEY = keccak256("MLP.price");

    constructor(address _pendleStorage) initializer {
        pendleStorage = _pendleStorage;
    }

    function initialize() external initializer {
        __BoringOwnable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getPrice() external view returns (uint256) {
        return IPOffchainStorage(pendleStorage).getUint256(KEY);
    }
}
