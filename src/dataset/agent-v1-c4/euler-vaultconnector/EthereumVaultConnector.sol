// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import {Set, SetStorage} from "./Set.sol";
import {Events} from "./Events.sol";
import {Errors} from "./Errors.sol";
import {ExecutionContext, EC} from "./ExecutionContext.sol";
import {TransientStorage} from "./TransientStorage.sol";
import {IEVC} from "./interfaces/IEthereumVaultConnector.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IERC1271} from "./interfaces/IERC1271.sol";

/// @title EthereumVaultConnector
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This contract implements the Ethereum Vault Connector.
contract EthereumVaultConnector is Events, Errors, TransientStorage, IEVC {
    using ExecutionContext for EC;
    using Set for SetStorage;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       CONSTANTS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Name of the Ethereum Vault Connector.
    string public constant name = "Ethereum Vault Connector";

    /// @notice Version of the Ethereum Vault Connector.
    string public constant version = "1";

    uint160 internal constant ACCOUNT_ID_OFFSET = 8;
    bytes32 internal constant HASHED_NAME = keccak256(bytes(name));
    bytes32 internal constant HASHED_VERSION = keccak256(bytes(version));

    bytes32 internal constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 internal constant PERMIT_TYPEHASH = keccak256(
        "Permit(address signer,address sender,uint256 nonceNamespace,uint256 nonce,uint256 deadline,uint256 value,bytes data)"
    );

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

    // Internal data structure that stores the addressPrefix owner and mode flags
    struct OwnerStorage {
        // The addressPrefix owner
        address owner;
        // Flag indicating if the addressPrefix is in lockdown mode
        bool isLockdownMode;
        // Flag indicating if the permit function is disabled for the addressPrefix
        bool isPermitDisabledMode;
    }

    mapping(bytes19 addressPrefix => OwnerStorage) internal ownerLookup;

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

    /// @notice Fallback function to receive Ether.
    receive() external payable {
        // only allows to receive value when checks are deferred
        if (!executionContext.areChecksDeferred()) {
            revert EVC_NotAuthorized();
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       MODIFIERS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice A modifier that allows only the address recorded as an owner of the address prefix to call the function.
    /// @dev The owner of an address prefix is an address that matches the address that has previously been recorded (or
    /// will be) as an owner in the ownerLookup.
    /// @param addressPrefix The address prefix for which it is checked whether the caller is the owner.
    modifier onlyOwner(bytes19 addressPrefix) {
        authenticateCaller({addressPrefix: addressPrefix, allowOperator: false, checkLockdownMode: false});

        _;
    }

    /// @notice A modifier that allows only the owner or an operator of the account to call the function.
    /// @dev The owner of an address prefix is an address that matches the address that has previously been recorded (or
    /// will be) as an owner in the ownerLookup. An operator of an account is an address that has been authorized by the
    /// owner of an account to perform operations on behalf of the owner.
    /// @param account The address of the account for which it is checked whether the caller is the owner or an
    /// operator.
    modifier onlyOwnerOrOperator(address account) {
        authenticateCaller({account: account, allowOperator: true, checkLockdownMode: true});

        _;
    }

    /// @notice A modifier checks whether msg.sender is the only controller for the account.
    /// @dev The controller cannot use permit function in conjunction with this modifier.
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

    /// @notice A modifier that verifies whether account or vault status checks are re-entered.
    modifier nonReentrantChecks() {
        if (executionContext.areChecksInProgress()) {
            revert EVC_ChecksReentrancy();
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
    modifier nonReentrantChecksAcquireLock() {
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
        external
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
    function getAccountOwner(address account) external view returns (address) {
        return getAccountOwnerInternal(account);
    }

    /// @inheritdoc IEVC
    function isLockdownMode(bytes19 addressPrefix) external view returns (bool) {
        return ownerLookup[addressPrefix].isLockdownMode;
    }

    /// @inheritdoc IEVC
    function isPermitDisabledMode(bytes19 addressPrefix) external view returns (bool) {
        return ownerLookup[addressPrefix].isPermitDisabledMode;
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
    function setLockdownMode(bytes19 addressPrefix, bool enabled) public payable virtual onlyOwner(addressPrefix) {
        if (ownerLookup[addressPrefix].isLockdownMode != enabled) {
            // to increase user security, it is prohibited to disable this mode within the self-call of the permit
            // function or within a checks-deferrable call. to disable this mode, the setLockdownMode function must be
            // called directly
            if (!enabled && (executionContext.areChecksDeferred() || inPermitSelfCall())) {
                revert EVC_NotAuthorized();
            }

            ownerLookup[addressPrefix].isLockdownMode = enabled;
            emit LockdownModeStatus(addressPrefix, enabled);
        }
    }

    /// @inheritdoc IEVC
    function setPermitDisabledMode(
        bytes19 addressPrefix,
        bool enabled
    ) public payable virtual onlyOwner(addressPrefix) {
        if (ownerLookup[addressPrefix].isPermitDisabledMode != enabled) {
            // to increase user security, it is prohibited to disable this mode within the self-call of the permit
            // function (verified in the permit function) or within a checks-deferrable call. to disable this mode the
            // setPermitDisabledMode function must be called directly
            if (!enabled && executionContext.areChecksDeferred()) {
                revert EVC_NotAuthorized();
            }

            ownerLookup[addressPrefix].isPermitDisabledMode = enabled;
            emit PermitDisabledModeStatus(addressPrefix, enabled);
        }
    }

    /// @inheritdoc IEVC
    function setNonce(
        bytes19 addressPrefix,
        uint256 nonceNamespace,
        uint256 nonce
    ) public payable virtual onlyOwner(addressPrefix) {
        uint256 currentNonce = nonceLookup[addressPrefix][nonceNamespace];

        if (currentNonce >= nonce) {
            revert EVC_InvalidNonce();
        }

        nonceLookup[addressPrefix][nonceNamespace] = nonce;

        emit NonceStatus(addressPrefix, nonceNamespace, currentNonce, nonce);
    }

    /// @inheritdoc IEVC
    /// @dev Uses authenticateCaller() function instead of onlyOwner() modifier to authenticate and get the caller
    /// address at once.
    function setOperator(bytes19 addressPrefix, address operator, uint256 operatorBitField) public payable virtual {
        address msgSender =
            authenticateCaller({addressPrefix: addressPrefix, allowOperator: false, checkLockdownMode: false});

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
        address msgSender = authenticateCaller({account: account, allowOperator: true, checkLockdownMode: false});

        // if the account and the caller have a common owner, the caller must be the owner. if the account and the
        // caller don't have a common owner, the caller must be an operator and the owner address is taken from the
        // storage. the caller authentication above guarantees that the account owner is already registered hence
        // non-zero
        address owner = haveCommonOwnerInternal(account, msgSender) ? msgSender : getAccountOwnerInternal(account);

        // if it's an operator calling, it can only act for itself and must not be able to change other operators status
        if (owner != msgSender && operator != msgSender) {
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
        address sender,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256 value,
        bytes calldata data,
        bytes calldata signature
    ) public payable virtual nonReentrantChecksAndControlCollateral {
        // cannot be called within the self-call of the permit function; can occur for nested calls.
        // the permit function can be called only by the specified sender
        if (inPermitSelfCall() || (sender != address(0) && sender != msg.sender)) {
            revert EVC_NotAuthorized();
        }

        if (signer == address(0) || !isSignerValid(signer)) {
            revert EVC_InvalidAddress();
        }

        bytes19 addressPrefix = getAddressPrefixInternal(signer);

        if (ownerLookup[addressPrefix].isPermitDisabledMode) {
            revert EVC_PermitDisabledMode();
        }

        {
            uint256 currentNonce = nonceLookup[addressPrefix][nonceNamespace];

            if (currentNonce == type(uint256).max || currentNonce != nonce) {
                revert EVC_InvalidNonce();
            }
        }

        if (deadline < block.timestamp) {
            revert EVC_InvalidTimestamp();
        }

        if (data.length == 0) {
            revert EVC_InvalidData();
        }

        bytes32 permitHash = getPermitHash(signer, sender, nonceNamespace, nonce, deadline, value, data);

        if (
            signer != recoverECDSASigner(permitHash, signature)
                && !isValidERC1271Signature(signer, permitHash, signature)
        ) {
            revert EVC_NotAuthorized();
        }

        unchecked {
            nonceLookup[addressPrefix][nonceNamespace] = nonce + 1;
        }

        emit NonceUsed(addressPrefix, nonceNamespace, nonce);

        // EVC address becomes the msg.sender for the duration this self-call, no authentication is required here.
        // the signer will be later on authenticated as per data, depending on the functions that will be called
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
        for (uint256 i; i < length; ++i) {
            BatchItem calldata item = items[i];
            (bool success, bytes memory result) =
                callWithAuthenticationInternal(item.targetContract, item.onBehalfOfAccount, item.value, item.data);

            if (!success) revertBytes(result);
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

        for (uint256 i; i < length; ++i) {
            BatchItem calldata item = items[i];
            (batchItemsResult[i].success, batchItemsResult[i].result) =
                callWithAuthenticationInternal(item.targetContract, item.onBehalfOfAccount, item.value, item.data);
        }

        executionContext = contextCache.setChecksInProgress().setOnBehalfOfAccount(address(0));

        accountsStatusCheckResult = checkStatusAllWithResult(SetType.Account);
        vaultsStatusCheckResult = checkStatusAllWithResult(SetType.Vault);

        executionContext = contextCache;

        revert EVC_RevertedBatchResult(batchItemsResult, accountsStatusCheckResult, vaultsStatusCheckResult);
    }

    /// @inheritdoc IEVC
    function batchSimulation(BatchItem[] calldata items)
        external
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
        } else if (result.length < 4 || bytes4(result) != EVC_RevertedBatchResult.selector) {
            revertBytes(result);
        }

        assembly {
            let length := mload(result)
            // skip 4-byte EVC_RevertedBatchResult selector
            result := add(result, 4)
            // write new array length = original length - 4-byte selector
            // cannot underflow as we require result.length >= 4 above
            mstore(result, sub(length, 4))
        }

        (batchItemsResult, accountsStatusCheckResult, vaultsStatusCheckResult) =
            abi.decode(result, (BatchItemResult[], StatusCheckResult[], StatusCheckResult[]));
    }

    // Account Status Check

    /// @inheritdoc IEVC
    function getLastAccountStatusCheckTimestamp(address account) external view nonReentrantChecks returns (uint256) {
        return accountControllers[account].getMetadata();
    }

    /// @inheritdoc IEVC
    function isAccountStatusCheckDeferred(address account) external view nonReentrantChecks returns (bool) {
        return accountStatusChecks.contains(account);
    }

    /// @inheritdoc IEVC
    function requireAccountStatusCheck(address account) public payable virtual {
        if (executionContext.areChecksDeferred()) {
            accountStatusChecks.insert(account);
        } else {
            requireAccountStatusCheckInternalNonReentrantChecks(account);
        }
    }

    /// @inheritdoc IEVC
    function forgiveAccountStatusCheck(address account)
        public
        payable
        virtual
        nonReentrantChecksAcquireLock
        onlyController(account)
    {
        accountStatusChecks.remove(account);
    }

    // Vault Status Check

    /// @inheritdoc IEVC
    function isVaultStatusCheckDeferred(address vault) external view nonReentrantChecks returns (bool) {
        return vaultStatusChecks.contains(vault);
    }

    /// @inheritdoc IEVC
    function requireVaultStatusCheck() public payable virtual {
        if (executionContext.areChecksDeferred()) {
            vaultStatusChecks.insert(msg.sender);
        } else {
            requireVaultStatusCheckInternalNonReentrantChecks(msg.sender);
        }
    }

    /// @inheritdoc IEVC
    function forgiveVaultStatusCheck() public payable virtual nonReentrantChecksAcquireLock {
        vaultStatusChecks.remove(msg.sender);
    }

    /// @inheritdoc IEVC
    function requireAccountAndVaultStatusCheck(address account) public payable virtual {
        if (executionContext.areChecksDeferred()) {
            accountStatusChecks.insert(account);
            vaultStatusChecks.insert(msg.sender);
        } else {
            requireAccountStatusCheckInternalNonReentrantChecks(account);
            requireVaultStatusCheckInternalNonReentrantChecks(msg.sender);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL FUNCTIONS                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Authenticates the caller of a function.
    /// @dev This function checks if the caller is the owner or an authorized operator of the account, and if the
    /// account is not in lockdown mode.
    /// @param account The account address to authenticate the caller against.
    /// @param allowOperator A boolean indicating if operators are allowed to authenticate as the caller.
    /// @param checkLockdownMode A boolean indicating if the function should check for lockdown mode on the account.
    /// @return The address of the authenticated caller.
    function authenticateCaller(
        address account,
        bool allowOperator,
        bool checkLockdownMode
    ) internal virtual returns (address) {
        bytes19 addressPrefix = getAddressPrefixInternal(account);
        address owner = ownerLookup[addressPrefix].owner;
        bool lockdownMode = ownerLookup[addressPrefix].isLockdownMode;
        address msgSender = _msgSender();
        bool authenticated = false;

        // check if the caller is the owner of the account
        if (haveCommonOwnerInternal(account, msgSender)) {
            // if the owner is not registered, register it
            if (owner == address(0)) {
                ownerLookup[addressPrefix].owner = msgSender;
                emit OwnerRegistered(addressPrefix, msgSender);
                authenticated = true;
            } else if (owner == msgSender) {
                authenticated = true;
            }
        }

        // if the caller is not the owner, check if it is an operator if operators are allowed
        if (!authenticated && allowOperator && isAccountOperatorAuthorizedInternal(account, msgSender)) {
            authenticated = true;
        }

        // must revert if neither the owner nor the operator were authenticated
        if (!authenticated) {
            revert EVC_NotAuthorized();
        }

        // revert if the account is in lockdown mode unless the lockdown mode is not being checked
        if (checkLockdownMode && lockdownMode) {
            revert EVC_LockdownMode();
        }

        return msgSender;
    }

    /// @notice Authenticates the caller of a function.
    /// @dev This function converts a bytes19 address prefix into a phantom account address which is an account address
    /// that belongs to the owner of the address prefix.
    /// @param addressPrefix The bytes19 address prefix to authenticate the caller against.
    /// @param allowOperator A boolean indicating if operators are allowed to authenticate as the caller.
    /// @param checkLockdownMode A boolean indicating if the function should check for lockdown mode on the account.
    /// @return The address of the authenticated caller.
    function authenticateCaller(
        bytes19 addressPrefix,
        bool allowOperator,
        bool checkLockdownMode
    ) internal virtual returns (address) {
        address phantomAccount = address(uint160(uint152(addressPrefix)) << ACCOUNT_ID_OFFSET);

        return authenticateCaller({
            account: phantomAccount,
            allowOperator: allowOperator,
            checkLockdownMode: checkLockdownMode
        });
    }

    /// @notice Internal function to make a call to a target contract with a specific context.
    /// @dev This function sets the execution context for the duration of the call.
    /// @param targetContract The contract address to call.
    /// @param onBehalfOfAccount The account address on behalf of which the call is made.
    /// @param value The amount of value to send with the call.
    /// @param data The calldata to send with the call.
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

    /// @notice Internal function to call a target contract with necessary authentication.
    /// @dev This function decides whether to use delegatecall or a regular call based on the target contract.
    /// If the target contract is this contract, it uses delegatecall to preserve msg.sender for authentication.
    /// Otherwise, it authenticates the caller if needed and proceeds with a regular call.
    /// @param targetContract The contract address to call.
    /// @param onBehalfOfAccount The account address on behalf of which the call is made.
    /// @param value The amount of value to send with the call.
    /// @param data The calldata to send with the call.
    /// @return success A boolean indicating if the call was successful.
    /// @return result The bytes returned from the call.
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

            // delegatecall is used here to preserve msg.sender in order to be able to perform authentication
            (success, result) = address(this).delegatecall(data);
        } else {
            // when the target contract is equal to the msg.sender, both in call() and batch(), authentication is not
            // required
            if (targetContract != msg.sender) {
                authenticateCaller({account: onBehalfOfAccount, allowOperator: true, checkLockdownMode: true});
            }

            (success, result) = callWithContextInternal(targetContract, onBehalfOfAccount, value, data);
        }
    }

    /// @notice Restores the execution context from a cached state.
    /// @dev This function restores the execution context to a previously cached state, performing necessary status
    /// checks if they are no longer deferred. If checks are no longer deferred, it sets the execution context to
    /// indicate checks are in progress and clears the 'on behalf of' account. It then performs status checks for both
    /// accounts and vaults before restoring the execution context to the cached state.
    /// @param contextCache The cached execution context to restore from.
    function restoreExecutionContext(EC contextCache) internal virtual {
        if (!contextCache.areChecksDeferred()) {
            executionContext = contextCache.setChecksInProgress().setOnBehalfOfAccount(address(0));

            checkStatusAll(SetType.Account);
            checkStatusAll(SetType.Vault);
        }

        executionContext = contextCache;
    }

    /// @notice Checks the status of an account internally.
    /// @dev This function first checks the number of controllers for the account. If there are no controllers enabled,
    /// it returns true immediately, indicating the account status is valid without further checks. If there is more
    /// than one controller, it reverts with an EVC_ControllerViolation error. For a single controller, it proceeds to
    /// call the controller to check the account status.
    /// @param account The account address to check the status for.
    /// @return isValid A boolean indicating if the account status is valid.
    /// @return result The bytes returned from the controller call, indicating the account status.
    function checkAccountStatusInternal(address account) internal virtual returns (bool isValid, bytes memory result) {
        SetStorage storage accountControllersStorage = accountControllers[account];
        uint256 numOfControllers = accountControllersStorage.numElements;
        address controller = accountControllersStorage.firstElement;
        uint8 stamp = accountControllersStorage.stamp;

        if (numOfControllers == 0) return (true, "");
        else if (numOfControllers > 1) return (false, abi.encodeWithSelector(EVC_ControllerViolation.selector));

        bool success;
        (success, result) =
            controller.call(abi.encodeCall(IVault.checkAccountStatus, (account, accountCollaterals[account].get())));

        isValid = success && result.length == 32
            && abi.decode(result, (bytes32)) == bytes32(IVault.checkAccountStatus.selector);

        if (isValid) {
            accountControllersStorage.numElements = uint8(numOfControllers);
            accountControllersStorage.firstElement = controller;
            accountControllersStorage.metadata = uint80(block.timestamp);
            accountControllersStorage.stamp = stamp;
        }

        emit AccountStatusCheck(account, controller);
    }

    function requireAccountStatusCheckInternal(address account) internal virtual {
        (bool isValid, bytes memory result) = checkAccountStatusInternal(account);

        if (!isValid) {
            revertBytes(result);
        }
    }

    function requireAccountStatusCheckInternalNonReentrantChecks(address account)
        internal
        virtual
        nonReentrantChecksAcquireLock
    {
        requireAccountStatusCheckInternal(account);
    }

    /// @notice Checks the status of a vault internally.
    /// @dev This function makes an external call to the vault to check its status.
    /// @param vault The address of the vault to check the status for.
    /// @return isValid A boolean indicating if the vault status is valid.
    /// @return result The bytes returned from the vault call, indicating the vault status.
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

    function requireVaultStatusCheckInternalNonReentrantChecks(address vault)
        internal
        virtual
        nonReentrantChecksAcquireLock
    {
        requireVaultStatusCheckInternal(vault);
    }

    /// @notice Checks the status of all entities in a set, either accounts or vaults, and clears the checks.
    /// @dev Iterates over either accountStatusChecks or vaultStatusChecks based on the setType and performs status
    /// checks.
    /// Clears the checks while performing them.
    /// @param setType The type of set to perform the status checks on, either accounts or vaults.
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

        for (uint256 i; i < length; ++i) {
            (address checkedAddress, bool isValid, bytes memory result) =
                abi.decode(callbackResult[i], (address, bool, bytes));
            checksResult[i] = StatusCheckResult({checkedAddress: checkedAddress, isValid: isValid, result: result});
        }
    }

    // Permit-related functions

    /// @notice Determines if the signer address is valid.
    /// @dev It's important to revisit this logic when deploying on chains other than the Ethereum mainnet. If new
    /// precompiles had been added to the Ethereum mainnet, the current implementation of the function would not be
    /// future-proof and would need to be updated.
    /// @param signer The address of the signer to validate.
    /// @return bool Returns true if the signer is valid, false otherwise.
    function isSignerValid(address signer) internal pure virtual returns (bool) {
        // not valid if the signer address falls into any of the precompiles/predeploys
        // addresses space (depends on the chain ID).
        return !haveCommonOwnerInternal(signer, address(0));
    }

    /// @notice Computes the permit hash for a given set of parameters.
    /// @dev This function generates a permit hash using EIP712 typed data signing.
    /// @param signer The address of the signer.
    /// @param nonceNamespace The namespace of the nonce.
    /// @param nonce The nonce value, ensuring permits are used once.
    /// @param deadline The time until when the permit is valid.
    /// @param value The value associated with the permit.
    /// @param data Calldata associated with the permit.
    /// @return permitHash The computed permit hash.
    function getPermitHash(
        address signer,
        address sender,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256 value,
        bytes calldata data
    ) internal view returns (bytes32 permitHash) {
        bytes32 domainSeparator =
            block.chainid == CACHED_CHAIN_ID ? CACHED_DOMAIN_SEPARATOR : calculateDomainSeparator();

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer, sender, nonceNamespace, nonce, deadline, value, keccak256(data))
        );

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

    /// @notice Recovers the signer address from a hash and a signature.
    /// Based on:
    /// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol
    /// Note that the function returns zero address if the signature is invalid hence the result always has to be
    /// checked against address zero.
    /// @param hash The hash of the signed data.
    /// @param signature The signature to recover the signer from.
    /// @return signer The address of the signer, or the zero address if signature recovery fails.
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

    /// @notice Checks if a given signature is valid according to ERC-1271 standard.
    /// @dev This function is based on the implementation found in OpenZeppelin's SignatureChecker.
    /// See:
    /// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/SignatureChecker.sol
    /// It performs a static call to the signer's address with the signature data and checks if the returned value
    /// matches the expected valid signature selector.
    /// @param signer The address of the signer to validate the signature against.
    /// @param hash The hash of the data that was signed.
    /// @param signature The signature to validate.
    /// @return isValid True if the signature is valid according to ERC-1271, false otherwise.
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

    /// @notice Calculates the EIP-712 domain separator for the contract.
    /// @return The calculated EIP-712 domain separator as a bytes32 value.
    function calculateDomainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, HASHED_NAME, HASHED_VERSION, block.chainid, address(this)));
    }

    // Auxiliary functions

    /// @notice Returns the message sender's address.
    /// @dev In the context of a permit self-call, it returns the account on behalf of which the call is made.
    /// Otherwise, it returns `msg.sender`.
    /// @return The address of the message sender or the account on behalf of which the call is made.
    function _msgSender() internal view virtual returns (address) {
        return inPermitSelfCall() ? executionContext.getOnBehalfOfAccount() : msg.sender;
    }

    /// @notice Checks if the contract is in the context of a permit self-call.
    /// @dev EVC can only be `msg.sender` during the self-call in the permit function.
    /// @return True if the current call is a self-call within the permit function, false otherwise.
    function inPermitSelfCall() internal view returns (bool) {
        return address(this) == msg.sender;
    }

    /// @notice Determines if two accounts have a common owner by comparing their address prefixes.
    /// @param account The first account address to compare.
    /// @param otherAccount The second account address to compare.
    /// @return result True if the accounts have a common owner, false otherwise.
    function haveCommonOwnerInternal(address account, address otherAccount) internal pure returns (bool result) {
        assembly {
            result := lt(xor(account, otherAccount), 0x100)
        }
    }

    /// @notice Computes the address prefix for a given account address.
    /// @dev The address prefix is derived by right-shifting the account address by 8 bits which effectively reduces the
    /// address size to 19 bytes.
    /// @param account The account address to compute the prefix for.
    /// @return The computed address prefix as a bytes19 value.
    function getAddressPrefixInternal(address account) internal pure returns (bytes19) {
        return bytes19(uint152(uint160(account) >> ACCOUNT_ID_OFFSET));
    }

    /// @notice Retrieves the owner of a given account by its address prefix.
    /// @param account The account address to retrieve the owner for.
    /// @return The address of the account owner.
    function getAccountOwnerInternal(address account) internal view returns (address) {
        bytes19 addressPrefix = getAddressPrefixInternal(account);
        return ownerLookup[addressPrefix].owner;
    }

    /// @notice Checks if an operator is authorized for a specific account.
    /// @dev Determines operator authorization by checking if the operator's bit is set in the operator's bit field for
    /// the account's address prefix. If the owner is not registered (address(0)), it implies the operator cannot be
    /// authorized, hence returns false. The bitMask is calculated by shifting 1 left by the XOR of the owner's and
    /// account's address, effectively checking the operator's authorization for the specific account.
    /// @param account The account address to check the operator authorization for.
    /// @param operator The operator address to check authorization status.
    /// @return isAuthorized True if the operator is authorized for the account, false otherwise.
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

    /// @notice Reverts the transaction with a custom error message if provided, otherwise reverts with a generic empty
    /// error.
    /// @param errMsg The custom error message to revert the transaction with.
    function revertBytes(bytes memory errMsg) internal pure {
        if (errMsg.length != 0) {
            assembly {
                revert(add(32, errMsg), mload(errMsg))
            }
        }
        revert EVC_EmptyError();
    }
}
