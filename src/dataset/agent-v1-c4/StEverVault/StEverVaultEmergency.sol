pragma solidity >=0.7.0 <0.9.0;
import "./StEverVaultBase.tsol";
import "../interfaces/IStrategy.tsol";
import "../StEverAccount.tsol";
import "../utils/ErrorCodes.tsol";
import "../utils/Constants.tsol";

import "../../external/@broxus/contracts/contracts/libraries/MsgFlag.tsol";

/**
 * @title StEverVaultEmergency
 *
 * @dev Contract to handle emergency situations in the {StEverVault}.
 * It is inherited by the {StEverVaultBase} contract to handle emergencies
 * in those contracts as well.
 */
abstract contract StEverVaultEmergency is StEverVaultBase {
    /**
     * @dev Enables the emergency state.
     * @param _emergencyEmitter The address that start the emergency state.
     */
    function enableEmergencyState(address _emergencyEmitter) internal {
        emergencyState = EmergencyState({
            isEmergency: true,
            emitter: _emergencyEmitter,
            emitTimestamp: now,
            isPaused: false
        });
    }

    /**
     * @dev Modifier to allow function calls only in emergency state.
     */
    modifier onlyEmergencyState() {
        require(isEmergencyProcess(), ErrorCodes.NOT_EMERGENCY_STATE);
        _;
    }
    //predicate
    /**
     * @dev Checks if the contract is in emergency process.
     * @return A boolean indicating if the contract is in emergency process.
     */
    function isEmergencyProcess() public view returns (bool) {
        return emergencyState.isEmergency && !emergencyState.isPaused;
    }

    /**
     * @dev See {IStEverVault-startEmergencyProcess}.
     *
     * **Preconditions**:
     *
     *  - The contract must not be is paused state.
     *  - The contract must not be in an emergency state.
     *  - The value of the message must be greater than or equal to the required message value.
     *
     * **Postconditions**:
     *
     *  - The emergency process is started.
     *  - The {EmergencyProcessStarted} event is emitted.
     */
    function startEmergencyProcess(uint64 _proofNonce) override external notPaused {
        require(!emergencyState.isEmergency, ErrorCodes.EMERGENCY_ALREADY_RUN);

        uint128 countOfStrategies = uint128(strategies.keys().length);
        uint128 feeForOneStrategy = StEverVaultGas.MIN_STRATEGY_INTERACTION_FEE + StEverVaultGas.EXPERIMENTAL_FEE;
        uint128 requiredMsgValue = countOfStrategies * feeForOneStrategy + StEverVaultGas.MIN_CALL_MSG_VALUE;

        require(msg.value >= requiredMsgValue, ErrorCodes.NOT_ENOUGH_VALUE);
        tvm.rawReserve(_reserve(), 0);

        address accountAddress = getAccountAddress(msg.sender);
        IStEverAccount(accountAddress).onStartEmergency{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(
            _proofNonce,
            timeAfterEmergencyCanBeActivated
        );
    }

    /**
     * @dev See {IStEverVault-stopEmergencyProcess}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the owner.
     *  - The contract must be in an emergency state.
     *  - The call value must be greater than or equal to the minimum call value.
     *
     * **Postconditions**:
     *
     *  - The emergency process is stopped.
     *  - The {EmergencyStopped} event is emitted.
     */
    function stopEmergencyProcess() override external onlyOwner minCallValue {
        require (emergencyState.isEmergency, ErrorCodes.NOT_EMERGENCY_STATE);
        tvm.rawReserve(_reserve(), 0);

        // set initial emergencyState
        delete emergencyState;

        emit EmergencyStopped();

        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-startEmergencyRejected}.
     *
     * **Preconditions**:
     *
     *   - The caller must be the user account.
     *
     * **Postconditions**:
     *
     *  - The {EmergencyProcessRejectedByAccount} event is emitted.
     */
    function startEmergencyRejected(address _user, uint16 errcode) override external onlyAccount(_user) {
        tvm.rawReserve(_reserve(), 0);

        emit EmergencyProcessRejectedByAccount(_user, errcode);

        _user.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-emergencyWithdrawFromStrategiesProcess}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the user account.
     *  - The contract must not be in an emergency state.
     *
     * **Postconditions**:
     *
     *  - The emergency withdrawal process is started.
     *  - The {EmergencyProcessStarted} event is emitted.
     */
    function emergencyWithdrawFromStrategiesProcess(address _user) override external onlyAccount(_user) {
        require (!isEmergencyProcess(), ErrorCodes.EMERGENCY_ALREADY_RUN);

        tvm.rawReserve(_reserve(), 0);
        emit EmergencyProcessStarted(_user);

        enableEmergencyState(_user);
        optional(address, StrategyParams) startPair = strategies.min();
        this._processEmergencyWithdrawFromStrategy{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(_user, startPair);
    }

    /**
     * @dev See {IStEverVault-_processEmergencyWithdrawFromStrategy}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the itself.
     *
     * **Postconditions**:
     *
     *  - The emergency withdrawal from a strategy is processed.
     *  - The {ProcessWithdrawFromStrategyError} event may be emitted.
     */
    function _processEmergencyWithdrawFromStrategy(address _user, optional(address, StrategyParams) _startPair) override external onlySelf {
        uint256 chunkSize = 50;
        tvm.rawReserve(_reserve(), 0);

        optional(address, StrategyParams) pair = _startPair;

        for (uint256 i = 0; i < chunkSize && pair.hasValue(); i++) {

            (address strategy,) = pair.get();
            pair = strategies.next(strategy);

            if (!isStrategyInInitialState(strategy, true)) {
                emit ProcessWithdrawFromStrategyError(strategy, ErrorCodes.STRATEGY_NOT_IN_INITIAL_STATE);
                continue;
            }

            strategies[strategy].withdrawingAmount = Constants.MAX_UINT_64;

            IStrategy(strategy).withdraw{value: StEverVaultGas.MIN_STRATEGY_INTERACTION_FEE, bounce: false}(uint64(Constants.MAX_UINT_64));
        }

        if (pair.hasValue()) {
            this._processEmergencyWithdrawFromStrategy{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce:false}(_user, pair);
            return;
        }

        _user.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-changeEmergencyPauseState}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the owner.
     *  - The call value must be greater than or equal to the minimum call value.
     *  - The contract must be in an emergency state.
     *
     * **Postconditions**:
     *
     *  - The pause state of the emergency process is changed.
     *  - The {EmergencyStatePaused} or {EmergencyStateContinued} event is emitted.
     */
    function changeEmergencyPauseState(bool _isPaused) override external onlyOwner minCallValue {
        require(emergencyState.isEmergency, ErrorCodes.NOT_EMERGENCY_STATE);

        tvm.rawReserve(_reserve(), 0);

        emergencyState.isPaused = _isPaused;
        if (_isPaused) {
            emit EmergencyStatePaused();
        } else {
            emit EmergencyStateContinued();
        }

        msg.sender.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }
    /**
     * @dev See {IStEverVault-emergencyWithdrawToUser}.
     *
     * **Preconditions**:
     *
     *  - The contract must be in an emergency state.
     *  - The call value must be greater than or equal to the minimum call value.
     *
     * **Postconditions**:
     *
     *  - The emergency withdrawal to a user is initiated.
     */
    function emergencyWithdrawToUser() override external onlyEmergencyState  {
        require(msg.value >= StEverVaultGas.MIN_CALL_MSG_VALUE * 2, ErrorCodes.NOT_ENOUGH_VALUE);
        tvm.rawReserve(_reserve(), 0);
        address accountAddress = getAccountAddress(msg.sender);
        IStEverAccount(accountAddress).onEmergencyWithdrawToUser{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}();
    }
}