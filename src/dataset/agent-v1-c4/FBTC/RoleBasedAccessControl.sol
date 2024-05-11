// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @dev A simple RoleBasedAccessControl module modified from
///    https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol
///    https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/extensions/AccessControlEnumerable.sol
abstract contract RoleBasedAccessControl is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(bytes32 role => EnumerableSet.AddressSet) private _roleMembers;

    event RoleGranted(bytes32 indexed role, address indexed account);
    event RoleRevoked(bytes32 indexed role, address indexed account);

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "Unauthorized role member");
        _;
    }

    function _grantRole(bytes32 role, address account) internal {
        _roleMembers[role].add(account);
    }

    function _revokeRole(bytes32 role, address account) internal {
        _roleMembers[role].remove(account);
    }

    function grantRole(bytes32 role, address account) external onlyOwner {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyOwner {
        _revokeRole(role, account);
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roleMembers[role].contains(account);
    }

    function getRoleMember(
        bytes32 role,
        uint256 index
    ) external view returns (address) {
        return _roleMembers[role].at(index);
    }

    function getRoleMemberCount(bytes32 role) external view returns (uint256) {
        return _roleMembers[role].length();
    }

    function getRoleMembers(
        bytes32 role
    ) external view returns (address[] memory) {
        return _roleMembers[role].values();
    }
}
