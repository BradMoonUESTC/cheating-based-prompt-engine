// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Request} from "./Common.sol";
import {FireBridge} from "./FireBridge.sol";
import {RoleBasedAccessControl, Ownable} from "./RoleBasedAccessControl.sol";

contract FBTCMinter is RoleBasedAccessControl {
    FireBridge public bridge;

    bytes32 public constant MINT_ROLE = "minter.confirm_mint";
    bytes32 public constant BURN_ROLE = "minter.confirm_burn";
    bytes32 public constant CROSSCHAIN_ROLE = "minter.confirm_crosschain";

    event BridgeUpdated(address indexed newBridge, address indexed oldBridge);

    constructor(address _owner, address _bridge) Ownable(_owner) {
        bridge = FireBridge(_bridge);
    }

    function setBridge(address _bridge) external onlyOwner {
        address oldBridge = address(bridge);
        bridge = FireBridge(_bridge);
        emit BridgeUpdated(_bridge, oldBridge);
    }

    /// Operator methods.

    function confirmMintRequest(bytes32 _hash) external onlyRole(MINT_ROLE) {
        bridge.confirmMintRequest(_hash);
    }

    function confirmBurnRequest(
        bytes32 _hash,
        bytes32 _withdrawalTxid,
        uint256 _outputIndex
    ) external onlyRole(BURN_ROLE) {
        bridge.confirmBurnRequest(_hash, _withdrawalTxid, _outputIndex);
    }

    function confirmCrosschainRequest(
        Request calldata r
    )
        external
        onlyRole(CROSSCHAIN_ROLE)
        returns (bytes32 _hash, Request memory _r)
    {
        (_hash, _r) = bridge.confirmCrosschainRequest(r);
    }

    function batchConfirmCrosschainRequest(
        Request[] calldata rs
    ) external onlyRole(CROSSCHAIN_ROLE) {
        for (uint256 i = 0; i < rs.length; i++) {
            bridge.confirmCrosschainRequest(rs[i]);
        }
    }
}
