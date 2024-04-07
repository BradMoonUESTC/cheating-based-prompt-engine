// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/IPActionCallbackV3.sol";
import "../core/libraries/Errors.sol";
import "./base/CallbackHelper.sol";

import "../core/libraries/TokenHelper.sol";

contract ActionCallbackV3 is IPLimitOrderType, IPActionCallbackV3, CallbackHelper, TokenHelper {
    using PMath for int256;
    using PMath for uint256;
    using PYIndexLib for PYIndex;
    using PYIndexLib for IPYieldToken;

    function swapCallback(int256 ptToAccount, int256 syToAccount, bytes calldata data) external override {
        ActionType swapType = _getActionType(data);
        if (swapType == ActionType.SwapExactSyForYt) {
            _callbackSwapExactSyForYt(ptToAccount, syToAccount, data);
        } else if (swapType == ActionType.SwapYtForSy) {
            _callbackSwapYtForSy(ptToAccount, syToAccount, data);
        } else if (swapType == ActionType.SwapExactYtForPt) {
            _callbackSwapExactYtForPt(ptToAccount, syToAccount, data);
        } else if (swapType == ActionType.SwapExactPtForYt) {
            _callbackSwapExactPtForYt(ptToAccount, syToAccount, data);
        } else {
            assert(false);
        }
    }

    function limitRouterCallback(
        uint256 actualMaking,
        uint256 actualTaking,
        uint256,
        /*totalFee*/ bytes memory data
    )
        external
        returns (
            bytes memory // encode as netTransferToLimit, netOutputFromLimit
        )
    {
        (OrderType orderType, IPYieldToken YT, uint256 netRemaining, address receiver) = abi.decode(
            data,
            (OrderType, IPYieldToken, uint256, address)
        );

        if (orderType == OrderType.SY_FOR_PT || orderType == OrderType.SY_FOR_YT) {
            PYIndex index = YT.newIndex();
            uint256 totalSyToMintPy = index.assetToSyUp(actualTaking);
            uint256 additionalSyToMint = totalSyToMintPy - actualMaking;

            require(additionalSyToMint <= netRemaining, "Router: Max SY to pull exceeded");

            _transferOut(YT.SY(), address(YT), additionalSyToMint);

            uint256 netPyToReceiver;
            if (orderType == OrderType.SY_FOR_PT) {
                netPyToReceiver = YT.mintPY(address(this), receiver);
                _safeApproveInf(YT.PT(), msg.sender);
            } else {
                netPyToReceiver = YT.mintPY(receiver, address(this));
                _safeApproveInf(address(YT), msg.sender);
            }

            return abi.encode(additionalSyToMint, netPyToReceiver);
        } else {
            require(actualMaking <= netRemaining, "Router: Max PY to pull exceeded");

            if (orderType == OrderType.PT_FOR_SY) {
                _transferOut(address(YT), address(YT), actualMaking);
            } else {
                _transferOut(YT.PT(), address(YT), actualMaking);
            }

            uint256 netSyRedeemed = IPYieldToken(YT).redeemPY(address(this));

            require(actualTaking <= netSyRedeemed, "Router: Insufficient SY redeemed");

            uint256 netSyToReceiver = netSyRedeemed - actualTaking;

            address SY = YT.SY();

            _transferOut(SY, receiver, netSyToReceiver);
            _safeApproveInf(SY, msg.sender);

            return abi.encode(actualMaking, netSyToReceiver);
        }
    }

    function _callbackSwapExactSyForYt(int256 ptToAccount, int256, /*syToAccount*/ bytes calldata data) internal {
        (address receiver, IPYieldToken YT) = _decodeSwapExactSyForYt(data);

        uint256 ptOwed = ptToAccount.abs();
        uint256 netPyOut = YT.mintPY(msg.sender, receiver);

        if (netPyOut < ptOwed) revert Errors.RouterInsufficientPtRepay(netPyOut, ptOwed);
    }

    function _callbackSwapYtForSy(int256 ptToAccount, int256 syToAccount, bytes calldata data) internal {
        (address receiver, IPYieldToken YT) = _decodeSwapYtForSy(data);
        PYIndex pyIndex = YT.newIndex();

        uint256 syOwed = syToAccount.neg().Uint();

        address[] memory receivers = new address[](2);
        uint256[] memory amountPYToRedeems = new uint256[](2);

        (receivers[0], amountPYToRedeems[0]) = (msg.sender, pyIndex.syToAssetUp(syOwed));
        (receivers[1], amountPYToRedeems[1]) = (receiver, ptToAccount.Uint() - amountPYToRedeems[0]);

        YT.redeemPYMulti(receivers, amountPYToRedeems);
    }

    function _callbackSwapExactPtForYt(int256 ptToAccount, int256, /*syToAccount*/ bytes calldata data) internal {
        (address receiver, uint256 exactPtIn, uint256 minYtOut, IPYieldToken YT) = _decodeSwapExactPtForYt(data);
        uint256 netPtOwed = ptToAccount.abs();

        uint256 netPyOut = YT.mintPY(msg.sender, receiver);
        if (netPyOut < minYtOut) revert Errors.RouterInsufficientYtOut(netPyOut, minYtOut);
        if (exactPtIn + netPyOut < netPtOwed) {
            revert Errors.RouterInsufficientPtRepay(exactPtIn + netPyOut, netPtOwed);
        }
    }

    function _callbackSwapExactYtForPt(int256 ptToAccount, int256 syToAccount, bytes calldata data) internal {
        (address receiver, uint256 netPtOut, IPPrincipalToken PT, IPYieldToken YT) = _decodeSwapExactYtForPt(data);

        uint256 netSyOwed = syToAccount.abs();

        uint256 netPtRedeemSy = ptToAccount.Uint() - netPtOut;
        _transferOut(address(PT), address(YT), netPtRedeemSy);

        uint256 netSyToMarket = YT.redeemPY(msg.sender);

        if (netSyToMarket < netSyOwed) {
            revert Errors.RouterInsufficientSyRepay(netSyToMarket, netSyOwed);
        }

        _transferOut(address(PT), receiver, netPtOut);
    }
}
