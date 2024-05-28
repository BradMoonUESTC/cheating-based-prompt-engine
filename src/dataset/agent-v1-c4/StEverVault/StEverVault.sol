pragma solidity >=0.7.0 <0.9.0;
import "./interfaces/IStrategy.tsol";
import "./StEverAccount.tsol";
import "./base/StEverVaultEmergency.tsol";
import "./base/StEverStrategiesManager.tsol";
import "./base/StEverVaultStrategiesController.tsol";
import "./base/StEverVaultValidators.tsol";

import "./utils/ErrorCodes.tsol";
import "./utils/Constants.tsol";

import "../external/@broxus/contracts/contracts/libraries/MsgFlag.tsol";
import "../external/broxus-ton-tokens-contracts/contracts/interfaces/ITokenRoot.tsol";
import "../external/broxus-ton-tokens-contracts/contracts/interfaces/ITokenWallet.tsol";
import "../external/broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensBurnCallback.tsol";
import "../external/broxus-ton-tokens-contracts/contracts/interfaces/IAcceptTokensTransferCallback.tsol";
import "../external/broxus-ton-tokens-contracts/contracts/abstract/TokenWalletBurnableBase.tsol";


/**
 * @title StEverVault
 *
 * @dev StEverVault is the central contract of the StEver staking platform,
 * inheriting functionalities from several other contracts and interfaces.
 *
 * This contract is an implementation of the IStEverVault interface,
 * encompassing the essential functionalities required for depositing and
 * withdrawing ever tokens, managing withdrawal requests, and handling token transfers.
 *
 * Additionally, it serves as the main entry point for all user, owner,
 * and governance operations.
 *
 * It is responsible for managing ever assets, issuing StEver tokens, processing withdrawals
 * after a hold time and governance approval, managing strategies, validating deposit and
 * withdrawal requests, and handling emergencies.
 */
contract StEverVault is
    StEverVaultEmergency,
    StEverStrategiesManager,
    StEverVaultStrategiesController,
    StEverVaultValidators,
    IAcceptTokensBurnCallback,
    IAcceptTokensTransferCallback
{
    constructor(
        address _owner,
        uint128 _gainFee,
        uint32 _stEverFeePercent,
        address _stTokenRoot
    ) public {
        require (tvm.pubkey() != 0, ErrorCodes.WRONG_PUB_KEY);
        require (tvm.pubkey() == msg.pubkey(), ErrorCodes.WRONG_PUB_KEY);
        require(_gainFee >= StEverVaultGas.MIN_GAIN_FEE, ErrorCodes.GAIN_FEE_SHOULD_BE_GT_MIN);
        require(_stEverFeePercent <= Constants.ONE_HUNDRED_PERCENT, ErrorCodes.BAD_FEE_PERCENT);

        tvm.accept();
        owner = _owner;
        gainFee = _gainFee;
        stTokenRoot = _stTokenRoot;
        stEverFeePercent = _stEverFeePercent;
        ITokenRoot(stTokenRoot).deployWallet{
			value: StEverVaultGas.ST_EVER_WALLET_DEPLOY_VALUE,
			callback: StEverVaultBase.receiveTokenWalletAddress,
            bounce: false
		}(address(this), StEverVaultGas.ST_EVER_WALLET_DEPLOY_GRAMS_VALUE);
    }

    /**
     * @dev See {IStEverVault-deposit}.
     *
     * **Preconditions**:
     *
     *  - The system must not be paused.
     *  - The value of the message must be greater than or equal to the sum of the deposit amount and the minimum call message value.
     *
     * **Postconditions**:
     *
     *  - The total assets, available assets and stEverSupply are increased by the deposit amount.
     *  - The Deposit event is emitted.
     *  - The mint function of the stTokenRoot contract is called.
     */
    function deposit(uint128 _amount, uint64 _nonce) override external notPaused {
        require (msg.value >= _amount + StEverVaultGas.MIN_CALL_MSG_VALUE, ErrorCodes.NOT_ENOUGH_DEPOSIT_VALUE);

        tvm.rawReserve(address(this).balance - (msg.value - _amount), 0);
        unlockAssets();
        uint128 amountToSend = getDepositStEverAmount(_amount);

        increaseTotalAssets(_amount);
        availableAssets += _amount;
        stEverSupply += amountToSend;

        TvmBuilder builder;
		builder.store(_nonce);

        emit Deposit(msg.sender, _amount, amountToSend);
        ITokenRoot(stTokenRoot).mint{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            bounce: false
        }(
            amountToSend,
            msg.sender,
            StEverVaultGas.ST_EVER_WALLET_DEPLOY_VALUE,
            msg.sender,
            false,
            builder.toCell()
        );
    }

    /**
     * @dev Handles a incoming stTokens transfer, for withdraw locked native tokens.
     *
     * This function checks if the withdrawal request is valid by checking if the sender is the stEverWallet,
     * if the value of the message is greater than or equal to the required attached value, and if the system is not paused.
     * @param _amount The amount to be withdrawn.
     * @param _sender The sender of the withdrawal request.
     * @param _remainingGasTo The address to which the remaining gas will be sent.
     * @param _payload The payload of the withdrawal request.
     *
     * **Preconditions**:
     *
     *  - The sender must be the stEverWallet.
     *  - The value of the message must be greater than or equal to the required attached value.
     *  - The system must not be paused.
     *
     * **Postconditions**:
     *
     *  - The requestWithdraw function is called if the conditions are met.
     *  - If any condition is not met, the transfer function of the stEverWallet contract is called to refund the tokens to the sender.
     */
    function onAcceptTokensTransfer(
        address,
        uint128 _amount,
        address _sender,
        address,
        address _remainingGasTo,
        TvmCell _payload
    ) override external {
        require (msg.sender == stEverWallet, ErrorCodes.NOT_ROOT_WALLET);


        (uint64 _nonce, bool _correct) = decodeDepositPayload(_payload);

        if (pendingWithdrawals.exists(_nonce)) {
            _correct = false;
        }
        /*
        StEverVaultGas.WITHDRAW_FEE: reserved as gas that will be used in IStEverAccount.processWithdraw in processSendToUsers method
        StEverVaultGas.FEE_FOR_WITHDRAW_TO_USER_ITERATION: reserved for gas that will be used for iteration through users
        StEverVaultGas.WITHDRAW_FEE_FOR_USER_DATA: will be used for creating(if needed) and adding pending withdrawal to account
        */
        uint128 requiredAttachedValue = StEverVaultGas.WITHDRAW_FEE +
            StEverVaultGas.FEE_FOR_WITHDRAW_TO_USER_ITERATION +
            StEverVaultGas.WITHDRAW_FEE_FOR_USER_DATA;

        // if something went wrong, resend tokens to sender
        if (
            msg.value < requiredAttachedValue ||
            !_correct ||
            isPaused
        ) {
            tvm.rawReserve(_reserve(), 0);
            emit BadWithdrawRequest(_sender, _amount, msg.value);
            ITokenWallet(stEverWallet).transfer{
                value: 0,
                flag: MsgFlag.ALL_NOT_RESERVED,
                bounce: false
            }(
                _amount,
                _sender,
                0,
                _remainingGasTo,
                false,
                _payload
            );
            return;
        }
        requestWithdraw(_sender, _amount, _nonce, _remainingGasTo);
    }

    /**
     * @dev Requests a withdrawal for a user.
     *
     * @param _user The user requesting the withdrawal.
     * @param _amount The amount to be withdrawn.
     * @param _nonce The nonce of the withdrawal.
     * @param _remainingGasTo The address to which the remaining gas will be sent.
     *
     * **Preconditions**:
     *
     *  - The value of the message must be greater than or equal to the required attached value.
     *
     * **Postconditions**:
     *
     *  - A new pending withdrawal is created and added to the {pendingWithdrawals}.
     *  - The {addPendingValueToAccount} function is called.
     */
    function requestWithdraw(address _user, uint128 _amount, uint64 _nonce, address _remainingGasTo) internal {
        // making StEverVaultGas.WITHDRAW_FEE_FOR_USER_DATA free
        tvm.rawReserve(address(this).balance - (msg.value - StEverVaultGas.WITHDRAW_FEE - StEverVaultGas.FEE_FOR_WITHDRAW_TO_USER_ITERATION), 0);

        address accountAddr = getAccountAddress(_user);
        uint64 unlockTime = uint64(now) + withdrawHoldTime;
        pendingWithdrawals[_nonce] = PendingWithdraw({
            amount: _amount,
            user: _user,
            remainingGasTo: _remainingGasTo,
            unlockTime: unlockTime
        });

        addPendingValueToAccount(_nonce, _amount, accountAddr, unlockTime, 0, MsgFlag.ALL_NOT_RESERVED, _remainingGasTo);
    }

    /**
     * @dev Handles the error of adding a pending value to an account.
     *
     * @param _slice The slice of the error message.
     *
     * **Postconditions**:
     *
     *  - The {addPendingValueToAccount} function is called again.
     */
    function handleAddPendingValueError(TvmSlice _slice) internal view {
        tvm.rawReserve(_reserve(), 0);

        uint64 _withdrawNonce = _slice.decode(uint64);

        PendingWithdraw pendingWithdraw = pendingWithdrawals[_withdrawNonce];

        address account = deployAccount(pendingWithdraw.user);

        addPendingValueToAccount(
            _withdrawNonce,
            pendingWithdraw.amount,
            account,
            pendingWithdraw.unlockTime,
            0,
            MsgFlag.ALL_NOT_RESERVED,
            pendingWithdraw.remainingGasTo
        );
    }

    /**
     * @dev Adds a pending value to an account.
     *
     * @param _withdrawNonce The nonce of the withdrawal.
     * @param _amount The amount to be withdrawn.
     * @param _account The account to which the pending value will be added.
     * @param _unlockTime The unlock time of the withdrawal.
     * @param _value The value to be added.
     * @param _flag The flag of the message.
     * @param _remainingGasTo The address to which the remaining gas will be sent.
     *
     * **Postconditions**:
     *
     *  - The {StEverAccount-addPendingValue} function is called.
     */
    function addPendingValueToAccount(
        uint64 _withdrawNonce,
        uint128 _amount,
        address _account,
        uint64 _unlockTime,
        uint128 _value,
        uint8 _flag,
        address _remainingGasTo
    ) internal pure {
        IStEverAccount(_account).addPendingValue{
            value:_value,
            flag: _flag,
            bounce: true
        }(_withdrawNonce, _amount, _unlockTime, _remainingGasTo);
    }

    /**
     * @dev See {IStEverVault-onPendingWithdrawAccepted}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the account of the user.
     *
     * **Postconditions**:
     *
     *  - The pending withdrawal is removed from the pendingWithdrawals.
     *  - The WithdrawRequest event is emitted.
     *  - The remaining gas is transferred to the remainingGasTo address.
     */
    function onPendingWithdrawAccepted(
        uint64 _nonce,
        address _user,
        address _remainingGasTo
    ) override external onlyAccount(_user) {
       tvm.rawReserve(_reserve(), 0);

       PendingWithdraw pendingWithdraw = pendingWithdrawals[_nonce];
       emit WithdrawRequest(pendingWithdraw.user, pendingWithdraw.amount, pendingWithdraw.unlockTime, _nonce);
       delete pendingWithdrawals[_nonce];

       _remainingGasTo.transfer({value:0, flag:MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-onPendingWithdrawRejected}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the account of the user.
     *
     * **Postconditions**:
     *
     *  - The pending withdrawal is removed from the pendingWithdrawals.
     *  - The tokens are transferred back to the user.
     *
     */
    function onPendingWithdrawRejected(uint64 _nonce, address _user, uint128 _amount, address _remainingGasTo) override external onlyAccount(_user) {
        tvm.rawReserve(
            _reserveWithValue(StEverVaultGas.WITHDRAW_FEE + StEverVaultGas.FEE_FOR_WITHDRAW_TO_USER_ITERATION),
            0
        );

        delete pendingWithdrawals[_nonce];

        TvmCell payload;
        ITokenWallet(stEverWallet).transfer{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            bounce: false
        }(
            _amount,
            _user,
            0,
            _remainingGasTo,
            false,
            payload
        );
    }

    /**
     * @dev See {IStEverVault-removePendingWithdraw}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the user of the account.
     *
     * **Postconditions**:
     *
     *  - The removePendingWithdraw function of the StEverAccount contract is called.
     *
     */
    function removePendingWithdraw(uint64 _nonce) override external minCallValue {
        tvm.rawReserve(_reserve(), 0);
        address account = getAccountAddress(msg.sender);
        IStEverAccount(account).removePendingWithdraw{value:0, flag:MsgFlag.ALL_NOT_RESERVED, bounce: false}(_nonce);
    }

    /**
     * @dev See {IStEverVault-onPendingWithdrawRemoved}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the account of the user.
     *
     * **Postconditions**:
     *
     *  - The pending withdrawal is removed from the pendingWithdrawals.
     *  - The WithdrawRequestRemoved event is emitted.
     *  - The tokens are transferred to the user.
     */
    function onPendingWithdrawRemoved(address _user, uint64 _nonce, uint128 _amount) override external onlyAccount(_user) {
        tvm.rawReserve(
            _reserveWithValue(StEverVaultGas.WITHDRAW_FEE + StEverVaultGas.FEE_FOR_WITHDRAW_TO_USER_ITERATION),
            0
        );

        emit WithdrawRequestRemoved(_user, _nonce);

        TvmCell payload;
        ITokenWallet(stEverWallet).transfer{
            value:0,
            flag:MsgFlag.ALL_NOT_RESERVED,
            bounce:false
        }(
            _amount,
            _user,
            0,
            _user,
            false,
            payload
        );
    }

    /**
     * @dev See {IStEverVault-processSendToUsers}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the governance or the contract itself.
     *
     * **Postconditions**:
     *
     *  - The {IStEverAccount-processWithdraw} function is called for each user in the `sendConfig` mapping.
     *  - If the sendConfig mapping is not empty after the iteration, the processSendToUsers function is called again.
     */
    function processSendToUsers(mapping (address => SendToUserConfig) sendConfig) override external onlyGovernanceOrSelfAndAccept {
        uint256 chunkSize = 50;

        for (uint256 i = 0; i < chunkSize && !sendConfig.empty(); i++) {
            (address user, SendToUserConfig config) = sendConfig.delMin().get();

            // if there is more than MAX_PENDING_COUNT nonces, skip this user
            if (config.nonces.length > Constants.MAX_PENDING_COUNT) {
                continue;
            }

            address account = getAccountAddress(user);

            uint128 unusedIterationFee = (uint128(config.nonces.length) - 1) * StEverVaultGas.FEE_FOR_WITHDRAW_TO_USER_ITERATION;

            IStEverAccount(account).processWithdraw{
                    value: StEverVaultGas.WITHDRAW_FEE * uint128(config.nonces.length) + unusedIterationFee,
                    bounce: false
            }(config.nonces);
        }

        if (!sendConfig.empty()) {
            this.processSendToUsers{value: StEverVaultGas.SEND_SELF_VALUE, bounce: false}(sendConfig);
        }
    }

    /**
     * @dev See {IStEverVault-withdrawToUser}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the account of the user.
     *
     * **Postconditions**:
     *
     *  - The total assets, available assets and stEverSupply are decreased by the withdrawal amount.
     *  - The WithdrawError or WithdrawSuccess event is emitted.
     *  - The tokens are burned.
     */
    function withdrawToUser(
        uint128 _amount,
        address _user,
        mapping(uint64 => IStEverAccount.WithdrawRequest) _withdrawals
    ) override external onlyAccount(_user) {
        if(_withdrawals.empty()) {
            return;
        }

        unlockAssets();
        // create and check withdraw info
        (
            mapping(uint64 => WithdrawToUserInfo) withdrawInfo,
            bool isOk
        ) = getAndCheckWithdrawToUserInfo(_withdrawals);

        uint128 everAmount = getWithdrawEverAmount(_amount);
        // if not enough balance, reset pending to the Account;
        if (availableAssets < everAmount || !isOk) {
            tvm.rawReserve(_reserve(), 0);

            emit WithdrawError(_user, withdrawInfo, _amount);

            if (isEmergencyProcess()) {
                IStEverAccount(msg.sender).resetPendingValues{
                    value:0,
                    flag:MsgFlag.ALL_NOT_RESERVED,
                    bounce: false
                }(_withdrawals, _user);
                return;
            }

            IStEverAccount(msg.sender).resetPendingValues{
                value:0,
                flag:MsgFlag.ALL_NOT_RESERVED,
                bounce: false
            }(_withdrawals, address(this));
            return;
        }

        decreaseTotalAssets(everAmount);
        availableAssets -= everAmount;
        stEverSupply -= _amount;


        TvmBuilder builder;
        builder.store(_user);
        builder.store(everAmount);
        builder.store(withdrawInfo);
        tvm.rawReserve(_reserveWithValue(everAmount), 0);

        TokenWalletBurnableBase(stEverWallet).burn{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(
            _amount,
            address(this),
            address(this),
            builder.toCell()
        );
    }

    /**
     * @dev Last step in withdraw native tokens flow.
     *
     * **Preconditions**:
     *
     *  - The caller must be the stTokenRoot.
     *  - The wallet must be the stEverWallet.
     *
     * **Postconditions**:
     *
     *  - The WithdrawSuccess event is emitted.
     *  - The remaining gas is transferred to the user.
     */
    function onAcceptTokensBurn(
        uint128,
        address,
        address _wallet,
        address,
        TvmCell _payload
    ) override external {
        require (_wallet == stEverWallet, ErrorCodes.NOT_ROOT_WALLET);
        require (msg.sender == stTokenRoot, ErrorCodes.NOT_TOKEN_ROOT);
        tvm.rawReserve(_reserve(), 0);

        TvmSlice slice = _payload.toSlice();
        address user = slice.decode(address);
        uint128 everAmount = slice.decode(uint128);
        mapping(uint64 => WithdrawToUserInfo) withdrawals = slice.decode(mapping(uint64 => WithdrawToUserInfo));

        emit WithdrawSuccess(user, everAmount, withdrawals);
        user.transfer({value: 0, flag :MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }


     /// @dev Handles a bounce.
     /// @param _slice The slice to decode.
    onBounce(TvmSlice _slice) external view {
		tvm.accept();

		uint32 functionId = _slice.decode(uint32);
		if (functionId == tvm.functionId(StEverAccount.addPendingValue)) {
			handleAddPendingValueError(_slice);
		}
	}

    /**
     * @dev See {IStEverVault-withdrawStEverFee}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the Owner.
     *  - The total stEver fee must be greater than or equal to the amount to be withdrawn.
     *  - The contract must be able to transfer the specified amount.
     *
     * **Postconditions**:
     *
     *  - The total stEver fee and available assets are decreased by the withdrawal amount.
     *  - The WithdrawFee event is emitted.
     *  - The remaining gas is transferred to the owner.
     */
    function withdrawStEverFee(uint128 _amount) override external onlyOwner {
        require (totalStEverFee >= _amount, ErrorCodes.NOT_ENOUGH_ST_EVER_FEE);
        require (canTransferValue(_amount), ErrorCodes.NOT_ENOUGH_AVAILABLE_ASSETS);
        // fee should payed by admin
        tvm.rawReserve(address(this).balance - (_amount + msg.value), 0);

        totalStEverFee -= _amount;
        availableAssets -= _amount;
        emit WithdrawFee(_amount);
        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-withdrawExtraEver}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the owner.
     *  - The value of the message must be greater than or equal to the minimum call value.
     *  - The available assets must be greater than the total assets and the total stEver fee.
     *
     * **Postconditions**:
     *
     *  - The available assets are decreased by the extra available assets.
     *  - The SuccessWithdrawExtraEver event is emitted.
     *  - The remaining gas is transferred to the owner.
     */
    function withdrawExtraEver() override external onlyOwner minCallValue {
        require (
            availableAssets > totalAssets && (availableAssets - totalAssets) > totalStEverFee,
            ErrorCodes.AVAILABLE_ASSETS_SHOULD_GT_TOTAL_ASSETS
        );

        uint128 extraAvailableAssets = availableAssets - totalAssets - totalStEverFee;
        uint128 extraPureBalance = math.min(address(this).balance - extraAvailableAssets - StEverVaultGas.CONTRACT_MIN_BALANCE - msg.value, extraAvailableAssets);
        uint128 totalExtraEver = extraAvailableAssets + extraPureBalance;

        // remove extra ever from availableAssets
        availableAssets -= extraAvailableAssets;

        tvm.rawReserve(_reserveWithValue(totalExtraEver), 0);

        emit SuccessWithdrawExtraEver(totalExtraEver);

        owner.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverVault-upgrade}.
     *
     * **Preconditions**:
     *
     *  - The caller must be the owner.
     *  - The call value must be greater than or equal to the minimum call value.
     *
     * **Postconditions**:
     *
     *  - If the new version is the same as the current version, the remaining gas is sent to the specified address and the function returns.
     *  - If the new version is different, the contract's state is updated with the new version's data and the contract's code is replaced with the new code.
     */
    function upgrade(TvmCell _newCode, uint32 _newVersion, address _sendGasTo) override external minCallValue onlyOwner {
        if (_newVersion == stEverVaultVersion) {
            tvm.rawReserve(_reserve(), 0);
            _sendGasTo.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce:false});
            return;
        }

        // should be unpacked in the same order!
        TvmCell data = abi.encode(
            _newVersion, // uint32
            _sendGasTo, // address
            governance, // uint256
            platformCode, // TvmCell
            accountCode, // TvmCell
            clusterCode, // TvmCell


            stEverSupply, // uint128
            totalAssets, // uint128
            availableAssets, // uint128
            totalStEverFee, // uint128
            effectiveEverAssets, //uint128,
            remainingLockedAssets, // uint128
            unlockPerSecond, // uint128


            stEverWallet, // address
            stTokenRoot, // address


            lastUnlockTime, // uint64
            fullUnlockSeconds, // uint64
            remainingSeconds, // uint64


            gainFee, // uint128
            stEverFeePercent, // uint32
            minStrategyDepositValue, // uint128
            minStrategyWithdrawValue, // uint128
            isPaused, // bool
            strategyFactory, // address,
            withdrawHoldTime, // uint64


            owner, // address
            accountVersion, // uint32
            stEverVaultVersion, // uint32
            clusterVersion, // uint32


            strategies, // mapping(address => StrategyParams)
            clusterPools, // mapping(address => ClustersPool)
            pendingWithdrawals, // mapping(uint64 => PendingWithdraw)


            emergencyState, // EmergencyState,
            timeAfterEmergencyCanBeActivated
        );

        // set code after complete this method
        tvm.setcode(_newCode);
        // run onCodeUpgrade from new code
        tvm.setCurrentCode(_newCode);

        onCodeUpgrade(data);
    }

    // upgrade to v5
    function onCodeUpgrade(TvmCell _upgradeData) private {}
}