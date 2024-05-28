pragma solidity >=0.7.0 <0.9.0;
import "./TokenWalletBase.tsol";
import "../interfaces/ITokenRoot.tsol";
import "../interfaces/IBurnableTokenWallet.tsol";
import "../libraries/TokenErrors.tsol";
import "../libraries/TokenMsgFlag.tsol";


abstract contract TokenWalletBurnableBase is TokenWalletBase, IBurnableTokenWallet {

    /*
        @notice Burn tokens
        @dev Can be called only by token wallet owner
        @param tokens How much tokens to burn
        @param grams How much EVERs attach to tokensBurned in case called with owner public key
        @param remainingGasTo Receiver of the remaining EVERs balance, used in tokensBurned callback
        @param callbackTo Address of contract, which implement IAcceptTokensBurnCallback.onAcceptTokensBurn
               if it equals to 0:0 then no callbacks
        @param payload Custom data will be delivered into IAcceptTokensBurnCallback.onAcceptTokensBurn
    */
    function burn(uint128 amount, address remainingGasTo, address callbackTo, TvmCell payload)
        override
        external
        onlyOwner
    {
        _burn(amount, remainingGasTo, callbackTo, payload);
    }
}