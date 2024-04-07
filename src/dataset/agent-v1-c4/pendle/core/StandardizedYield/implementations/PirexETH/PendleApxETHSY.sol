// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.23;

import "../../SYBase.sol";
import "../../../../interfaces/PirexETH/IPirexETH.sol";
import "../../../../interfaces/IERC4626.sol";

contract PendleApxETHSY is SYBase {
    uint256 public constant FEE_DENOMINATOR = 1_000_000;

    error ApxETHNotEnoughBuffer();

    address public immutable pirexETH;
    address public immutable pxETH;
    address public immutable apxETH;

    constructor(
        address _pirexETH
    ) SYBase("SY Autocompounding Pirex ETH", "SY-apxETH", IPirexETH(_pirexETH).autoPxEth()) {
        pirexETH = _pirexETH;
        pxETH = IPirexETH(_pirexETH).pxEth();
        apxETH = IPirexETH(_pirexETH).autoPxEth();

        _safeApproveInf(pxETH, apxETH);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == apxETH) {
            return amountDeposited;
        }

        uint256 preBalance = _selfBalance(apxETH);
        if (tokenIn == NATIVE) {
            IPirexETH(pirexETH).deposit{value: amountDeposited}(address(this), true);
        } else {
            IERC4626(apxETH).deposit(amountDeposited, address(this));
        }
        return _selfBalance(apxETH) - preBalance;
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256 amountTokenOut) {
        if (tokenOut == apxETH) {
            amountTokenOut = amountSharesToRedeem;
        } else {
            uint256 amountPxETH = IERC4626(apxETH).redeem(amountSharesToRedeem, address(this), address(this));
            if (tokenOut == pxETH) {
                amountTokenOut = amountPxETH;
            } else {
                (amountTokenOut, ) = IPirexETH(pirexETH).instantRedeemWithPxEth(amountPxETH, address(this));
            }
        }
        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view override returns (uint256) {
        return IERC4626(apxETH).convertToAssets(1 ether);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == apxETH) {
            return amountTokenToDeposit;
        } else {
            uint256 fee = IPirexETH(pirexETH).fees(IPirexETH.Fees.Deposit);
            uint256 amountPxETH = amountTokenToDeposit - (amountTokenToDeposit * fee) / FEE_DENOMINATOR;
            return IERC4626(apxETH).previewDeposit(amountPxETH);
        }
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 /*amountTokenOut*/) {
        if (tokenOut == apxETH) {
            return amountSharesToRedeem;
        } else {
            uint256 amountPxETH = IERC4626(apxETH).previewRedeem(amountSharesToRedeem);
            if (tokenOut == pxETH) {
                return amountPxETH;
            } else {
                uint256 feeRatio = IPirexETH(pirexETH).fees(IPirexETH.Fees.InstantRedemption);
                uint256 postFeeAmount = amountPxETH - (amountPxETH * feeRatio) / FEE_DENOMINATOR;
                if (postFeeAmount > IPirexETH(pirexETH).buffer()) revert ApxETHNotEnoughBuffer();
                return postFeeAmount;
            }
        }
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, pxETH, apxETH);
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, pxETH, apxETH);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == pxETH || token == apxETH;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == NATIVE || token == pxETH || token == apxETH;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, pxETH, 18);
    }
}
