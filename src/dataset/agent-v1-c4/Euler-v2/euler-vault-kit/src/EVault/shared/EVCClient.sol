// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Storage} from "./Storage.sol";
import {Events} from "./Events.sol";
import {Errors} from "./Errors.sol";
import {ProxyUtils} from "./lib/ProxyUtils.sol";
import {AddressUtils} from "./lib/AddressUtils.sol";

import "./Constants.sol";

import {IERC20} from "../IEVault.sol";
import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";

/// @title EVCClient
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Utilities for interacting with the EVC (Ethereum Vault Connector)
abstract contract EVCClient is Storage, Events, Errors {
    IEVC internal immutable evc;

    modifier onlyEVCChecks() {
        if (msg.sender != address(evc) || !evc.areChecksInProgress()) {
            revert E_CheckUnauthorized();
        }

        _;
    }

    constructor(address _evc) {
        evc = IEVC(AddressUtils.checkContract(_evc));
    }

    function disableControllerInternal(address account) internal virtual {
        evc.disableController(account);
    }

    // Authenticate the account and the controller, making sure the call is made through EVC and the status checks are
    // deferred
    function EVCAuthenticateDeferred(bool checkController) internal view virtual returns (address) {
        assert(msg.sender == address(evc)); // this ensures that callThroughEVC modifier was utilized

        (address onBehalfOfAccount, bool controllerEnabled) =
            evc.getCurrentOnBehalfOfAccount(checkController ? address(this) : address(0));

        if (checkController && !controllerEnabled) revert E_ControllerDisabled();

        return onBehalfOfAccount;
    }

    // Authenticate the account
    function EVCAuthenticate() internal view virtual returns (address) {
        if (msg.sender == address(evc)) {
            (address onBehalfOfAccount,) = evc.getCurrentOnBehalfOfAccount(address(0));

            return onBehalfOfAccount;
        }
        return msg.sender;
    }

    // Authenticate the governor, making sure neither a sub-account nor operator is used. Prohibit the use of control
    // collateral
    function EVCAuthenticateGovernor() internal view virtual returns (address) {
        if (msg.sender == address(evc)) {
            (address onBehalfOfAccount,) = evc.getCurrentOnBehalfOfAccount(address(0));

            if (
                isKnownNonOwnerAccount(onBehalfOfAccount) || evc.isOperatorAuthenticated()
                    || evc.isControlCollateralInProgress()
            ) {
                revert E_Unauthorized();
            }

            return onBehalfOfAccount;
        }
        return msg.sender;
    }

    // Checks if the account is known to EVC to be a non-owner sub-account.
    // Assets that are not EVC integrated should not be sent to those accounts,
    // as there will be no way to transfer them out.
    function isKnownNonOwnerAccount(address account) internal view returns (bool) {
        address owner = evc.getAccountOwner(account);
        return owner != address(0) && owner != account;
    }

    function EVCRequireStatusChecks(address account) internal virtual {
        assert(account != CHECKACCOUNT_CALLER); // the special value should be resolved by now

        if (account == CHECKACCOUNT_NONE) {
            evc.requireVaultStatusCheck();
        } else {
            evc.requireAccountAndVaultStatusCheck(account);
        }
    }

    function enforceCollateralTransfer(address collateral, uint256 amount, address from, address receiver)
        internal
        virtual
    {
        evc.controlCollateral(collateral, from, 0, abi.encodeCall(IERC20.transfer, (receiver, amount)));
    }

    function forgiveAccountStatusCheck(address account) internal virtual {
        evc.forgiveAccountStatusCheck(account);
    }

    function hasAnyControllerEnabled(address account) internal view returns (bool) {
        return evc.getControllers(account).length > 0;
    }

    function getCollaterals(address account) internal view returns (address[] memory) {
        return evc.getCollaterals(account);
    }

    function isCollateralEnabled(address account, address collateral) internal view returns (bool) {
        return evc.isCollateralEnabled(account, collateral);
    }

    function isAccountStatusCheckDeferred(address account) internal view returns (bool) {
        return evc.isAccountStatusCheckDeferred(account);
    }

    function isVaultStatusCheckDeferred() internal view returns (bool) {
        return evc.isVaultStatusCheckDeferred(address(this));
    }

    function isControlCollateralInProgress() internal view returns (bool) {
        return evc.isControlCollateralInProgress();
    }

    function getLastAccountStatusCheckTimestamp(address account) internal view returns (uint256) {
        return evc.getLastAccountStatusCheckTimestamp(account);
    }

    function validateController(address account) internal view {
        address[] memory controllers = evc.getControllers(account);

        if (controllers.length > 1) revert E_TransientState();
        if (controllers.length == 0) revert E_NoLiability();
        if (controllers[0] != address(this)) revert E_NotController();
    }
}
