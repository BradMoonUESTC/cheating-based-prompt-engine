// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Base Contracts
import {HandlerAggregator} from "../HandlerAggregator.t.sol";

/// @title LiquidationModuleInvariants
/// @notice Implements Invariants for the liquidation module
/// @dev Inherits HandlerAggregator for checking actions in assertion testing mode
abstract contract LiquidationModuleInvariants is HandlerAggregator {}
