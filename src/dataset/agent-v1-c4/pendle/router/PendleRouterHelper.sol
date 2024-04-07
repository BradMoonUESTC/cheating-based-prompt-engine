// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../interfaces/IPMarket.sol";
import "../interfaces/IPRouterHelper.sol";
import "./base/MarketApproxLib.sol";
import "../interfaces/IAddressProvider.sol";
import "../core/libraries/TokenHelper.sol";

contract PendleRouterHelper is TokenHelper, IPRouterHelper {
    RouterV2InterfaceForRouterHelper public immutable ROUTER;
    address public immutable WETH;

    constructor(address _ROUTER, IAddressProvider provider) {
        ROUTER = RouterV2InterfaceForRouterHelper(_ROUTER);
        WETH = _getWETHAddress(provider, 1);
        _safeApproveInf(WETH, address(ROUTER));
    }

    function _getWETHAddress(IAddressProvider provider, uint256 providerId) internal view returns (address) {
        return provider.get(providerId);
    }

    receive() external payable {}

    /**
     * @dev all the parameters for this function should be generated in the same way as they are
     *  generated for the main Router, except that input.tokenIn & swapData should be generated
     *  for tokenIn == WETH instead of ETH
     */
    function addLiquiditySingleTokenKeepYtWithEth(
        address receiver,
        address market,
        uint256 minLpOut,
        uint256 minYtOut,
        TokenInput calldata input
    ) external payable returns (uint256 netLpOut, uint256 netYtOut) {
        require(input.tokenIn == WETH);

        _transferIn(NATIVE, msg.sender, input.netTokenIn);

        _wrap_unwrap_ETH(NATIVE, WETH, input.netTokenIn);
        (netLpOut, netYtOut) = ROUTER.addLiquiditySingleTokenKeepYt(receiver, market, minLpOut, minYtOut, input);

        emit AddLiquiditySingleTokenKeepYt(
            msg.sender,
            market,
            NATIVE,
            msg.sender,
            input.netTokenIn,
            netLpOut,
            netYtOut
        );
    }

    function transferLiquidityDifferentSyNormal(
        RemoveLiquiditySingleTokenStruct calldata fromMarket,
        AddLiquiditySingleTokenStruct calldata toMarket
    ) external returns (uint256 netLpOut, uint256 netTokenZapIn, uint256 netSyFeeOfRemove, uint256 netSyFeeOfAdd) {
        (netTokenZapIn, netSyFeeOfRemove) = removeLiquiditySingleToken(fromMarket);
        (netLpOut, netSyFeeOfAdd) = _addLiquiditySingleToken(toMarket, fromMarket.output.tokenOut, netTokenZapIn);
    }

    function transferLiquidityDifferentSyKeepYt(
        RemoveLiquiditySingleTokenStruct calldata fromMarket,
        AddLiquiditySingleTokenKeepYtStruct calldata toMarket
    ) external returns (uint256 netLpOut, uint256 netYtOut, uint256 netTokenZapIn, uint256 netSyFeeOfRemove) {
        (netTokenZapIn, netSyFeeOfRemove) = removeLiquiditySingleToken(fromMarket);
        (netLpOut, netYtOut) = _addLiquiditySingleTokenKeepYt(toMarket, fromMarket.output.tokenOut, netTokenZapIn);
    }

    function transferLiquiditySameSyNormal(
        RemoveLiquiditySingleSyStruct calldata fromMarket,
        AddLiquiditySingleSyStruct calldata toMarket
    ) external returns (uint256 netLpOut, uint256 netSyZapIn, uint256 netSyFeeOfRemove, uint256 netSyFeeOfAdd) {
        (netSyZapIn, netSyFeeOfRemove) = removeLiquiditySingleSy(fromMarket);
        (netLpOut, netSyFeeOfAdd) = _addLiquiditySingleSy(toMarket, netSyZapIn);
    }

    function transferLiquiditySameSyKeepYt(
        RemoveLiquiditySingleSyStruct calldata fromMarket,
        AddLiquiditySingleSyKeepYtStruct calldata toMarket
    ) external returns (uint256 netLpOut, uint256 netYtOut, uint256 netSyZapIn, uint256 netSyFeeOfRemove) {
        (netSyZapIn, netSyFeeOfRemove) = removeLiquiditySingleSy(fromMarket);
        (netLpOut, netYtOut) = _addLiquiditySingleSyKeepYt(toMarket, netSyZapIn);
    }

    function removeLiquiditySingleToken(
        RemoveLiquiditySingleTokenStruct calldata fromMarket
    ) public returns (uint256 netTokenOut, uint256 netSyFee) {
        _transferFrom(IERC20(fromMarket.market), msg.sender, address(this), fromMarket.netLpToRemove);

        _safeApproveInf(fromMarket.market, address(ROUTER));

        (netTokenOut, netSyFee) = ROUTER.removeLiquiditySingleToken(
            address(this),
            fromMarket.market,
            fromMarket.netLpToRemove,
            fromMarket.output
        );

        if (fromMarket.doRedeemRewards) {
            IPMarket(fromMarket.market).redeemRewards(msg.sender);
        }

        emit RemoveLiquiditySingleToken(
            msg.sender,
            fromMarket.market,
            fromMarket.output.tokenOut,
            msg.sender,
            fromMarket.netLpToRemove,
            netTokenOut
        );
    }

    function removeLiquiditySingleSy(
        RemoveLiquiditySingleSyStruct calldata fromMarket
    ) public returns (uint256 netSyOut, uint256 netSyFee) {
        _transferFrom(IERC20(fromMarket.market), msg.sender, address(this), fromMarket.netLpToRemove);

        _safeApproveInf(fromMarket.market, address(ROUTER));

        (netSyOut, netSyFee) = ROUTER.removeLiquiditySingleSy(
            address(this),
            fromMarket.market,
            fromMarket.netLpToRemove,
            0
        );

        if (fromMarket.doRedeemRewards) {
            IPMarket(fromMarket.market).redeemRewards(msg.sender);
        }

        emit RemoveLiquiditySingleSy(msg.sender, fromMarket.market, msg.sender, fromMarket.netLpToRemove, netSyOut);
    }

    function _addLiquiditySingleToken(
        AddLiquiditySingleTokenStruct calldata toMarket,
        address tokenToZapIn,
        uint256 actualNetTokenIn
    ) internal returns (uint256 netLpOut, uint256 netSyFee) {
        uint256 netNativeToAttach;
        if (tokenToZapIn == NATIVE) {
            netNativeToAttach = actualNetTokenIn;
        }

        _safeApproveInf(tokenToZapIn, address(ROUTER));

        (netLpOut, netSyFee) = ROUTER.addLiquiditySingleToken{value: netNativeToAttach}(
            msg.sender,
            toMarket.market,
            toMarket.minLpOut,
            _scaleApproxParams(toMarket.guessPtReceivedFromSy, toMarket.guessNetTokenIn, actualNetTokenIn),
            _newTokenInputStruct(tokenToZapIn, actualNetTokenIn)
        );

        emit AddLiquiditySingleToken(msg.sender, toMarket.market, tokenToZapIn, msg.sender, actualNetTokenIn, netLpOut);
    }

    function _addLiquiditySingleSy(
        AddLiquiditySingleSyStruct calldata toMarket,
        uint256 actualNetSyIn
    ) internal returns (uint256 netLpOut, uint256 netSyFee) {
        (IStandardizedYield SY, , ) = IPMarket(toMarket.market).readTokens();

        _safeApproveInf(address(SY), address(ROUTER));

        (netLpOut, netSyFee) = ROUTER.addLiquiditySingleSy(
            msg.sender,
            toMarket.market,
            actualNetSyIn,
            toMarket.minLpOut,
            _scaleApproxParams(toMarket.guessPtReceivedFromSy, toMarket.guessNetSyIn, actualNetSyIn)
        );

        emit AddLiquiditySingleSy(msg.sender, toMarket.market, msg.sender, actualNetSyIn, netLpOut);
    }

    function _addLiquiditySingleTokenKeepYt(
        AddLiquiditySingleTokenKeepYtStruct calldata toMarket,
        address tokenToZapIn,
        uint256 actualNetTokenIn
    ) internal returns (uint256 netLpOut, uint256 netYtOut) {
        if (tokenToZapIn == NATIVE) {
            tokenToZapIn = WETH;
            _wrap_unwrap_ETH(NATIVE, WETH, actualNetTokenIn);
        }

        _safeApproveInf(tokenToZapIn, address(ROUTER));

        (netLpOut, netYtOut) = ROUTER.addLiquiditySingleTokenKeepYt(
            msg.sender,
            toMarket.market,
            toMarket.minLpOut,
            toMarket.minYtOut,
            _newTokenInputStruct(tokenToZapIn, actualNetTokenIn)
        );

        emit AddLiquiditySingleTokenKeepYt(
            msg.sender,
            toMarket.market,
            tokenToZapIn,
            msg.sender,
            actualNetTokenIn,
            netLpOut,
            netYtOut
        );
    }

    function _addLiquiditySingleSyKeepYt(
        AddLiquiditySingleSyKeepYtStruct calldata toMarket,
        uint256 actualNetSyIn
    ) internal returns (uint256 netLpOut, uint256 netYtOut) {
        (IStandardizedYield SY, , ) = IPMarket(toMarket.market).readTokens();

        _safeApproveInf(address(SY), address(ROUTER));

        (netLpOut, netYtOut) = ROUTER.addLiquiditySingleSyKeepYt(
            msg.sender,
            toMarket.market,
            actualNetSyIn,
            toMarket.minLpOut,
            toMarket.minYtOut
        );

        emit AddLiquiditySingleSyKeepYt(msg.sender, toMarket.market, msg.sender, actualNetSyIn, netLpOut, netYtOut);
    }

    // ============ struct helpers ============

    function _newTokenInputStruct(address tokenIn, uint256 netTokenIn) internal pure returns (TokenInput memory res) {
        res.tokenIn = res.tokenMintSy = tokenIn;
        res.netTokenIn = netTokenIn;
        return res;
    }

    /// @dev either SY or Token here is good since token->sy conversion is almost linearly proportional
    function _scaleApproxParams(
        ApproxParams calldata params,
        uint256 guessNetTokenIn,
        uint256 actualNetTokenIn
    ) internal pure returns (ApproxParams memory) {
        if (params.guessOffchain == 0) {
            require(params.guessMin == 0 && params.guessMax == type(uint256).max, "invalid guess");
            return params;
        }

        return
            ApproxParams({
                guessMin: (params.guessMin * actualNetTokenIn) / guessNetTokenIn,
                guessMax: (params.guessMax * actualNetTokenIn) / guessNetTokenIn,
                guessOffchain: (params.guessOffchain * actualNetTokenIn) / guessNetTokenIn,
                maxIteration: params.maxIteration,
                eps: params.eps
            });
    }
}

interface RouterV2InterfaceForRouterHelper {
    function addLiquiditySingleSy(
        address receiver,
        address market,
        uint256 netSyIn,
        uint256 minLpOut,
        ApproxParams calldata guessPtReceivedFromSy
    ) external returns (uint256 netLpOut, uint256 netSyFee);

    function addLiquiditySingleToken(
        address receiver,
        address market,
        uint256 minLpOut,
        ApproxParams calldata guessPtReceivedFromSy,
        TokenInput calldata input
    ) external payable returns (uint256 netLpOut, uint256 netSyFee);

    function addLiquiditySingleSyKeepYt(
        address receiver,
        address market,
        uint256 netSyIn,
        uint256 minLpOut,
        uint256 minYtOut
    ) external returns (uint256 netLpOut, uint256 netYtOut);

    function addLiquiditySingleTokenKeepYt(
        address receiver,
        address market,
        uint256 minLpOut,
        uint256 minYtOut,
        TokenInput calldata input
    ) external returns (uint256 netLpOut, uint256 netYtOut);

    function removeLiquiditySingleSy(
        address receiver,
        address market,
        uint256 netLpToRemove,
        uint256 minSyOut
    ) external returns (uint256 netSyOut, uint256 netSyFee);

    function removeLiquiditySingleToken(
        address receiver,
        address market,
        uint256 netLpToRemove,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut, uint256 netSyFee);
}
