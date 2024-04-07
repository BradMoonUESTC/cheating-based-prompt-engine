// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseWithRewards.sol";
import "../../../../interfaces/IQiErc20.sol";
import "../../../../interfaces/IQiAvax.sol";
import "../../../../interfaces/IBenQiComptroller.sol";
import "../../../../interfaces/IWETH.sol";

import "./PendleQiTokenHelper.sol";

contract PendleQiTokenSY is SYBaseWithRewards, PendleQiTokenHelper {
    address public immutable underlying;
    address public immutable QI;
    address public immutable WAVAX;
    address public immutable comptroller;
    address public immutable qiToken;

    constructor(
        string memory _name,
        string memory _symbol,
        address _qiToken,
        bool isUnderlyingNative,
        address _WAVAX,
        uint256 _initialExchangeRateMantissa
    ) SYBaseWithRewards(_name, _symbol, _qiToken) PendleQiTokenHelper(_qiToken, _initialExchangeRateMantissa) {
        qiToken = _qiToken;

        underlying = isUnderlyingNative ? NATIVE : IQiErc20(qiToken).underlying();
        comptroller = IQiToken(qiToken).comptroller();

        QI = IBenQiComptroller(comptroller).qiAddress();
        WAVAX = _WAVAX;

        _safeApproveInf(underlying, qiToken);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {SYBase-_deposit}
     *
     * The underlying yield token is qiToken. If the base token deposited is underlying asset, the function
     * first convert those deposited into qiToken. Then the corresponding amount of shares is returned.
     *
     * The exchange rate of qiToken to shares is 1:1
     */
    function _deposit(address tokenIn, uint256 amount) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == qiToken) {
            amountSharesOut = amount;
        } else {
            // tokenIn is underlying -> convert it into qiToken first
            uint256 preBalanceQiToken = _selfBalance(qiToken);

            if (underlying == NATIVE) {
                IQiAvax(qiToken).mint{value: amount}();
            } else {
                uint256 errCode = IQiErc20(qiToken).mint(amount);
                if (errCode != 0) revert Errors.SYQiTokenMintFailed(errCode);
            }

            amountSharesOut = _selfBalance(qiToken) - preBalanceQiToken;
        }
    }

    /**
     * @dev See {SYBase-_redeem}
     *
     * The shares are redeemed into the same amount of qiTokens. If `tokenOut` is the underlying asset,
     * the function also redeems said asset from the corresponding amount of qiToken.
     */
    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256 amountTokenOut) {
        if (tokenOut == qiToken) {
            amountTokenOut = amountSharesToRedeem;
        } else {
            uint256 preBalanceUnderlying = _selfBalance(underlying);

            if (underlying == NATIVE) {
                uint256 errCode = IQiAvax(qiToken).redeem(amountSharesToRedeem);
                if (errCode != 0) revert Errors.SYQiTokenRedeemFailed(errCode);
            } else {
                uint256 errCode = IQiErc20(qiToken).redeem(amountSharesToRedeem);
                if (errCode != 0) revert Errors.SYQiTokenRedeemFailed(errCode);
            }

            // underlying is potentially also rewardToken, hence we need to manually track the balance here
            amountTokenOut = _selfBalance(underlying) - preBalanceUnderlying;
        }
        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates and updates the exchange rate of shares to underlying asset token
     * @dev It is the exchange rate of qiToken to its underlying asset
     */
    function exchangeRate() public view override returns (uint256) {
        return _exchangeRateCurrentView();
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-getRewardTokens}
     */
    function _getRewardTokens() internal view override returns (address[] memory res) {
        res = new address[](2);
        res[0] = QI;
        res[1] = WAVAX;
    }

    function _redeemExternalReward() internal override {
        address[] memory holders = new address[](1);
        address[] memory qiTokens = new address[](1);
        holders[0] = address(this);
        qiTokens[0] = qiToken;

        IBenQiComptroller(comptroller).claimReward(0, holders, qiTokens, false, true);
        IBenQiComptroller(comptroller).claimReward(1, holders, qiTokens, false, true);

        uint256 rewardAccruedType0 = IBenQiComptroller(comptroller).rewardAccrued(0, address(this));
        uint256 rewardAccruedType1 = IBenQiComptroller(comptroller).rewardAccrued(1, address(this));

        if (rewardAccruedType0 > 0 || rewardAccruedType1 > 0)
            revert Errors.SYQiTokenRedeemRewardsFailed(rewardAccruedType0, rewardAccruedType1);

        if (address(this).balance != 0) IWETH(WAVAX).deposit{value: address(this).balance}();
    }

    /*///////////////////////////////////////////////////////////////
                    MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 amountSharesOut) {
        if (tokenIn == qiToken) amountSharesOut = amountTokenToDeposit;
        else amountSharesOut = (amountTokenToDeposit * 1e18) / exchangeRate();
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 amountTokenOut) {
        if (tokenOut == qiToken) amountTokenOut = amountSharesToRedeem;
        else amountTokenOut = (amountSharesToRedeem * exchangeRate()) / 1e18;
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = qiToken;
        res[1] = underlying;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = qiToken;
        res[1] = underlying;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == qiToken || token == underlying;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == qiToken || token == underlying;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, underlying, underlying == NATIVE ? 18 : IERC20Metadata(underlying).decimals());
    }
}
