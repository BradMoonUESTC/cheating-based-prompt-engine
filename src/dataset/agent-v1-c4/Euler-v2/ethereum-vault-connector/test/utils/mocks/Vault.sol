// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "./Target.sol";
import "../../../src/interfaces/IVault.sol";

// mock vault contract that implements required interface and helps with status checks verification
contract Vault is IVault, Target {
    IEVC public immutable evc;

    uint256 internal vaultStatusState;
    uint256 internal accountStatusState;

    bool[] internal vaultStatusChecked;
    address[] internal accountStatusChecked;

    constructor(IEVC _evc) {
        evc = _evc;
    }

    function reset() external {
        vaultStatusState = 0;
        accountStatusState = 0;
        delete vaultStatusChecked;
        delete accountStatusChecked;
    }

    function clearChecks() external {
        delete vaultStatusChecked;
        delete accountStatusChecked;
    }

    function setVaultStatusState(uint256 state) external {
        vaultStatusState = state;
    }

    function setAccountStatusState(uint256 state) external {
        accountStatusState = state;
    }

    function pushVaultStatusChecked() external {
        vaultStatusChecked.push(true);
    }

    function pushAccountStatusChecked(address account) external {
        accountStatusChecked.push(account);
    }

    function getVaultStatusChecked() external view returns (bool[] memory) {
        return vaultStatusChecked;
    }

    function getAccountStatusChecked() external view returns (address[] memory) {
        return accountStatusChecked;
    }

    function disableController() external virtual override {
        address msgSender = msg.sender;
        if (msgSender == address(evc)) {
            (address onBehalfOfAccount,) = evc.getCurrentOnBehalfOfAccount(address(0));
            msgSender = onBehalfOfAccount;
        }

        evc.disableController(msgSender);
    }

    function checkVaultStatus() external virtual override returns (bytes4 magicValue) {
        try evc.getCurrentOnBehalfOfAccount(address(0)) {
            revert("cvs/on-behalf-of-account");
        } catch (bytes memory reason) {
            if (bytes4(reason) != Errors.EVC_OnBehalfOfAccountNotAuthenticated.selector) {
                revert("cvs/on-behalf-of-account-2");
            }
        }
        try evc.getLastAccountStatusCheckTimestamp(address(0)) {
            revert("cvs/last-account-status-check-timestamp");
        } catch (bytes memory reason) {
            if (bytes4(reason) != Errors.EVC_ChecksReentrancy.selector) {
                revert("cvs/last-account-status-check-timestamp-2");
            }
        }
        require(evc.areChecksInProgress(), "cvs/checks-not-in-progress");

        if (vaultStatusState == 0) {
            return 0x4b3d1223;
        } else if (vaultStatusState == 1) {
            revert("vault status violation");
        } else {
            return bytes4(uint32(1));
        }
    }

    function checkAccountStatus(address, address[] memory) external virtual override returns (bytes4 magicValue) {
        try evc.getCurrentOnBehalfOfAccount(address(0)) {
            revert("cas/on-behalf-of-account");
        } catch (bytes memory reason) {
            if (bytes4(reason) != Errors.EVC_OnBehalfOfAccountNotAuthenticated.selector) {
                revert("cas/on-behalf-of-account-2");
            }
        }
        try evc.getLastAccountStatusCheckTimestamp(address(0)) {
            revert("cas/last-account-status-check-timestamp");
        } catch (bytes memory reason) {
            if (bytes4(reason) != Errors.EVC_ChecksReentrancy.selector) {
                revert("cas/last-account-status-check-timestamp-2");
            }
        }
        require(evc.areChecksInProgress(), "cas/checks-not-in-progress");

        if (accountStatusState == 0) {
            return 0xb168c58f;
        } else if (accountStatusState == 1) {
            revert("account status violation");
        } else {
            return bytes4(uint32(2));
        }
    }

    function requireChecks(address account) external payable {
        evc.requireAccountAndVaultStatusCheck(account);
    }

    function requireChecksWithSimulationCheck(address account, bool expectedSimulationInProgress) external payable {
        require(
            evc.isSimulationInProgress() == expectedSimulationInProgress, "requireChecksWithSimulationCheck/simulation"
        );

        evc.requireAccountAndVaultStatusCheck(account);
    }

    function call(address target, bytes memory data) external payable virtual {
        (bool success,) = target.call{value: msg.value}(data);
        require(success, "call/failed");
    }
}

contract VaultMalicious is Vault {
    bytes4 internal expectedErrorSelector;

    constructor(IEVC _evc) Vault(_evc) {}

    function setExpectedErrorSelector(bytes4 selector) external {
        expectedErrorSelector = selector;
    }

    function callBatch() external payable {
        (bool success, bytes memory result) =
            address(evc).call(abi.encodeWithSelector(evc.batch.selector, new IEVC.BatchItem[](0)));

        require(!success, "callBatch/succeeded");
        if (bytes4(result) == expectedErrorSelector) {
            revert("callBatch/expected-error");
        }
    }

    function checkVaultStatus() external virtual override returns (bytes4) {
        try evc.getCurrentOnBehalfOfAccount(address(0)) {
            revert("cvs/on-behalf-of-account");
        } catch (bytes memory reason) {
            if (bytes4(reason) != Errors.EVC_OnBehalfOfAccountNotAuthenticated.selector) {
                revert("cvs/on-behalf-of-account-2");
            }
        }
        try evc.getLastAccountStatusCheckTimestamp(address(0)) {
            revert("cvs/last-account-status-check-timestamp");
        } catch (bytes memory reason) {
            if (bytes4(reason) != Errors.EVC_ChecksReentrancy.selector) {
                revert("cvs/last-account-status-check-timestamp-2");
            }
        }
        require(evc.areChecksInProgress(), "cvs/checks-not-in-progress");

        if (expectedErrorSelector == 0) {
            return this.checkVaultStatus.selector;
        }

        (bool success, bytes memory result) =
            address(evc).call(abi.encodeWithSelector(evc.batch.selector, new IEVC.BatchItem[](0)));

        if (success || bytes4(result) != expectedErrorSelector) {
            return this.checkVaultStatus.selector;
        }

        revert("malicious vault");
    }

    function checkAccountStatus(address, address[] memory) external override returns (bytes4) {
        try evc.getCurrentOnBehalfOfAccount(address(0)) {
            revert("cas/on-behalf-of-account");
        } catch (bytes memory reason) {
            if (bytes4(reason) != Errors.EVC_OnBehalfOfAccountNotAuthenticated.selector) {
                revert("cas/on-behalf-of-account-2");
            }
        }
        try evc.getLastAccountStatusCheckTimestamp(address(0)) {
            revert("cas/last-account-status-check-timestamp");
        } catch (bytes memory reason) {
            if (bytes4(reason) != Errors.EVC_ChecksReentrancy.selector) {
                revert("cas/last-account-status-check-timestamp-2");
            }
        }
        require(evc.areChecksInProgress(), "cas/checks-not-in-progress");

        if (expectedErrorSelector == 0) {
            return this.checkAccountStatus.selector;
        }

        (bool success, bytes memory result) =
            address(evc).call(abi.encodeWithSelector(evc.batch.selector, new IEVC.BatchItem[](0)));

        if (success || bytes4(result) != expectedErrorSelector) {
            return this.checkAccountStatus.selector;
        }

        revert("malicious vault");
    }
}
