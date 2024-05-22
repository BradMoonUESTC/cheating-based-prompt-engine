// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title PoolManager
 * @dev PoolManager is a contract for managing the bridge
 */
contract ProxyTimeLockController is TimelockController {
    /**
     * @dev constructor
     * @param minDelay The minimum delay for timelock controller
     * @param proposers The proposers for timelock controller
     * @param executors The executors for timelock controller
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}

    function setRoleAdmin(
        bytes32 role,
        bytes32 adminRole
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }

    function setRelayer(
        address pool,
        address _relayer
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        //bytes32 public constant ReLayer =
        //        keccak256(abi.encode(uint256(keccak256("ReLayer")) - 1)) &
        //            ~bytes32(uint256(0xff));
        // 0x0685f9a33ecc8d58f6db2634bbe92aa174d2b8ca9e4e571760206f3509a84e00
        AccessControlUpgradeable(pool).grantRole(
            0x0685f9a33ecc8d58f6db2634bbe92aa174d2b8ca9e4e571760206f3509a84e00,
            _relayer
        );
    }
}
