pragma solidity >=0.7.0 <0.9.0;
import "./StEverVaultBase.tsol";
import "./StEverVaultEmergency.tsol";
import "./StEverStrategiesManager.tsol";

import "../interfaces/IStrategy.tsol";



/**
 * @title StEverVaultStrategiesController
 *
 * @dev This abstract contract manages strategies in the {StEverVault}.
 *
 * It provides methods for various operations such as deposits, withdrawals,
 * reporting strategy results, and handling failed transactions.
 * The contract ensures the safety and security of the funds in the vault
 * and provides transparency through events.
 */
abstract contract StEverVaultStrategiesController is StEverVaultBase, StEverVaultEmergency, StEverStrategiesManager  {
    /**
     * @dev See {IStEverVault-depositToStrategies}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the governance or the contract itself.
     *  - The value of the message must be greater than or equal to the sum of the deposit amount and the fee.
     *
     * **Postconditions**:
     *
     *  - Funds are deposited to the strategies according to the deposit configurations.
     *  - The available assets and total assets are updated accordingly.
     */
    function depositToStrategies(mapping (address => DepositConfig) _depositConfigs) override external onlyGovernanceOrSelfAndAccept {
        uint256 chunkSize = 50;

        for (uint256 i = 0; i < chunkSize && !_depositConfigs.empty(); i++) {

            (address strategy, DepositConfig depositConfig) = _depositConfigs.delMin().get();

            // calculate required amount to send
            uint128 valueToSend = depositConfig.amount + depositConfig.fee;
            if (!canTransferValue(valueToSend)) {
                emit ProcessDepositToStrategyError(strategy, ErrorCodes.NOT_ENOUGH_VALUE_TO_DEPOSIT);
                continue;
            }

            if (!strategies.exists(strategy)) {
                emit ProcessDepositToStrategyError(strategy, ErrorCodes.STRATEGY_NOT_EXISTS);
                continue;
            }

            if (depositConfig.amount < minStrategyDepositValue) {
                emit ProcessDepositToStrategyError(strategy, ErrorCodes.BAD_DEPOSIT_TO_STRATEGY_VALUE);
                continue;
            }

            if (depositConfig.fee < StEverVaultGas.MIN_STRATEGY_INTERACTION_FEE) {
                emit ProcessDepositToStrategyError(strategy, ErrorCodes.BAD_DEPOSIT_TO_STRATEGY_FEE);
                continue;
            }

            if (totalAssets < depositConfig.fee) {
                emit ProcessDepositToStrategyError(strategy, ErrorCodes.NOT_ENOUGH_TOTAL_ASSETS);
                continue;
            }

            if (!isStrategyInInitialState(strategy, false)) {
                emit ProcessDepositToStrategyError(strategy, ErrorCodes.STRATEGY_NOT_IN_INITIAL_STATE);
                continue;
            }


            // change depositing strategy state
            strategies[strategy].depositingAmount = depositConfig.amount;

            // reduce availableAssets
            availableAssets -= valueToSend;

            // grab fee from total assets, then add it back after receiving response from strategy

            decreaseTotalAssets(depositConfig.fee);
            IStrategy(strategy).deposit{value: depositConfig.amount + depositConfig.fee, bounce: false}(uint64(depositConfig.amount));
        }
        if (!_depositConfigs.empty()) {
            this.depositToStrategies{value: StEverVaultGas.SEND_SELF_VALUE, bounce: false}(_depositConfigs);
        }
    }

    /**
     * @dev See {IStEverVault-onStrategyHandledDeposit}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the strategy.
     *
     * **Postconditions**:
     *
     *  - The depositing amount for the strategy is reset to 0.
     *  - The total assets for the strategy are updated.
     *  - The available assets are increased by the returned fee.
     *  - The StrategyHandledDeposit event is emitted.
     */
    function onStrategyHandledDeposit() override external onlyStrategy {
        uint128 depositingAmount = strategies[msg.sender].depositingAmount;
        // set init state for depositing
        strategies[msg.sender].depositingAmount = 0;

        // calculate remaining gas
        uint128 returnedFee = (msg.value - StEverVaultGas.HANDLING_STRATEGY_CB_FEE);
        updateTotalAssetsForStrategy(msg.sender, depositingAmount, true);
        // add fee back
        availableAssets += returnedFee;
        increaseTotalAssets(returnedFee);
        emit StrategyHandledDeposit(msg.sender, depositingAmount);
    }

    /**
     * @dev See {IStEverVault-onStrategyDidntHandleDeposit}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the strategy.
     *
     * **Postconditions**:
     *
     *  - The depositing amount for the strategy is reset to 0.
     *  - The available assets are increased by the remaining gas.
     *  - The total assets are updated based on the depositing amount and the message value.
     *  - The StrategyDidntHandleDeposit event is emitted.
     */
    function onStrategyDidntHandleDeposit(uint32 _errcode) override external onlyStrategy {
        uint128 depositingAmount = strategies[msg.sender].depositingAmount;
        // set init state for depositing
        strategies[msg.sender].depositingAmount = 0;

        availableAssets += msg.value - StEverVaultGas.HANDLING_STRATEGY_CB_FEE;

        // add fee back to total assets
        if (depositingAmount > msg.value) {
            // if depositing amount gt msg.value therefore we spent more than attached fee
            decreaseTotalAssets(depositingAmount - msg.value + StEverVaultGas.HANDLING_STRATEGY_CB_FEE);
        }
        if (msg.value > depositingAmount) {
            increaseTotalAssets(msg.value - depositingAmount - StEverVaultGas.HANDLING_STRATEGY_CB_FEE);
        }
        emit StrategyDidntHandleDeposit(msg.sender, _errcode);
    }

    /**
     * @dev See {IStEverVault-strategyReport}
     *
     * **Preconditions**:
     *
     *  - The caller must be the strategy.
     *
     * **Postconditions**:
     *
     *  - The strategy's last report time is updated.
     *  - The total gain for the strategy is increased by the reported gain.
     *  - The total assets for the strategy are updated.
     *  - The StrategyReported event is emitted.
     */
    function strategyReport(uint128 _gain, uint128 _loss, uint128 _totalAssets, uint128 _requestedBalance) override external onlyStrategy {

        strategies[msg.sender].lastReport = now;
        strategies[msg.sender].totalGain += _gain;

        uint128 stEverFee = math.muldiv(_gain, stEverFeePercent, Constants.ONE_HUNDRED_PERCENT);
        totalStEverFee += stEverFee;
        uint128 gainWithoutStEverFee = _gain - stEverFee;


        // if gain less than the fee, therefore, we shouldn't increase total assets
        uint128 gainWithoutGainFee = gainWithoutStEverFee > gainFee ?
        gainWithoutStEverFee - gainFee :
        0;

        increaseTotalAssets(gainWithoutGainFee);

        if (gainWithoutGainFee > 0) {
            if (unlockPerSecond == 0) {
                unlockPerSecond = gainWithoutGainFee / fullUnlockSeconds;
                remainingLockedAssets = gainWithoutGainFee;
                remainingSeconds = fullUnlockSeconds;
            } else {
                remainingSeconds =
                    (remainingLockedAssets * remainingSeconds + gainWithoutGainFee * fullUnlockSeconds) /
                        (remainingLockedAssets + gainWithoutGainFee);

                remainingLockedAssets += gainWithoutGainFee;

                unlockPerSecond = remainingLockedAssets / remainingSeconds;
            }
        }
        unlockAssets();

        ///
        updateTotalAssetsForStrategy(msg.sender, gainWithoutGainFee, true);

        emit StrategyReported(msg.sender, StrategyReport(gainWithoutGainFee, _loss, _totalAssets));


        uint128 sendValueToStrategy;
        if (_requestedBalance > 0 && canTransferValue(_requestedBalance)) {
            decreaseTotalAssets(_requestedBalance);
            availableAssets -= _requestedBalance;
            sendValueToStrategy = _requestedBalance;
        }
        tvm.rawReserve(_reserveWithValue(sendValueToStrategy), 0);
        msg.sender.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-processWithdrawFromStrategies}
     *
     * **Preconditions**:
     *
     *  - The caller must be the governance or the contract itself.
     *  - The value of the message must be greater than or equal to the sum of the withdrawal amount and the fee.
     *
     * **Postconditions**:
     *
     *  - Funds are withdrawn from the strategies according to the withdrawal configurations.
     *  - The available assets and total assets are updated accordingly.
     */
    function processWithdrawFromStrategies(mapping (address => WithdrawConfig) _withdrawConfig) override external onlyGovernanceOrSelfAndAccept {
        uint256 chunkSize = 50;

        for (uint256 i = 0; i < chunkSize && !_withdrawConfig.empty(); i++) {
            (address strategy, WithdrawConfig config) = _withdrawConfig.delMin().get();

            if (config.amount < minStrategyWithdrawValue) {
                emit ProcessWithdrawFromStrategyError(strategy, ErrorCodes.BAD_WITHDRAW_FROM_STRATEGY_VALUE);
                continue;
            }

            if (!strategies.exists(strategy)) {
                emit ProcessWithdrawFromStrategyError(strategy, ErrorCodes.STRATEGY_NOT_EXISTS);
                continue;
            }

            if (config.fee < StEverVaultGas.MIN_STRATEGY_INTERACTION_FEE) {
                emit ProcessWithdrawFromStrategyError(strategy, ErrorCodes.BAD_WITHDRAW_FROM_STRATEGY_FEE);
                continue;
            }

            if (!canTransferValue(config.fee)) {
                emit ProcessWithdrawFromStrategyError(strategy, ErrorCodes.NOT_ENOUGH_VALUE_TO_WITHDRAW);
                continue;
            }

            if (!isStrategyInInitialState(strategy, true)) {
                emit ProcessWithdrawFromStrategyError(strategy, ErrorCodes.STRATEGY_NOT_IN_INITIAL_STATE);
                continue;
            }

            if (totalAssets < config.fee) {
                emit ProcessWithdrawFromStrategyError(strategy, ErrorCodes.NOT_ENOUGH_TOTAL_ASSETS);
                continue;
            }

            // grab fee, then add it back after receiving response from strategy
            availableAssets -= config.fee;

            decreaseTotalAssets(config.fee);
            // change withdrawing strategy state
            strategies[strategy].withdrawingAmount = config.amount;

            IStrategy(strategy).withdraw{value:config.fee, bounce: false}(uint64(config.amount));
        }
        if (!_withdrawConfig.empty()) {
            this.processWithdrawFromStrategies{value: StEverVaultGas.SEND_SELF_VALUE, bounce:false}(_withdrawConfig);
        }
    }

    /**
     * @dev See {IStEverVault-onStrategyHandledWithdrawRequest}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the strategy.
     *
     * **Postconditions**:
     *
     *  - The StrategyHandledWithdrawRequest event is emitted.
     *  - The available assets are increased by the returned fee.
     *  - The total assets are updated based on the withdrawal amount.
     */
    function onStrategyHandledWithdrawRequest() override external onlyStrategy {

        emit StrategyHandledWithdrawRequest(msg.sender, strategies[msg.sender].withdrawingAmount);

        if (isEmergencyProcess()) {
            tvm.rawReserve(_reserve(), 0);

            emergencyState.emitter.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
            return;
        }
        // set back remaining gas after withdraw request
        availableAssets += msg.value - StEverVaultGas.HANDLING_STRATEGY_CB_FEE;
        increaseTotalAssets(msg.value - StEverVaultGas.HANDLING_STRATEGY_CB_FEE);
    }

    /**
     * @dev See {IStEverVault-forceWithdrawFromStrategies}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the governance or the contract itself.
     *  - The value of the message must be greater than or equal to the sum of the withdrawal amount and the fee.
     *
     * **Postconditions**:
     *
     *  - Funds are forcibly withdrawn from the strategies according to the withdrawal configurations.
     *  - The available assets and total assets are updated accordingly.
     */
    function forceWithdrawFromStrategies(mapping (address => WithdrawConfig) _withdrawConfig) override external onlyGovernanceOrSelfAndAccept {
        uint256 chunkSize = 50;
        for (uint256 i = 0; i < chunkSize && !_withdrawConfig.empty(); i++) {
            (address strategy, WithdrawConfig config) = _withdrawConfig.delMin().get();

            if (!strategies.exists(strategy)) {
                emit ProcessWithdrawFromStrategyError(strategy, ErrorCodes.STRATEGY_NOT_EXISTS);
                continue;
            }

            if (!canTransferValue(config.fee)) {
                emit ProcessWithdrawFromStrategyError(strategy, ErrorCodes.NOT_ENOUGH_VALUE_TO_WITHDRAW);
                continue;
            }

            if (totalAssets < config.fee) {
                emit ProcessWithdrawFromStrategyError(strategy, ErrorCodes.NOT_ENOUGH_TOTAL_ASSETS);
                continue;
            }

            // grab fee, then add it back after receiving response from strategy
            availableAssets -= config.fee;
            decreaseTotalAssets(config.fee);

            // change withdrawing strategy state
            strategies[strategy].withdrawingAmount = config.amount;

            IStrategy(strategy).withdrawForce{value:config.fee, bounce: false}(uint64(config.amount));
        }
        if (!_withdrawConfig.empty()) {
            this.forceWithdrawFromStrategies{value: StEverVaultGas.SEND_SELF_VALUE, bounce: false}(_withdrawConfig);
        }
    }

    /**
     * @dev See {IStEverVault-receiveFromStrategy}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the strategy.
     *
     * **Postconditions**:
     *
     *  - The withdrawing amount for the strategy is reset to 0.
     *  - The total assets for the strategy are updated.
     *  - The available assets are increased by the received amount.
     *  - The StrategyWithdrawSuccess event is emitted.
     *  - The strategy is removed if it is ready to be deleted.
     */
    function receiveFromStrategy() override external onlyStrategy {
        // set init state for withdrawing
        strategies[msg.sender].withdrawingAmount = 0;

        uint128 receivedAmount = msg.value - StEverVaultGas.HANDLING_STRATEGY_CB_FEE;

        updateTotalAssetsForStrategy(msg.sender, msg.value, false);

        availableAssets += receivedAmount;

        emit StrategyWithdrawSuccess(msg.sender, receivedAmount);

        if (isStrategyReadyToDelete(msg.sender)) {
            removeStrategy(msg.sender);
        }
    }

    /**
     * @dev See {IStEverVault-receiveAdditionalTransferFromStrategy}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the strategy.
     *
     * **Postconditions**:
     *
     *  - The available assets are increased by the received amount.
     *  - The total assets for the strategy are updated.
     *  - The strategy is removed if it is ready to be deleted.
     *  - The {ReceiveAdditionalTransferFromStrategy} event is emitted.
     */
    function receiveAdditionalTransferFromStrategy() override external onlyStrategy {
        uint128 receivedAmount = msg.value - StEverVaultGas.HANDLING_STRATEGY_CB_FEE;

        availableAssets += receivedAmount;
        updateTotalAssetsForStrategy(msg.sender, msg.value, false);

        if (isStrategyReadyToDelete(msg.sender)) {
            removeStrategy(msg.sender);
        }

        emit ReceiveAdditionalTransferFromStrategy(msg.sender, receivedAmount);
    }

    /**
     * @dev Checks if a strategy is ready to be deleted.
     *
     * @param _strategy The address of the strategy.
     *
     * **Postconditions**:
     *
     *  - Returns true if the strategy is in the removing state and has no total assets.
     */
    function isStrategyReadyToDelete(address _strategy) internal view returns(bool) {
        StrategyParams strategy = strategies[_strategy];
        return strategy.state == StrategyState.REMOVING && strategy.totalAssets == 0;
    }

    /**
     * @dev Updates the total assets for a strategy.
     *
     * @param _strategy The address of the strategy.
     * @param _amount The amount to increase or decrease the total assets by.
     * @param _isIncrease Whether to increase or decrease the total assets.
     *
     * **Postconditions**:
     *
     *  - The total assets for the strategy are increased or decreased based on the _isIncrease parameter.
     */
    function updateTotalAssetsForStrategy(address _strategy, uint128 _amount, bool _isIncrease) internal {

        if (_isIncrease) {
            uint128 correctedAmount = _amount >= Constants.INCREASE_STRATEGY_TOTAL_ASSETS_CORRECTION ?
            _amount - Constants.INCREASE_STRATEGY_TOTAL_ASSETS_CORRECTION :
            0;

            strategies[_strategy].totalAssets += correctedAmount;
            return;
        }

        uint128 currentStrategyAssets = strategies[_strategy].totalAssets;

        if (_amount >= currentStrategyAssets) {
            strategies[_strategy].totalAssets = 0;
            return;
        }

        strategies[_strategy].totalAssets -= _amount;

    }

    /**
     * @dev See {IStEverVault-withdrawFromStrategyError}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the strategy.
     *
     * **Postconditions**:
     *
     *  - The StrategyWithdrawError event is emitted.
     *  - The withdrawing amount for the strategy is reset to 0.
     *  - The available assets are increased by the remaining gas.
     *  - The total assets are increased by the remaining gas.
     */
    function withdrawFromStrategyError(uint32 _errcode) override external onlyStrategy {
        emit StrategyWithdrawError(msg.sender, _errcode);
        // set init state for withdrawing
        strategies[msg.sender].withdrawingAmount = 0;

        if (isEmergencyProcess()) {
            tvm.rawReserve(_reserve(), 0);

            emergencyState.emitter.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
            return;
        }
        // calculate remaining gas
        uint128 notUsedFee = msg.value - StEverVaultGas.HANDLING_STRATEGY_CB_FEE;

        // set remaining gas
        availableAssets += notUsedFee;
        increaseTotalAssets(notUsedFee);
    }

    /**
     * @dev See {IStEverVault-processWithdrawExtraMoneyFromStrategies}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the governance or the contract itself.
     *
     * **Postconditions**:
     *
     *  - Extra money is withdrawn from the strategies.
     *  - The available assets are decreased by the minimum transaction value for each strategy.
     */
    function processWithdrawExtraMoneyFromStrategies(address[] _strategies) override external onlyGovernanceOrSelfAndAccept {

        for (address strategy : _strategies) {
            if (!strategies.exists(strategy)) {
                emit ProcessWithdrawExtraMoneyFromStrategyError(strategy, ErrorCodes.STRATEGY_NOT_EXISTS);
                continue;
            }

            if (!canTransferValue(StEverVaultGas.MIN_CALL_MSG_VALUE)) {
                emit ProcessWithdrawExtraMoneyFromStrategyError(strategy, ErrorCodes.NOT_ENOUGH_VALUE);
                continue;
            }

            availableAssets -= StEverVaultGas.MIN_CALL_MSG_VALUE;

            IStrategy(strategy).withdrawExtraMoney{value: StEverVaultGas.MIN_CALL_MSG_VALUE, bounce: false}();
        }
    }

    /**
     * @dev See {IStEverVault-receiveExtraMoneyFromStrategy}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the strategy.
     *
     * **Postconditions**:
     *
     *  - The available assets are increased by the received value.
     *  - The ReceiveExtraMoneyFromStrategy event is emitted.
     */
    function receiveExtraMoneyFromStrategy() override external onlyStrategy {
        uint128 receivedValue = msg.value > StEverVaultGas.HANDLING_STRATEGY_CB_FEE
            ? msg.value - StEverVaultGas.HANDLING_STRATEGY_CB_FEE
            : 0;

        availableAssets += receivedValue;

        uint128 availableAssetsIncreasedFor = receivedValue > StEverVaultGas.MIN_CALL_MSG_VALUE
            ? receivedValue - StEverVaultGas.MIN_CALL_MSG_VALUE
            : 0;

        emit ReceiveExtraMoneyFromStrategy(msg.sender, availableAssetsIncreasedFor);
    }

    /**
     * @dev See {IStEverVault-forceStrategyRemove}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the owner.
     *  - The value of the message must be greater than or equal to StEverVaultGas.REMOVE_STRATEGY_RESERVE.
     *
     * **Postconditions**:
     *
     *  - If the strategy exists, it is removed.
     *  - The onStrategyRemoved event is emitted.
     */
    function forceStrategyRemove(address _strategy, address _cluster) override external onlyOwner {
        require(
            msg.value >= StEverVaultGas.REMOVE_STRATEGY_RESERVE + Constants.MIN_TRANSACTION_VALUE,
            ErrorCodes.NOT_ENOUGH_VALUE
        );

        tvm.rawReserve(_reserve(), 0);

        if (!strategies.exists(_strategy)) {
            IStEverCluster(_cluster).onStrategyRemoved{
                    value: StEverVaultGas.REMOVE_STRATEGY_RESERVE,
                    bounce: false
            }(_strategy);
        }

        msg.sender.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

}

