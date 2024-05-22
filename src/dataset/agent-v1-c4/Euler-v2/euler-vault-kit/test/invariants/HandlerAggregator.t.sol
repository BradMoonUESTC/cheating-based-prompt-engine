// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Modules Handler Contracts
import {VaultModuleHandler} from "./handlers/modules/VaultModuleHandler.t.sol";
import {BorrowingModuleHandler} from "./handlers/modules/BorrowingModuleHandler.t.sol";
import {LiquidationModuleHandler} from "./handlers/modules/LiquidationModuleHandler.t.sol";
import {EVCHandler} from "./handlers/external/EVCHandler.t.sol";
import {TokenModuleHandler} from "./handlers/modules/TokenModuleHandler.t.sol";
import {RiskManagerModuleHandler} from "./handlers/modules/RiskManagerModuleHandler.t.sol";
import {BalanceForwarderModuleHandler} from "./handlers/modules/BalanceForwarderModuleHandler.t.sol";
import {GovernanceModuleHandler} from "./handlers/modules/GovernanceModuleHandler.t.sol";

// Simulators
import {DonationAttackHandler} from "./handlers/simulators/DonationAttackHandler.t.sol";
import {FlashLoanHandler} from "./handlers/simulators/FlashLoanHandler.t.sol";
import {IRMHandler} from "./handlers/simulators/IRMHandler.t.sol";
import {PriceOracleHandler} from "./handlers/simulators/PriceOracleHandler.t.sol";

/// @notice Helper contract to aggregate all handler contracts, inherited in BaseInvariants
abstract contract HandlerAggregator is
    TokenModuleHandler, // Module handlers
    VaultModuleHandler,
    BorrowingModuleHandler,
    LiquidationModuleHandler,
    RiskManagerModuleHandler,
    BalanceForwarderModuleHandler,
    GovernanceModuleHandler,
    EVCHandler, // EVC handler
    DonationAttackHandler, // Simulator handlers
    FlashLoanHandler,
    IRMHandler,
    PriceOracleHandler
{
    /// @notice Helper function in case any handler requires additional setup
    function _setUpHandlers() internal {}
}
