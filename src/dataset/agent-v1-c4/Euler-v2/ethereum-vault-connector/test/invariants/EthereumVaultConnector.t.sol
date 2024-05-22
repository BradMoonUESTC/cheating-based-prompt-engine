// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/Set.sol";
import "../../src/interfaces/IERC1271.sol";
import "../evc/EthereumVaultConnectorScribble.sol";

contract VaultMock is IVault {
    IEVC public immutable evc;

    constructor(IEVC _evc) {
        evc = _evc;
    }

    function disableController() public override {}

    function checkAccountStatus(address, address[] memory) external pure override returns (bytes4) {
        return this.checkAccountStatus.selector;
    }

    function checkVaultStatus() external pure override returns (bytes4) {
        return this.checkVaultStatus.selector;
    }

    fallback(bytes calldata) external payable returns (bytes memory) {
        evc.requireAccountStatusCheck(address(0));
        evc.requireVaultStatusCheck();
        return "";
    }

    receive() external payable {}
}

contract SignerMock {
    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4 magicValue) {
        return IERC1271.isValidSignature.selector;
    }
}

contract EthereumVaultConnectorHandler is EthereumVaultConnectorScribble, Test {
    using Set for SetStorage;

    address internal vaultMock;
    address internal signerMock;
    address[] public touchedAccounts;

    constructor() {
        vaultMock = address(new VaultMock(IEVC(address(this))));
        signerMock = address(new SignerMock());
    }

    fallback() external payable {}

    function authenticateCaller(address, bool, bool) internal view override returns (address) {
        return msg.sender;
    }

    function getTouchedAccounts() external view returns (address[] memory) {
        return touchedAccounts;
    }

    function setup(address account, address vault) internal {
        touchedAccounts.push(account);
        vm.etch(vault, vaultMock.code);
    }

    function setLockdownMode(bytes19, bool) public payable override {
        // do nothing here to avoid reverts that will appear when the lockdown mode is on
        return;
    }

    function setPermitDisabledMode(bytes19, bool) public payable override {
        // do nothing here to avoid reverts that will appear when the permit disabled mode is on
        return;
    }

    function setNonce(bytes19 addressPrefix, uint256 nonceNamespace, uint256 nonce) public payable override {
        if (msg.sender == address(this)) return;
        if (nonceLookup[addressPrefix][nonceNamespace] == type(uint256).max) return;
        nonce = nonceLookup[addressPrefix][nonceNamespace] + 1;
        super.setNonce(addressPrefix, nonceNamespace, nonce);
    }

    function setOperator(bytes19 addressPrefix, address operator, uint256 operatorBitField) public payable override {
        if (msg.sender == address(this)) return;
        if (operator == address(0) || operator == address(this)) return;
        if (haveCommonOwnerInternal(msg.sender, operator)) return;
        if (operatorLookup[addressPrefix][operator] == operatorBitField) return;
        super.setOperator(addressPrefix, operator, operatorBitField);
    }

    function setAccountOperator(address account, address operator, bool authorized) public payable override {
        operator = msg.sender;
        if (msg.sender == address(this)) return;
        if (account == address(0)) return;
        if (operator == address(0) || operator == address(this)) return;
        if (haveCommonOwnerInternal(msg.sender, operator)) return;
        if (isAccountOperatorAuthorizedInternal(account, operator) == authorized) return;
        super.setAccountOperator(account, operator, authorized);
    }

    function enableCollateral(address account, address vault) public payable override {
        if (msg.sender == address(this)) return;
        if (haveCommonOwnerInternal(account, msg.sender)) return;
        if (account == address(0)) return;
        if (uint160(vault) <= 10) return;
        if (vault == address(this)) return;
        setup(account, vault);
        super.enableCollateral(account, vault);
    }

    function disableCollateral(address account, address vault) public payable override {
        if (msg.sender == address(this)) return;
        if (haveCommonOwnerInternal(account, msg.sender)) return;
        if (account == address(0)) return;
        if (uint160(vault) <= 10) return;
        if (vault == address(this)) return;
        setup(account, vault);
        super.disableCollateral(account, vault);
    }

    function reorderCollaterals(address account, uint8 index1, uint8 index2) public payable override {
        if (msg.sender == address(this)) return;
        if (haveCommonOwnerInternal(account, msg.sender)) return;
        if (account == address(0)) return;

        if (index1 >= index2 || int256(uint256(index2)) >= int256(uint256(accountCollaterals[account].numElements)) - 2)
        {
            return;
        }

        super.reorderCollaterals(account, index1, index2);
    }

    function enableController(address account, address vault) public payable override {
        if (msg.sender == address(this)) return;
        if (haveCommonOwnerInternal(account, msg.sender)) return;
        if (account == address(0)) return;
        if (uint160(vault) <= 10) return;
        if (vault == address(this)) return;
        setup(account, vault);
        super.enableController(account, vault);
    }

    function disableController(address account) public payable override {
        if (account == address(0) || account == msg.sender || address(this) == msg.sender) return;
        if (uint160(msg.sender) <= 10) return;
        setup(account, msg.sender);
        super.disableController(account);
    }

    function call(
        address targetContract,
        address onBehalfOfAccount,
        uint256,
        bytes calldata data
    ) public payable override returns (bytes memory result) {
        if (haveCommonOwnerInternal(onBehalfOfAccount, msg.sender)) return "";
        if (onBehalfOfAccount == address(0)) return "";
        if (uint160(targetContract) <= 10) return "";
        if (targetContract == address(this)) return "";
        if (bytes4(data) == VaultMock.checkAccountStatus.selector) return "";

        setup(onBehalfOfAccount, targetContract);

        result = super.call(targetContract, onBehalfOfAccount, 0, data);
    }

    function controlCollateral(
        address targetCollateral,
        address onBehalfOfAccount,
        uint256,
        bytes calldata data
    ) public payable override returns (bytes memory result) {
        if (uint160(msg.sender) <= 10 || msg.sender == address(this)) return "";
        if (onBehalfOfAccount == address(0)) return "";
        if (uint160(targetCollateral) <= 10) return "";
        if (targetCollateral == address(this)) return "";
        if (bytes4(data) == VaultMock.checkAccountStatus.selector) return "";

        setup(onBehalfOfAccount, msg.sender);
        accountCollaterals[onBehalfOfAccount].insert(targetCollateral);

        uint8 numElementsCache = accountControllers[onBehalfOfAccount].numElements;
        address firstElementCache = accountControllers[onBehalfOfAccount].firstElement;
        accountControllers[onBehalfOfAccount].numElements = 1;
        accountControllers[onBehalfOfAccount].firstElement = msg.sender;

        result = super.controlCollateral(targetCollateral, onBehalfOfAccount, 0, data);

        accountControllers[onBehalfOfAccount].numElements = numElementsCache;
        accountControllers[onBehalfOfAccount].firstElement = firstElementCache;
    }

    function permit(
        address signer,
        address,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256,
        bytes calldata data,
        bytes calldata signature
    ) public payable override {
        if (uint160(signer) <= 255 || signer == address(this)) return;
        if (nonce == type(uint256).max) return;
        if (data.length == 0 || bytes4(data) == 0) return;
        vm.etch(signer, signerMock.code);
        nonce = nonceLookup[getAddressPrefixInternal(signer)][nonceNamespace];
        deadline = block.timestamp;
        try this.permit(signer, msg.sender, nonceNamespace, nonce, deadline, 0, data, signature) {} catch {}
    }

    function batch(BatchItem[] calldata items) public payable override {
        if (items.length > SET_MAX_ELEMENTS) return;

        for (uint256 i = 0; i < items.length; i++) {
            if (items[i].value > 0) return;
            if (uint160(items[i].targetContract) <= 10) return;
            if (items[i].targetContract == address(this)) return;
            if (bytes4(items[i].data) == VaultMock.checkAccountStatus.selector) return;
        }

        super.batch(items);
    }

    function batchRevert(BatchItem[] calldata) public payable override {
        return;
    }

    function batchSimulation(BatchItem[] calldata)
        public
        payable
        override
        returns (
            BatchItemResult[] memory batchItemsResult,
            StatusCheckResult[] memory accountsStatusCheckResult,
            StatusCheckResult[] memory vaultsStatusCheckResult
        )
    {
        return (new BatchItemResult[](0), new StatusCheckResult[](0), new StatusCheckResult[](0));
    }

    function forgiveAccountStatusCheck(address account) public payable override {
        if (msg.sender == address(0)) return;

        uint8 numElementsCache = accountControllers[account].numElements;
        address firstElementCache = accountControllers[account].firstElement;
        accountControllers[account].numElements = 1;
        accountControllers[account].firstElement = msg.sender;

        super.forgiveAccountStatusCheck(account);

        accountControllers[account].numElements = numElementsCache;
        accountControllers[account].firstElement = firstElementCache;
    }

    function requireAccountStatusCheckInternal(address) internal pure override {
        return;
    }

    function requireVaultStatusCheckInternal(address) internal pure override {
        return;
    }

    function exposeAccountCollaterals(address account) external view returns (uint8, address[] memory) {
        address[] memory result = new address[](SET_MAX_ELEMENTS);

        for (uint256 i = 0; i < SET_MAX_ELEMENTS; i++) {
            if (i == 0) {
                result[i] = accountCollaterals[account].firstElement;
            } else {
                result[i] = accountCollaterals[account].elements[i].value;
            }
        }
        return (accountCollaterals[account].numElements, result);
    }

    function exposeAccountControllers(address account) external view returns (uint8, address[] memory) {
        address[] memory result = new address[](SET_MAX_ELEMENTS);

        for (uint256 i = 0; i < SET_MAX_ELEMENTS; i++) {
            if (i == 0) {
                result[i] = accountControllers[account].firstElement;
            } else {
                result[i] = accountControllers[account].elements[i].value;
            }
        }
        return (accountControllers[account].numElements, result);
    }

    function exposeAccountAndVaultStatusCheck()
        external
        view
        returns (uint8, address[] memory, uint8, address[] memory)
    {
        address[] memory result1 = new address[](SET_MAX_ELEMENTS);
        address[] memory result2 = new address[](SET_MAX_ELEMENTS);

        for (uint256 i = 0; i < SET_MAX_ELEMENTS; i++) {
            if (i == 0) {
                result1[i] = accountStatusChecks.firstElement;
                result2[i] = vaultStatusChecks.firstElement;
            } else {
                result1[i] = accountStatusChecks.elements[i].value;
                result2[i] = vaultStatusChecks.elements[i].value;
            }
        }
        return (accountStatusChecks.numElements, result1, vaultStatusChecks.numElements, result2);
    }
}

contract EthereumVaultConnectorInvariants is Test {
    EthereumVaultConnectorHandler internal evc;

    function setUp() public {
        evc = new EthereumVaultConnectorHandler();

        targetContract(address(evc));
    }

    function invariant_ExecutionContext() external {
        vm.expectRevert(Errors.EVC_OnBehalfOfAccountNotAuthenticated.selector);
        evc.getCurrentOnBehalfOfAccount(address(0));

        assertEq(evc.getRawExecutionContext(), 1 << 200);
        assertEq(evc.areChecksDeferred(), false);
        assertEq(evc.areChecksInProgress(), false);
        assertEq(evc.isControlCollateralInProgress(), false);
        assertEq(evc.isOperatorAuthenticated(), false);
        assertEq(evc.isSimulationInProgress(), false);
    }

    function invariant_AccountAndVaultStatusChecks() external {
        (
            uint8 accountStatusChecksNumElements,
            address[] memory accountStatusChecks,
            uint8 vaultStatusChecksNumElements,
            address[] memory vaultStatusChecks
        ) = evc.exposeAccountAndVaultStatusCheck();

        assertTrue(accountStatusChecksNumElements == 0);
        for (uint256 i = 0; i < accountStatusChecks.length; ++i) {
            assertTrue(accountStatusChecks[i] == address(0));
        }

        assertTrue(vaultStatusChecksNumElements == 0);
        for (uint256 i = 0; i < vaultStatusChecks.length; ++i) {
            assertTrue(vaultStatusChecks[i] == address(0));
        }
    }

    function invariant_ControllersCollaterals() external {
        address[] memory touchedAccounts = evc.getTouchedAccounts();
        for (uint256 i = 0; i < touchedAccounts.length; i++) {
            // controllers
            (uint8 accountControllersNumElements, address[] memory accountControllersArray) =
                evc.exposeAccountControllers(touchedAccounts[i]);

            assertTrue(accountControllersNumElements == 0 || accountControllersNumElements == 1);
            assertTrue(
                (accountControllersNumElements == 0 && accountControllersArray[0] == address(0))
                    || (accountControllersNumElements == 1 && accountControllersArray[0] != address(0))
            );

            for (uint256 j = 1; j < accountControllersArray.length; j++) {
                assertTrue(accountControllersArray[j] == address(0));
            }

            // collaterals
            (uint8 accountCollateralsNumCollaterals, address[] memory accountCollateralsArray) =
                evc.exposeAccountCollaterals(touchedAccounts[i]);

            assertTrue(accountCollateralsNumCollaterals <= SET_MAX_ELEMENTS);
            for (uint256 j = 0; j < accountCollateralsNumCollaterals; j++) {
                assertTrue(accountCollateralsArray[j] != address(0));
            }

            // verify that none entry is duplicated
            for (uint256 j = 1; j < accountCollateralsNumCollaterals; j++) {
                for (uint256 k = 0; k < j; k++) {
                    assertTrue(accountCollateralsArray[j] != accountCollateralsArray[k]);
                }
            }
        }
    }
}
