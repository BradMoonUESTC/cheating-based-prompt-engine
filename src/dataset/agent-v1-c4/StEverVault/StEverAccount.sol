pragma solidity >=0.7.0 <0.9.0;
import "./interfaces/IStEverAccount.tsol";
import "./interfaces/IStEverVault.tsol";
import "./utils/ErrorCodes.tsol";
import "./utils/Gas.tsol";
import "./utils/Constants.tsol";

import "../external/@broxus/contracts/contracts/libraries/MsgFlag.tsol";

/**
 * @title StEverAccount
 *
 * @dev Implementation of the {IStEverAccount} interface.
 *
 *
 * This contract represents a user's account for handling withdrawal requests
 * in the StEver staking platform.
 *
 *
 * It is linked to the {StEverVault} contract, which manages all ever assets and issues StEver tokens.
 *
 *
 * A user initiates a withdrawal from the StEverVault, creating a withdrawal request in their StEverAccount.
 * The user can also cancel this request.
 */
contract StEverAccount is IStEverAccount {
    address vault; // setup from initData
    address user; // setup from initData
    uint32 currentVersion; //setup from _init

    // Mapping of withdrawal requests
    mapping(uint64 => IStEverAccount.WithdrawRequest) public withdrawRequests;

    constructor() public {
        revert();
    }

    /**
     * @dev Internal function to initialize the contract.
     * @param _version The version to set as the current version.
     */
    function _init(uint32 _version) internal {
        currentVersion = _version;
    }

    /**
     * @dev Modifier to make a function callable only when the caller is the vault.
     */
    modifier onlyVault() {
        require (msg.sender == vault, ErrorCodes.ONLY_VAULT);
        _;
    }

    /**
    * @dev Calculates the reserve by taking the maximum of the contract's
    * current balance minus the value sent in the message
    * (i.e., the amount of native coins sent with the current transaction) and the
    * minimum balance of the contract (as determined by the {StEverAccountGas.CONTRACT_MIN_BALANCE} constant).
    *
    *
    * This ensures that the reserve is set to the higher of the contract's
    * current balance minus the message value or its minimum balance, ensuring that the contract
    * does not spend more native coins than it has available.
    *
    * @return The calculated reserve.
    */
    function _reserve() internal pure returns (uint128) {
		return
			math.max(address(this).balance - msg.value, StEverAccountGas.CONTRACT_MIN_BALANCE);
	}

    /**
     * @dev See {IStEverAccount-getDetails}.
     */
    function getDetails()
		external
		view
		responsible
		override
		returns (IStEverAccount.AccountDetails)
	{
		return
			{
				value: 0,
				bounce: false,
				flag: MsgFlag.REMAINING_GAS
			} AccountDetails(user, vault, currentVersion);
	}

    /**
     * @dev See {IStEverAccount-addPendingValue}.
     *
     * **Preconditions**:
     *
     * - The caller must be the vault.
     *
     * - The number of withdrawal requests must be less than `MAX_PENDING_COUNT`.
     *
     * - The withdrawal request with the given nonce must not exist.
     *
     * **Postconditions**:
     *
     * - A new withdrawal request is added to the withdrawal requests.
     *
     * - The {IStEverVault-onPendingWithdrawAccepted} function of the {StEverVault} contract is called.
     *
     */
    function addPendingValue(
        uint64 _nonce,
        uint128 _amount,
        uint64 _unlockTime,
        address _remainingGasTo
    ) override external onlyVault {
        tvm.rawReserve(_reserve(), 0);
        if (withdrawRequests.keys().length < Constants.MAX_PENDING_COUNT && !withdrawRequests.exists(_nonce)) {

            withdrawRequests[_nonce] = WithdrawRequest({
                amount: _amount,
                timestamp: now,
                unlockTime: _unlockTime
            });

            IStEverVault(vault).onPendingWithdrawAccepted{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(_nonce, user, _remainingGasTo);
            return;
        }
        IStEverVault(vault).onPendingWithdrawRejected{value: 0, flag:MsgFlag.ALL_NOT_RESERVED, bounce: false}(_nonce, user, _amount, _remainingGasTo);
    }

    /**
     * @dev See {IStEverAccount-resetPendingValues}.
     *
     * **Preconditions**:
     *
     *
     * - The caller must be the vault.
     *
     * **Postconditions**:
     *
     *
     * - The withdrawal requests are reset to the given withdrawal requests.
     *
     * - The gas is sent to the given address.
     */
    function resetPendingValues(mapping(uint64 => IStEverAccount.WithdrawRequest) rejectedWithdrawals, address _sendGasTo) override external onlyVault {
        tvm.rawReserve(_reserve(), 0);

        for ((uint64 nonce, IStEverAccount.WithdrawRequest rejectedWithdrawRequest) : rejectedWithdrawals) {
            withdrawRequests[nonce] = rejectedWithdrawRequest;
        }

        _sendGasTo.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev See {IStEverAccount-removePendingWithdraw}.
     *
     * **Preconditions**:
     *
     *
     * - The caller must be the vault.
     *
     * - The withdrawal request with the given nonce must exist.
     *
     * **Postconditions**:
     *
     *
     * - The withdrawal request with the given nonce is removed from the withdrawal requests.
     *
     * - The onPendingWithdrawRemoved function of the StEverVault contract is called.
     */
    function removePendingWithdraw(uint64 _nonce) override external onlyVault {
        tvm.rawReserve(_reserve(), 0);
        if (withdrawRequests.exists(_nonce)) {
            IStEverAccount.WithdrawRequest withdrawRequest = withdrawRequests[_nonce];
            delete withdrawRequests[_nonce];
            IStEverVault(vault).onPendingWithdrawRemoved{
                value: 0,
                flag:MsgFlag.ALL_NOT_RESERVED,
                bounce: false
            }(user, _nonce, withdrawRequest.amount);
            return;
        }
        user.transfer({value:0, flag:MsgFlag.ALL_NOT_RESERVED, bounce: false});
    }

    /**
     * @dev Prepares data about withdraw requests that will send to the vault.
     *
     * @param _satisfiedWithdrawRequests The withdrawal requests to satisfy.
     *
     *
     * @dev Postconditions:
     *
     * - The withdrawal requests are removed from the withdrawal requests.
     *
     * - The withdrawToUser function of the StEverVault contract is called.
     */
    function createAndSendWithdrawToUserRequest(uint64[] _satisfiedWithdrawRequests) internal {

        uint128 totalAmount = 0;
        mapping(uint64 => IStEverAccount.WithdrawRequest) withdrawals;

        for (uint256 i = 0; i < _satisfiedWithdrawRequests.length; i++) {
            uint64 withdrawRequestKey = _satisfiedWithdrawRequests[i];
            if (withdrawRequests.exists(withdrawRequestKey)) {
                IStEverAccount.WithdrawRequest withdrawRequest = withdrawRequests[withdrawRequestKey];
                withdrawals[withdrawRequestKey] = withdrawRequest;
                delete withdrawRequests[withdrawRequestKey];
                totalAmount += withdrawRequest.amount;
            }
        }

        IStEverVault(vault).withdrawToUser{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            bounce: false
        }(
            totalAmount, user, withdrawals
        );
    }

    /**
     * @dev See {IStEverAccount-processWithdraw}.
     *
     *
     * **Preconditions**:
     *
     *
     * - The caller must be the vault.
     *
     *
     * **Postconditions**:
     *
     *
     * - The {createAndSendWithdrawToUserRequest} function is called with the given withdrawal requests.
     */
    function processWithdraw(uint64[] _satisfiedWithdrawRequests) override external onlyVault {
        tvm.rawReserve(_reserve(), 0);
        createAndSendWithdrawToUserRequest(_satisfiedWithdrawRequests);
    }

    /**
     * @dev See {IStEverAccount-onEmergencyWithdrawToUser}.
     *
     * **Preconditions**:
     *
     * - The caller must be the vault.
     *
     * **Postconditions**:
     *
     * - If there are no withdrawal requests, the user is sent 0 value.
     *
     * - Otherwise, the {createAndSendWithdrawToUserRequest} function is called with all the withdrawal requests.
     */
    function onEmergencyWithdrawToUser() override external onlyVault {
        tvm.rawReserve(_reserve(), 0);
        uint64[] satisfiedWithdrawRequests;
        for((uint64 nonce,) : withdrawRequests) {
            satisfiedWithdrawRequests.push(nonce);
        }
        if (satisfiedWithdrawRequests.length == 0) {
            user.transfer({value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false});
            return;
        }
        createAndSendWithdrawToUserRequest(satisfiedWithdrawRequests);
    }

    /**
     * @dev See {IStEverAccount-onStartEmergency}.
     *
     * **Preconditions**:
     *
     * - The caller must be the vault.
     *
     * - The withdrawal request with the given nonce must exist.
     *
     * - The withdrawal request must be eligible for an emergency withdrawal.
     *
     * **Postconditions**:
     *
     * - If the withdrawal request is not eligible for an emergency withdrawal,
     *    the {IStEverVault-startEmergencyRejected} is called.
     *
     * - Otherwise, the {IStEverVault-emergencyWithdrawFromStrategiesProcess} is called.
     */
    function onStartEmergency(uint64 _proofNonce, uint64 _timeAfterEmergencyCanBeActivated) override external onlyVault {
        tvm.rawReserve(_reserve(), 0);
        if (!withdrawRequests.exists(_proofNonce)) {
            IStEverVault(vault).startEmergencyRejected{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(user, ErrorCodes.REQUEST_NOT_EXISTS);
            return;
        }

        IStEverAccount.WithdrawRequest withdrawRequest = withdrawRequests[_proofNonce];
        if ((withdrawRequest.unlockTime + _timeAfterEmergencyCanBeActivated) > now) {
            IStEverVault(vault).startEmergencyRejected{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(user, ErrorCodes.EMERGENCY_CANT_BE_ACTIVATED);
            return;
        }

        IStEverVault(vault).emergencyWithdrawFromStrategiesProcess{value: 0, flag: MsgFlag.ALL_NOT_RESERVED, bounce: false}(user);
    }

    /**
     * @dev See {IStEverAccount-upgrade}.
     *
     * **Preconditions**:
     *
     * - The caller must be the vault.
     *
     * - The new version must not be the same as the current version.
     *
     * **Postconditions**:
     *
     * - If the new version is the same as the current version, the gas is sent to the given address.
     *
     * - Otherwise, the contract is upgraded to the new code and the new version.
     */
    function upgrade(TvmCell _newCode, uint32 _newVersion, address _sendGasTo) external virtual override onlyVault {


        if (_newVersion == currentVersion) {
            tvm.rawReserve(_reserve(), 0);
            _sendGasTo.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
            return;
        }


        TvmBuilder mainBuilder;
        mainBuilder.store(vault);
        mainBuilder.store(uint8(0));
        mainBuilder.store(_sendGasTo);

        TvmCell dummyPlatformCode;
        mainBuilder.store(dummyPlatformCode);

        TvmCell initialData = abi.encode(user);

        TvmCell constructorParams = abi.encode(_newVersion, currentVersion);

        mainBuilder.storeRef(initialData);
        mainBuilder.storeRef(constructorParams);

        TvmCell storageData = abi.encode(
            vault,              //address
            user,               //address
            currentVersion,     //uint32
            withdrawRequests    //mapping(uint64 => WithdrawRequest)
        );

        mainBuilder.storeRef(storageData);


        // set code after complete this method
        tvm.setcode(_newCode);
        // run onCodeUpgrade from new code
        tvm.setCurrentCode(_newCode);

        onCodeUpgrade(mainBuilder.toCell());
    }

    /**
     * @dev Called when the factory code is upgraded for rewriting the storage.
     * @param _upgradeData The data to use for the upgrade.
     *
     * **Postconditions**:
     *
     * - The storage is reset.
     *
     * - The gas is sent to the given address.
     *
     * - If the new version is the same as the current version, the contract is initialized with the new version.
     *
     * - Otherwise, the contract is upgraded to the new code and the new version.
     */
    function onCodeUpgrade(TvmCell _upgradeData) private {
        tvm.resetStorage();
        tvm.rawReserve(_reserve(), 0);
        TvmSlice s = _upgradeData.toSlice();

        (address root_, , address sendGasTo, ) = s.decode(address, uint8, address,TvmCell);
        vault = root_;

        TvmCell initialData = s.loadRef();
        (user) = abi.decode(initialData, (address));

        TvmCell constructorParams = s.loadRef();
        (uint32 _newVersion, uint32 _currentVersion) = abi.decode(constructorParams, (uint32, uint32));

        if (_newVersion == _currentVersion) {
            _init(_newVersion);
        }

        if  (_newVersion != _currentVersion) {
            (
                ,
                ,
                ,
                mapping(uint64 => IStEverAccount.WithdrawRequest) oldWithdrawRequests
            ) = abi.decode(
                s.loadRef(),
                (
                    address,
                    address,
                    uint32,
                    mapping(uint64 => IStEverAccount.WithdrawRequest)
                )
            );
            currentVersion = _newVersion;
            for ((uint64 nonce, IStEverAccount.WithdrawRequest oldWithdrawRequest) : oldWithdrawRequests) {
                withdrawRequests[nonce] = IStEverAccount.WithdrawRequest(oldWithdrawRequest.amount, oldWithdrawRequest.timestamp, 0);
            }
        }


        sendGasTo.transfer({value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED});
    }
}