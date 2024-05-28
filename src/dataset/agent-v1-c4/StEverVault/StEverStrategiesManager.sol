pragma solidity >=0.7.0 <0.9.0;import "./StEverVaultBase.tsol";
import "../interfaces/IStEverCluster.tsol";

/**
 * @dev This contract is used to manage the strategies for the StEver staking platform.
 *
 * This abstraction extends the functionality of {StEverVaultBase} and provides
 * the capabilities for managing the strategies for the StEver staking platform.
 *
 * It allows for the creation and removal of clusters, addition and removal of strategies,
 * and delegation of strategies to different clusters.
 */
abstract contract StEverStrategiesManager is StEverVaultBase {

    /**
     * @dev See {IStEverVault-createCluster}
     *
     * **Preconditions**:
     *
     * - The caller must be the owner.
     *
     * - The value of the message must be greater than or equal to the sum of DEPLOY_CLUSTER_VALUE and MIN_CALL_MSG_VALUE.
     *
     * **Postconditions**:
     *
     *
     * - A new cluster is created and added to the clusterPools.
     *
     * - The {ClusterCreated} event is emitted.
     */
    function createCluster(
        address _clusterOwner,
        uint128 _assurance,
        uint32 _maxStrategiesCount
    ) override external onlyOwner {
        require(
            msg.value >= StEverVaultGas.DEPLOY_CLUSTER_VALUE + StEverVaultGas.MIN_CALL_MSG_VALUE,
            ErrorCodes.NOT_ENOUGH_VALUE
        );
        require(Utils.isValidAddress(strategyFactory), ErrorCodes.STRATEGY_FACTORY_DID_NOT_SET);
        tvm.rawReserve(_reserve(), 0);


        if (!clusterPools.exists(_clusterOwner)) {
            mapping(uint32 => address) emptyClusters;
            clusterPools[_clusterOwner] = ClustersPool({
                currentClusterNonce: 0,
                clusters: emptyClusters
            });
        } else {
            clusterPools[_clusterOwner].currentClusterNonce++;
        }

        address cluster = deployCluster(
            _clusterOwner,
            clusterPools[_clusterOwner].currentClusterNonce,
            _assurance,
            _maxStrategiesCount,
            strategyFactory,
            stTokenRoot,
            owner
        );

        clusterPools[_clusterOwner].clusters[clusterPools[_clusterOwner].currentClusterNonce] = cluster;
        emit ClusterCreated(_clusterOwner, _assurance, _maxStrategiesCount, cluster);
        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-onClusterRemoved}
     *
     * **Preconditions**:
     *
     * - The caller must be the cluster.
     *
     * **Postconditions**:
     *
     * - The specified cluster is removed from the clusterPools.
     *
     * - The {ClusterRemoved} event is emitted.
     */
    function onClusterRemoved(
        address _clusterOwner,
        uint32 _clusterNonce
    ) override external onlyCluster(_clusterOwner, _clusterNonce) {
        delete clusterPools[_clusterOwner].clusters[_clusterNonce];
        if (clusterPools[_clusterOwner].clusters.keys().length == 0) {
            delete clusterPools[_clusterOwner];
        }
        emit ClusterRemoved(msg.sender, _clusterOwner, _clusterNonce);
    }

    /**
     * @dev See {IStEverVault-addStrategies}
     *
     * **Preconditions**:
     *
     * - The caller must be the cluster.
     *
     * - The value of the message must be greater than or equal to the product of the length of _strategies and EXPERIMENTAL_FEE.
     *
     * - The length of _strategies must be less than or equal to the batchSize.
     *
     * - Each strategy in _strategies must not already exist in the strategies.
     *
     * **Postconditions**:
     *
     * - The strategies are added to the strategies.
     *
     * - The {StrategiesAdded} event is emitted.
     *
     * - The {IStEverCluster-onStrategiesAdded} is called.
     */
    function addStrategies(address[] _strategies, address _clusterOwner, uint32 _clusterId) override external onlyCluster(_clusterOwner, _clusterId)  {
        require (msg.value >= _strategies.length * StEverVaultGas.EXPERIMENTAL_FEE, ErrorCodes.NOT_ENOUGH_VALUE);

        uint8 batchSize = 50;

        require (_strategies.length <= batchSize, ErrorCodes.MAX_BATCH_SIZE_REACHED);

        for (address strategy : _strategies) {
            require (!strategies.exists(strategy), ErrorCodes.STRATEGY_ALREADY_EXISTS);

            strategies[strategy] = StrategyParams({
                    lastReport: 0,
                    totalGain: 0,
                    depositingAmount: 0,
                    withdrawingAmount: 0,
                    totalAssets: 0,
                    cluster: msg.sender,
                    state: StrategyState.ACTIVE
            });
        }

        tvm.rawReserve(_reserve(), 0);

        emit StrategiesAdded(_strategies);

        IStEverCluster(msg.sender).onStrategiesAdded{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            bounce: false
        }(_strategies);
    }

    /**
     * @dev See {IStEverVault-removeStrategies}
     *
     * **Preconditions**:
     *
     * - The caller must be the cluster.
     *
     * **Postconditions**:
     *
     * - The strategies are removed from the strategies.
     *
     * - The {StrategiesPendingRemove} event is emitted.
     *
     * - The {IStEverCluster-onPendingStrategyRemove} is called.
     */
    function removeStrategies(
        address[] _strategies,
        address _clusterOwner,
        uint32 _clusterId
    ) override external onlyCluster(_clusterOwner, _clusterId) {

        address[] pendingDeleteStrategies;
        for (address _strategy : _strategies) {
            strategies[_strategy].state = StrategyState.REMOVING;

            if (strategies[_strategy].totalAssets == 0) {
                removeStrategy(_strategy);
                continue;
            }

            pendingDeleteStrategies.push(_strategy);
        }

        if (pendingDeleteStrategies.length == 0) {
            tvm.rawReserve(_reserve(), 0);
            _clusterOwner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
            return;
        }

        uint128 minimalRemoveStrategyValue = uint128(pendingDeleteStrategies.length) * StEverVaultGas.REMOVE_STRATEGY_RESERVE;

        tvm.rawReserve(address(this).balance - (msg.value - minimalRemoveStrategyValue), 0);
        emit StrategiesPendingRemove(pendingDeleteStrategies);

        IStEverCluster(msg.sender).onPendingStrategyRemove{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            bounce: false
        }(pendingDeleteStrategies);
    }

    /**
     * @dev Removes a strategy.
     * @param _strategy The address of the strategy to remove.
     *
     * **Preconditions**:
     *
     * - The caller must be the contract itself.
     *
     * **Postconditions**:
     *
     * - The strategy is removed from the strategies.
     *
     * - The {StrategyRemoved} event is emitted.
     *
     * - The {IStEverCluster-onStrategyRemoved} is called.
     */
    function removeStrategy(address _strategy) internal pure {
        this._removeStrategy{
            value: StEverVaultGas.REMOVE_STRATEGY_RESERVE,
            bounce: false
        }(_strategy);
    }

    /**
     * @dev Removes a strategy.
     * @param _strategy The address of the strategy
     *
     * **Preconditions**:
     *
     * - The caller must be the contract itself.
     *
     * **Postconditions**:
     *
     * - The strategy is removed from the strategies.
     *
     * - The {StrategyRemoved} event is emitted.
     *
     * - The {IStEverCluster-onStrategyRemoved} is called.
     */
    function _removeStrategy(address _strategy) external override onlySelf {
        tvm.rawReserve(_reserve(), 0);

        StrategyParams strategy = strategies[_strategy];
        delete strategies[_strategy];
        emit StrategyRemoved(_strategy);

        IStEverCluster(strategy.cluster).onStrategyRemoved{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            bounce: false
        }(_strategy);
    }

    /**
     * @dev See {IStEverVault-onStrategiesDelegationHandled}
     *
     * **Preconditions**:
     *
     * - The caller must be the cluster.
     *
     * **Postconditions**:
     *
     * - The strategies are delegated to the cluster.
     *
     * - The {ClusterHandledStrategiesDelegation} event is emitted.
     */
    function onStrategiesDelegationHandled(
        address _clusterOwner,
        uint32 _clusterNonce,
        address[] _strategies
    ) override external onlyCluster(_clusterOwner, _clusterNonce) {
        tvm.rawReserve(_reserve(), 0);

        for (address strategy : _strategies) {
            strategies[strategy].state = StrategyState.ACTIVE;
            strategies[strategy].cluster = msg.sender;
        }

        emit ClusterHandledStrategiesDelegation(msg.sender, _clusterOwner, _clusterNonce, _strategies);

        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }
}