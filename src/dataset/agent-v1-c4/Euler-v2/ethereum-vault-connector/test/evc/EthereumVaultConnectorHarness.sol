// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "./EthereumVaultConnectorScribble.sol";
import "../utils/mocks/Vault.sol";

// helper contract that allows to set EVC's internal state and overrides original
// EVC functions in order to verify the account and vault checks
contract EthereumVaultConnectorHarness is EthereumVaultConnectorScribble {
    using ExecutionContext for EC;
    using Set for SetStorage;

    address[] internal expectedAccountsChecked;
    address[] internal expectedVaultsChecked;

    function isFuzzSender() internal view returns (bool) {
        // as per https://fuzzing-docs.diligence.tools/getting-started-1/seed-state
        // fuzzer always sends transactions from the EOA while Foundry does it from the test contract
        if (msg.sender.code.length == 0) return true;
        else return false;
    }

    function reset() external {
        delete accountStatusChecks;
        delete vaultStatusChecks;
        delete expectedAccountsChecked;
        delete expectedVaultsChecked;
    }

    function clearExpectedChecks() public {
        delete expectedAccountsChecked;
        delete expectedVaultsChecked;
    }

    function pushExpectedAccountsCheck(address account) external {
        expectedAccountsChecked.push(account);
    }

    function pushExpectedVaultsCheck(address vault) external {
        expectedVaultsChecked.push(vault);
    }

    function getExpectedAccountStatusChecks() external view returns (address[] memory) {
        return expectedAccountsChecked;
    }

    function getExpectedVaultStatusChecks() external view returns (address[] memory) {
        return expectedVaultsChecked;
    }

    function setLockdown(bytes19 addressPrefix, bool enabled) external {
        if (isFuzzSender()) return;

        ownerLookup[addressPrefix].isLockdownMode = enabled;
    }

    function setPermitDisabled(bytes19 addressPrefix, bool enabled) external {
        if (isFuzzSender()) return;

        ownerLookup[addressPrefix].isPermitDisabledMode = enabled;
    }

    function setChecksDeferred(bool deferred) external {
        if (isFuzzSender()) return;

        if (deferred) {
            executionContext = executionContext.setChecksDeferred();
        } else {
            executionContext =
                EC.wrap(EC.unwrap(executionContext) & ~uint256(0xFF0000000000000000000000000000000000000000));
        }
    }

    function setChecksInProgress(bool inProgress) external {
        if (isFuzzSender()) return;

        if (inProgress) {
            executionContext = executionContext.setChecksInProgress();
        } else {
            executionContext =
                EC.wrap(EC.unwrap(executionContext) & ~uint256(0xFF000000000000000000000000000000000000000000));
        }
    }

    function setControlCollateralInProgress(bool inProgress) external {
        if (isFuzzSender()) return;

        if (inProgress) {
            executionContext = executionContext.setControlCollateralInProgress();
        } else {
            executionContext =
                EC.wrap(EC.unwrap(executionContext) & ~uint256(0xFF00000000000000000000000000000000000000000000));
        }
    }

    function setOperatorAuthenticated(bool authenticated) external {
        if (isFuzzSender()) return;

        if (authenticated) {
            executionContext = executionContext.setOperatorAuthenticated();
        } else {
            executionContext = executionContext.clearOperatorAuthenticated();
        }
    }

    function setSimulation(bool inProgress) external {
        if (isFuzzSender()) return;

        if (inProgress) {
            executionContext = executionContext.setSimulationInProgress();
        } else {
            executionContext =
                EC.wrap(EC.unwrap(executionContext) & ~uint256(0xFF000000000000000000000000000000000000000000000000));
        }
    }

    function setOnBehalfOfAccount(address account) external {
        if (isFuzzSender()) return;
        executionContext = executionContext.setOnBehalfOfAccount(account);
    }

    // function overrides in order to verify the account and vault checks
    function requireAccountStatusCheck(address account) public payable override {
        super.requireAccountStatusCheck(account);
        expectedAccountsChecked.push(account);
    }

    function requireVaultStatusCheck() public payable override {
        super.requireVaultStatusCheck();

        expectedVaultsChecked.push(msg.sender);
    }

    function requireAccountAndVaultStatusCheck(address account) public payable override {
        super.requireAccountAndVaultStatusCheck(account);

        expectedAccountsChecked.push(account);
        expectedVaultsChecked.push(msg.sender);
    }

    function requireAccountStatusCheckInternal(address account) internal override {
        super.requireAccountStatusCheckInternal(account);

        address[] memory controllers = accountControllers[account].get();
        if (controllers.length == 1) {
            Vault(controllers[0]).pushAccountStatusChecked(account);
        }
    }

    function requireVaultStatusCheckInternal(address vault) internal override {
        super.requireVaultStatusCheckInternal(vault);

        Vault(vault).pushVaultStatusChecked();
    }

    function verifyVaultStatusChecks() public view {
        for (uint256 i = 0; i < expectedVaultsChecked.length; ++i) {
            require(Vault(expectedVaultsChecked[i]).getVaultStatusChecked().length == 1, "verifyVaultStatusChecks");
        }
    }

    function verifyAccountStatusChecks() public view {
        for (uint256 i = 0; i < expectedAccountsChecked.length; ++i) {
            address[] memory controllers = accountControllers[expectedAccountsChecked[i]].get();
            uint256 lastAccountStatusCheckTimestamp = accountControllers[expectedAccountsChecked[i]].getMetadata();

            require(controllers.length <= 1, "verifyAccountStatusChecks/length");

            if (controllers.length == 0) continue;

            address[] memory accounts = Vault(controllers[0]).getAccountStatusChecked();

            uint256 counter = 0;
            for (uint256 j = 0; j < accounts.length; ++j) {
                if (accounts[j] == expectedAccountsChecked[i]) counter++;
            }

            require(counter == 1, "verifyAccountStatusChecks/counter");
            require(lastAccountStatusCheckTimestamp == block.timestamp, "verifyAccountStatusChecks/timestamp");
        }
    }
}
