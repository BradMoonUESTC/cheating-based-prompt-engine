// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {Errors} from "src/lib/Errors.sol";

/// @title Governable
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Contract mixin for governance.
abstract contract Governable {
    /// @notice The active governor address. If `address(0)` then the role is renounced.
    address public governor;

    /// @notice Set the governor of the contract.
    /// @param oldGovernor The address of the previous governor.
    /// @param newGovernor The address of the newly appointed governor.
    event GovernorSet(address indexed oldGovernor, address indexed newGovernor);

    constructor(address _governor) {
        _setGovernor(_governor);
    }

    /// @notice Transfer the governor role to another address.
    /// @param newGovernor The address of the next governor.
    /// @dev Can only be called by the current governor.
    function transferGovernance(address newGovernor) external onlyGovernor {
        _setGovernor(newGovernor);
    }

    /// @notice Restrict access to the governor.
    modifier onlyGovernor() {
        if (msg.sender != governor) {
            revert Errors.Governance_CallerNotGovernor();
        }
        _;
    }

    /// @notice Set the governor address.
    /// @param newGovernor The address of the new governor.
    function _setGovernor(address newGovernor) internal {
        emit GovernorSet(governor, newGovernor);
        governor = newGovernor;
    }
}
