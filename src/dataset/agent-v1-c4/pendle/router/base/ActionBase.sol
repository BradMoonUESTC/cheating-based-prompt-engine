// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../core/libraries/TokenHelper.sol";
import "../../interfaces/IStandardizedYield.sol";
import "../../interfaces/IPYieldToken.sol";
import "../../interfaces/IPAllActionTypeV3.sol";
import "../../interfaces/IPMarket.sol";
import "../../router/base/MarketApproxLib.sol";

import "../../core/libraries/Errors.sol";
import "../swap-aggregator/IPSwapAggregator.sol";

abstract contract ActionBase is TokenHelper, IPLimitOrderType {
    using MarketApproxPtOutLib for MarketState;
    using PMath for uint256;
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;

    bytes internal constant EMPTY_BYTES = abi.encode();

    // ----------------- MINT REDEEM SY PY -----------------

    function _mintSyFromToken(
        address receiver,
        address SY,
        uint256 minSyOut,
        TokenInput calldata inp
    ) internal returns (uint256 netSyOut) {
        SwapType swapType = inp.swapData.swapType;

        uint256 netTokenMintSy;

        if (swapType == SwapType.NONE) {
            _transferIn(inp.tokenIn, msg.sender, inp.netTokenIn);
            netTokenMintSy = inp.netTokenIn;
        } else if (swapType == SwapType.ETH_WETH) {
            _transferIn(inp.tokenIn, msg.sender, inp.netTokenIn);
            _wrap_unwrap_ETH(inp.tokenIn, inp.tokenMintSy, inp.netTokenIn);
            netTokenMintSy = inp.netTokenIn;
        } else {
            _swapTokenInput(inp);
            netTokenMintSy = _selfBalance(inp.tokenMintSy);
        }

        netSyOut = __mintSy(receiver, SY, netTokenMintSy, minSyOut, inp);
    }

    function _swapTokenInput(TokenInput calldata inp) internal {
        if (inp.tokenIn == NATIVE) _transferIn(NATIVE, msg.sender, inp.netTokenIn);
        else _transferFrom(IERC20(inp.tokenIn), msg.sender, inp.pendleSwap, inp.netTokenIn);

        IPSwapAggregator(inp.pendleSwap).swap{value: inp.tokenIn == NATIVE ? inp.netTokenIn : 0}(
            inp.tokenIn,
            inp.netTokenIn,
            inp.swapData
        );
    }

    function __mintSy(
        address receiver,
        address SY,
        uint256 netTokenMintSy,
        uint256 minSyOut,
        TokenInput calldata inp
    ) private returns (uint256 netSyOut) {
        uint256 netNative = inp.tokenMintSy == NATIVE ? netTokenMintSy : 0;
        _safeApproveInf(inp.tokenMintSy, SY);
        netSyOut = IStandardizedYield(SY).deposit{value: netNative}(
            receiver,
            inp.tokenMintSy,
            netTokenMintSy,
            minSyOut
        );
    }

    function _redeemSyToToken(
        address receiver,
        address SY,
        uint256 netSyIn,
        TokenOutput calldata out,
        bool doPull
    ) internal returns (uint256 netTokenOut) {
        SwapType swapType = out.swapData.swapType;

        if (swapType == SwapType.NONE) {
            netTokenOut = __redeemSy(receiver, SY, netSyIn, out, doPull);
        } else if (swapType == SwapType.ETH_WETH) {
            netTokenOut = __redeemSy(address(this), SY, netSyIn, out, doPull); // ETH:WETH is 1:1

            _wrap_unwrap_ETH(out.tokenRedeemSy, out.tokenOut, netTokenOut);

            _transferOut(out.tokenOut, receiver, netTokenOut);
        } else {
            uint256 netTokenRedeemed = __redeemSy(out.pendleSwap, SY, netSyIn, out, doPull);

            IPSwapAggregator(out.pendleSwap).swap(out.tokenRedeemSy, netTokenRedeemed, out.swapData);

            netTokenOut = _selfBalance(out.tokenOut);

            _transferOut(out.tokenOut, receiver, netTokenOut);
        }

        if (netTokenOut < out.minTokenOut) {
            revert Errors.RouterInsufficientTokenOut(netTokenOut, out.minTokenOut);
        }
    }

    function __redeemSy(
        address receiver,
        address SY,
        uint256 netSyIn,
        TokenOutput calldata out,
        bool doPull
    ) private returns (uint256 netTokenRedeemed) {
        if (doPull) {
            _transferFrom(IERC20(SY), msg.sender, SY, netSyIn);
        }

        netTokenRedeemed = IStandardizedYield(SY).redeem(receiver, netSyIn, out.tokenRedeemSy, 0, true);
    }

    function _mintPyFromSy(
        address receiver,
        address SY,
        address YT,
        uint256 netSyIn,
        uint256 minPyOut,
        bool doPull
    ) internal returns (uint256 netPyOut) {
        if (doPull) {
            _transferFrom(IERC20(SY), msg.sender, YT, netSyIn);
        }

        netPyOut = IPYieldToken(YT).mintPY(receiver, receiver);
        if (netPyOut < minPyOut) revert Errors.RouterInsufficientPYOut(netPyOut, minPyOut);
    }

    function _redeemPyToSy(
        address receiver,
        address YT,
        uint256 netPyIn,
        uint256 minSyOut
    ) internal returns (uint256 netSyOut) {
        address PT = IPYieldToken(YT).PT();

        _transferFrom(IERC20(PT), msg.sender, YT, netPyIn);

        bool needToBurnYt = (!IPYieldToken(YT).isExpired());
        if (needToBurnYt) _transferFrom(IERC20(YT), msg.sender, YT, netPyIn);

        netSyOut = IPYieldToken(YT).redeemPY(receiver);
        if (netSyOut < minSyOut) revert Errors.RouterInsufficientSyOut(netSyOut, minSyOut);
    }

    // ----------------- HELPER -----------------

    function _readMarket(address market) internal view returns (MarketState memory) {
        return IPMarket(market).readState(address(this));
    }

    // ----------------- PT SWAP -----------------

    function _entry_swapExactPtForSy(address market, LimitOrderData calldata limit) internal view returns (address) {
        return !_isEmptyLimit(limit) ? address(this) : market;
    }

    function _swapExactPtForSy(
        address receiver,
        address market,
        uint256 exactPtIn,
        uint256 minSyOut,
        LimitOrderData calldata limit
    ) internal returns (uint256 netSyOut, uint256 netSyFee) {
        (, IPPrincipalToken PT, ) = IPMarket(market).readTokens();

        uint256 netPtLeft = exactPtIn;
        bool doMarketOrder = true;

        if (!_isEmptyLimit(limit)) {
            (netPtLeft, netSyOut, netSyFee, doMarketOrder) = _fillLimit(receiver, PT, netPtLeft, limit);
            if (doMarketOrder) {
                _transferOut(address(PT), market, netPtLeft);
            }
        }

        if (doMarketOrder) {
            (uint256 netSyOutMarket, uint256 netSyFeeMarket) = IPMarket(market).swapExactPtForSy(
                receiver,
                netPtLeft,
                EMPTY_BYTES
            );

            netSyOut += netSyOutMarket;
            netSyFee += netSyFeeMarket;
        }

        if (netSyOut < minSyOut) revert Errors.RouterInsufficientSyOut(netSyOut, minSyOut);
    }

    function _entry_swapExactSyForPt(address market, LimitOrderData calldata limit) internal view returns (address) {
        return !_isEmptyLimit(limit) ? address(this) : market;
    }

    function _swapExactSyForPt(
        address receiver,
        address market,
        uint256 exactSyIn,
        uint256 minPtOut,
        ApproxParams calldata guessPtOut,
        LimitOrderData calldata limit
    ) internal returns (uint256 netPtOut, uint256 netSyFee) {
        (IStandardizedYield SY, , IPYieldToken YT) = IPMarket(market).readTokens();
        uint256 netSyLeft = exactSyIn;
        bool doMarketOrder = true;

        if (!_isEmptyLimit(limit)) {
            (netSyLeft, netPtOut, netSyFee, doMarketOrder) = _fillLimit(receiver, SY, netSyLeft, limit);
            if (doMarketOrder) {
                _transferOut(address(SY), market, netSyLeft);
            }
        }

        if (doMarketOrder) {
            (uint256 netPtOutMarket, ) = _readMarket(market).approxSwapExactSyForPt(
                YT.newIndex(),
                netSyLeft,
                block.timestamp,
                guessPtOut
            );

            (, uint256 netSyFeeMarket) = IPMarket(market).swapSyForExactPt(receiver, netPtOutMarket, EMPTY_BYTES);

            netPtOut += netPtOutMarket;
            netSyFee += netSyFeeMarket;
        }

        if (netPtOut < minPtOut) revert Errors.RouterInsufficientPtOut(netPtOut, minPtOut);
    }

    // ----------------- LIMIT ORDERS -----------------
    function _fillLimit(
        address receiver,
        IERC20 tokenIn,
        uint256 netInput,
        LimitOrderData calldata lim
    ) internal returns (uint256 netLeft, uint256 netOut, uint256 netSyFee, bool doMarketOrder) {
        IPLimitRouter router = IPLimitRouter(lim.limitRouter);
        netLeft = netInput;

        if (lim.normalFills.length != 0) {
            _safeApproveInf(address(tokenIn), lim.limitRouter);
            (uint256 actualMaking, uint256 actualTaking, uint256 totalFee, ) = router.fill(
                lim.normalFills,
                receiver,
                netLeft,
                lim.optData,
                EMPTY_BYTES
            );
            netOut += actualMaking;
            netLeft -= actualTaking;
            netSyFee += totalFee;
        }

        if (lim.flashFills.length != 0) {
            address YT = lim.flashFills[0].order.YT;
            OrderType orderType = lim.flashFills[0].order.orderType;

            (, , uint256 totalFee, bytes memory ret) = router.fill(
                lim.flashFills,
                YT,
                type(uint256).max,
                lim.optData,
                abi.encode(orderType, YT, netLeft, receiver)
            );
            (uint256 netUse, uint256 netReceived) = abi.decode(ret, (uint256, uint256));

            netOut += netReceived;
            netLeft -= netUse;
            netSyFee += totalFee;
        }

        doMarketOrder = netLeft > netInput.mulDown(lim.epsSkipMarket);
    }

    function _isEmptyLimit(LimitOrderData calldata a) internal pure returns (bool) {
        return a.normalFills.length == 0 && a.flashFills.length == 0;
    }
}
