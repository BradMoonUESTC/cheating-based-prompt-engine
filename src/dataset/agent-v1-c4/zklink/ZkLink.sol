// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AddressAliasHelper} from "./zksync/l1-contracts/vendor/AddressAliasHelper.sol";
import {IZkLink} from "./interfaces/IZkLink.sol";
import {IL2Gateway} from "./interfaces/IL2Gateway.sol";
import {IMailbox, TxStatus} from "./zksync/l1-contracts/zksync/interfaces/IMailbox.sol";
import {IAdmin} from "./zksync/l1-contracts/zksync/interfaces/IAdmin.sol";
import {IZkSync} from "./zksync/l1-contracts/zksync/interfaces/IZkSync.sol";
import {Merkle} from "./zksync/l1-contracts/zksync/libraries/Merkle.sol";
import {TransactionValidator} from "./zksync/l1-contracts/zksync/libraries/TransactionValidator.sol";
import {L2Log, L2Message, PubdataPricingMode, FeeParams, SecondaryChainSyncStatus} from "./zksync/l1-contracts/zksync/Storage.sol";
import {UncheckedMath} from "./zksync/l1-contracts/common/libraries/UncheckedMath.sol";
import {UnsafeBytes} from "./zksync/l1-contracts/common/libraries/UnsafeBytes.sol";
import {REQUIRED_L2_GAS_PRICE_PER_PUBDATA, MAX_NEW_FACTORY_DEPS, L1_GAS_PER_PUBDATA_BYTE, L2_L1_LOGS_TREE_DEFAULT_LEAF_HASH} from "./zksync/l1-contracts/zksync/Config.sol";
import {L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR, L2_BOOTLOADER_ADDRESS, L2_ETH_TOKEN_SYSTEM_CONTRACT_ADDR} from "./zksync/l1-contracts/common/L2ContractAddresses.sol";
import {IGetters} from "./zksync/l1-contracts/zksync/interfaces/IGetters.sol";

/// @title ZkLink contract
/// @author zk.link
contract ZkLink is
    IZkLink,
    IMailbox,
    IAdmin,
    IGetters,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using UncheckedMath for uint256;

    /// @dev The forward request type hash
    bytes32 public constant FORWARD_REQUEST_TYPE_HASH =
        keccak256(
            "ForwardL2Request(address gateway,bool isContractCall,address sender,uint256 txId,address contractAddressL2,uint256 l2Value,bytes32 l2CallDataHash,uint256 l2GasLimit,uint256 l2GasPricePerPubdata,bytes32 factoryDepsHash,address refundRecipient)"
        );

    /// @dev The length of withdraw message sent to secondary chain
    uint256 private constant L2_WITHDRAW_MESSAGE_LENGTH = 108;

    /// @dev Whether eth is the gas token
    bool public immutable IS_ETH_GAS_TOKEN;

    /// @notice The gateway is used for communicating with L1
    IL2Gateway public gateway;
    /// @notice List of permitted validators
    mapping(address validatorAddress => bool isValidator) public validators;
    /// @dev The white list allow to send request L2 request
    mapping(address contractAddress => bool isPermitToSendL2Request) public allowLists;
    /// @dev Gas price of primary chain
    uint256 public txGasPrice;
    /// @dev Fee params used to derive gasPrice for the L1->L2 transactions. For L2 transactions,
    /// the bootloader gives enough freedom to the operator.
    FeeParams public feeParams;
    /// @dev The total number of priority operations that were added to the priority queue
    uint256 public totalPriorityTxs;
    /// @dev The total number of synced priority operations
    uint256 public totalSyncedPriorityTxs;
    /// @dev The sync status for each priority operation
    mapping(uint256 priorityOpId => SecondaryChainSyncStatus) public priorityOpSyncStatus;
    /// @notice Total number of executed batches i.e. batches[totalBatchesExecuted] points at the latest executed batch
    /// (batch 0 is genesis)
    uint256 public totalBatchesExecuted;
    /// @dev Stored root hashes of L2 -> L1 logs
    mapping(uint256 batchNumber => bytes32 l2LogsRootHash) public l2LogsRootHashes;
    /// @dev Stored the l2 tx hash map from secondary chain to primary chain
    mapping(bytes32 l2TxHash => bytes32 primaryChainL2TxHash) public l2TxHashMap;
    /// @dev The total forward fee payed to validator
    uint256 public totalValidatorForwardFee;
    /// @dev The total forward fee withdrawn by validator
    uint256 public totalValidatorForwardFeeWithdrawn;
    /// @dev A mapping L2 batch number => message number => flag.
    /// @dev The L2 -> L1 log is sent for every withdrawal, so this mapping is serving as
    /// a flag to indicate that the message was already processed.
    /// @dev Used to indicate that eth withdrawal was already processed
    mapping(uint256 l2BatchNumber => mapping(uint256 l2ToL1MessageNumber => bool isFinalized))
        public isEthWithdrawalFinalized;
    /// @dev The forward fee allocator
    address public forwardFeeAllocator;
    /// @dev The range batch root hash of [fromBatchNumber, toBatchNumber]
    /// The key is keccak256(abi.encodePacked(fromBatchNumber, toBatchNumber))
    mapping(bytes32 range => bytes32 rangeBatchRootHash) public rangBatchRootHashes;
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;

    /// @notice Gateway init
    event InitGateway(IL2Gateway indexed gateway);
    /// @notice Contract's permit status changed
    event ContractAllowStatusUpdate(address indexed contractAddress, bool isPermit);
    /// @notice Tx gas price changed
    event TxGasPriceUpdate(uint256 oldTxGasPrice, uint256 newTxGasPrice);
    /// @notice Validator's status changed
    event ValidatorStatusUpdate(address indexed validatorAddress, bool isActive);
    /// @notice Fee params for L1->L2 transactions changed
    event NewFeeParams(FeeParams oldFeeParams, FeeParams newFeeParams);
    /// @notice New priority request event. Emitted when a request is placed into the priority queue
    event NewPriorityRequest(uint256 priorityOpId, ForwardL2Request l2Request);
    /// @notice Emitted send sync status to primary chain.
    event SyncL2Requests(uint256 totalSyncedPriorityTxs, bytes32 syncHash, uint256 forwardEthAmount);
    /// @notice Emitted when receive batch root from primary chain.
    event SyncBatchRoot(uint256 batchNumber, bytes32 l2LogsRootHash, uint256 forwardEthAmount);
    /// @notice Emitted when receive range batch root hash from primary chain.
    event SyncRangeBatchRoot(
        uint256 fromBatchNumber,
        uint256 toBatchNumber,
        bytes32 rangeBatchRootHash,
        uint256 forwardEthAmount
    );
    /// @notice Emitted when open range batch root hash.
    event OpenRangeBatchRoot(uint256 fromBatchNumber, uint256 toBatchNumber);
    /// @notice Emitted when receive l2 tx hash from primary chain.
    event SyncL2TxHash(bytes32 l2TxHash, bytes32 primaryChainL2TxHash);
    /// @notice Emitted when validator withdraw forward fee
    event WithdrawForwardFee(address indexed receiver, uint256 amount);
    /// @notice Emitted when the withdrawal is finalized on L1 and funds are released.
    /// @param to The address to which the funds were sent
    /// @param amount The amount of funds that were sent
    event EthWithdrawalFinalized(address indexed to, uint256 amount);
    /// @notice Forward fee allocator changed
    event ForwardFeeAllocatorUpdate(address oldAllocator, address newAllocator);

    /// @notice Check if msg sender is gateway
    modifier onlyGateway() {
        require(msg.sender == address(gateway), "Not gateway");
        _;
    }

    /// @notice Checks if validator is active
    modifier onlyValidator() {
        require(validators[msg.sender], "Not validator"); // validator is not active
        _;
    }

    /// @notice Checks if msg sender is forward fee allocator
    modifier onlyForwardFeeAllocator() {
        require(msg.sender == forwardFeeAllocator, "Not forward fee allocator");
        _;
    }

    constructor(bool _isEthGasToken) {
        IS_ETH_GAS_TOKEN = _isEthGasToken;
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // can only called by owner
    }

    /// @dev Pause the contract, can only be called by the owner
    function pause() external onlyOwner {
        _pause();
    }

    /// @dev Unpause the contract, can only be called by the owner
    function unpause() external onlyOwner {
        _unpause();
    }

    function getGateway() external view returns (IL2Gateway) {
        return gateway;
    }

    function getGovernor() external view returns (address) {
        return owner();
    }

    function getTotalBatchesExecuted() external view returns (uint256) {
        return totalBatchesExecuted;
    }

    function getTotalPriorityTxs() external view returns (uint256) {
        return totalPriorityTxs;
    }

    function isValidator(address _address) external view returns (bool) {
        return validators[_address];
    }

    function l2LogsRootHash(uint256 _batchNumber) external view returns (bytes32 merkleRoot) {
        return l2LogsRootHashes[_batchNumber];
    }

    function getPriorityTxMaxGasLimit() public pure returns (uint256) {
        return 72000000;
    }

    /// @dev Init gateway, can only be called by the owner
    function setGateway(IL2Gateway _gateway) external onlyOwner {
        require(address(gateway) == address(0), "Duplicate init gateway");
        require(address(_gateway) != address(0), "Invalid gateway");
        gateway = _gateway;
        emit InitGateway(_gateway);
    }

    /// @dev Update the permit status of contract, can only be called by the owner
    function setAllowList(address _contractAddress, bool _permitted) external onlyOwner {
        if (allowLists[_contractAddress] != _permitted) {
            allowLists[_contractAddress] = _permitted;
            emit ContractAllowStatusUpdate(_contractAddress, _permitted);
        }
    }

    /// @dev Update the tx gas price
    function setTxGasPrice(uint256 _newTxGasPrice) external onlyOwner {
        uint256 oldTxGasPrice = txGasPrice;
        if (oldTxGasPrice != _newTxGasPrice) {
            txGasPrice = _newTxGasPrice;
            emit TxGasPriceUpdate(oldTxGasPrice, _newTxGasPrice);
        }
    }

    function setValidator(address _validator, bool _active) external onlyGateway {
        if (validators[_validator] != _active) {
            validators[_validator] = _active;
            emit ValidatorStatusUpdate(_validator, _active);
        }
    }

    /// @dev https://github.com/matter-labs/era-contracts/blob/e0a33ce73c4decd381446a6eb812b14c2ff69c47/l1-contracts/contracts/zksync/facets/Admin.sol#L88
    function changeFeeParams(FeeParams calldata _newFeeParams) external onlyGateway {
        // Double checking that the new fee params are valid, i.e.
        // the maximal pubdata per batch is not less than the maximal pubdata per priority transaction.
        require(_newFeeParams.maxPubdataPerBatch >= _newFeeParams.priorityTxMaxPubdata, "n6");

        FeeParams memory oldFeeParams = feeParams;
        feeParams = _newFeeParams;

        emit NewFeeParams(oldFeeParams, _newFeeParams);
    }

    /// @dev Update the forward fee allocator
    function setForwardFeeAllocator(address _newForwardFeeAllocator) external onlyOwner {
        require(_newForwardFeeAllocator != address(0), "Invalid allocator");
        address oldAllocator = forwardFeeAllocator;
        if (oldAllocator != _newForwardFeeAllocator) {
            forwardFeeAllocator = _newForwardFeeAllocator;
            emit ForwardFeeAllocatorUpdate(oldAllocator, _newForwardFeeAllocator);
        }
    }

    function l2TransactionBaseCost(
        uint256 _gasPrice,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit
    ) public view returns (uint256) {
        uint256 l2GasPrice = _deriveL2GasPrice(_gasPrice, _l2GasPerPubdataByteLimit);
        return l2GasPrice * _l2GasLimit;
    }

    function requestL2Transaction(
        address _contractL2,
        uint256 _l2Value,
        bytes calldata _calldata,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit,
        bytes[] calldata _factoryDeps,
        address _refundRecipient
    ) external payable nonReentrant whenNotPaused returns (bytes32 canonicalTxHash) {
        // Disable l2 value if eth is not the gas token
        if (!IS_ETH_GAS_TOKEN) {
            require(_l2Value == 0, "Not allow l2 value");
        }
        // Change the sender address if it is a smart contract to prevent address collision between L1 and L2.
        // Please note, currently zkSync address derivation is different from Ethereum one, but it may be changed in the future.
        address sender = msg.sender;
        bool isContractCall = false;
        // solhint-disable-next-line avoid-tx-origin
        if (sender != tx.origin) {
            // Check contract call is allowed for safe reasons
            require(allowLists[sender], "Not allow to send L2 request");
            sender = AddressAliasHelper.applyL1ToL2Alias(msg.sender);
            isContractCall = true;
        } else {
            // Temporarily prohibit contract calls from EOA address for safe reasons
            require(_calldata.length == 0, "Not allow to call contract");
        }

        // Enforcing that `_l2GasPerPubdataByteLimit` equals to a certain constant number. This is needed
        // to ensure that users do not get used to using "exotic" numbers for _l2GasPerPubdataByteLimit, e.g. 1-2, etc.
        // VERY IMPORTANT: nobody should rely on this constant to be fixed and every contract should give their users the ability to provide the
        // ability to provide `_l2GasPerPubdataByteLimit` for each independent transaction.
        // CHANGING THIS CONSTANT SHOULD BE A CLIENT-SIDE CHANGE.
        require(_l2GasPerPubdataByteLimit == REQUIRED_L2_GAS_PRICE_PER_PUBDATA, "Invalid l2GasPerPubdataByteLimit");
        require(_factoryDeps.length <= MAX_NEW_FACTORY_DEPS, "Invalid factoryDeps");

        // Checking that the user provided enough ether to pay for the transaction.
        uint256 l2GasPrice = _deriveL2GasPrice(txGasPrice, _l2GasPerPubdataByteLimit);
        uint256 baseCost = l2GasPrice * _l2GasLimit;
        require(msg.value == baseCost + _l2Value, "Invalid msg value"); // The `msg.value` doesn't cover the transaction cost
        totalValidatorForwardFee = totalValidatorForwardFee + baseCost;

        // If the `_refundRecipient` is not provided, we use the `sender` as the recipient.
        address refundRecipient = _refundRecipient == address(0) ? sender : _refundRecipient;
        // If the `_refundRecipient` is a smart contract, we apply the L1 to L2 alias to prevent foot guns.
        if (refundRecipient.code.length > 0) {
            refundRecipient = AddressAliasHelper.applyL1ToL2Alias(refundRecipient);
        }

        // Build l2 request params
        uint256 _totalPriorityTxs = totalPriorityTxs;
        ForwardL2Request memory request = ForwardL2Request(
            gateway.getRemoteGateway(),
            isContractCall,
            sender,
            _totalPriorityTxs,
            _contractL2,
            _l2Value,
            _calldata,
            _l2GasLimit,
            _l2GasPerPubdataByteLimit,
            _factoryDeps,
            refundRecipient
        );
        // Validate l2 transaction
        {
            L2CanonicalTransaction memory transaction = _serializeL2Transaction(request);
            bytes memory transactionEncoding = abi.encode(transaction);
            TransactionValidator.validateL1ToL2Transaction(
                transaction,
                transactionEncoding,
                getPriorityTxMaxGasLimit(),
                feeParams.priorityTxMaxPubdata
            );
        }
        canonicalTxHash = hashForwardL2Request(request);

        // Accumulate sync status
        SecondaryChainSyncStatus memory syncStatus;
        if (_totalPriorityTxs == 0) {
            syncStatus.hash = canonicalTxHash;
            syncStatus.amount = _l2Value;
        } else {
            syncStatus = priorityOpSyncStatus[_totalPriorityTxs - 1];
            syncStatus.hash = keccak256(abi.encodePacked(syncStatus.hash, canonicalTxHash));
            syncStatus.amount = syncStatus.amount + _l2Value;
        }
        priorityOpSyncStatus[_totalPriorityTxs] = syncStatus;
        totalPriorityTxs = _totalPriorityTxs + 1;

        emit NewPriorityRequest(request.txId, request);
    }

    function finalizeEthWithdrawal(
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes calldata _message,
        bytes32[] calldata _merkleProof
    ) external nonReentrant {
        require(IS_ETH_GAS_TOKEN, "Not allow eth withdraw");
        require(!isEthWithdrawalFinalized[_l2BatchNumber][_l2MessageIndex], "jj");

        L2Message memory l2ToL1Message = L2Message({
            txNumberInBatch: _l2TxNumberInBatch,
            sender: L2_ETH_TOKEN_SYSTEM_CONTRACT_ADDR,
            data: _message
        });

        (address _l1Gateway, uint256 _amount, address _l1WithdrawReceiver) = _parseL2WithdrawalMessage(_message);
        require(_l1Gateway == gateway.getRemoteGateway(), "rg");

        bool proofValid = proveL2MessageInclusion(_l2BatchNumber, _l2MessageIndex, l2ToL1Message, _merkleProof);
        require(proofValid, "pi"); // Failed to verify that withdrawal was actually initialized on L2

        isEthWithdrawalFinalized[_l2BatchNumber][_l2MessageIndex] = true;
        _withdrawFunds(_l1WithdrawReceiver, _amount);

        emit EthWithdrawalFinalized(_l1WithdrawReceiver, _amount);
    }

    function proveL2MessageInclusion(
        uint256 _batchNumber,
        uint256 _index,
        L2Message memory _message,
        bytes32[] calldata _proof
    ) public view returns (bool) {
        return _proveL2LogInclusion(_batchNumber, _index, _L2MessageToLog(_message), _proof);
    }

    function proveL1ToL2TransactionStatus(
        bytes32 _l2TxHash,
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _merkleProof,
        TxStatus _status
    ) public view returns (bool) {
        // Get l2 tx hash on primary chain
        bytes32 primaryChainL2TxHash = l2TxHashMap[_l2TxHash];
        require(primaryChainL2TxHash != bytes32(0), "Invalid l2 tx hash");

        // Bootloader sends an L2 -> L1 log only after processing the L1 -> L2 transaction.
        // Thus, we can verify that the L1 -> L2 transaction was included in the L2 batch with specified status.
        //
        // The semantics of such L2 -> L1 log is always:
        // - sender = L2_BOOTLOADER_ADDRESS
        // - key = hash(L1ToL2Transaction)
        // - value = status of the processing transaction (1 - success & 0 - fail)
        // - isService = true (just a conventional value)
        // - l2ShardId = 0 (means that L1 -> L2 transaction was processed in a rollup shard, other shards are not available yet anyway)
        // - txNumberInBatch = number of transaction in the batch
        L2Log memory l2Log = L2Log({
            l2ShardId: 0,
            isService: true,
            txNumberInBatch: _l2TxNumberInBatch,
            sender: L2_BOOTLOADER_ADDRESS,
            key: primaryChainL2TxHash,
            value: bytes32(uint256(_status))
        });
        return _proveL2LogInclusion(_l2BatchNumber, _l2MessageIndex, l2Log, _merkleProof);
    }

    function syncL2Requests(uint256 _newTotalSyncedPriorityTxs) external payable onlyValidator {
        // Check newTotalSyncedPriorityTxs
        require(
            _newTotalSyncedPriorityTxs <= totalPriorityTxs && _newTotalSyncedPriorityTxs > totalSyncedPriorityTxs,
            "Invalid sync point"
        );

        // Forward eth amount is the difference of two accumulate amount
        SecondaryChainSyncStatus memory lastSyncStatus;
        if (totalSyncedPriorityTxs > 0) {
            lastSyncStatus = priorityOpSyncStatus[totalSyncedPriorityTxs - 1];
        }
        SecondaryChainSyncStatus memory currentSyncStatus = priorityOpSyncStatus[_newTotalSyncedPriorityTxs - 1];
        uint256 forwardAmount = currentSyncStatus.amount - lastSyncStatus.amount;

        // Update synced priority txs
        totalSyncedPriorityTxs = _newTotalSyncedPriorityTxs;

        // Send sync status to L1 gateway
        bytes memory callData = abi.encodeCall(
            IZkSync.syncL2Requests,
            (gateway.getRemoteGateway(), _newTotalSyncedPriorityTxs, currentSyncStatus.hash, forwardAmount)
        );
        gateway.sendMessage{value: msg.value + forwardAmount}(forwardAmount, callData);

        emit SyncL2Requests(_newTotalSyncedPriorityTxs, currentSyncStatus.hash, forwardAmount);
    }

    function syncBatchRoot(
        uint256 _batchNumber,
        bytes32 _l2LogsRootHash,
        uint256 _forwardEthAmount
    ) external payable onlyGateway {
        require(msg.value == _forwardEthAmount, "Invalid forward amount");
        // Allows repeated sending of the forward amount of the batch
        if (_batchNumber > totalBatchesExecuted) {
            totalBatchesExecuted = _batchNumber;
        }
        l2LogsRootHashes[_batchNumber] = _l2LogsRootHash;
        emit SyncBatchRoot(_batchNumber, _l2LogsRootHash, _forwardEthAmount);
    }

    function syncRangeBatchRoot(
        uint256 _fromBatchNumber,
        uint256 _toBatchNumber,
        bytes32 _rangeBatchRootHash,
        uint256 _forwardEthAmount
    ) external payable onlyGateway {
        require(_toBatchNumber >= _fromBatchNumber, "Invalid range");
        require(msg.value == _forwardEthAmount, "Invalid forward amount");
        bytes32 range = keccak256(abi.encodePacked(_fromBatchNumber, _toBatchNumber));
        rangBatchRootHashes[range] = _rangeBatchRootHash;
        emit SyncRangeBatchRoot(_fromBatchNumber, _toBatchNumber, _rangeBatchRootHash, _forwardEthAmount);
    }

    /// @dev Unzip the root hashes in the range
    /// @param _fromBatchNumber The batch number from
    /// @param _toBatchNumber The batch number to
    /// @param _l2LogsRootHashes The l2LogsRootHash list in the range [`_fromBatchNumber`, `_toBatchNumber`]
    function openRangeBatchRootHash(
        uint256 _fromBatchNumber,
        uint256 _toBatchNumber,
        bytes32[] memory _l2LogsRootHashes
    ) external onlyValidator {
        require(_toBatchNumber >= _fromBatchNumber, "Invalid range");
        bytes32 range = keccak256(abi.encodePacked(_fromBatchNumber, _toBatchNumber));
        bytes32 rangeBatchRootHash = rangBatchRootHashes[range];
        require(rangeBatchRootHash != bytes32(0), "Rang batch root hash not exist");
        uint256 rootHashesLength = _l2LogsRootHashes.length;
        require(rootHashesLength == _toBatchNumber - _fromBatchNumber + 1, "Invalid root hashes length");
        bytes32 _rangeBatchRootHash = _l2LogsRootHashes[0];
        l2LogsRootHashes[_fromBatchNumber] = _rangeBatchRootHash;
        unchecked {
            for (uint256 i = 1; i < rootHashesLength; ++i) {
                bytes32 _l2LogsRootHash = _l2LogsRootHashes[i];
                l2LogsRootHashes[_fromBatchNumber + i] = _l2LogsRootHash;
                _rangeBatchRootHash = Merkle._efficientHash(_rangeBatchRootHash, _l2LogsRootHash);
            }
        }
        require(_rangeBatchRootHash == rangeBatchRootHash, "Incorrect root hash");
        delete rangBatchRootHashes[range];
        if (_toBatchNumber > totalBatchesExecuted) {
            totalBatchesExecuted = _toBatchNumber;
        }
        emit OpenRangeBatchRoot(_fromBatchNumber, _toBatchNumber);
    }

    function syncL2TxHash(bytes32 _l2TxHash, bytes32 _primaryChainL2TxHash) external onlyGateway {
        l2TxHashMap[_l2TxHash] = _primaryChainL2TxHash;
        emit SyncL2TxHash(_l2TxHash, _primaryChainL2TxHash);
    }

    function withdrawForwardFee(address _receiver, uint256 _amount) external nonReentrant onlyForwardFeeAllocator {
        require(_amount > 0, "Invalid amount");
        uint256 newWithdrawnFee = totalValidatorForwardFeeWithdrawn + _amount;
        require(totalValidatorForwardFee >= newWithdrawnFee, "Withdraw exceed");

        // Update withdrawn fee
        totalValidatorForwardFeeWithdrawn = newWithdrawnFee;
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = _receiver.call{value: _amount}("");
        require(success, "Withdraw failed");
        emit WithdrawForwardFee(_receiver, _amount);
    }

    /// @notice Derives the price for L2 gas in ETH to be paid.
    /// @dev https://github.com/matter-labs/era-contracts/blob/e0a33ce73c4decd381446a6eb812b14c2ff69c47/l1-contracts/contracts/zksync/facets/Mailbox.sol#L147
    /// @param _l1GasPrice The gas price on L1.
    /// @param _gasPerPubdata The price for each pubdata byte in L2 gas
    /// @return The price of L2 gas in ETH
    function _deriveL2GasPrice(uint256 _l1GasPrice, uint256 _gasPerPubdata) internal view returns (uint256) {
        FeeParams memory _feeParams = feeParams;

        uint256 pubdataPriceETH;
        if (_feeParams.pubdataPricingMode == PubdataPricingMode.Rollup) {
            pubdataPriceETH = L1_GAS_PER_PUBDATA_BYTE * _l1GasPrice;
        }

        uint256 batchOverheadETH = uint256(_feeParams.batchOverheadL1Gas) * _l1GasPrice;
        uint256 fullPubdataPriceETH = pubdataPriceETH + batchOverheadETH / uint256(_feeParams.maxPubdataPerBatch);

        uint256 l2GasPrice = _feeParams.minimalL2GasPrice + batchOverheadETH / uint256(_feeParams.maxL2GasPerBatch);
        uint256 minL2GasPriceETH = (fullPubdataPriceETH + _gasPerPubdata - 1) / _gasPerPubdata;

        return Math.max(l2GasPrice, minL2GasPriceETH);
    }

    function _serializeL2Transaction(
        ForwardL2Request memory _request
    ) internal pure returns (L2CanonicalTransaction memory transaction) {
        transaction = L2CanonicalTransaction({
            txType: uint256(0),
            from: uint256(0),
            to: uint256(0),
            gasLimit: _request.l2GasLimit, // Used in validate l2 transaction
            gasPerPubdataByteLimit: _request.l2GasPricePerPubdata, // Used in validate l2 transaction
            maxFeePerGas: uint256(0),
            maxPriorityFeePerGas: uint256(0),
            paymaster: uint256(0),
            nonce: uint256(0),
            value: uint256(0),
            reserved: [uint256(0), uint256(0), uint256(0), uint256(0)],
            data: _request.l2CallData, // Length used in validate l2 transaction
            signature: new bytes(0),
            factoryDeps: new uint256[](_request.factoryDeps.length), // Length used in validate l2 transaction
            paymasterInput: new bytes(0),
            reservedDynamic: new bytes(0)
        });
    }

    /// @dev Convert arbitrary-length message to the raw l2 log
    function _L2MessageToLog(L2Message memory _message) internal pure returns (L2Log memory) {
        return
            L2Log({
                l2ShardId: 0,
                isService: true,
                txNumberInBatch: _message.txNumberInBatch,
                sender: L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR,
                key: bytes32(uint256(uint160(_message.sender))),
                value: keccak256(_message.data)
            });
    }

    /// @dev Prove that a specific L2 log was sent in a specific L2 batch number
    function _proveL2LogInclusion(
        uint256 _batchNumber,
        uint256 _index,
        L2Log memory _log,
        bytes32[] calldata _proof
    ) internal view returns (bool) {
        require(_batchNumber <= totalBatchesExecuted, "xx");

        bytes32 hashedLog = keccak256(
            abi.encodePacked(_log.l2ShardId, _log.isService, _log.txNumberInBatch, _log.sender, _log.key, _log.value)
        );
        // Check that hashed log is not the default one,
        // otherwise it means that the value is out of range of sent L2 -> L1 logs
        require(hashedLog != L2_L1_LOGS_TREE_DEFAULT_LEAF_HASH, "tw");

        // It is ok to not check length of `_proof` array, as length
        // of leaf preimage (which is `L2_TO_L1_LOG_SERIALIZE_SIZE`) is not
        // equal to the length of other nodes preimages (which are `2 * 32`)

        bytes32 calculatedRootHash = Merkle.calculateRoot(_proof, _index, hashedLog);
        bytes32 actualRootHash = l2LogsRootHashes[_batchNumber];

        return actualRootHash == calculatedRootHash;
    }

    /// @dev Decode the withdraw message that came from L2
    function _parseL2WithdrawalMessage(
        bytes memory _message
    ) internal pure returns (address l1Gateway, uint256 amount, address l1Receiver) {
        // We check that the message is long enough to read the data.
        // Please note that there are two versions of the message:
        // 1. The message that is sent by `withdraw(address _l1Receiver)`
        // It should be equal to the length of the bytes4 function signature + address l1Receiver + uint256 amount = 4 + 20 + 32 = 56 (bytes).
        // 2. The message that is sent by `withdrawWithMessage(address _l1Receiver, bytes calldata _additionalData)`
        // It should be equal to the length of the following:
        // bytes4 function signature + address l1Gateway + uint256 amount + address l2Sender + bytes _additionalData
        // (where the _additionalData = abi.encode(l1Receiver))
        // = 4 + 20 + 32 + 20 + 32 == 108 (bytes).
        require(_message.length == L2_WITHDRAW_MESSAGE_LENGTH, "pm");

        (uint32 functionSignature, uint256 offset) = UnsafeBytes.readUint32(_message, 0);
        require(bytes4(functionSignature) == this.finalizeEthWithdrawal.selector, "is");

        (l1Gateway, offset) = UnsafeBytes.readAddress(_message, offset);
        (amount, offset) = UnsafeBytes.readUint256(_message, offset);
        // The additional data is l1 receiver address
        (l1Receiver, offset) = UnsafeBytes.readAddress(_message, offset + 32);
    }

    /// @notice Transfer ether from the contract to the receiver
    /// @dev Reverts only if the transfer call failed
    function _withdrawFunds(address _to, uint256 _amount) internal {
        bool callSuccess;
        // Low-level assembly call, to avoid any memory copying (save gas)
        assembly {
            callSuccess := call(gas(), _to, _amount, 0, 0, 0, 0)
        }
        require(callSuccess, "pz");
    }

    function hashForwardL2Request(ForwardL2Request memory _request) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    FORWARD_REQUEST_TYPE_HASH,
                    _request.gateway,
                    _request.isContractCall,
                    _request.sender,
                    _request.txId,
                    _request.contractAddressL2,
                    _request.l2Value,
                    keccak256(_request.l2CallData),
                    _request.l2GasLimit,
                    _request.l2GasPricePerPubdata,
                    keccak256(abi.encode(_request.factoryDeps)),
                    _request.refundRecipient
                )
            );
    }
}
