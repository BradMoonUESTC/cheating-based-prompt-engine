// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IMailbox, TxStatus} from "../interfaces/IMailbox.sol";
import {IZkLink} from "../interfaces/IZkLink.sol";
import {Merkle} from "../libraries/Merkle.sol";
import {PriorityQueue, PriorityOperation} from "../libraries/PriorityQueue.sol";
import {TransactionValidator} from "../libraries/TransactionValidator.sol";
import {L2Message, L2Log, FeeParams, PubdataPricingMode, SecondaryChain, SecondaryChainSyncStatus, SecondaryChainOp} from "../Storage.sol";
import {UncheckedMath} from "../../common/libraries/UncheckedMath.sol";
import {UnsafeBytes} from "../../common/libraries/UnsafeBytes.sol";
import {L2ContractHelper} from "../../common/libraries/L2ContractHelper.sol";
import {AddressAliasHelper} from "../../vendor/AddressAliasHelper.sol";
import {Base} from "./Base.sol";
import {REQUIRED_L2_GAS_PRICE_PER_PUBDATA, L1_GAS_PER_PUBDATA_BYTE, L2_L1_LOGS_TREE_DEFAULT_LEAF_HASH, PRIORITY_OPERATION_L2_TX_TYPE, PRIORITY_EXPIRATION, MAX_NEW_FACTORY_DEPS} from "../Config.sol";
import {L2_BOOTLOADER_ADDRESS, L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR, L2_ETH_TOKEN_SYSTEM_CONTRACT_ADDR} from "../../common/L2ContractAddresses.sol";

// While formally the following import is not used, it is needed to inherit documentation from it
import {IBase} from "../interfaces/IBase.sol";

/// @title zkSync Mailbox contract providing interfaces for L1 <-> L2 interaction.
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
contract MailboxFacet is Base, IMailbox {
    using UncheckedMath for uint256;
    using PriorityQueue for PriorityQueue.Queue;

    /// @inheritdoc IBase
    string public constant override getName = "MailboxFacet";

    /// @dev The forward request type hash
    bytes32 public constant FORWARD_REQUEST_TYPE_HASH =
        keccak256(
            "ForwardL2Request(address gateway,bool isContractCall,address sender,uint256 txId,address contractAddressL2,uint256 l2Value,bytes32 l2CallDataHash,uint256 l2GasLimit,uint256 l2GasPricePerPubdata,bytes32 factoryDepsHash,address refundRecipient)"
        );

    /// @inheritdoc IMailbox
    function proveL2MessageInclusion(
        uint256 _batchNumber,
        uint256 _index,
        L2Message memory _message,
        bytes32[] calldata _proof
    ) public view returns (bool) {
        return _proveL2LogInclusion(_batchNumber, _index, _L2MessageToLog(_message), _proof);
    }

    /// @inheritdoc IMailbox
    function proveL2LogInclusion(
        uint256 _batchNumber,
        uint256 _index,
        L2Log memory _log,
        bytes32[] calldata _proof
    ) external view returns (bool) {
        return _proveL2LogInclusion(_batchNumber, _index, _log, _proof);
    }

    /// @inheritdoc IMailbox
    function proveL1ToL2TransactionStatus(
        bytes32 _l2TxHash,
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _merkleProof,
        TxStatus _status
    ) public view returns (bool) {
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
            key: _l2TxHash,
            value: bytes32(uint256(_status))
        });
        return _proveL2LogInclusion(_l2BatchNumber, _l2MessageIndex, l2Log, _merkleProof);
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

    /// @dev Prove that a specific L2 log was sent in a specific L2 batch number
    function _proveL2LogInclusion(
        uint256 _batchNumber,
        uint256 _index,
        L2Log memory _log,
        bytes32[] calldata _proof
    ) internal view returns (bool) {
        require(_batchNumber <= s.totalBatchesExecuted, "xx");

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
        bytes32 actualRootHash = s.l2LogsRootHashes[_batchNumber];

        return actualRootHash == calculatedRootHash;
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

    /// @inheritdoc IMailbox
    function l2TransactionBaseCost(
        uint256 _gasPrice,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit
    ) public view returns (uint256) {
        uint256 l2GasPrice = _deriveL2GasPrice(_gasPrice, _l2GasPerPubdataByteLimit);
        return l2GasPrice * _l2GasLimit;
    }

    /// @inheritdoc IMailbox
    function syncL2Requests(
        address _secondaryChainGateway,
        uint256 _newTotalSyncedPriorityTxs,
        bytes32 _syncHash,
        uint256 _forwardEthAmount
    ) external payable onlyGateway {
        // Secondary chain should be registered
        SecondaryChain memory secondaryChain = s.secondaryChains[_secondaryChainGateway];
        require(secondaryChain.valid, "ssc");

        // Check newTotalSyncedPriorityTxs
        require(
            _newTotalSyncedPriorityTxs <= secondaryChain.totalPriorityTxs &&
                _newTotalSyncedPriorityTxs > secondaryChain.totalSyncedPriorityTxs,
            "spt"
        );

        // Check sync hash at new point
        SecondaryChainSyncStatus memory syncStatus = s.secondaryChainSyncStatus[_secondaryChainGateway][
            _newTotalSyncedPriorityTxs - 1
        ];
        require(syncStatus.hash == _syncHash, "ssh");

        // Check forward eth amount
        SecondaryChainSyncStatus memory lastSyncStatus;
        if (secondaryChain.totalSyncedPriorityTxs > 0) {
            lastSyncStatus = s.secondaryChainSyncStatus[_secondaryChainGateway][
                secondaryChain.totalSyncedPriorityTxs - 1
            ];
        }
        require(syncStatus.amount - lastSyncStatus.amount == _forwardEthAmount, "sfm");
        require(msg.value == _forwardEthAmount, "smv");

        // Update totalSyncedPriorityTxs
        s.secondaryChains[_secondaryChainGateway].totalSyncedPriorityTxs = _newTotalSyncedPriorityTxs;
        emit SyncL2Requests(_secondaryChainGateway, _newTotalSyncedPriorityTxs, _syncHash, _forwardEthAmount);
    }

    /// @inheritdoc IMailbox
    function syncBatchRoot(
        address _secondaryChainGateway,
        uint256 _batchNumber,
        uint256 _forwardEthAmount
    ) external payable nonReentrant onlyValidator {
        // Secondary chain should be registered
        SecondaryChain memory secondaryChain = s.secondaryChains[_secondaryChainGateway];
        require(secondaryChain.valid, "bsc");

        // The batch should be executed
        require(_batchNumber <= s.totalBatchesExecuted, "bsl");
        bytes32 l2LogsRootHash = s.l2LogsRootHashes[_batchNumber];

        // Check the forward eth amount
        require(_forwardEthAmount <= secondaryChain.totalPendingWithdraw, "bwn");
        s.secondaryChains[_secondaryChainGateway].totalPendingWithdraw =
            secondaryChain.totalPendingWithdraw -
            _forwardEthAmount;

        // Send batch root to secondary chain by gateway
        bytes[] memory gatewayDataList = new bytes[](1);
        bytes memory callData = abi.encodeCall(
            IZkLink.syncBatchRoot,
            (_batchNumber, l2LogsRootHash, _forwardEthAmount)
        );
        gatewayDataList[0] = abi.encode(_secondaryChainGateway, _forwardEthAmount, callData);
        // Forward fee to gateway
        s.gateway.sendMessage{value: msg.value + _forwardEthAmount}(_forwardEthAmount, abi.encode(gatewayDataList));
        emit SyncBatchRoot(_secondaryChainGateway, _batchNumber, _forwardEthAmount);
    }

    /// @inheritdoc IMailbox
    function syncRangeBatchRoot(
        address[] calldata _secondaryChainGateways,
        uint256 _fromBatchNumber,
        uint256 _toBatchNumber
    ) external payable nonReentrant onlyValidator {
        // The batch should be executed
        require(_fromBatchNumber <= _toBatchNumber, "brf");
        require(_toBatchNumber <= s.totalBatchesExecuted, "brt");

        bytes32 rangeBatchRootHash = s.l2LogsRootHashes[_fromBatchNumber];
        unchecked {
            for (uint256 i = _fromBatchNumber + 1; i <= _toBatchNumber; ++i) {
                bytes32 l2LogsRootHash = s.l2LogsRootHashes[i];
                rangeBatchRootHash = Merkle._efficientHash(rangeBatchRootHash, l2LogsRootHash);
            }
        }

        uint256 gatewayLength = _secondaryChainGateways.length;
        bytes[] memory gatewayDataList = new bytes[](gatewayLength);
        uint256 totalForwardEthAmount = 0;
        unchecked {
            for (uint256 i = 0; i < gatewayLength; ++i) {
                // Secondary chain should be registered
                address _secondaryChainGateway = _secondaryChainGateways[i];
                SecondaryChain memory secondaryChain = s.secondaryChains[_secondaryChainGateway];
                require(secondaryChain.valid, "bsc");
                uint256 _forwardEthAmount = s.secondaryChains[_secondaryChainGateway].totalPendingWithdraw;
                // Withdraw eth amount impossible overflow
                totalForwardEthAmount += _forwardEthAmount;
                s.secondaryChains[_secondaryChainGateway].totalPendingWithdraw = 0;
                // Send range batch root to secondary chain
                bytes memory gatewayCallData = abi.encodeCall(
                    IZkLink.syncRangeBatchRoot,
                    (_fromBatchNumber, _toBatchNumber, rangeBatchRootHash, _forwardEthAmount)
                );
                gatewayDataList[i] = abi.encode(_secondaryChainGateway, _forwardEthAmount, gatewayCallData);
                emit SyncRangeBatchRoot(
                    _secondaryChainGateway,
                    _fromBatchNumber,
                    _toBatchNumber,
                    rangeBatchRootHash,
                    _forwardEthAmount
                );
            }
        }

        // Forward fee to gateway
        s.gateway.sendMessage{value: msg.value + totalForwardEthAmount}(
            totalForwardEthAmount,
            abi.encode(gatewayDataList)
        );
    }

    /// @inheritdoc IMailbox
    function syncL2TxHash(bytes32 _l2TxHash) external payable nonReentrant onlyValidator {
        SecondaryChainOp memory op = s.canonicalTxToSecondaryChainOp[_l2TxHash];
        require(op.gateway != address(0), "tsc");

        // Send l2 tx hash to secondary chain by gateway
        bytes[] memory gatewayDataList = new bytes[](1);
        bytes memory callData = abi.encodeCall(IZkLink.syncL2TxHash, (op.canonicalTxHash, _l2TxHash));
        gatewayDataList[0] = abi.encode(op.gateway, 0, callData);
        // Forward fee to gateway
        s.gateway.sendMessage{value: msg.value}(0, abi.encode(gatewayDataList));
        emit SyncL2TxHash(_l2TxHash);
    }

    /// @notice Derives the price for L2 gas in ETH to be paid.
    /// @param _l1GasPrice The gas price on L1.
    /// @param _gasPerPubdata The price for each pubdata byte in L2 gas
    /// @return The price of L2 gas in ETH
    function _deriveL2GasPrice(uint256 _l1GasPrice, uint256 _gasPerPubdata) internal view returns (uint256) {
        FeeParams memory feeParams = s.feeParams;

        uint256 pubdataPriceETH;
        if (feeParams.pubdataPricingMode == PubdataPricingMode.Rollup) {
            pubdataPriceETH = L1_GAS_PER_PUBDATA_BYTE * _l1GasPrice;
        }

        uint256 batchOverheadETH = uint256(feeParams.batchOverheadL1Gas) * _l1GasPrice;
        uint256 fullPubdataPriceETH = pubdataPriceETH + batchOverheadETH / uint256(feeParams.maxPubdataPerBatch);

        uint256 l2GasPrice = feeParams.minimalL2GasPrice + batchOverheadETH / uint256(feeParams.maxL2GasPerBatch);
        uint256 minL2GasPriceETH = (fullPubdataPriceETH + _gasPerPubdata - 1) / _gasPerPubdata;

        return Math.max(l2GasPrice, minL2GasPriceETH);
    }

    /// @inheritdoc IMailbox
    function finalizeEthWithdrawal(
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes calldata _message,
        bytes32[] calldata _merkleProof
    ) external nonReentrant {
        require(!s.isEthWithdrawalFinalized[_l2BatchNumber][_l2MessageIndex], "jj");

        L2Message memory l2ToL1Message = L2Message({
            txNumberInBatch: _l2TxNumberInBatch,
            sender: L2_ETH_TOKEN_SYSTEM_CONTRACT_ADDR,
            data: _message
        });

        (address _l1WithdrawReceiver, uint256 _amount) = _parseL2WithdrawalMessage(_message);

        bool proofValid = proveL2MessageInclusion(_l2BatchNumber, _l2MessageIndex, l2ToL1Message, _merkleProof);
        require(proofValid, "pi"); // Failed to verify that withdrawal was actually initialized on L2

        s.isEthWithdrawalFinalized[_l2BatchNumber][_l2MessageIndex] = true;
        if (s.secondaryChains[_l1WithdrawReceiver].valid) {
            s.secondaryChains[_l1WithdrawReceiver].totalPendingWithdraw += _amount;
        } else {
            _withdrawFunds(_l1WithdrawReceiver, _amount);
        }

        emit EthWithdrawalFinalized(_l1WithdrawReceiver, _amount);
    }

    /// @inheritdoc IMailbox
    function requestL2Transaction(
        address _contractL2,
        uint256 _l2Value,
        bytes calldata _calldata,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit,
        bytes[] calldata _factoryDeps,
        address _refundRecipient
    ) external payable nonReentrant returns (bytes32 canonicalTxHash) {
        // Change the sender address if it is a smart contract to prevent address collision between L1 and L2.
        // Please note, currently zkSync address derivation is different from Ethereum one, but it may be changed in the future.
        address sender = msg.sender;
        if (sender != tx.origin) {
            sender = AddressAliasHelper.applyL1ToL2Alias(msg.sender);
        }

        // Enforcing that `_l2GasPerPubdataByteLimit` equals to a certain constant number. This is needed
        // to ensure that users do not get used to using "exotic" numbers for _l2GasPerPubdataByteLimit, e.g. 1-2, etc.
        // VERY IMPORTANT: nobody should rely on this constant to be fixed and every contract should give their users the ability to provide the
        // ability to provide `_l2GasPerPubdataByteLimit` for each independent transaction.
        // CHANGING THIS CONSTANT SHOULD BE A CLIENT-SIDE CHANGE.
        require(_l2GasPerPubdataByteLimit == REQUIRED_L2_GAS_PRICE_PER_PUBDATA, "qp");

        canonicalTxHash = _requestL2Transaction(
            sender,
            _contractL2,
            _l2Value,
            _calldata,
            _l2GasLimit,
            _l2GasPerPubdataByteLimit,
            _factoryDeps,
            false,
            _refundRecipient
        );
    }

    /// @inheritdoc IMailbox
    function forwardRequestL2Transaction(
        ForwardL2Request calldata _request
    ) external payable nonReentrant onlyValidator returns (bytes32 canonicalTxHash) {
        bytes32 secondaryChainCanonicalTxHash = hashForwardL2Request(_request);
        {
            SecondaryChain memory secondaryChain = s.secondaryChains[_request.gateway];
            require(secondaryChain.valid, "fsc");
            require(secondaryChain.totalPriorityTxs == _request.txId, "fst");

            SecondaryChainSyncStatus memory syncStatus;
            if (secondaryChain.totalPriorityTxs == 0) {
                syncStatus.hash = secondaryChainCanonicalTxHash;
                syncStatus.amount = _request.l2Value;
            } else {
                syncStatus = s.secondaryChainSyncStatus[_request.gateway][secondaryChain.totalPriorityTxs - 1];
                syncStatus.hash = keccak256(abi.encodePacked(syncStatus.hash, secondaryChainCanonicalTxHash));
                syncStatus.amount = syncStatus.amount + _request.l2Value;
            }
            s.secondaryChainSyncStatus[_request.gateway][secondaryChain.totalPriorityTxs] = syncStatus;
            s.secondaryChains[_request.gateway].totalPriorityTxs = secondaryChain.totalPriorityTxs + 1;
        }

        // Here we manually assign fields for the struct to prevent "stack too deep" error
        WritePriorityOpParams memory params;
        params.sender = _request.sender;
        params.txId = s.priorityQueue.getTotalPriorityTxs();
        params.l2Value = _request.l2Value;
        params.contractAddressL2 = _request.contractAddressL2;
        params.expirationTimestamp = uint64(block.timestamp + PRIORITY_EXPIRATION); // Safe to cast
        params.l2GasLimit = _request.l2GasLimit;

        // Checking that the user provided enough ether to pay for the transaction.
        // Using a new scope to prevent "stack too deep" error
        {
            params.l2GasPrice = _deriveL2GasPrice(tx.gasprice, _request.l2GasPricePerPubdata);
            uint256 baseCost = params.l2GasPrice * _request.l2GasLimit;
            require(msg.value >= baseCost, "fmv"); // The `msg.value` doesn't cover the transaction cost
            uint256 leftMsgValue = msg.value - baseCost;
            if (leftMsgValue > 0) {
                // solhint-disable-next-line avoid-low-level-calls
                (bool success, ) = msg.sender.call{value: leftMsgValue}("");
                require(success, "fse");
            }
            params.valueToMint = baseCost + _request.l2Value;
        }
        params.l2GasPricePerPubdata = _request.l2GasPricePerPubdata;
        {
            // If the `_refundRecipient` is a smart contract, we apply the L1 to L2 alias to prevent foot guns.
            address refundRecipient = _request.refundRecipient;
            if (refundRecipient.code.length > 0) {
                refundRecipient = AddressAliasHelper.applyL1ToL2Alias(refundRecipient);
            }
            params.refundRecipient = refundRecipient;
        }

        canonicalTxHash = _writePriorityOp(params, _request.l2CallData, _request.factoryDeps);
        s.canonicalTxToSecondaryChainOp[canonicalTxHash] = SecondaryChainOp(
            _request.gateway,
            _request.txId,
            secondaryChainCanonicalTxHash
        );
        s.secondaryToCanonicalTxHash[secondaryChainCanonicalTxHash] = canonicalTxHash;
    }

    function _requestL2Transaction(
        address _sender,
        address _contractAddressL2,
        uint256 _l2Value,
        bytes calldata _calldata,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit,
        bytes[] calldata _factoryDeps,
        bool _isFree,
        address _refundRecipient
    ) internal returns (bytes32 canonicalTxHash) {
        require(_factoryDeps.length <= MAX_NEW_FACTORY_DEPS, "uj");
        uint64 expirationTimestamp = uint64(block.timestamp + PRIORITY_EXPIRATION); // Safe to cast
        uint256 txId = s.priorityQueue.getTotalPriorityTxs();

        // Here we manually assign fields for the struct to prevent "stack too deep" error
        WritePriorityOpParams memory params;

        // Checking that the user provided enough ether to pay for the transaction.
        // Using a new scope to prevent "stack too deep" error
        {
            params.l2GasPrice = _isFree ? 0 : _deriveL2GasPrice(tx.gasprice, _l2GasPerPubdataByteLimit);
            uint256 baseCost = params.l2GasPrice * _l2GasLimit;
            require(msg.value >= baseCost + _l2Value, "mv"); // The `msg.value` doesn't cover the transaction cost
        }

        // If the `_refundRecipient` is not provided, we use the `_sender` as the recipient.
        address refundRecipient = _refundRecipient == address(0) ? _sender : _refundRecipient;
        // If the `_refundRecipient` is a smart contract, we apply the L1 to L2 alias to prevent foot guns.
        if (refundRecipient.code.length > 0) {
            refundRecipient = AddressAliasHelper.applyL1ToL2Alias(refundRecipient);
        }

        params.sender = _sender;
        params.txId = txId;
        params.l2Value = _l2Value;
        params.contractAddressL2 = _contractAddressL2;
        params.expirationTimestamp = expirationTimestamp;
        params.l2GasLimit = _l2GasLimit;
        params.l2GasPricePerPubdata = _l2GasPerPubdataByteLimit;
        params.valueToMint = msg.value;
        params.refundRecipient = refundRecipient;

        canonicalTxHash = _writePriorityOp(params, _calldata, _factoryDeps);
    }

    function _serializeL2Transaction(
        WritePriorityOpParams memory _priorityOpParams,
        bytes calldata _calldata,
        bytes[] calldata _factoryDeps
    ) internal pure returns (L2CanonicalTransaction memory transaction) {
        transaction = L2CanonicalTransaction({
            txType: PRIORITY_OPERATION_L2_TX_TYPE,
            from: uint256(uint160(_priorityOpParams.sender)),
            to: uint256(uint160(_priorityOpParams.contractAddressL2)),
            gasLimit: _priorityOpParams.l2GasLimit,
            gasPerPubdataByteLimit: _priorityOpParams.l2GasPricePerPubdata,
            maxFeePerGas: uint256(_priorityOpParams.l2GasPrice),
            maxPriorityFeePerGas: uint256(0),
            paymaster: uint256(0),
            // Note, that the priority operation id is used as "nonce" for L1->L2 transactions
            nonce: uint256(_priorityOpParams.txId),
            value: _priorityOpParams.l2Value,
            reserved: [_priorityOpParams.valueToMint, uint256(uint160(_priorityOpParams.refundRecipient)), 0, 0],
            data: _calldata,
            signature: new bytes(0),
            factoryDeps: _hashFactoryDeps(_factoryDeps),
            paymasterInput: new bytes(0),
            reservedDynamic: new bytes(0)
        });
    }

    /// @notice Stores a transaction record in storage & send event about that
    function _writePriorityOp(
        WritePriorityOpParams memory _priorityOpParams,
        bytes calldata _calldata,
        bytes[] calldata _factoryDeps
    ) internal returns (bytes32 canonicalTxHash) {
        L2CanonicalTransaction memory transaction = _serializeL2Transaction(_priorityOpParams, _calldata, _factoryDeps);

        bytes memory transactionEncoding = abi.encode(transaction);

        TransactionValidator.validateL1ToL2Transaction(
            transaction,
            transactionEncoding,
            s.priorityTxMaxGasLimit,
            s.feeParams.priorityTxMaxPubdata
        );

        canonicalTxHash = keccak256(transactionEncoding);

        s.priorityQueue.pushBack(
            PriorityOperation({
                canonicalTxHash: canonicalTxHash,
                expirationTimestamp: _priorityOpParams.expirationTimestamp,
                layer2Tip: uint192(0) // TODO: Restore after fee modeling will be stable. (SMA-1230)
            })
        );

        // Data that is needed for the operator to simulate priority queue offchain
        emit NewPriorityRequest(
            _priorityOpParams.txId,
            canonicalTxHash,
            _priorityOpParams.expirationTimestamp,
            transaction,
            _factoryDeps
        );
    }

    /// @notice Hashes the L2 bytecodes and returns them in the format in which they are processed by the bootloader
    function _hashFactoryDeps(
        bytes[] calldata _factoryDeps
    ) internal pure returns (uint256[] memory hashedFactoryDeps) {
        uint256 factoryDepsLen = _factoryDeps.length;
        hashedFactoryDeps = new uint256[](factoryDepsLen);
        for (uint256 i = 0; i < factoryDepsLen; i = i.uncheckedInc()) {
            bytes32 hashedBytecode = L2ContractHelper.hashL2Bytecode(_factoryDeps[i]);

            // Store the resulting hash sequentially in bytes.
            assembly {
                mstore(add(hashedFactoryDeps, mul(add(i, 1), 32)), hashedBytecode)
            }
        }
    }

    /// @dev Decode the withdraw message that came from L2
    function _parseL2WithdrawalMessage(
        bytes memory _message
    ) internal pure returns (address l1Receiver, uint256 amount) {
        // We check that the message is long enough to read the data.
        // Please note that there are two versions of the message:
        // 1. The message that is sent by `withdraw(address _l1Receiver)`
        // It should be equal to the length of the bytes4 function signature + address l1Receiver + uint256 amount = 4 + 20 + 32 = 56 (bytes).
        // 2. The message that is sent by `withdrawWithMessage(address _l1Receiver, bytes calldata _additionalData)`
        // It should be equal to the length of the following:
        // bytes4 function signature + address l1Receiver + uint256 amount + address l2Sender + bytes _additionalData =
        // = 4 + 20 + 32 + 32 + _additionalData.length >= 68 (bytes).

        // So the data is expected to be at least 56 bytes long.
        require(_message.length >= 56, "pm");

        (uint32 functionSignature, uint256 offset) = UnsafeBytes.readUint32(_message, 0);
        require(bytes4(functionSignature) == this.finalizeEthWithdrawal.selector, "is");

        (l1Receiver, offset) = UnsafeBytes.readAddress(_message, offset);
        (amount, offset) = UnsafeBytes.readUint256(_message, offset);
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
