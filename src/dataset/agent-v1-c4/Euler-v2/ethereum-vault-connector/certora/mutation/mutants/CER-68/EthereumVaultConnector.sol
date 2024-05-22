// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "./Set.sol";
import "./Events.sol";
import "./Errors.sol";
import "./TransientStorage.sol";
import "./interfaces/IEthereumVaultConnector.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IERC1271.sol";

/// @title EthereumVaultConnector
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This contract implements the Ethereum Vault Connector.
contract EthereumVaultConnector is Events, Errors, TransientStorage, IEVC {
    using ExecutionContext for EC;
    using Set for SetStorage;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       CONSTANTS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string public constant name = "Ethereum Vault Connector";
    string public constant version = "1";

    bytes32 internal constant HASHED_NAME = keccak256(bytes(name));
    bytes32 internal constant HASHED_VERSION = keccak256(bytes(version));

    bytes32 internal constant PERMIT_TYPEHASH = keccak256(
        "Permit(address signer,uint256 nonceNamespace,uint256 nonce,uint256 deadline,uint256 value,bytes data)"
    );

    bytes32 internal constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    uint256 internal immutable CACHED_CHAIN_ID;
    bytes32 internal immutable CACHED_DOMAIN_SEPARATOR;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        STORAGE                                            //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // EVC implements controller isolation, meaning that unless in transient state, only one controller per account can
    // be enabled. However, this can lead to a suboptimal user experience. In the event a user wants to have multiple
    // controllers enabled, a separate wallet must be created and funded. Although there is nothing wrong with having
    // many accounts within the same wallet, this can be a bad experience. In order to improve on this, EVC supports
    // the concept of an owner that owns 256 accounts within EVC.

    // Every Ethereum address has 256 accounts in the EVC (including the primary account - called the owner).
    // Each account has an account ID from 0-255, where 0 is the owner account's ID. In order to compute the account
    // addresses, the account ID is treated as a uint256 and XORed (exclusive ORed) with the Ethereum address.
    // In order to record the owner of a group of 256 accounts, the EVC uses a definition of an address prefix.
    // An address prefix is a part of an address having the first 19 bytes common with any of the 256 account
    // addresses belonging to the same group.
    // account/152 -> prefix/152
    // To get an address prefix for the account, it's enough to take the account address and right shift it by 8 bits.

    // Yes, this reduces the security of addresses by 8 bits, but creating multiple addresses in the wallet also reduces
    // security: if somebody is trying to brute-force one of user's N>1 private keys, they have N times as many chances
    // of succeeding per guess. It has to be admitted that the EVC model is weaker because finding a private key for
    // an owner gives access to all accounts, but there is still a very comfortable security margin.

    mapping(bytes19 addressPrefix => address owner) internal ownerLookup;

    mapping(bytes19 addressPrefix => mapping(address operator => uint256 operatorBitField)) internal operatorLookup;

    mapping(bytes19 addressPrefix => mapping(uint256 nonceNamespace => uint256 nonce)) internal nonceLookup;

    mapping(address account => SetStorage) internal accountCollaterals;

    mapping(address account => SetStorage) internal accountControllers;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                CONSTRUCTOR, FALLBACKS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    constructor() {
        CACHED_CHAIN_ID = block.chainid;
        CACHED_DOMAIN_SEPARATOR = calculateDomainSeparator();
    }

    receive() external payable {}

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       MODIFIERS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice A modifier that allows only the address recorded as an owner of the address prefix to call the function.
    /// @dev The owner of an address prefix is an address that matches the address that has previously been recorded (or
    /// will be) as an owner in the ownerLookup. In case of the self-call in the permit() function, the EVC address
    /// becomes msg.sender hence the "true" caller address (that is permit message signer) is taken from the execution
    /// context via _msgSender() function.
    /// @param addressPrefix The address prefix for which it is checked whether the caller is the owner.
    modifier onlyOwner(bytes19 addressPrefix) {
        // calculate a phantom address from the address prefix which can be used as an input to the authenticateCaller()
        // function
        address phantomAccount = address(uint160(uint152(addressPrefix)) << 8);
        authenticateCaller(phantomAccount, false);

        _;
    }

    /// @notice A modifier that allows only the owner or an operator of the account to call the function.
    /// @dev The owner of an address prefix is an address that matches the address that has previously been recorded (or
    /// will be) as an owner in the ownerLookup. An operator of an account is an address that has been authorized by the
    /// owner of an account to perform operations on behalf of the owner. In case of the self-call in the permit()
    /// function, the EVC address becomes msg.sender hence the "true" caller address (that is permit message signer) is
    /// taken from the execution context via _msgSender() function.
    /// @param account The address of the account for which it is checked whether the caller is the owner or an
    /// operator.
    modifier onlyOwnerOrOperator(address account) {
        authenticateCaller(account, true);

        _;
    }

    /// @notice A modifier checks whether msg.sender is the only controller for the account.
    /// @dev The controller cannot use permit() function in conjunction with this modifier.
    modifier onlyController(address account) {
        {
            uint256 numOfControllers = accountControllers[account].numElements;
            address controller = accountControllers[account].firstElement;

            if (numOfControllers != 1) {
                revert EVC_ControllerViolation();
            }

            if (controller != msg.sender) {
                revert EVC_NotAuthorized();
            }
        }

        _;
    }

    /// @notice A modifier that verifies whether account or vault status checks are re-entered as well as checks for
    /// controlCollateral re-entrancy.
    modifier nonReentrantChecksAndControlCollateral() {
        {
            EC context = executionContext;

            if (context.areChecksInProgress()) {
                revert EVC_ChecksReentrancy();
            }

            if (context.isControlCollateralInProgress()) {
                revert EVC_ControlCollateralReentrancy();
            }
        }

        _;
    }

    /// @notice A modifier that verifies whether account or vault status checks are re-entered and sets the lock.
    /// @dev This modifier also clears the current account on behalf of which the operation is performed as it shouldn't
    /// be relied upon when the checks are in progress.
    modifier nonReentrantChecks() virtual {
        EC contextCache = executionContext;

        if (contextCache.areChecksInProgress()) {
            revert EVC_ChecksReentrancy();
        }

        executionContext = contextCache.setChecksInProgress().setOnBehalfOfAccount(address(0));

        _;

        executionContext = contextCache;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   PUBLIC FUNCTIONS                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // Execution internals

    /// @inheritdoc IEVC
    function getRawExecutionContext() external view returns (uint256 context) {
        context = EC.unwrap(executionContext);
    }

    /// @inheritdoc IEVC
    function getCurrentOnBehalfOfAccount(address controllerToCheck)
        public
        view
        returns (address onBehalfOfAccount, bool controllerEnabled)
    {
        onBehalfOfAccount = executionContext.getOnBehalfOfAccount();

        // for safety, revert if no account has been authenticated
        if (onBehalfOfAccount == address(0)) {
            revert EVC_OnBehalfOfAccountNotAuthenticated();
        }

        controllerEnabled =
            controllerToCheck == address(0) ? false : accountControllers[onBehalfOfAccount].contains(controllerToCheck);
    }

    /// @inheritdoc IEVC
    function areChecksDeferred() external view returns (bool) {
        return executionContext.areChecksDeferred();
    }

    /// @inheritdoc IEVC
    function areChecksInProgress() external view returns (bool) {
        return executionContext.areChecksInProgress();
    }

    /// @inheritdoc IEVC
    function isControlCollateralInProgress() external view returns (bool) {
        return executionContext.isControlCollateralInProgress();
    }

    /// @inheritdoc IEVC
    function isOperatorAuthenticated() external view returns (bool) {
        return executionContext.isOperatorAuthenticated();
    }

    /// @inheritdoc IEVC
    function isSimulationInProgress() external view returns (bool) {
        return executionContext.isSimulationInProgress();
    }

    // Owners and operators

    /// @inheritdoc IEVC
    function haveCommonOwner(address account, address otherAccount) external pure returns (bool) {
        return haveCommonOwnerInternal(account, otherAccount);
    }

    /// @inheritdoc IEVC
    function getAddressPrefix(address account) external pure returns (bytes19) {
        return getAddressPrefixInternal(account);
    }

    /// @inheritdoc IEVC
    function getAccountOwner(address account) external view returns (address owner) {
        owner = getAccountOwnerInternal(account);

        if (owner == address(0)) revert EVC_AccountOwnerNotRegistered();
    }

    /// @inheritdoc IEVC
    function getNonce(bytes19 addressPrefix, uint256 nonceNamespace) external view returns (uint256) {
        return nonceLookup[addressPrefix][nonceNamespace];
    }

    /// @inheritdoc IEVC
    function getOperator(bytes19 addressPrefix, address operator) external view returns (uint256) {
        return operatorLookup[addressPrefix][operator];
    }

    /// @inheritdoc IEVC
    function isAccountOperatorAuthorized(address account, address operator) external view returns (bool) {
        return isAccountOperatorAuthorizedInternal(account, operator);
    }

    /// @inheritdoc IEVC
    function setNonce(
        bytes19 addressPrefix,
        uint256 nonceNamespace,
        uint256 nonce
    ) public payable virtual onlyOwner(addressPrefix) {
        if (nonceLookup[addressPrefix][nonceNamespace] >= nonce) {
            revert EVC_InvalidNonce();
        }

        nonceLookup[addressPrefix][nonceNamespace] = nonce;

        unchecked {
            nonce -= 1;
        }

        emit NonceUsed(addressPrefix, nonceNamespace, nonce);
    }

    /// @inheritdoc IEVC
    /// @dev Uses authenticateCaller() function instead of onlyOwner() modifier to authenticate and get the caller
    /// address at once.
    function setOperator(bytes19 addressPrefix, address operator, uint256 operatorBitField) public payable virtual {
        // calculate a phantom address from the address prefix which can be used as an input to the authenticateCaller()
        // function
        address phantomAccount = address(uint160(uint152(addressPrefix)) << 8);
        address msgSender = authenticateCaller(phantomAccount, false);

        // the operator can neither be the EVC nor can be one of 256 accounts of the owner
        if (operator == address(this) || haveCommonOwnerInternal(msgSender, operator)) {
            revert EVC_InvalidAddress();
        }

        if (operatorLookup[addressPrefix][operator] == operatorBitField) {
            revert EVC_InvalidOperatorStatus();
        } else {
            operatorLookup[addressPrefix][operator] = operatorBitField;

            emit OperatorStatus(addressPrefix, operator, operatorBitField);
        }
    }

    /// @inheritdoc IEVC
    /// @dev Uses authenticateCaller() function instead of onlyOwnerOrOperator() modifier to authenticate and get the
    /// caller address at once.
    function setAccountOperator(address account, address operator, bool authorized) public payable virtual {
        address msgSender = authenticateCaller(account, true);

        // if the account and the caller have a common owner, the caller must be the owner. if the account and the
        // caller don't have a common owner, the caller must be an operator and the owner address is taken from the
        // storage
        address owner = haveCommonOwnerInternal(account, msgSender) ? msgSender : getAccountOwnerInternal(account);

        // if it's an operator calling, it can only act for itself and must not be able to change other operators status
        // Mutate: Based on bug found in audit
        if (owner != msgSender && operator != msgSender  && address(this) != msg.sender) {
            revert EVC_NotAuthorized();
        }

        // the operator can neither be the EVC nor can be one of 256 accounts of the owner
        if (operator == address(this) || haveCommonOwnerInternal(owner, operator)) {
            revert EVC_InvalidAddress();
        }

        bytes19 addressPrefix = getAddressPrefixInternal(account);

        // The bitMask defines which accounts the operator is authorized for. The bitMask is created from the account
        // number which is a number up to 2^8 in binary, or 256. 1 << (uint160(owner) ^ uint160(account)) transforms
        // that number in an 256-position binary array like 0...010...0, marking the account positionally in a uint256.
        uint256 bitMask = 1 << (uint160(owner) ^ uint160(account));

        // The operatorBitField is a 256-position binary array, where each 1 signals by position the account that the
        // operator is authorized for.
        uint256 oldOperatorBitField = operatorLookup[addressPrefix][operator];
        uint256 newOperatorBitField = authorized ? oldOperatorBitField | bitMask : oldOperatorBitField & ~bitMask;

        if (oldOperatorBitField == newOperatorBitField) {
            revert EVC_InvalidOperatorStatus();
        } else {
            operatorLookup[addressPrefix][operator] = newOperatorBitField;

            emit OperatorStatus(addressPrefix, operator, newOperatorBitField);
        }
    }

    // Collaterals management

    /// @inheritdoc IEVC
    function getCollaterals(address account) external view returns (address[] memory) {
        return accountCollaterals[account].get();
    }

    /// @inheritdoc IEVC
    function isCollateralEnabled(address account, address vault) external view returns (bool) {
        return accountCollaterals[account].contains(vault);
    }

    /// @inheritdoc IEVC
    function enableCollateral(
        address account,
        address vault
    ) public payable virtual nonReentrantChecksAndControlCollateral onlyOwnerOrOperator(account) {
        if (vault == address(this)) revert EVC_InvalidAddress();

        if (accountCollaterals[account].insert(vault)) {
            emit CollateralStatus(account, vault, true);
        }
        requireAccountStatusCheck(account);
    }

    /// @inheritdoc IEVC
    function disableCollateral(
        address account,
        address vault
    ) public payable virtual nonReentrantChecksAndControlCollateral onlyOwnerOrOperator(account) {
        if (accountCollaterals[account].remove(vault)) {
            emit CollateralStatus(account, vault, false);
        }
        requireAccountStatusCheck(account);
    }

    /// @inheritdoc IEVC
    function reorderCollaterals(
        address account,
        uint8 index1,
        uint8 index2
    ) public payable virtual nonReentrantChecksAndControlCollateral onlyOwnerOrOperator(account) {
        accountCollaterals[account].reorder(index1, index2);
        requireAccountStatusCheck(account);
    }

    // Controllers management

    /// @inheritdoc IEVC
    function getControllers(address account) external view returns (address[] memory) {
        return accountControllers[account].get();
    }

    /// @inheritdoc IEVC
    function isControllerEnabled(address account, address vault) external view returns (bool) {
        return accountControllers[account].contains(vault);
    }

    /// @inheritdoc IEVC
    function enableController(
        address account,
        address vault
    ) public payable virtual nonReentrantChecksAndControlCollateral onlyOwnerOrOperator(account) {
        if (vault == address(this)) revert EVC_InvalidAddress();

        if (accountControllers[account].insert(vault)) {
            emit ControllerStatus(account, vault, true);
        }
        requireAccountStatusCheck(account);
    }

    /// @inheritdoc IEVC
    function disableController(address account) public payable virtual nonReentrantChecksAndControlCollateral {
        if (accountControllers[account].remove(msg.sender)) {
            emit ControllerStatus(account, msg.sender, false);
        }
        requireAccountStatusCheck(account);
    }

    // Permit

    /// @inheritdoc IEVC
    function permit(
        address signer,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256 value,
        bytes calldata data,
        bytes calldata signature
    ) public payable virtual nonReentrantChecksAndControlCollateral {
        // cannot be called within the self-call of the permit(); can occur for nested permit() calls
        if (address(this) == msg.sender) {
            revert EVC_NotAuthorized();
        }

        bytes19 addressPrefix = getAddressPrefixInternal(signer);

        if (signer == address(0) || !isSignerValid(signer)) {
            revert EVC_InvalidAddress();
        }

        uint256 currentNonce = nonceLookup[addressPrefix][nonceNamespace];

        if (currentNonce == type(uint256).max || currentNonce != nonce) {
            revert EVC_InvalidNonce();
        }

        if (deadline < block.timestamp) {
            revert EVC_InvalidTimestamp();
        }

        if (data.length == 0) {
            revert EVC_InvalidData();
        }

        bytes32 permitHash = getPermitHash(signer, nonceNamespace, nonce, deadline, value, data);

        if (
            signer != recoverECDSASigner(permitHash, signature)
                && !isValidERC1271Signature(signer, permitHash, signature)
        ) {
            revert EVC_NotAuthorized();
        }

        unchecked {
            nonceLookup[addressPrefix][nonceNamespace] = currentNonce + 1;
        }

        emit NonceUsed(addressPrefix, nonceNamespace, nonce);

        // EVC address becomes msg.sender for the duration this self-call, no authentication is required
        (bool success, bytes memory result) = callWithContextInternal(address(this), signer, value, data);

        if (!success) revertBytes(result);
    }

    // Calls forwarding

    /// @inheritdoc IEVC
    function call(
        address targetContract,
        address onBehalfOfAccount,
        uint256 value,
        bytes calldata data
    ) public payable virtual nonReentrantChecksAndControlCollateral returns (bytes memory result) {
        EC contextCache = executionContext;
        executionContext = contextCache.setChecksDeferred();

        bool success;
        (success, result) = callWithAuthenticationInternal(targetContract, onBehalfOfAccount, value, data);

        if (!success) revertBytes(result);

        restoreExecutionContext(contextCache);
    }

    /// @inheritdoc IEVC
    function controlCollateral(
        address targetCollateral,
        address onBehalfOfAccount,
        uint256 value,
        bytes calldata data
    )
        public
        payable
        virtual
        nonReentrantChecksAndControlCollateral
        onlyController(onBehalfOfAccount)
        returns (bytes memory result)
    {
        if (!accountCollaterals[onBehalfOfAccount].contains(targetCollateral)) {
            revert EVC_NotAuthorized();
        }

        EC contextCache = executionContext;
        executionContext = contextCache.setChecksDeferred().setControlCollateralInProgress();

        bool success;
        (success, result) = callWithContextInternal(targetCollateral, onBehalfOfAccount, value, data);

        if (!success) revertBytes(result);

        restoreExecutionContext(contextCache);
    }

    /// @inheritdoc IEVC
    function batch(BatchItem[] calldata items) public payable virtual nonReentrantChecksAndControlCollateral {
        EC contextCache = executionContext;
        executionContext = contextCache.setChecksDeferred();

        uint256 length = items.length;
        for (uint256 i; i < length;) {
            BatchItem calldata item = items[i];
            (bool success, bytes memory result) =
                callWithAuthenticationInternal(item.targetContract, item.onBehalfOfAccount, item.value, item.data);

            if (!success) revertBytes(result);

            unchecked {
                ++i;
            }
        }

        restoreExecutionContext(contextCache);
    }

    // Simulations

    /// @inheritdoc IEVC
    function batchRevert(BatchItem[] calldata items) public payable virtual nonReentrantChecksAndControlCollateral {
        BatchItemResult[] memory batchItemsResult;
        StatusCheckResult[] memory accountsStatusCheckResult;
        StatusCheckResult[] memory vaultsStatusCheckResult;

        EC contextCache = executionContext;

        if (contextCache.areChecksDeferred()) {
            revert EVC_SimulationBatchNested();
        }

        executionContext = contextCache.setChecksDeferred().setSimulationInProgress();

        uint256 length = items.length;
        batchItemsResult = new BatchItemResult[](length);

        for (uint256 i; i < length;) {
            BatchItem calldata item = items[i];
            (batchItemsResult[i].success, batchItemsResult[i].result) =
                callWithAuthenticationInternal(item.targetContract, item.onBehalfOfAccount, item.value, item.data);

            unchecked {
                ++i;
            }
        }

        executionContext = contextCache.setChecksInProgress();

        accountsStatusCheckResult = checkStatusAllWithResult(SetType.Account);
        vaultsStatusCheckResult = checkStatusAllWithResult(SetType.Vault);

        executionContext = contextCache;

        revert EVC_RevertedBatchResult(batchItemsResult, accountsStatusCheckResult, vaultsStatusCheckResult);
    }

    /// @inheritdoc IEVC
    function batchSimulation(BatchItem[] calldata items)
        public
        payable
        virtual
        returns (
            BatchItemResult[] memory batchItemsResult,
            StatusCheckResult[] memory accountsStatusCheckResult,
            StatusCheckResult[] memory vaultsStatusCheckResult
        )
    {
        (bool success, bytes memory result) = address(this).delegatecall(abi.encodeCall(this.batchRevert, items));

        if (success) {
            revert EVC_BatchPanic();
        } else if (bytes4(result) != EVC_RevertedBatchResult.selector) {
            revertBytes(result);
        }

        assembly {
            result := add(result, 4)
        }

        (batchItemsResult, accountsStatusCheckResult, vaultsStatusCheckResult) =
            abi.decode(result, (BatchItemResult[], StatusCheckResult[], StatusCheckResult[]));
    }

    // Account Status Check

    /// @inheritdoc IEVC
    function isAccountStatusCheckDeferred(address account) external view returns (bool) {
        if (executionContext.areChecksInProgress()) {
            revert EVC_ChecksReentrancy();
        }

        return accountStatusChecks.contains(account);
    }

    /// @inheritdoc IEVC
    function requireAccountStatusCheck(address account) public payable virtual nonReentrantChecks {
        if (executionContext.areChecksDeferred()) {
            accountStatusChecks.insert(account);
        } else {
            requireAccountStatusCheckInternal(account);
        }
    }

    /// @inheritdoc IEVC
    function forgiveAccountStatusCheck(address account)
        public
        payable
        virtual
        nonReentrantChecks
        onlyController(account)
    {
        accountStatusChecks.remove(account);
    }

    // Vault Status Check

    /// @inheritdoc IEVC
    function isVaultStatusCheckDeferred(address vault) external view returns (bool) {
        if (executionContext.areChecksInProgress()) {
            revert EVC_ChecksReentrancy();
        }

        return vaultStatusChecks.contains(vault);
    }

    /// @inheritdoc IEVC
    function requireVaultStatusCheck() public payable virtual nonReentrantChecks {
        if (executionContext.areChecksDeferred()) {
            vaultStatusChecks.insert(msg.sender);
        } else {
            requireVaultStatusCheckInternal(msg.sender);
        }
    }

    /// @inheritdoc IEVC
    function forgiveVaultStatusCheck() public payable virtual nonReentrantChecks {
        vaultStatusChecks.remove(msg.sender);
    }

    /// @inheritdoc IEVC
    function requireAccountAndVaultStatusCheck(address account) public payable virtual nonReentrantChecks {
        if (executionContext.areChecksDeferred()) {
            accountStatusChecks.insert(account);
            vaultStatusChecks.insert(msg.sender);
        } else {
            requireAccountStatusCheckInternal(account);
            requireVaultStatusCheckInternal(msg.sender);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL FUNCTIONS                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function authenticateCaller(address account, bool allowOperator) internal virtual returns (address) {
        bool authenticated = false;
        address msgSender = _msgSender();

        // check if the caller is the owner of the account
        if (haveCommonOwnerInternal(account, msgSender)) {
            address owner = getAccountOwnerInternal(account);

            // if the owner is not registered, register it
            if (owner == address(0)) {
                setAccountOwnerInternal(account, msgSender);
                authenticated = true;
            } else if (owner == msgSender) {
                authenticated = true;
            }
        }

        // if the caller is not the owner, check if it is an operator if operators are allowed
        if (!authenticated && allowOperator) {
            authenticated = isAccountOperatorAuthorizedInternal(account, msgSender);
        }

        // must revert if neither the owner nor the operator were authenticated
        if (!authenticated) {
            revert EVC_NotAuthorized();
        }

        return msgSender;
    }

    function callWithContextInternal(
        address targetContract,
        address onBehalfOfAccount,
        uint256 value,
        bytes calldata data
    ) internal virtual returns (bool success, bytes memory result) {
        if (value == type(uint256).max) {
            value = address(this).balance;
        } else if (value > address(this).balance) {
            revert EVC_InvalidValue();
        }

        EC contextCache = executionContext;

        // in case of the self-call in the permit() function, the EVC address becomes msg.sender hence the "true" caller
        // address (that is permit message signer) is taken from the execution context via _msgSender() function.
        address msgSender = _msgSender();

        // set the onBehalfOfAccount in the execution context for the duration of the external call.
        // considering that the operatorAuthenticated is only meant to be observable by external
        // contracts, it is sufficient to set it here rather than in the authentication function.
        // apart from the usual scenario (when an owner operates on behalf of its account),
        // the operatorAuthenticated should be cleared when about to execute the permit self-call, when
        // target contract is equal to the msg.sender in call() and batch(), or when the controlCollateral is in
        // progress (in which case the operatorAuthenticated is not relevant)
        if (
            haveCommonOwnerInternal(onBehalfOfAccount, msgSender) || targetContract == msg.sender
                || targetContract == address(this) || contextCache.isControlCollateralInProgress()
        ) {
            executionContext = contextCache.setOnBehalfOfAccount(onBehalfOfAccount).clearOperatorAuthenticated();
        } else {
            executionContext = contextCache.setOnBehalfOfAccount(onBehalfOfAccount).setOperatorAuthenticated();
        }

        emit CallWithContext(
            msgSender, getAddressPrefixInternal(onBehalfOfAccount), onBehalfOfAccount, targetContract, bytes4(data)
        );

        (success, result) = targetContract.call{value: value}(data);

        executionContext = contextCache;
    }

    function callWithAuthenticationInternal(
        address targetContract,
        address onBehalfOfAccount,
        uint256 value,
        bytes calldata data
    ) internal virtual returns (bool success, bytes memory result) {
        if (targetContract == address(this)) {
            if (onBehalfOfAccount != address(0)) {
                revert EVC_InvalidAddress();
            }

            if (value != 0) {
                revert EVC_InvalidValue();
            }

            // delegatecall is used here to preserve msg.sender in order
            // to be able to perform authentication
            (success, result) = address(this).delegatecall(data);
        } else {
            // when the target contract is equal to the msg.sender, both in call() and batch(), authentication is not
            // required
            if (targetContract != msg.sender) {
                authenticateCaller(onBehalfOfAccount, true);
            }

            (success, result) = callWithContextInternal(targetContract, onBehalfOfAccount, value, data);
        }
    }

    function restoreExecutionContext(EC contextCache) internal virtual {
        if (!contextCache.areChecksDeferred()) {
            executionContext = contextCache.setChecksInProgress().setOnBehalfOfAccount(address(0));

            checkStatusAll(SetType.Account);
            checkStatusAll(SetType.Vault);
        }

        executionContext = contextCache;
    }

    function checkAccountStatusInternal(address account) internal virtual returns (bool isValid, bytes memory result) {
        uint256 numOfControllers = accountControllers[account].numElements;
        address controller = accountControllers[account].firstElement;

        if (numOfControllers == 0) return (true, "");
        else if (numOfControllers > 1) revert EVC_ControllerViolation();

        bool success;
        (success, result) =
            controller.call(abi.encodeCall(IVault.checkAccountStatus, (account, accountCollaterals[account].get())));

        isValid = success && result.length == 32
            && abi.decode(result, (bytes32)) == bytes32(IVault.checkAccountStatus.selector);

        emit AccountStatusCheck(account, controller);
    }

    function requireAccountStatusCheckInternal(address account) internal virtual {
        (bool isValid, bytes memory result) = checkAccountStatusInternal(account);

        if (!isValid) {
            revertBytes(result);
        }
    }

    function checkVaultStatusInternal(address vault) internal returns (bool isValid, bytes memory result) {
        bool success;
        (success, result) = vault.call(abi.encodeCall(IVault.checkVaultStatus, ()));

        isValid =
            success && result.length == 32 && abi.decode(result, (bytes32)) == bytes32(IVault.checkVaultStatus.selector);

        emit VaultStatusCheck(vault);
    }

    function requireVaultStatusCheckInternal(address vault) internal virtual {
        (bool isValid, bytes memory result) = checkVaultStatusInternal(vault);

        if (!isValid) {
            revertBytes(result);
        }
    }

    function checkStatusAll(SetType setType) internal virtual {
        setType == SetType.Account
            ? accountStatusChecks.forEachAndClear(requireAccountStatusCheckInternal)
            : vaultStatusChecks.forEachAndClear(requireVaultStatusCheckInternal);
    }

    function checkStatusAllWithResult(SetType setType)
        internal
        virtual
        returns (StatusCheckResult[] memory checksResult)
    {
        bytes[] memory callbackResult = setType == SetType.Account
            ? accountStatusChecks.forEachAndClearWithResult(checkAccountStatusInternal)
            : vaultStatusChecks.forEachAndClearWithResult(checkVaultStatusInternal);

        uint256 length = callbackResult.length;
        checksResult = new StatusCheckResult[](length);

        for (uint256 i; i < length;) {
            (address checkedAddress, bool isValid, bytes memory result) =
                abi.decode(callbackResult[i], (address, bool, bytes));
            checksResult[i] = StatusCheckResult(checkedAddress, isValid, result);

            unchecked {
                ++i;
            }
        }
    }

    // Permit-related functions

    function isSignerValid(address signer) internal pure returns (bool) {
        // not valid if the signer address falls into any of the precompiles/predeploys
        // addresses space (depends on the chain ID).
        // IMPORTANT: revisit this logic when deploying on chains other than the Ethereum mainnet
        return !haveCommonOwnerInternal(signer, address(0));
    }

    function getPermitHash(
        address signer,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256 value,
        bytes calldata data
    ) internal view returns (bytes32 permitHash) {
        bytes32 domainSeparator =
            block.chainid == CACHED_CHAIN_ID ? CACHED_DOMAIN_SEPARATOR : calculateDomainSeparator();

        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, signer, nonceNamespace, nonce, deadline, value, keccak256(data)));

        // This code overwrites the two most significant bytes of the free memory pointer,
        // and restores them to 0 after
        assembly ("memory-safe") {
            mstore(0x00, "\x19\x01")
            mstore(0x02, domainSeparator)
            mstore(0x22, structHash)
            permitHash := keccak256(0x00, 0x42)
            mstore(0x22, 0)
        }
    }

    // Based on:
    // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol
    // Note that the function returns zero address if the signature is invalid hence the result always has to be
    // checked against address zero.
    function recoverECDSASigner(bytes32 hash, bytes memory signature) internal pure returns (address signer) {
        if (signature.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;

        // ecrecover takes the signature parameters, and the only way to get them
        // currently is to use assembly.
        /// @solidity memory-safe-assembly
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }

        // return the signer address (note that it might be zero address)
        signer = ecrecover(hash, v, r, s);
    }

    // Based on:
    // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/SignatureChecker.sol
    function isValidERC1271Signature(
        address signer,
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool isValid) {
        if (signer.code.length == 0) return false;

        (bool success, bytes memory result) =
            signer.staticcall(abi.encodeCall(IERC1271.isValidSignature, (hash, signature)));

        isValid = success && result.length == 32
            && abi.decode(result, (bytes32)) == bytes32(IERC1271.isValidSignature.selector);
    }

    function calculateDomainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, HASHED_NAME, HASHED_VERSION, block.chainid, address(this)));
    }

    // Auxiliary functions

    function _msgSender() internal view virtual returns (address) {
        // EVC can only be msg.sender during the self-call in the permit() function. in that case,
        // the "true" caller address (that is the permit message signer) is taken from the execution context
        return address(this) == msg.sender ? executionContext.getOnBehalfOfAccount() : msg.sender;
    }

    function haveCommonOwnerInternal(address account, address otherAccount) internal pure returns (bool result) {
        assembly {
            result := lt(xor(account, otherAccount), 0x100)
        }
    }

    function getAddressPrefixInternal(address account) internal pure returns (bytes19) {
        return bytes19(uint152(uint160(account) >> 8));
    }

    function getAccountOwnerInternal(address account) internal view returns (address) {
        bytes19 addressPrefix = getAddressPrefixInternal(account);
        return ownerLookup[addressPrefix];
    }

    function isAccountOperatorAuthorizedInternal(
        address account,
        address operator
    ) internal view returns (bool isAuthorized) {
        address owner = getAccountOwnerInternal(account);

        // if the owner is not registered yet, it means that the operator couldn't have been authorized
        if (owner == address(0)) return false;

        bytes19 addressPrefix = getAddressPrefixInternal(account);

        // The bitMask defines which accounts the operator is authorized for. The bitMask is created from the account
        // number which is a number up to 2^8 in binary, or 256. 1 << (uint160(owner) ^ uint160(account)) transforms
        // that number in an 256-position binary array like 0...010...0, marking the account positionally in a uint256.
        uint256 bitMask = 1 << (uint160(owner) ^ uint160(account));

        return operatorLookup[addressPrefix][operator] & bitMask != 0;
    }

    function setAccountOwnerInternal(address account, address owner) internal {
        bytes19 addressPrefix = getAddressPrefixInternal(account);
        ownerLookup[addressPrefix] = owner;
        emit OwnerRegistered(addressPrefix, owner);
    }

    function revertBytes(bytes memory errMsg) internal pure {
        if (errMsg.length != 0) {
            assembly {
                revert(add(32, errMsg), mload(errMsg))
            }
        }
        revert EVC_EmptyError();
    }
}
