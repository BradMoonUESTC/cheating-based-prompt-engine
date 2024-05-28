pragma solidity >=0.7.0 <0.9.0;

import "./StEverVaultStorage.tsol";
import "../interfaces/IStEverVault.tsol";
import "../interfaces/IStEverCluster.tsol";
import "../StEverAccount.tsol";
import "../Platform.tsol";
import "../utils/ErrorCodes.tsol";
import "../utils/Gas.tsol";
import "../utils/Utils.tsol";
import "../utils/Constants.tsol";

import "../../external/@broxus/contracts/contracts/libraries/MsgFlag.tsol";

/**
 * @title StEverVaultBase
 *
 * @dev This contract is the base for the {StEverVault} contract and other related contracts.
 * It includes the basic functionalities and state variables inherited from the {StEverVaultStorage}.
 *
 * It is inherited by the StEverVault contract and other related contracts such as
 * {StEverVaultValidators}, {StEverVaultStrategiesController}, {StEverVaultEmergency},
 * and {StEverStrategiesManager}, which includes the main functionalities of the StEver staking platform.
 */
abstract contract StEverVaultBase is StEverVaultStorage {
    /**
     * @dev Modifier to make a function callable only by the governance or the contract itself.
     */
    modifier onlyGovernanceOrSelfAndAccept() {
        require (msg.pubkey() == governance || msg.sender == address(this), ErrorCodes.NOT_GOVERNANCE);
        tvm.accept();
        _;
    }

    /**
     * @dev Modifier to make a function callable only by the contract itself.
     */
    modifier onlySelf() {
        require(msg.sender == address(this), ErrorCodes.NOT_SELF);
        _;
    }

    /**
     * @dev Modifier to make a function callable only by the owner.
     */
    modifier onlyOwner() {
        require (msg.sender == owner,ErrorCodes.NOT_OWNER);
        _;
    }

    /**
     * @dev Modifier for checking if the msg.sender is account that is deployed by this vault
     * @param _user The address of the user.
     */
    modifier onlyAccount(address _user) {
        address account = getAccountAddress(_user);

        require (msg.sender == account, ErrorCodes.NOT_USER_DATA);
        _;
    }

    /**
     * @dev Modifier to make a function callable only by the cluster.
     * @param _clusterOwner The address of the cluster owner.
     * @param _clusterNonce The nonce of the cluster.
     */
    modifier onlyCluster(address _clusterOwner, uint32 _clusterNonce) {
        address cluster = getClusterAddress(_clusterOwner, _clusterNonce);
        require(msg.sender == cluster, ErrorCodes.NOT_CLUSTER_ACCOUNT);
        _;
    }

    /**
     * @dev Modifier to make a function callable only by the strategy.
     */
    modifier onlyStrategy() {
        require (strategies.exists(msg.sender), ErrorCodes.STRATEGY_NOT_EXISTS);
        _;
    }

    /**
     * @dev Modifier to make a function callable only if the call value
     * is greater than or equal to the minimum call value.
     */
    modifier minCallValue() {
        require (msg.value >= StEverVaultGas.MIN_CALL_MSG_VALUE, ErrorCodes.LOW_MSG_VALUE);
        _;
    }

    /**
     * @dev Modifier to make a function callable only if the contract is not paused.
     */
    modifier notPaused() {
        require(!isPaused, ErrorCodes.ST_EVER_VAULT_PAUSED);
        _;
    }

    /**
     * @dev See {IStEverVault-transferOwnership}.
     *
     * **Preconditions**:
     *
     * - The caller must be the current owner.
     *
     * **Postconditions**:
     *
     * - The ownership of the contract is transferred to `_newOwner`.
     *
     * - Gas is sent to `_sendGasTo`.
     */
    function transferOwnership(address _newOwner, address _sendGasTo) override external onlyOwner {
        require(Utils.isValidAddress(_newOwner), ErrorCodes.BAD_INPUT);

        uint countOfClusters;
        for ((,ClustersPool clusterPool) : clusterPools) {
            countOfClusters += clusterPool.clusters.keys().length;
        }

        require(msg.value > countOfClusters * (StEverVaultGas.MIN_CALL_MSG_VALUE + Constants.MIN_TRANSACTION_VALUE), ErrorCodes.LOW_MSG_VALUE);

        tvm.rawReserve(_reserve(), 0);

        owner = _newOwner;

        this.self_setStEverOwnerForClusters{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(_sendGasTo, clusterPools);
    }

    function self_setStEverOwnerForClusters(address _sendGasTo, mapping(address => ClustersPool) _clusterPools) public view onlySelf {
        tvm.rawReserve(_reserve(), 0);
        uint256 chunkSize = 25;
        while (chunkSize != 0 && !_clusterPools.empty()) {
            (address clusterOwner, ClustersPool clusterPool) = _clusterPools.min().get();
            mapping(uint32 => address) clusters = clusterPool.clusters;

            while (chunkSize != 0 && !clusters.empty()) {
                chunkSize--;
                (, address clusterAddress)  = clusters.delMin().get();
                IStEverCluster(clusterAddress).setStEverOwner{
                    value: StEverVaultGas.MIN_CALL_MSG_VALUE,
                    bounce: false
                }(owner);
            }

            if (clusters.empty()) {
                _clusterPools.delMin();
            } else {
                _clusterPools[clusterOwner] = ClustersPool({
                    clusters: clusters,
                    currentClusterNonce: clusterPool.currentClusterNonce
                });
            }
        }
        if (!_clusterPools.empty()) {
            this.self_setStEverOwnerForClusters{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(_sendGasTo, _clusterPools);
            return;
        }

        _sendGasTo.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    // ownership
    /**
     * @dev See {IStEverVault-transferGovernance}.
     *
     * **Preconditions**:
     *
     * - The caller must be the current owner.
     *
     * **Postconditions**:
     *
     * - The governance of the contract is transferred to `_newGovernance`.
     *
     * - Gas is sent to `_sendGasTo`.
     */
    function transferGovernance(uint256 _newGovernance, address _sendGasTo) override external onlyOwner {
        require(Utils.isValidPubKey(_newGovernance), ErrorCodes.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);

        governance = _newGovernance;

        _sendGasTo.transfer({value: 0, flag:MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev Receives the token wallet address.
     *
     * @param _wallet The address of the token wallet.
     *
     *
     * @notice Preconditions:
     *
     * - The caller must be the root wallet.
     *
     * **Postconditions**:
     *
     *
     * - The token wallet address is set to `_wallet`.
     */
    function receiveTokenWalletAddress(address _wallet) external virtual {
        require (msg.sender == stTokenRoot, ErrorCodes.NOT_ROOT_WALLET);
        stEverWallet = _wallet;
    }

    // setters
    /**
     * @dev See {IStEverVault-setGainFee}.
     *
     * **Preconditions**:
     *
     * - The caller must be the owner.
     *
     * **Postconditions**:
     *
     * - The gain fee is set to `_gainFee`.
     */
    function setGainFee(uint128 _gainFee) override external onlyOwner {
        require (_gainFee >= StEverVaultGas.MIN_GAIN_FEE, ErrorCodes.BAD_INPUT);
        tvm.rawReserve(_reserve(), 0);

        gainFee = _gainFee;

        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-setMinStrategyDepositValue}
     *
     * **Preconditions**:
     *
     * - The caller must be the owner.
     *
     * **Postconditions**:
     *
     * - The minimum strategy deposit value is set to `_minStrategyDepositValue`.
     */
    function setMinStrategyDepositValue(uint128 _minStrategyDepositValue) override external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        require(_minStrategyDepositValue >= StEverVaultGas.MIN_STRATEGY_DEPOSIT_VALUE, ErrorCodes.BAD_INPUT);
        minStrategyDepositValue = _minStrategyDepositValue;

        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-setMinStrategyWithdrawValue}
     *
     * **Preconditions**:
     *
     * - The caller must be the owner.
     *
     * **Postconditions**:
     *
     * - The minimum strategy withdraw value is set to `_minStrategyWithdrawValue`.
     */
    function setMinStrategyWithdrawValue(uint128 _minStrategyWithdrawValue) override external onlyOwner {
        tvm.rawReserve(_reserve(), 0);

        minStrategyWithdrawValue = _minStrategyWithdrawValue;

        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-setStEverFeePercent}.
     *
     * **Preconditions**:
     *
     * - The caller must be the owner.
     *
     * - `_stEverFeePercent` must be less than or equal to 100.
     *
     * **Postconditions**:
     *
     * - The StEver fee percent is set to `_stEverFeePercent`.
     */
    function setStEverFeePercent(uint32 _stEverFeePercent) override external onlyOwner {
        require (_stEverFeePercent <= Constants.ONE_HUNDRED_PERCENT, ErrorCodes.BAD_FEE_PERCENT);

        tvm.rawReserve(_reserve(), 0);

        stEverFeePercent = _stEverFeePercent;
        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce:false});
    }

    /**
     * @dev See {IStEverVault-setIsPaused}.
     *
     * **Preconditions**:
     *
     * - The caller must be the owner.
     *
     * - The value of the message must be greater than or equal to the minimum call message value.
     *
     * **Postconditions**:
     *
     * - The pause state of the contract is set to `_isPaused`.
     *
     * - The {PausedStateChanged} event is emitted.
     */
    function setIsPaused(bool _isPaused) override external onlyOwner minCallValue {
        tvm.rawReserve(_reserve(), 0);
        bool isNeedToEmit = isPaused != _isPaused;
        isPaused = _isPaused;

        if  (isNeedToEmit){
            emit PausedStateChanged(_isPaused);
        }
        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-setStrategyFactory}.
     *
     * **Preconditions**:
     *
     * - The caller must be the owner.
     *
     * - The value of the message must be greater than or equal to the minimum call message value.
     *
     * **Postconditions**:
     *
     * - The strategy factory address is set to `_strategyFactory`.
     *
     * - The {StrategyFactoryAddressUpdated} event is emitted.
     */
    function setStrategyFactory(address _strategyFactory) override external onlyOwner minCallValue {
        require(Utils.isValidAddress(_strategyFactory), ErrorCodes.BAD_INPUT);
        tvm.rawReserve(_reserve(), 0);

        strategyFactory = _strategyFactory;
        emit StrategyFactoryAddressUpdated(strategyFactory);

        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-setWithdrawHoldTimeInSeconds}.
     *
     * **Preconditions**:
     *
     * - The caller must be the owner.
     *
     * - The value of the message must be greater than or equal to the minimum call message value.
     *
     * **Postconditions**:
     *
     * - The withdraw hold time in seconds is set to `_holdTime`.
     *
     * - The {WithdrawHoldTimeUpdated} event is emitted.
     */
    function setWithdrawHoldTimeInSeconds(uint64 _holdTime) override external onlyOwner minCallValue {
        tvm.rawReserve(_reserve(), 0);

        withdrawHoldTime = _holdTime;
        emit WithdrawHoldTimeUpdated(withdrawHoldTime);

        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-setFullUnlockRewardSeconds}.
     *
     * **Preconditions**:
     *
     * - The caller must be the owner.
     *
     * - The value of the message must be greater than or equal to the minimum call message value.
     *
     * **Postconditions**:
     *
     * - The full unlock reward time in seconds is set to `_fullUnlockSeconds`.
     *
     * - The {FullUnlockTimeUpdated} event is emitted.
     */
    function setFullUnlockRewardSeconds(uint128 _fullUnlockSeconds) override external onlyOwner minCallValue {
        require(_fullUnlockSeconds > 0, ErrorCodes.BAD_INPUT);

        tvm.rawReserve(_reserve(), 0);
        fullUnlockSeconds = _fullUnlockSeconds;
        emit FullUnlockTimeUpdated(fullUnlockSeconds);
        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /// @dev function for setting period of time after emergency can be activated
    /// @param _newTimeAfterEmergencyCanBeActivated uint64 new period of time
    function setTimeAfterEmergencyCanBeActivated(
        uint64 _newTimeAfterEmergencyCanBeActivated
    ) public minCallValue onlyOwner  {
        tvm.rawReserve(_reserve(), 0);
        require(
            _newTimeAfterEmergencyCanBeActivated >= Constants.TIME_AFTER_EMERGENCY_CAN_BE_ACTIVATED &&
            _newTimeAfterEmergencyCanBeActivated <= Constants.TIME_AFTER_EMERGENCY_CAN_BE_ACTIVATED_MAX,
            ErrorCodes.BAD_INPUT
        );
        timeAfterEmergencyCanBeActivated = _newTimeAfterEmergencyCanBeActivated;
        emit TimeAfterEmergencyCanBeActivatedValueUpdated(timeAfterEmergencyCanBeActivated);
        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }
    // predicates
    /**
     * @dev Checks if the amount is available to transfer
     *
     * @param _amount The value to check.
     * @return Returns true if the contract can transfer the value, false otherwise.
     *
     *
     * **Preconditions**:
     *
     * - The contract must have available assets greater than the minimum available assets value.
     *
     * - The contract must have enough available assets to cover the transfer amount.
     *
     */
    function canTransferValue(uint128 _amount) internal view returns (bool) {
        return availableAssets > StEverVaultGas.MIN_AVAILABLE_ASSETS_VALUE &&
         availableAssets - StEverVaultGas.MIN_AVAILABLE_ASSETS_VALUE >= _amount;
    }

    /**
     * @dev Checks if a strategy is in its initial state.
     *
     * @param _strategy The address of the strategy.
     * @param isAllowedNotActiveState A flag the secondary rule that allows to check strategy in not active state.
     * @return Returns true if the strategy is in its initial state, false otherwise.
     *
     * **Preconditions**:
     *
     * - The strategy must not be depositing or withdrawing.
     *
     * - The strategy must be in an active state, unless a not active state is allowed.
     *
     */
    function isStrategyInInitialState(address _strategy, bool isAllowedNotActiveState) internal view returns (bool) {
        StrategyParams strategy = strategies[_strategy];
        return strategy.depositingAmount == 0 &&
            strategy.withdrawingAmount == 0 &&
            (isAllowedNotActiveState || strategy.state == StrategyState.ACTIVE);
    }


    // utils

    /**
     * @dev Returns the maximum between the contract balance minus the message value and the minimum contract balance.
     * @return The maximum value.
     */
    function _reserve() internal pure returns (uint128) {
		return
			math.max(address(this).balance - msg.value, StEverVaultGas.CONTRACT_MIN_BALANCE);
	}

    /**
     * @dev Returns the maximum between the contract balance minus the message value and the input value, and the minimum contract balance.
     * @param _value The value to subtract from the contract balance.
     * @return The maximum value.
     */
    function _reserveWithValue(uint128 _value) internal pure returns (uint128) {
		return math.max(address(this).balance - msg.value - _value, StEverVaultGas.CONTRACT_MIN_BALANCE);
	}

    /**
     * @dev See {IStEverVault-encodedDepositPayload}.
     */
    function encodeDepositPayload(uint64 _nonce) external override pure returns (TvmCell depositPayload) {
        return abi.encode(_nonce);
    }

    /**
     * @dev Decodes the deposit payload.
     *
     * @param _payload The payload to decode.
     * @return nonce The nonce decoded from the payload.
     *
     * @return correct A boolean indicating if the payload was correctly decoded.
     *
     * **Preconditions**:
     *
     * - The payload must be correctly assembled.
     */
    function decodeDepositPayload(TvmCell _payload) public virtual pure returns (uint64 nonce, bool correct) {
        // check if payload assembled correctly
        TvmSlice slice = _payload.toSlice();
        if (slice.bits() != 64) {
            return (0, false);
        }

        nonce = slice.decode(uint64);

        return (nonce, true);
    }

        // when the user deposits we should calculate the amount of stEver to send
        // when the user deposits we should calculate the amount of stEver to send

    // when the user deposits we should calculate the amount of stEver to send

    /**
     * @dev Calculates the amount of stEver to send when the user deposits.
     * @param _amount The amount the user deposits.
     * @return The amount of stEver to send.
     *
     * **Preconditions**:
     *
     * - The stEver supply and total assets must not be zero.
     */
    function getDepositStEverAmount(uint128 _amount) public view returns(uint128) {
        return getDepositStEverAmountFor(_amount,uint128(now));
    }

        // when the user withdraw we should calculate the amount of ever to send
        // when the user withdraw we should calculate the amount of ever to send

    // when the user withdraw we should calculate the amount of ever to send

    /**
     * @dev Calculates the amount of ever to send when the user withdraws.
     * @param _amount The amount the user withdraws.
     * @return The amount of ever to send.
     *
     * **Preconditions**:
     *
     * - The stEver supply and total assets must not be zero.
     */
    function getWithdrawEverAmount(uint128 _amount) public view returns(uint128) {
        return getWithdrawEverAmountFor(_amount,uint128(now));
    }

    // when the user deposits we should calculate the amount of stEver to send
    /**
     * @dev Calculates the amount of stEver to send when the user deposits for a specific time.
     * @param _amount The amount the user deposits.
     * @param _time The specific time.
     * @return The amount of stEver to send.
     *
     * **Preconditions**:
     *
     * - The stEver supply and total assets must not be zero.
     */
    function getDepositStEverAmountFor(uint128 _amount, uint128 _time) public view returns(uint128) {
        if(stEverSupply == 0 || totalAssets == 0) {
            return _amount;
        }
        (,,uint128 _effectiveEverAssets) = getLockStateFor(_time);
        return math.muldiv(_amount, stEverSupply, _effectiveEverAssets);
    }
    // when the user withdraw we should calculate the amount of ever to send

    /**
     * @dev Calculates the amount of ever to send when the user withdraws for a specific time.
     * @param _amount The amount the user withdraws.
     * @param _time The specific time.
     * @return The amount of ever to send.
     *
     * **Preconditions**:
     *
     * - The stEver supply and total assets must not be zero.
     */
    function getWithdrawEverAmountFor(uint128 _amount, uint128 _time) public view returns(uint128) {
        if(stEverSupply == 0 || totalAssets == 0) {
            return _amount;
        }
        (,,uint128 _effectiveEverAssets) = getLockStateFor(_time);
        return math.muldiv(_amount, _effectiveEverAssets, stEverSupply);
    }

    /**
     * @dev Unlocks the assets if the remaining locked assets is zero.
     *
     * **Postconditions**:
     *
     * - If remaining locked assets is zero, assets are unlocked.
     */
    function unlockAssets() internal {
        if  (remainingLockedAssets == 0) {
            effectiveEverAssets = totalAssets;
            lastUnlockTime = now;
            unlockPerSecond = 0;
            return;
        }

        (remainingLockedAssets, remainingSeconds, effectiveEverAssets) = getLockStateFor(uint128(now));
        lastUnlockTime = now;
    }

    /**
     * @dev Increases the total assets by the given amount and unlocks the assets.
     * @param _update The amount to increase the total assets by.
     *
     * **Postconditions**:
     *
     * - Total assets are increased by the given amount.
     *
     * - Assets are unlocked.
     */
    function increaseTotalAssets(uint128 _update) internal {
            totalAssets += _update;
            unlockAssets();
    }

    /**
     * @dev Decreases the total assets by the given amount and unlocks the assets.
     * @param _update The amount to decrease the total assets by.
     *
     * **Postconditions**:
     *
     * - Total assets are decreased by the given amount.
     *
     * - Assets are unlocked.
     */
    function decreaseTotalAssets(uint128 _update) internal {
            totalAssets -= _update;
            unlockAssets();
    }

    /**
     * @dev Returns the remaining locked assets, remaining seconds, and effective ever assets for a given time.
     * @param time The time to get the lock state for.
     */
    function getLockStateFor(uint128 time) public view returns (
        uint128 _remainingLockedAssets,
        uint128 _remainingSeconds,
        uint128 _effectiveEverAssets
    ) {
        uint128 timeFromLastUnlock = time - lastUnlockTime;
        uint128 unlockAmount = unlockPerSecond * timeFromLastUnlock;
        _remainingLockedAssets = remainingLockedAssets > unlockAmount ? remainingLockedAssets - unlockAmount : 0;
        _remainingSeconds = remainingSeconds > timeFromLastUnlock ? remainingSeconds - timeFromLastUnlock : 0;
        _effectiveEverAssets = totalAssets - _remainingLockedAssets;
    }

    /**
     * @dev Returns the withdrawal information for a user and checks if the withdrawal is okay.
     * @param _withdrawals The withdrawals to get the information for.
     * @return withdrawInfo The withdrawal information.
     * @return isOk A boolean indicating if the withdrawal is okay.
     */
    function getAndCheckWithdrawToUserInfo(mapping(uint64 => IStEverAccount.WithdrawRequest) _withdrawals) internal view returns(mapping(uint64 => WithdrawToUserInfo), bool) {
        bool isOk = true;
        mapping(uint64 => WithdrawToUserInfo) withdrawInfo;

        for ((uint64 _nonce, IStEverAccount.WithdrawRequest withdrawRequest) : _withdrawals) {
            if (withdrawRequest.unlockTime > now) {
                isOk = false;
            }
            withdrawInfo[_nonce] = WithdrawToUserInfo({
                stEverAmount: withdrawRequest.amount,
                everAmount: getWithdrawEverAmount(withdrawRequest.amount),
                unlockTime: withdrawRequest.unlockTime
            });
        }

        return (withdrawInfo, isOk);
    }


    // account utils
    /**
     * @dev Builds the account parameters that will be used for building init data for account.
     * @param _user The user to build the account parameters for.
     * @return The account parameters.
     */
    function _buildAccountParams(address _user) internal virtual pure returns (TvmCell) {
        return abi.encode(_user);
    }

    /**
     * @dev Builds the initial account with the given data.
     * @param _initialData The data to build the initial account with.
     * @return The initial account.
     */
    function _buildInitAccount(TvmCell _initialData)
		internal
		view
		virtual
		returns (TvmCell)
	{
		return
			tvm.buildStateInit({
				contr: Platform,
				varInit: {
					root: address(this),
                    platformType: PlatformType.ACCOUNT,
                    initialData: _initialData,
                    platformCode: platformCode
				},
				pubkey: 0,
				code: platformCode
			});
	}

    /**
     * @dev Deploys an account for a given user.
     * @param _user The user to deploy the account for.
     * @return The address of the deployed account.
     */
    function deployAccount(address _user)
		internal
		virtual
        view
		returns (address)
	{
        TvmCell constructorParams = abi.encode(
            accountVersion,
            accountVersion
        );

        return new Platform{
            stateInit: _buildInitAccount(_buildAccountParams(_user)),
            value: StEverVaultGas.USER_DATA_DEPLOY_VALUE
        }(accountCode, constructorParams, _user);
	}

    /**
     * @dev Returns the account address based on user address.
     * @param _user The user to get the account address for.
     * @return The account address.
     */
    function getAccountAddress(address _user)
		public
		view
		virtual
		responsible
		returns (address)
	{
		return
			{value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false} address(
				tvm.hash(_buildInitAccount(_buildAccountParams(_user)))
			);
	}

    /**
     * @dev See {IStEverVault-setNewAccountCode}.
     *
     * **Preconditions**:
     *
     * - The caller must be the owner.
     *
     * - The value of the message must be greater than or equal to the minimum call message value.
     *
     * **Postconditions**:
     *
     * - The account code is updated to the new account code.
     *
     * - The account version is incremented by 1.
     *
     * - The {NewAccountCodeSet} event is emitted.
     */
    function setNewAccountCode(TvmCell _newAccountCode) override external onlyOwner minCallValue {
        tvm.rawReserve(_reserve(), 0);

        accountCode = _newAccountCode;
        accountVersion += 1;

        emit NewAccountCodeSet(accountVersion);

        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-upgradeStEverAccount}.
     *
     * **Preconditions**:
     *
     * - The value of the message must be greater than or equal to the minimum call message value.
     *
     * **Postconditions**:
     *
     * - The StEverAccount is upgraded.
     */
    function upgradeStEverAccount() override external {
        require(msg.value >= StEverVaultGas.MIN_CALL_MSG_VALUE * 2, ErrorCodes.NOT_ENOUGH_VALUE);
        tvm.rawReserve(_reserve(), 0);

        address userData = getAccountAddress(msg.sender);
        IStEverAccount(userData).upgrade{
            value: StEverVaultGas.MIN_CALL_MSG_VALUE,
            bounce: false
        }(accountCode, accountVersion, msg.sender);
    }
     /**
     * @dev See {IStEverVault-upgradeStEverAccounts}.
     *
     * **Preconditions**:
     *
     * - The caller must be the owner.
     *
     * - The value of the message must be greater than or equal to the sum of the length
     *    of users times {StEverVaultGas-MIN_CALL_MSG_VALUE} and {StEverVaultGas-MIN_CALL_MSG_VALUE}.
     *
     * **Postconditions**:
     *
     * - The StEverAccounts for the provided users are upgraded.
     */
    function upgradeStEverAccounts(address _sendGasTo, address[] _users) override external onlyOwner {
        require(msg.value >= _users.length * StEverVaultGas.MIN_CALL_MSG_VALUE * 2, ErrorCodes.NOT_ENOUGH_VALUE);
        tvm.rawReserve(_reserve(), 0);
        this._upgradeStEverAccounts{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(_sendGasTo, _users, 0);
    }

    /**
     * @dev See {IStEverVault-_upgradeStEverAccounts}.
     *
     * Function for batch upgrade of accounts that can be called only by this contract
     * in case of batches more than 50.
     *
     * **Preconditions**:
     *
     * - The caller must be the contract itself.
     *
     * **Postconditions**:
     *
     * - The StEverAccounts for the provided users are upgraded starting from the provided index.
     */
    function _upgradeStEverAccounts(address _sendGasTo, address[] _users, uint128 _startIdx) override external onlySelf {
        tvm.rawReserve(_reserve(), 0);
        uint128 batchSize = 50;
        for (; _startIdx < _users.length && batchSize != 0; _startIdx++) {
            address user = _users[_startIdx];
            batchSize--;

            address userData = getAccountAddress(user);

            IStEverAccount(userData).upgrade{
                value: StEverVaultGas.MIN_CALL_MSG_VALUE
            }(accountCode, accountVersion, _sendGasTo);
        }

        if (_startIdx < _users.length) {
            this._upgradeStEverAccounts{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(_sendGasTo, _users, _startIdx);
            return;
        }

        _sendGasTo.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-onAccountUpgraded}.
     *
     * **Preconditions**:
     *
     * - The caller must be the account being upgraded.
     *
     * **Postconditions**:
     *
     * - The {AccountUpgraded} event is emitted.
     */
    function onAccountUpgraded(address _user, address _sendGasTo, uint32 _newVersion) override external onlyAccount(_user) {

        tvm.rawReserve(_reserve(), 0);

        emit AccountUpgraded(_user, _newVersion);
        _sendGasTo.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    // Cluster
    /**
     * @dev Builds the cluster parameters that will be used for building init data for cluster.
     * @param _clusterNonce The nonce for the cluster.
     * @param _stEverVault The StEverVault for the cluster.
     * @param _clusterOwner The owner of the cluster.
     * @return The cluster parameters.
     */
    function _buildClusterParams(
        uint32 _clusterNonce,
        address _stEverVault,
        address _clusterOwner
    ) internal virtual pure returns (TvmCell) {
        return abi.encode(
            _clusterNonce,
            _stEverVault,
            _clusterOwner
        );
    }

    /**
     * @dev Builds the initial cluster with the given data.
     * @param _initialData The data to build the initial cluster with.
     * @return The initial cluster.
     */
    function _buildInitCluster(TvmCell _initialData)
        internal
        view
        virtual
        returns (TvmCell)
    {
        return
        tvm.buildStateInit({
                contr: Platform,
                varInit: {
                    root: address(this),
                    platformType: PlatformType.CLUSTER,
                    initialData: _initialData,
                    platformCode: platformCode
                },
                pubkey: 0,
                code: platformCode
        });
    }

    /**
     * @dev Deploys a new cluster contract.
     *
     * @param _clusterOwner The owner of the new cluster.
     * @param _clusterNonce The nonce for the new cluster.
     * @param _assurance The assurance for the new cluster.
     * @param _maxStrategiesCount The maximum number of strategies for the new cluster.
     * @param _strategyFactory The strategy factory for the new cluster.
     * @param _stEverTokenRoot The StEver token root for the new cluster.
     * @param _stEverOwner The StEver owner for the new cluster.
     * @return The address of the newly deployed cluster.
     *
     * **Preconditions**:
     *
     * - The caller must be the contract itself.
     *
     * **Postconditions**:
     *
     * - A new cluster contract is deployed and its address is returned.
     */
    function deployCluster(
        address _clusterOwner,
        uint32 _clusterNonce,
        uint128 _assurance,
        uint32 _maxStrategiesCount,
        address _strategyFactory,
        address _stEverTokenRoot,
        address _stEverOwner
    )
        internal
        view
        returns (address)
    {
        TvmCell constructorParams = abi.encode(
            clusterVersion,
            clusterVersion,
            _assurance,
            _maxStrategiesCount,
            _strategyFactory,
            _stEverTokenRoot,
            _stEverOwner
        );

        return new Platform{
                stateInit: _buildInitCluster(
                    _buildClusterParams(
                        _clusterNonce,
                        address(this),
                        _clusterOwner
                    )
                ),
                value: StEverVaultGas.DEPLOY_CLUSTER_VALUE,
                bounce: false
        }(clusterCode, constructorParams, _clusterOwner);
    }

    /**
     * @dev Returns the address of a cluster contract based on cluster owner and cluster nonce.
     *
     * @param _clusterOwner The owner of the cluster.
     * @param _clusterNonce The nonce for the cluster.
     * @return The address of the cluster contract.
     */
    function getClusterAddress(address _clusterOwner, uint32 _clusterNonce)
        public
        view
        virtual
        responsible
        returns (address)
    {
        return
            {value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false} address(
                tvm.hash(
                    _buildInitCluster(
                        _buildClusterParams(
                            _clusterNonce,
                            address(this),
                            _clusterOwner
                        )
                    )
                )
        );
    }

    /**
     * @dev See {IStEverVault-setNewClusterCode}.
     *
     * **Preconditions**:
     *
     * - The caller must be the owner.
     *
     * - The value of the message must be greater than or equal to the minimum call message value.
     *
     * **Postconditions**:
     *
     * - The cluster code is updated to the new cluster code.
     */
    function setNewClusterCode(TvmCell _newClusterCode) override external onlyOwner minCallValue {
        tvm.rawReserve(_reserve(), 0);

        clusterCode = _newClusterCode;
        clusterVersion += 1;

        emit NewClusterCodeSet(clusterVersion);

        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-upgradeStEverCluster}.
     *
     * **Postconditions**:
     *
     * - The {StEverCluster} is upgraded.
     */
    function upgradeStEverCluster(uint32 _clusterNonce) override external {
        require(msg.value >= StEverVaultGas.MIN_CALL_MSG_VALUE * 2, ErrorCodes.NOT_ENOUGH_VALUE);

        tvm.rawReserve(_reserve(), 0);

        address cluster = getClusterAddress(msg.sender, _clusterNonce);
        IStEverCluster(cluster).upgrade{value: StEverVaultGas.MIN_CALL_MSG_VALUE}(clusterCode, clusterVersion, msg.sender);
    }

    /**
     * @dev See {IStEverVault-upgradeStEverClusters}.
     *
     * **Preconditions**:
     *
     * - The value of the message must be greater than or equal to the minimum call message value.
     *
     * - The caller must be the owner.
     *
     * **Postconditions**:
     *
     * - The StEverClusters for the provided clusters are upgraded.
     */
    function upgradeStEverClusters(address _sendGasTo, address[] _clusters) override external minCallValue onlyOwner {
        require(msg.value >= _clusters.length * StEverVaultGas.MIN_CALL_MSG_VALUE + StEverVaultGas.MIN_CALL_MSG_VALUE, ErrorCodes.NOT_ENOUGH_VALUE);
        tvm.rawReserve(_reserve(), 0);
        this._upgradeStEverClusters{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(_sendGasTo, _clusters, 0);
    }

    /**
     * @dev Function for batch upgrade of clusters that can be called only by this contract in case of batches more than 50
     * @dev Can only be called by the contract itself.
     * @param _sendGasTo The address to send gas to.
     * @param _clusters The clusters to upgrade the StEverClusters for.
     * @param _startIdx The start index of the array in case of recursive call.
     *
     * **Preconditions**:
     *
     * - The caller must be the contract itself.
     *
     * **Postconditions**:
     *
     * - The StEverClusters for the provided clusters are upgraded starting from the provided index.
     */
    function _upgradeStEverClusters(address _sendGasTo, address[] _clusters, uint128 _startIdx) external view onlySelf {
        tvm.rawReserve(_reserve(), 0);
        uint128 batchSize = 50;
        for (; _startIdx < _clusters.length && batchSize != 0; _startIdx++) {
            address clusterAddress = _clusters[_startIdx];
            batchSize--;
            IStEverCluster(clusterAddress).upgrade{value: StEverVaultGas.MIN_CALL_MSG_VALUE}(clusterCode, clusterVersion, _sendGasTo);
        }

        if (_startIdx < _clusters.length) {
            this._upgradeStEverClusters{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(_sendGasTo, _clusters, _startIdx);
            return;
        }

        _sendGasTo.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }
    /**
     * @dev See {IStEverVault-onClusterUpgraded}.
     *
     * **Preconditions**:
     *
     * - The caller must be the cluster being upgraded.
     *
     * **Postconditions**:
     *
     * - The {ClusterUpgraded} event is emitted.
     */
    function onClusterUpgraded(
        address _clusterOwner,
        uint32 _clusterNonce,
        address _sendGasTo,
        uint32 _newVersion
    ) override external onlyCluster(_clusterOwner, _clusterNonce) {
        tvm.rawReserve(_reserve(), 0);

        emit ClusterUpgraded(_clusterOwner, _clusterNonce, _newVersion);
        _sendGasTo.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev Returns the details of the contract.
     */
    function getDetails() override external responsible view returns(Details) {
        return {value:0, flag: MsgFlag.REMAINING_GAS, bounce: false} Details(
                nonce,
                governance,

                stEverSupply,
                totalAssets,
                availableAssets,
                totalStEverFee,
                effectiveEverAssets, //new
                remainingLockedAssets, //new
                unlockPerSecond, //new
                stEverWallet,
                stTokenRoot,

                lastUnlockTime, //new
                fullUnlockSeconds, //new
                remainingSeconds, //new

                gainFee,
                stEverFeePercent,
                minStrategyDepositValue,
                minStrategyWithdrawValue,
                isPaused,
                strategyFactory,

                withdrawHoldTime,

                owner,
                accountVersion,
                stEverVaultVersion,
                clusterVersion,
                timeAfterEmergencyCanBeActivated, //new
                emergencyState
            );
    }
}