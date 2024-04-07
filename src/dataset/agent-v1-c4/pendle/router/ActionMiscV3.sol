// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./base/ActionBase.sol";
import "../interfaces/IPActionMiscV3.sol";

contract ActionMiscV3 is IPActionMiscV3, ActionBase {
    function mintSyFromToken(
        address receiver,
        address SY,
        uint256 minSyOut,
        TokenInput calldata input
    ) external payable returns (uint256 netSyOut) {
        netSyOut = _mintSyFromToken(receiver, SY, minSyOut, input);
        emit MintSyFromToken(msg.sender, input.tokenIn, SY, receiver, input.netTokenIn, netSyOut);
    }

    function redeemSyToToken(
        address receiver,
        address SY,
        uint256 netSyIn,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut) {
        netTokenOut = _redeemSyToToken(receiver, SY, netSyIn, output, true);
        emit RedeemSyToToken(msg.sender, output.tokenOut, SY, receiver, netSyIn, netTokenOut);
    }

    function mintPyFromToken(
        address receiver,
        address YT,
        uint256 minPyOut,
        TokenInput calldata input
    ) external payable returns (uint256 netPyOut, uint256 netSyInterm) {
        address SY = IPYieldToken(YT).SY();

        netSyInterm = _mintSyFromToken(YT, SY, 0, input);
        netPyOut = _mintPyFromSy(receiver, SY, YT, netSyInterm, minPyOut, false);

        emit MintPyFromToken(msg.sender, input.tokenIn, YT, receiver, input.netTokenIn, netPyOut, netSyInterm);
    }

    function redeemPyToToken(
        address receiver,
        address YT,
        uint256 netPyIn,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut, uint256 netSyInterm) {
        address SY = IPYieldToken(YT).SY();

        netSyInterm = _redeemPyToSy(SY, YT, netPyIn, 1);
        netTokenOut = _redeemSyToToken(receiver, SY, netSyInterm, output, false);

        emit RedeemPyToToken(msg.sender, output.tokenOut, YT, receiver, netPyIn, netTokenOut, netSyInterm);
    }

    function mintPyFromSy(
        address receiver,
        address YT,
        uint256 netSyIn,
        uint256 minPyOut
    ) external returns (uint256 netPyOut) {
        netPyOut = _mintPyFromSy(receiver, IPYieldToken(YT).SY(), YT, netSyIn, minPyOut, true);
        emit MintPyFromSy(msg.sender, receiver, YT, netSyIn, netPyOut);
    }

    function redeemPyToSy(
        address receiver,
        address YT,
        uint256 netPyIn,
        uint256 minSyOut
    ) external returns (uint256 netSyOut) {
        netSyOut = _redeemPyToSy(receiver, YT, netPyIn, minSyOut);
        emit RedeemPyToSy(msg.sender, receiver, YT, netPyIn, netSyOut);
    }

    function redeemDueInterestAndRewards(
        address user,
        address[] calldata sys,
        address[] calldata yts,
        address[] calldata markets
    ) external {
        unchecked {
            for (uint256 i = 0; i < sys.length; ++i) {
                IStandardizedYield(sys[i]).claimRewards(user);
            }

            for (uint256 i = 0; i < yts.length; ++i) {
                IPYieldToken(yts[i]).redeemDueInterestAndRewards(user, true, true);
            }

            for (uint256 i = 0; i < markets.length; ++i) {
                IPMarket(markets[i]).redeemRewards(user);
            }
        }
    }

    function swapTokenToToken(
        address receiver,
        uint256 minTokenOut,
        TokenInput calldata inp
    ) external payable returns (uint256 netTokenOut) {
        _swapTokenInput(inp);

        netTokenOut = _selfBalance(inp.tokenMintSy);
        if (netTokenOut < minTokenOut) {
            revert Errors.RouterInsufficientTokenOut(netTokenOut, minTokenOut);
        }

        _transferOut(inp.tokenMintSy, receiver, netTokenOut);
    }

    function swapTokenToTokenViaSy(
        address receiver,
        address SY,
        TokenInput calldata input,
        address tokenRedeemSy,
        uint256 minTokenOut
    ) external payable returns (uint256 netTokenOut, uint256 netSyInterm) {
        netSyInterm = _mintSyFromToken(SY, SY, 0, input);
        netTokenOut = IStandardizedYield(SY).redeem(receiver, netSyInterm, tokenRedeemSy, minTokenOut, true);
    }

    // ----------------- MISC FUNCTIONS -----------------

    function boostMarkets(address[] memory markets) external {
        for (uint256 i = 0; i < markets.length; ) {
            IPMarket(markets[i]).transferFrom(msg.sender, markets[i], 0);
            unchecked {
                i++;
            }
        }
    }

    function multicall(Call3[] calldata calls) external payable returns (Result[] memory res) {
        uint256 length = calls.length;
        res = new Result[](length);
        Call3 calldata call;
        for (uint256 i = 0; i < length; ) {
            call = calls[i];

            // delegatecall to itself, it turns allowing invoking functions from other actions
            (bool success, bytes memory result) = address(this).delegatecall(call.callData);

            if (!success && !call.allowFailure) {
                assembly {
                    // We use Yul's revert() to bubble up errors from the target contract.
                    revert(add(32, result), mload(result))
                }
            }

            res[i].success = success;
            res[i].returnData = result;

            unchecked {
                ++i;
            }
        }
    }

    function simulate(address target, bytes calldata data) external payable {
        (bool success, bytes memory result) = target.delegatecall(data);
        revert Errors.SimulationResults(success, result);
    }
}
