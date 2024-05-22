// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../src/EthereumVaultConnector.sol";
import "../../src/ExecutionContext.sol";
import "../../src/Set.sol";

contract EthereumVaultConnectorHarness is EthereumVaultConnector {
    using ExecutionContext for EC;
    using Set for SetStorage;

    function getExecutionContextDefault() external view returns (uint256) {
        return 1 << ExecutionContext.STAMP_OFFSET;
    }

    function getExecutionContextAreChecksDeferred() external view returns (bool) {
        return executionContext.areChecksDeferred();
    }
    
    function numOfController(address account) public view returns (uint8) {
        return accountControllers[account].numElements;
    }
    function getAccountController(address account) public view returns (address) {
        return accountControllers[account].firstElement;
    }
    function accountCollateralsContains(address account, address collateral) public view returns (bool) {
        return accountCollaterals[account].contains(collateral);
    }

    function getExecutionContextOnBehalfOfAccount() external view returns (address) {
        return executionContext.getOnBehalfOfAccount();
    }

    function getOwnerOf(bytes19 prefix) public view returns (address) {
        return ownerLookup[prefix].owner;
    }

    function checkAccountStatus(address account) public returns (bool) {
        (bool status, ) = checkAccountStatusInternal(account);
        return status;
    }

    function requireAccountStatusCheckInternalHarness(address account) public {
        requireAccountStatusCheckInternal(account);
    }
    function checkVaultStatus(address vault) public returns (bool) {
        (bool isValid, ) = checkVaultStatusInternal(vault);
        return isValid;
    }
    function areAccountStatusChecksEmpty() public view returns (bool) {
        return accountStatusChecks.numElements == 0;
    }

    function areVaultStatusChecksEmpty() public view returns (bool) {
        return vaultStatusChecks.numElements == 0;
    }
    
    function getOperatorFromAddress(address account, address operator) external view returns (uint256) {
        bytes19 addressPrefix = getAddressPrefixInternal(account);
        return operatorLookup[addressPrefix][operator];
    }

    function getAccountCollaterals(address account) external view returns (address[] memory) {
        return accountCollaterals[account].get();
    }

    function isAccountController(address account, address controller) public view returns (bool) {
        return accountControllers[account].contains(controller);
    }

    function containsStatusCheckFor(address account) public view returns (bool) {
        return accountStatusChecks.contains(account);
    }
    
    function selfCallSuccessCheck(uint256 value, bytes calldata data) external returns (bool) {
        (bool success, ) = address(this).call{value: value}(data);
        return success;
    }
    function ecGetOnBehalfOfAccount(EC context) external pure returns (address result) {
        result = ExecutionContext.getOnBehalfOfAccount(context);
    }
}
