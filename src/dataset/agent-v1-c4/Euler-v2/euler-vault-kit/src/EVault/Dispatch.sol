// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Base} from "./shared/Base.sol";

import {TokenModule} from "./modules/Token.sol";
import {VaultModule} from "./modules/Vault.sol";
import {BorrowingModule} from "./modules/Borrowing.sol";
import {LiquidationModule} from "./modules/Liquidation.sol";
import {InitializeModule} from "./modules/Initialize.sol";
import {BalanceForwarderModule} from "./modules/BalanceForwarder.sol";
import {GovernanceModule} from "./modules/Governance.sol";
import {RiskManagerModule} from "./modules/RiskManager.sol";

import {AddressUtils} from "./shared/lib/AddressUtils.sol";
import "./shared/Constants.sol";

/// @title Dispatch
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Contract which ties in the EVault modules and provides utilities for routing calls to modules and the EVC
abstract contract Dispatch is
    InitializeModule,
    TokenModule,
    VaultModule,
    BorrowingModule,
    LiquidationModule,
    RiskManagerModule,
    BalanceForwarderModule,
    GovernanceModule
{
    /// @notice Address of the Initialize module
    address public immutable MODULE_INITIALIZE;
    /// @notice Address of the Token module
    address public immutable MODULE_TOKEN;
    /// @notice Address of the Vault module
    address public immutable MODULE_VAULT;
    /// @notice Address of the Borrowing module
    address public immutable MODULE_BORROWING;
    /// @notice Address of the Liquidation module
    address public immutable MODULE_LIQUIDATION;
    /// @notice Address of the RiskManager module
    address public immutable MODULE_RISKMANAGER;
    /// @notice Address of the BalanceForwarder module
    address public immutable MODULE_BALANCE_FORWARDER;
    /// @notice Address of the Governance module
    address public immutable MODULE_GOVERNANCE;

    /// @title DeployedModules
    /// @notice This struct is used to pass in the addresses of EVault modules during deployment
    struct DeployedModules {
        address initialize;
        address token;
        address vault;
        address borrowing;
        address liquidation;
        address riskManager;
        address balanceForwarder;
        address governance;
    }

    constructor(Integrations memory integrations, DeployedModules memory modules) Base(integrations) {
        MODULE_INITIALIZE = AddressUtils.checkContract(modules.initialize);
        MODULE_TOKEN = AddressUtils.checkContract(modules.token);
        MODULE_VAULT = AddressUtils.checkContract(modules.vault);
        MODULE_BORROWING = AddressUtils.checkContract(modules.borrowing);
        MODULE_LIQUIDATION = AddressUtils.checkContract(modules.liquidation);
        MODULE_RISKMANAGER = AddressUtils.checkContract(modules.riskManager);
        MODULE_BALANCE_FORWARDER = AddressUtils.checkContract(modules.balanceForwarder);
        MODULE_GOVERNANCE = AddressUtils.checkContract(modules.governance);
    }

    // Modifier proxies the function call to a module and low-level returns the result
    modifier use(address module) {
        _; // when using the modifier, it is assumed the function body is empty.
        delegateToModule(module);
    }

    // Delegate call can't be used in a view function. To work around this limitation,
    // static call `this.viewDelegate()` function, which in turn will delegate the payload to a module.
    modifier useView(address module) {
        _; // when using the modifier, it is assumed the function body is empty.
        delegateToModuleView(module);
    }

    // Modifier ensures, that the body of the function is always executed from the EVC call.
    // It is accomplished by intercepting calls incoming directly to the vault and passing them
    // to the EVC.call function. EVC calls the vault back with original calldata. As a result, the account
    // and vault status checks are always executed in the checks deferral frame, at the end of the call,
    // outside of the vault's re-entrancy protections.
    // The modifier is applied to all functions which schedule account or vault status checks.
    modifier callThroughEVC() {
        if (msg.sender == address(evc)) {
            _;
        } else {
            callThroughEVCInternal();
        }
    }

    // External function which is only callable by the EVault itself. Its purpose is to be static called by
    // `delegateToModuleView` which allows view functions to be implemented in modules, even though delegatecall cannot
    // be directly used within view functions.
    function viewDelegate() external payable {
        if (msg.sender != address(this)) revert E_Unauthorized();

        assembly {
            let size := sub(calldatasize(), 36)
            calldatacopy(0, 36, size)
            let result := delegatecall(gas(), calldataload(4), 0, size, 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    function delegateToModule(address module) private {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), module, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    function delegateToModuleView(address module) private view {
        assembly {
            // Construct optimized custom call data for `this.viewDelegate()`
            // [selector 4B][module address 32B][calldata with stripped proxy metadata][caller address 20B]
            // Proxy metadata will be appended back by the proxy on staticcall
            mstore(0, 0x1fe8b95300000000000000000000000000000000000000000000000000000000)
            let strippedCalldataSize := sub(calldatasize(), PROXY_METADATA_LENGTH)
            // we do the mstore first offset by -12 so the 20 address bytes align right behind 36 + strippedCalldataSize
            // note that it can write into the module address if the calldata is less than 12 bytes, therefore write
            // before we write module
            mstore(add(24, strippedCalldataSize), caller())
            mstore(4, module)
            calldatacopy(36, 0, strippedCalldataSize)
            // insize: stripped calldatasize + 36 (signature and module address) + 20 (caller address)
            let result := staticcall(gas(), address(), 0, add(strippedCalldataSize, 56), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    function callThroughEVCInternal() private {
        address _evc = address(evc);
        assembly {
            let mainCalldataLength := sub(calldatasize(), PROXY_METADATA_LENGTH)

            mstore(0, 0x1f8b521500000000000000000000000000000000000000000000000000000000) // EVC.call signature
            mstore(4, address()) // EVC.call 1st argument - address(this)
            mstore(36, caller()) // EVC.call 2nd argument - msg.sender
            mstore(68, callvalue()) // EVC.call 3rd argument - msg.value
            mstore(100, 128) // EVC.call 4th argument - msg.data, offset to the start of encoding - 128 bytes
            mstore(132, mainCalldataLength) // msg.data length without proxy metadata
            calldatacopy(164, 0, mainCalldataLength) // original calldata

            // abi encoded bytes array should be zero padded so its length is a multiple of 32
            // store zero word after msg.data bytes and round up mainCalldataLength to nearest multiple of 32
            mstore(add(164, mainCalldataLength), 0)
            let result := call(gas(), _evc, callvalue(), 0, add(164, and(add(mainCalldataLength, 31), not(31))), 0, 0)

            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(64, sub(returndatasize(), 64)) } // strip bytes encoding from call return
        }
    }
}
