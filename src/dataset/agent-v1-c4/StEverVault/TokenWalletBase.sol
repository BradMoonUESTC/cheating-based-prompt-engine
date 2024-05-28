pragma solidity >=0.7.0 <0.9.0;
import "../interfaces/ITokenWallet.tsol";
import "../interfaces/ITokenRoot.tsol";
import "../interfaces/IAcceptTokensTransferCallback.tsol";
import "../interfaces/IAcceptTokensMintCallback.tsol";
import "../interfaces/IBounceTokensTransferCallback.tsol";
import "../interfaces/IBounceTokensBurnCallback.tsol";
import "../libraries/TokenErrors.tsol";
import "../libraries/TokenMsgFlag.tsol";


abstract contract TokenWalletBase is ITokenWallet {

    address static root_;
    address static owner_;

    uint128 balance_;

    modifier onlyRoot() {
        require(root_ == msg.sender, TokenErrors.NOT_ROOT);
        _;
    }

    modifier onlyOwner() {
        require(owner_ == msg.sender, TokenErrors.NOT_OWNER);
        _;
    }

    function balance() override external view responsible returns (uint128) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } balance_;
    }

    function owner() override external view responsible returns (address) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } owner_;
    }

    function root() override external view responsible returns (address) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } root_;
    }

    function walletCode() override external view responsible returns (TvmCell) {
        return { value: 0, flag: TokenMsgFlag.REMAINING_GAS, bounce: false } tvm.code();
    }

    function transfer(
        uint128 amount,
        address recipient,
        uint128 deployWalletValue,
        address remainingGasTo,
        bool notify,
        TvmCell payload
    )
        override
        external
        onlyOwner
    {
        require(amount > 0, TokenErrors.WRONG_AMOUNT);
        require(amount <= balance_, TokenErrors.NOT_ENOUGH_BALANCE);
        require(recipient.value != 0 && recipient != owner_, TokenErrors.WRONG_RECIPIENT);

        tvm.rawReserve(_reserve(), 0);

        TvmCell stateInit = _buildWalletInitData(recipient);

        address recipientWallet;

        if (deployWalletValue > 0) {
            recipientWallet = _deployWallet(stateInit, deployWalletValue, remainingGasTo);
        } else {
            recipientWallet = address(tvm.hash(stateInit));
        }
            
        balance_ -= amount;

        ITokenWallet(recipientWallet).acceptTransfer{ value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED, bounce: true }(
            amount,
            owner_,
            remainingGasTo,
            notify,
            payload
        );
    }

    /*
        @notice Transfer tokens using another TokenWallet address, that wallet must be deployed previously
        @dev Can be called only by token wallet owner
        @param amount How much tokens to transfer
        @param recipientWallet Recipient TokenWallet address
        @param remainingGasTo Remaining gas receiver
        @param notify Notify receiver on incoming transfer
        @param payload Notification payload
    */
    function transferToWallet(
        uint128 amount,
        address recipientTokenWallet,
        address remainingGasTo,
        bool notify,
        TvmCell payload
    )
        override
        external
        onlyOwner
    {
        require(amount > 0, TokenErrors.WRONG_AMOUNT);
        require(amount <= balance_, TokenErrors.NOT_ENOUGH_BALANCE);
        require(recipientTokenWallet.value != 0 && recipientTokenWallet != address(this), TokenErrors.WRONG_RECIPIENT);

        tvm.rawReserve(_reserve(), 0);

        balance_ -= amount;

        ITokenWallet(recipientTokenWallet).acceptTransfer{ value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED, bounce: true }(
            amount,
            owner_,
            remainingGasTo,
            notify,
            payload
        );
    }

    /*
        @notice Callback for transfer operation
        @dev Can be called only by another valid TokenWallet contract with same root
        @param amount How much tokens to receive
        @param sender Sender address
        @param remainingGasTo Remaining gas receiver
        @param notify Notify receiver on incoming transfer
        @param payload Notification payload
    */
    function acceptTransfer(
        uint128 amount,
        address sender,
        address remainingGasTo,
        bool notify,
        TvmCell payload
    )
        override
        external
        functionID(0x67A0B95F)
    {
        require(msg.sender == address(tvm.hash(_buildWalletInitData(sender))), TokenErrors.SENDER_IS_NOT_VALID_WALLET);

        tvm.rawReserve(_reserve(), 2);

        balance_ += amount;

        if (notify) {
            IAcceptTokensTransferCallback(owner_).onAcceptTokensTransfer{
                value: 0,
                flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS,
                bounce: false
            }(
                root_,
                amount,
                sender,
                msg.sender,
                remainingGasTo,
                payload
            );
        } else {
            remainingGasTo.transfer({ value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS, bounce: false });
        }
    }

    /*
        @notice Accept minted tokens from root
        @dev Can be called only by root token
        @param amount How much tokens to accept
        @param data Additional data
    */
    function acceptMint(uint128 amount, address remainingGasTo, bool notify, TvmCell payload)
        override
        external
        functionID(0x4384F298)
        onlyRoot
    {
        tvm.rawReserve(_reserve(), 2);

        balance_ += amount;

        if (notify) {
            IAcceptTokensMintCallback(owner_).onAcceptTokensMint{
                value: 0,
                bounce: false,
                flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS
            }(
                root_,
                amount,
                remainingGasTo,
                payload
            );
        } else if (remainingGasTo.value != 0 && remainingGasTo != address(this)) {
            remainingGasTo.transfer({ value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS, bounce: false });
        }
    }

    /*
        @notice On-bounce handler
        @dev Catch bounce if acceptTransfer or tokensBurned fails
        @dev If transfer fails - increase back tokens balance and notify owner
        @dev If tokens burn root token callback fails - increase back tokens balance and notify owner
    */
    onBounce(TvmSlice body) external {
        tvm.rawReserve(_reserve(), 2);

        uint32 functionId = body.decode(uint32);

        if (functionId == tvm.functionId(ITokenWallet.acceptTransfer)) {
            uint128 amount = body.decode(uint128);
            balance_ += amount;
            IBounceTokensTransferCallback(owner_).onBounceTokensTransfer{
                value: 0,
                flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS,
                bounce: false
            }(
                root_,
                amount,
                msg.sender
            );
        } else if (functionId == tvm.functionId(ITokenRoot.acceptBurn)) {
            uint128 amount = body.decode(uint128);
            balance_ += amount;
            IBounceTokensBurnCallback(owner_).onBounceTokensBurn{
                value: 0,
                flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS,
                bounce: false
            }(
                root_,
                amount
            );
        }
    }

    function _burn(
        uint128 amount,
        address remainingGasTo,
        address callbackTo,
        TvmCell payload
    ) internal {
        require(amount > 0, TokenErrors.WRONG_AMOUNT);
        require(amount <= balance_, TokenErrors.NOT_ENOUGH_BALANCE);

        tvm.rawReserve(_reserve(), 0);

        balance_ -= amount;

        ITokenRoot(root_).acceptBurn{ value: 0, flag: TokenMsgFlag.ALL_NOT_RESERVED, bounce: true }(
            amount,
            owner_,
            remainingGasTo,
            callbackTo,
            payload
        );
    }

    /*
        @notice Withdraw all surplus balance in EVERs
        @dev Can by called only by owner address
        @param to Withdraw receiver
    */
    function sendSurplusGas(address to) external view onlyOwner {
        tvm.rawReserve(_targetBalance(), 0);
        to.transfer({
            value: 0,
            flag: TokenMsgFlag.ALL_NOT_RESERVED + TokenMsgFlag.IGNORE_ERRORS,
            bounce: false
        });
    }

    function _reserve() internal pure returns (uint128) {
        return math.max(address(this).balance - msg.value, _targetBalance());
    }

    function _targetBalance() virtual internal pure returns (uint128);
    function _buildWalletInitData(address walletOwner) virtual internal view returns (TvmCell);
    function _deployWallet(TvmCell initData, uint128 deployWalletValue, address remainingGasTo) virtual internal view returns (address);
}