// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./base/ActionBase.sol";
import "../interfaces/IPActionSwapPTV3.sol";

contract ActionSwapPTV3 is IPActionSwapPTV3, ActionBase {
    using PMath for uint256;

    // ------------------ SWAP TOKEN FOR PT ------------------
    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256 minPtOut,
        ApproxParams calldata guessPtOut,
        TokenInput calldata input,
        LimitOrderData calldata limit
    ) external payable returns (uint256 netPtOut, uint256 netSyFee, uint256 netSyInterm) {
        (IStandardizedYield SY, , ) = IPMarket(market).readTokens();
        netSyInterm = _mintSyFromToken(_entry_swapExactSyForPt(market, limit), address(SY), 1, input);

        (netPtOut, netSyFee) = _swapExactSyForPt(receiver, market, netSyInterm, minPtOut, guessPtOut, limit);
        emit SwapPtAndToken(
            msg.sender,
            market,
            input.tokenIn,
            receiver,
            netPtOut.Int(),
            input.netTokenIn.neg(),
            netSyInterm
        );
    }

    function swapExactSyForPt(
        address receiver,
        address market,
        uint256 exactSyIn,
        uint256 minPtOut,
        ApproxParams calldata guessPtOut,
        LimitOrderData calldata limit
    ) external returns (uint256 netPtOut, uint256 netSyFee) {
        (IStandardizedYield SY, , ) = IPMarket(market).readTokens();
        _transferFrom(SY, msg.sender, _entry_swapExactSyForPt(market, limit), exactSyIn);

        (netPtOut, netSyFee) = _swapExactSyForPt(receiver, market, exactSyIn, minPtOut, guessPtOut, limit);
        emit SwapPtAndSy(msg.sender, market, receiver, netPtOut.Int(), exactSyIn.neg());
    }

    function swapExactPtForToken(
        address receiver,
        address market,
        uint256 exactPtIn,
        TokenOutput calldata output,
        LimitOrderData calldata limit
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm) {
        (IStandardizedYield SY, IPPrincipalToken PT, ) = IPMarket(market).readTokens();
        _transferFrom(PT, msg.sender, _entry_swapExactPtForSy(market, limit), exactPtIn);

        (netSyInterm, netSyFee) = _swapExactPtForSy(address(SY), market, exactPtIn, 0, limit);

        netTokenOut = _redeemSyToToken(receiver, address(SY), netSyInterm, output, false);

        emit SwapPtAndToken(
            msg.sender,
            market,
            output.tokenOut,
            receiver,
            exactPtIn.neg(),
            netTokenOut.Int(),
            netSyInterm
        );
    }

    function swapExactPtForSy(
        address receiver,
        address market,
        uint256 exactPtIn,
        uint256 minSyOut,
        LimitOrderData calldata limit
    ) external returns (uint256 netSyOut, uint256 netSyFee) {
        (, IPPrincipalToken PT, ) = IPMarket(market).readTokens();
        _transferFrom(PT, msg.sender, _entry_swapExactPtForSy(market, limit), exactPtIn);

        (netSyOut, netSyFee) = _swapExactPtForSy(receiver, market, exactPtIn, minSyOut, limit);
        emit SwapPtAndSy(msg.sender, market, receiver, exactPtIn.neg(), netSyOut.Int());
    }
}
