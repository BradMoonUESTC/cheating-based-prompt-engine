// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Proxy.sol";
import "../../../../../libraries/BoringOwnableUpgradeable.sol";
import "../../../../../../interfaces/IStandardizedYield.sol";
import "../../../../../../interfaces/Balancer/IVersion.sol";

contract ComposableStablePreviewProxy is BoringOwnableUpgradeable, UUPSUpgradeable, Proxy {
    address internal immutable implementationV4;
    address internal immutable implementationV5;
    address internal constant ETHX_BBAWETH_POOL = 0xbA72de8B5B56552e537994DddFe82e7ce43409f5;
    bytes32 internal constant V3 =
        keccak256(
            abi.encodePacked(
                '{"name":"ComposableStablePool","version":3,"deployment":"20230206-composable-stable-pool-v3"}'
            )
        );
    bytes32 internal constant V4 =
        keccak256(
            abi.encodePacked(
                '{"name":"ComposableStablePool","version":4,"deployment":"20230320-composable-stable-pool-v4"}'
            )
        );
    bytes32 internal constant V5 =
        keccak256(
            abi.encodePacked(
                '{"name":"ComposableStablePool","version":5,"deployment":"20230711-composable-stable-pool-v5"}'
            )
        );

    constructor(address _implementationV4, address _implementationV5) initializer {
        implementationV4 = _implementationV4;
        implementationV5 = _implementationV5;
    }

    function initialize() external initializer {
        __BoringOwnable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _implementation() internal view override returns (address) {
        address LP = IStandardizedYield(msg.sender).yieldToken();
        bytes32 version = keccak256(abi.encodePacked(IVersion(LP).version()));

        if (version == V3 || version == V4) return implementationV4;
        else if (version == V5) return implementationV5;

        revert("no preview implementation");
    }
}
