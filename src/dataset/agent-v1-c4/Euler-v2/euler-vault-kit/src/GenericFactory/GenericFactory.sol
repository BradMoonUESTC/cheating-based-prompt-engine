// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {BeaconProxy} from "./BeaconProxy.sol";
import {MetaProxyDeployer} from "./MetaProxyDeployer.sol";

/// @title IComponent
/// @notice Minimal interface which must be implemented by the contract deployed by the factory
interface IComponent {
    /// @notice Function replacing the constructor in proxied contracts
    /// @param creator The new contract's creator address
    function initialize(address creator) external;
}

/// @title GenericFactory
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice The factory allows permissionless creation of upgradeable or non-upgradeable proxy contracts and serves as a
/// beacon for the upgradeable ones
contract GenericFactory is MetaProxyDeployer {
    // Constants

    uint256 internal constant REENTRANCYLOCK__UNLOCKED = 1;
    uint256 internal constant REENTRANCYLOCK__LOCKED = 2;

    // State

    /// @title ProxyConfig
    /// @notice This struct is used to store the configuration of a proxy deployed by the factory
    struct ProxyConfig {
        // If true, proxy is an instance of the BeaconProxy
        bool upgradeable;
        // Address of the implementation contract
        // May be an out-of-date value, if upgradeable (handled by getProxyConfig)
        address implementation;
        // The metadata attached to every call passing through the proxy
        bytes trailingData;
    }

    uint256 private reentrancyLock;

    /// @notice Address of the account authorized to upgrade the implementation contract
    address public upgradeAdmin;
    /// @notice Address of the implementation contract, which the deployed proxies will delegate-call to
    /// @dev The contract must implement the `IComponent` interface
    address public implementation;
    /// @notice A lookup for configurations of the proxy contracts deployed by the factory
    mapping(address proxy => ProxyConfig) internal proxyLookup;
    /// @notice An array of addresses of all the proxies deployed by the factory
    address[] public proxyList;

    // Events

    /// @notice The factory is created
    event Genesis();

    /// @notice A new proxy is created
    /// @param proxy Address of the new proxy
    /// @param upgradeable If true, proxy is an instance of the BeaconProxy. If false, the proxy is a minimal meta proxy
    /// @param implementation Address of the implementation contract, at the time the proxy was deployed
    /// @param trailingData The metadata that will be attached to every call passing through the proxy
    event ProxyCreated(address indexed proxy, bool upgradeable, address implementation, bytes trailingData);

    /// @notice Set a new implementation contract. All the BeaconProxies are upgraded to the new logic
    /// @param newImplementation Address of the new implementation contract
    event SetImplementation(address indexed newImplementation);

    /// @notice Set a new upgrade admin
    /// @param newUpgradeAdmin Address of the new admin
    event SetUpgradeAdmin(address indexed newUpgradeAdmin);

    // Errors

    error E_Reentrancy();
    error E_Unauthorized();
    error E_Implementation();
    error E_BadAddress();
    error E_BadQuery();

    // Modifiers

    modifier nonReentrant() {
        if (reentrancyLock == REENTRANCYLOCK__LOCKED) revert E_Reentrancy();

        reentrancyLock = REENTRANCYLOCK__LOCKED;
        _;
        reentrancyLock = REENTRANCYLOCK__UNLOCKED;
    }

    modifier adminOnly() {
        if (msg.sender != upgradeAdmin) revert E_Unauthorized();
        _;
    }

    constructor(address admin) {
        emit Genesis();

        if (admin == address(0)) revert E_BadAddress();

        reentrancyLock = REENTRANCYLOCK__UNLOCKED;

        upgradeAdmin = admin;

        emit SetUpgradeAdmin(admin);
    }

    /// @notice A permissionless funtion to deploy new proxies
    /// @param desiredImplementation Address of the implementation contract expected to be registered in the factory
    /// during proxy creation
    /// @param upgradeable If true, the proxy will be an instance of the BeaconProxy. If false, a minimal meta proxy
    /// will be deployed
    /// @param trailingData Metadata to be attached to every call passing through the new proxy
    /// @return The address of the new proxy
    /// @dev The desired implementation serves as a protection against (unintentional) front-running of upgrades
    function createProxy(address desiredImplementation, bool upgradeable, bytes memory trailingData)
        external
        nonReentrant
        returns (address)
    {
        address _implementation = implementation;
        if (desiredImplementation == address(0)) desiredImplementation = _implementation;

        if (desiredImplementation == address(0) || desiredImplementation != _implementation) revert E_Implementation();

        address proxy;

        if (upgradeable) {
            proxy = address(new BeaconProxy(trailingData));
        } else {
            proxy = deployMetaProxy(desiredImplementation, trailingData);
        }

        proxyLookup[proxy] =
            ProxyConfig({upgradeable: upgradeable, implementation: desiredImplementation, trailingData: trailingData});

        proxyList.push(proxy);

        IComponent(proxy).initialize(msg.sender);

        emit ProxyCreated(proxy, upgradeable, desiredImplementation, trailingData);

        return proxy;
    }

    // EVault beacon upgrade

    /// @notice Set a new implementation contract
    /// @param newImplementation Address of the new implementation contract
    /// @dev Upgrades all existing BeaconProxies to the new logic immediately
    function setImplementation(address newImplementation) external nonReentrant adminOnly {
        if (newImplementation == address(0)) revert E_BadAddress();
        implementation = newImplementation;
        emit SetImplementation(newImplementation);
    }

    // Admin role

    /// @notice Transfer admin rights to a new address
    /// @param newUpgradeAdmin Address of the new admin
    /// @dev For creating non upgradeable factories, or to finalize all upgradeable proxies to current implementation,
    /// @dev set the admin to zero address.
    /// @dev If setting to address zero, make sure the implementation contract is already set
    function setUpgradeAdmin(address newUpgradeAdmin) external nonReentrant adminOnly {
        upgradeAdmin = newUpgradeAdmin;
        emit SetUpgradeAdmin(newUpgradeAdmin);
    }

    // Proxy getters

    /// @notice Get current proxy configuration
    /// @param proxy Address of the proxy to query
    /// @return config The proxy's configuration, including current implementation
    function getProxyConfig(address proxy) external view returns (ProxyConfig memory config) {
        config = proxyLookup[proxy];
        if (config.upgradeable) config.implementation = implementation;
    }

    /// @notice Check if an address is a proxy deployed with this factory
    /// @param proxy Address to check
    /// @return True if the address is a proxy
    function isProxy(address proxy) external view returns (bool) {
        return proxyLookup[proxy].implementation != address(0);
    }

    /// @notice Fetch the length of the deployed proxies list
    /// @return The length of the proxy list array
    function getProxyListLength() external view returns (uint256) {
        return proxyList.length;
    }

    /// @notice Get a slice of the deployed proxies array
    /// @param start Start index of the slice
    /// @param end End index of the slice
    /// @return list An array containing the slice of the proxy list
    function getProxyListSlice(uint256 start, uint256 end) external view returns (address[] memory list) {
        if (end == type(uint256).max) end = proxyList.length;
        if (end < start || end > proxyList.length) revert E_BadQuery();

        list = new address[](end - start);
        for (uint256 i; i < end - start; ++i) {
            list[i] = proxyList[start + i];
        }
    }
}
