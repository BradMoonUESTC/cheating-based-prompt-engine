// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "../../../src/EthereumVaultConnector.sol";

// mock target contract that allows to test call() and controlCollateral() functions of the EVC
contract Target {
    function callTest(
        address evc,
        address msgSender,
        uint256 value,
        address onBehalfOfAccount,
        bool operatorAuthenticated
    ) external payable returns (uint256) {
        try IEVC(evc).getCurrentOnBehalfOfAccount(address(0)) returns (address _onBehalfOfAccount, bool) {
            require(_onBehalfOfAccount == onBehalfOfAccount, "ct/invalid-on-behalf-of-account");
        } catch {
            require(onBehalfOfAccount == address(0), "ct/invalid-on-behalf-of-account-2");
        }
        require(msg.sender == msgSender, "ct/invalid-sender");
        require(msg.value == value, "ct/invalid-msg-value");
        require(IEVC(evc).areChecksDeferred(), "ct/invalid-checks-deferred");
        require(!IEVC(evc).areChecksInProgress(), "ct/checks-lock");
        require(!IEVC(evc).isControlCollateralInProgress(), "ct/controlCollateral-lock");
        require(
            operatorAuthenticated ? IEVC(evc).isOperatorAuthenticated() : !IEVC(evc).isOperatorAuthenticated(),
            "ct/operator-authenticated"
        );

        IEVC(evc).requireAccountStatusCheck(onBehalfOfAccount);
        require(IEVC(evc).isAccountStatusCheckDeferred(onBehalfOfAccount), "ct/account-status-checks-not-deferred");
        return msg.value;
    }

    function controlCollateralTest(
        address evc,
        address msgSender,
        uint256 value,
        address onBehalfOfAccount
    ) external payable returns (uint256) {
        try IEVC(evc).getCurrentOnBehalfOfAccount(address(0)) returns (address _onBehalfOfAccount, bool) {
            require(_onBehalfOfAccount == onBehalfOfAccount, "it/invalid-on-behalf-of-account");
        } catch {
            require(onBehalfOfAccount == address(0), "it/invalid-on-behalf-of-account-2");
        }
        require(msg.sender == msgSender, "it/invalid-sender");
        require(msg.value == value, "it/invalid-msg-value");
        require(IEVC(evc).areChecksDeferred(), "it/invalid-checks-deferred");
        require(!IEVC(evc).areChecksInProgress(), "it/checks-lock");
        require(IEVC(evc).isControlCollateralInProgress(), "it/controlCollateral-lock");

        IEVC(evc).requireAccountStatusCheck(onBehalfOfAccount);
        require(IEVC(evc).isAccountStatusCheckDeferred(onBehalfOfAccount), "it/account-status-checks-not-deferred");

        return msg.value;
    }

    function callbackTest(
        address evc,
        address msgSender,
        uint256 value,
        address onBehalfOfAccount
    ) external payable returns (uint256) {
        try IEVC(evc).getCurrentOnBehalfOfAccount(address(0)) returns (address _onBehalfOfAccount, bool) {
            require(_onBehalfOfAccount == onBehalfOfAccount, "cbt/invalid-on-behalf-of-account");
        } catch {
            require(onBehalfOfAccount == address(0), "cbt/invalid-on-behalf-of-account-2");
        }
        require(msg.sender == msgSender, "cbt/invalid-sender");
        require(msg.value == value, "ct/invalid-msg-value");
        require(IEVC(evc).areChecksDeferred(), "cbt/invalid-checks-deferred");

        require(!IEVC(evc).areChecksInProgress(), "cbt/controlCollateral-lock");
        require(!IEVC(evc).isControlCollateralInProgress(), "cbt/controlCollateral-lock");
        require(!IEVC(evc).isOperatorAuthenticated(), "cbt/operator-authenticated");

        IEVC(evc).requireAccountStatusCheck(onBehalfOfAccount);
        require(IEVC(evc).isAccountStatusCheckDeferred(onBehalfOfAccount), "cbt/account-status-checks-not-deferred");
        return msg.value;
    }

    function revertEmptyTest() external pure {
        revert();
    }
}

contract TargetWithNesting {
    function nestedCallTest(
        address evc,
        address msgSender,
        address targetContract,
        uint256 value,
        address onBehalfOfAccount,
        bool operatorAuthenticated
    ) external payable returns (uint256) {
        try IEVC(evc).getCurrentOnBehalfOfAccount(address(0)) returns (address _onBehalfOfAccount, bool) {
            require(_onBehalfOfAccount == onBehalfOfAccount, "nct/invalid-on-behalf-of-account");
        } catch {
            require(onBehalfOfAccount == address(0), "nct/invalid-on-behalf-of-account-2");
        }
        require(msg.sender == msgSender, "nct/invalid-sender");
        require(msg.value == value, "nct/invalid-msg-value");
        require(IEVC(evc).areChecksDeferred(), "nct/invalid-checks-deferred");
        require(!IEVC(evc).areChecksInProgress(), "nct/checks-lock");
        require(!IEVC(evc).isControlCollateralInProgress(), "nct/controlCollateral-lock");
        require(
            operatorAuthenticated ? IEVC(evc).isOperatorAuthenticated() : !IEVC(evc).isOperatorAuthenticated(),
            "nct/operator-authenticated"
        );

        bytes memory result = IEVC(evc).call(
            targetContract,
            address(this),
            0,
            abi.encodeWithSelector(Target.callTest.selector, evc, evc, 0, address(this), false, false)
        );
        require(abi.decode(result, (uint256)) == 0, "nct/result");

        try IEVC(evc).getCurrentOnBehalfOfAccount(address(0)) returns (address _onBehalfOfAccount, bool) {
            require(_onBehalfOfAccount == onBehalfOfAccount, "nct/invalid-on-behalf-of-account-3");
        } catch {
            require(onBehalfOfAccount == address(0), "nct/invalid-on-behalf-of-account-4");
        }
        require(IEVC(evc).areChecksDeferred(), "nct/invalid-checks-deferred-2");
        require(!IEVC(evc).isControlCollateralInProgress(), "nct/controlCollateral-lock-2");
        require(
            operatorAuthenticated ? IEVC(evc).isOperatorAuthenticated() : !IEVC(evc).isOperatorAuthenticated(),
            "nct/operator-authenticated-2"
        );

        return msg.value;
    }
}
