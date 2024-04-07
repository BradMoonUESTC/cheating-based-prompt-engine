// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./base/ActionBase.sol";
import "./base/CallbackHelper.sol";
import "../interfaces/IPActionSwapYTV3.sol";

contract ActionSwapYTV3 is CallbackHelper, IPActionSwapYTV3, ActionBase {
    using PMath for uint256;
    using MarketApproxPtInLib for MarketState;
    using MarketApproxPtOutLib for MarketState;
    using PYIndexLib for IPYieldToken;

    // ------------------ SWAP TOKEN FOR YT ------------------

    function swapExactTokenForYt(
        address receiver,
        address market,
        uint256 minYtOut,
        ApproxParams calldata guessYtOut,
        TokenInput calldata input,
        LimitOrderData calldata limit
    ) external payable returns (uint256 netYtOut, uint256 netSyFee, uint256 netSyInterm) {
        (IStandardizedYield SY, , IPYieldToken YT) = IPMarket(market).readTokens();

        netSyInterm = _mintSyFromToken(_entry_swapExactSyForYt(YT, limit), address(SY), 1, input);
        (netYtOut, netSyFee) = _swapExactSyForYt(receiver, market, SY, YT, netSyInterm, minYtOut, guessYtOut, limit);

        emit SwapYtAndToken(
            msg.sender,
            market,
            input.tokenIn,
            receiver,
            netYtOut.Int(),
            input.netTokenIn.neg(),
            netSyInterm
        );
    }

    function swapExactSyForYt(
        address receiver,
        address market,
        uint256 exactSyIn,
        uint256 minYtOut,
        ApproxParams calldata guessYtOut,
        LimitOrderData calldata limit
    ) external returns (uint256 netYtOut, uint256 netSyFee) {
        (IStandardizedYield SY, , IPYieldToken YT) = IPMarket(market).readTokens();
        _transferFrom(SY, msg.sender, _entry_swapExactSyForYt(YT, limit), exactSyIn);

        (netYtOut, netSyFee) = _swapExactSyForYt(receiver, market, SY, YT, exactSyIn, minYtOut, guessYtOut, limit);
        emit SwapYtAndSy(msg.sender, market, receiver, netYtOut.Int(), exactSyIn.neg());
    }

    function _entry_swapExactSyForYt(IPYieldToken YT, LimitOrderData calldata limit) internal view returns (address) {
        return !_isEmptyLimit(limit) ? address(this) : address(YT);
    }

    function _swapExactSyForYt(
        address receiver,
        address market,
        IStandardizedYield SY,
        IPYieldToken YT,
        uint256 exactSyIn,
        uint256 minYtOut,
        ApproxParams calldata guessYtOut,
        LimitOrderData calldata limit
    ) internal returns (uint256 netYtOut, uint256 netSyFee) {
        uint256 netSyLeft = exactSyIn;
        bool doMarketOrder = true;

        if (!_isEmptyLimit(limit)) {
            (netSyLeft, netYtOut, netSyFee, doMarketOrder) = _fillLimit(receiver, SY, netSyLeft, limit);
            if (doMarketOrder) {
                _transferOut(address(SY), address(YT), netSyLeft);
            }
        }

        if (doMarketOrder) {
            (uint256 netYtOutMarket, ) = _readMarket(market).approxSwapExactSyForYt(
                YT.newIndex(),
                netSyLeft,
                block.timestamp,
                guessYtOut
            );

            (, uint256 netSyFeeMarket) = IPMarket(market).swapExactPtForSy(
                address(YT),
                netYtOutMarket, // exactPtIn = netYtOut
                _encodeSwapExactSyForYt(receiver, YT)
            );

            netYtOut += netYtOutMarket;
            netSyFee += netSyFeeMarket;
        }

        if (netYtOut < minYtOut) revert Errors.RouterInsufficientYtOut(netYtOut, minYtOut);
    }

    // ------------------ SWAP TOKEN FOR TOKEN ------------------

    function swapExactYtForToken(
        address receiver,
        address market,
        uint256 exactYtIn,
        TokenOutput calldata output,
        LimitOrderData calldata limit
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm) {
        (IStandardizedYield SY, , IPYieldToken YT) = IPMarket(market).readTokens();
        _transferFrom(YT, msg.sender, _entry_swapExactYtForSy(YT, limit), exactYtIn);

        (netSyInterm, netSyFee) = _swapExactYtForSy(address(SY), market, SY, YT, exactYtIn, 0, limit);

        netTokenOut = _redeemSyToToken(receiver, address(SY), netSyInterm, output, false);

        emit SwapYtAndToken(
            msg.sender,
            market,
            output.tokenOut,
            receiver,
            exactYtIn.neg(),
            netTokenOut.Int(),
            netSyInterm
        );
    }

    function swapExactYtForSy(
        address receiver,
        address market,
        uint256 exactYtIn,
        uint256 minSyOut,
        LimitOrderData calldata limit
    ) external returns (uint256 netSyOut, uint256 netSyFee) {
        (IStandardizedYield SY, , IPYieldToken YT) = IPMarket(market).readTokens();
        _transferFrom(YT, msg.sender, _entry_swapExactYtForSy(YT, limit), exactYtIn);

        (netSyOut, netSyFee) = _swapExactYtForSy(receiver, market, SY, YT, exactYtIn, minSyOut, limit);
        emit SwapYtAndSy(msg.sender, market, receiver, exactYtIn.neg(), netSyOut.Int());
    }

    function _entry_swapExactYtForSy(IPYieldToken YT, LimitOrderData calldata limit) internal view returns (address) {
        return !_isEmptyLimit(limit) ? address(this) : address(YT);
    }

    function _swapExactYtForSy(
        address receiver,
        address market,
        IStandardizedYield SY,
        IPYieldToken YT,
        uint256 exactYtIn,
        uint256 minSyOut,
        LimitOrderData calldata limit
    ) internal returns (uint256 netSyOut, uint256 netSyFee) {
        uint256 netYtLeft = exactYtIn;
        bool doMarketOrder = true;

        if (!_isEmptyLimit(limit)) {
            (netYtLeft, netSyOut, netSyFee, doMarketOrder) = _fillLimit(receiver, YT, netYtLeft, limit);
            if (doMarketOrder) {
                _transferOut(address(YT), address(YT), netYtLeft);
            }
        }

        if (doMarketOrder) {
            uint256 preSyBalance = SY.balanceOf(receiver);

            (, uint256 netSyFeeMarket) = IPMarket(market).swapSyForExactPt(
                address(YT),
                netYtLeft, // exactPtOut = netYtLeft
                _encodeSwapYtForSy(receiver, YT)
            );

            // avoid stack issue
            netSyFee += netSyFeeMarket;
            netSyOut += SY.balanceOf(receiver) - preSyBalance;
        }

        if (netSyOut < minSyOut) revert Errors.RouterInsufficientSyOut(netSyOut, minSyOut);
    }

    // ------------------ SWAP PT FOR YT ------------------

    function swapExactPtForYt(
        address receiver,
        address market,
        uint256 exactPtIn,
        uint256 minYtOut,
        ApproxParams calldata guessTotalPtToSwap
    ) external returns (uint256 netYtOut, uint256 netSyFee) {
        (, IPPrincipalToken PT, IPYieldToken YT) = IPMarket(market).readTokens();

        uint256 totalPtToSwap;
        (netYtOut, totalPtToSwap, netSyFee) = _readMarket(market).approxSwapExactPtForYt(
            YT.newIndex(),
            exactPtIn,
            block.timestamp,
            guessTotalPtToSwap
        );

        _transferFrom(IERC20(PT), msg.sender, market, exactPtIn);

        IPMarket(market).swapExactPtForSy(
            address(YT),
            totalPtToSwap,
            _encodeSwapExactPtForYt(receiver, exactPtIn, minYtOut, YT)
        );

        emit SwapPtAndYt(msg.sender, market, receiver, exactPtIn.neg(), netYtOut.Int());
    }

    // ------------------ SWAP YT FOR PT ------------------
    function swapExactYtForPt(
        address receiver,
        address market,
        uint256 exactYtIn,
        uint256 minPtOut,
        ApproxParams calldata guessTotalPtFromSwap
    ) external returns (uint256 netPtOut, uint256 netSyFee) {
        (, IPPrincipalToken PT, IPYieldToken YT) = IPMarket(market).readTokens();

        uint256 totalPtFromSwap;
        (netPtOut, totalPtFromSwap, netSyFee) = _readMarket(market).approxSwapExactYtForPt(
            YT.newIndex(),
            exactYtIn,
            block.timestamp,
            guessTotalPtFromSwap
        );

        if (netPtOut < minPtOut) revert Errors.RouterInsufficientPtOut(netPtOut, minPtOut);

        _transferFrom(IERC20(YT), msg.sender, address(YT), exactYtIn);
        IPMarket(market).swapSyForExactPt(
            address(this),
            totalPtFromSwap,
            _encodeSwapExactYtForPt(receiver, netPtOut, PT, YT)
        );

        emit SwapPtAndYt(msg.sender, market, receiver, netPtOut.Int(), exactYtIn.neg());
    }
}
