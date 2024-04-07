// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./base/PendleAuraBalancerStableLPSYV2.sol";
import "./base/ComposableStable/ComposableStablePreview.sol";
import "../../StEthHelper.sol";

contract PendleAuraWstethAnkreth is PendleAuraBalancerStableLPSYV2, StEthHelper {
    uint256 internal constant AURA_PID = 125;
    address internal constant LP = 0xdfE6e7e18f6Cc65FA13C8D8966013d4FdA74b6ba;
    address internal constant ANKRETH = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;

    bool internal constant NO_TOKENS_EXEMPT = true;
    bool internal constant ALL_TOKENS_EXEMPT = false;

    constructor(
        string memory _name,
        string memory _symbol,
        ComposableStablePreview _composablePreviewHelper
    )
        PendleAuraBalancerStableLPSYV2(_name, _symbol, LP, AURA_PID, _composablePreviewHelper) //solhint-disable-next-line
    {}

    function _deposit(address tokenIn, uint256 amount) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE || tokenIn == STETH) {
            uint256 amountWstETH = _depositWstETH(tokenIn, amount);
            amountSharesOut = super._deposit(WSTETH, amountWstETH);
        } else {
            amountSharesOut = super._deposit(tokenIn, amount);
        }
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256 amountTokenOut) {
        if (tokenOut == STETH) {
            uint256 amountWstETH = super._redeem(address(this), WSTETH, amountSharesToRedeem);
            amountTokenOut = _redeemWstETH(receiver, amountWstETH);
        } else {
            amountTokenOut = super._redeem(receiver, tokenOut, amountSharesToRedeem);
        }
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        if (tokenIn == NATIVE || tokenIn == STETH) {
            uint256 amountWstETH = _previewDepositWstETH(tokenIn, amountTokenToDeposit);
            return super._previewDeposit(WSTETH, amountWstETH);
        } else {
            return super._previewDeposit(tokenIn, amountTokenToDeposit);
        }
    }

    function _previewRedeem(address tokenOut, uint256 amountSharesToRedeem) internal view override returns (uint256) {
        if (tokenOut == STETH) {
            uint256 amountWstETH = super._previewRedeem(WSTETH, amountSharesToRedeem);
            return _previewRedeemWstETH(amountWstETH);
        } else {
            return super._previewRedeem(tokenOut, amountSharesToRedeem);
        }
    }

    function _getImmutablePoolData() internal pure override returns (bytes memory ret) {
        ComposableStablePreview.ImmutableData memory res;
        res.poolTokens = _getPoolTokenAddresses();
        res.rateProviders = _getRateProviders();
        res.rawScalingFactors = _getRawScalingFactors();
        res.isExemptFromYieldProtocolFee = _getExemption();
        res.LP = LP;
        res.noTokensExempt = NO_TOKENS_EXEMPT;
        res.allTokensExempt = ALL_TOKENS_EXEMPT;
        res.bptIndex = _getBPTIndex();
        res.totalTokens = res.poolTokens.length;

        return abi.encode(res);
    }

    //  --------------------------------- POOL CONSTANTS ---------------------------------
    function _getPoolTokenAddresses() internal pure override returns (address[] memory res) {
        res = new address[](3);
        res[0] = WSTETH;
        res[1] = LP;
        res[2] = ANKRETH;
    }

    function _getBPTIndex() internal pure override returns (uint256) {
        return 1;
    }

    function _getRateProviders() internal pure returns (address[] memory res) {
        res = new address[](3);
        res[0] = 0x72D07D7DcA67b8A406aD1Ec34ce969c90bFEE768;
        res[1] = 0x0000000000000000000000000000000000000000;
        res[2] = 0x00F8e64a8651E3479A0B20F46b1D462Fe29D6aBc;
    }

    function _getRawScalingFactors() internal pure returns (uint256[] memory res) {
        res = new uint256[](3);
        res[0] = res[1] = res[2] = 1e18;
    }

    function _getExemption() internal pure returns (bool[] memory res) {
        res = new bool[](3);
        res[0] = res[1] = res[2] = false;
    }

    function getTokensIn() public pure override returns (address[] memory res) {
        res = new address[](5);
        res[0] = NATIVE;
        res[1] = STETH;
        res[2] = WSTETH;
        res[3] = ANKRETH;
        res[4] = LP;
    }

    function getTokensOut() public pure override returns (address[] memory res) {
        res = new address[](4);
        res[0] = STETH;
        res[1] = WSTETH;
        res[2] = ANKRETH;
        res[3] = LP;
    }

    function isValidTokenIn(address token) public pure override returns (bool) {
        return (token == NATIVE || token == STETH || token == WSTETH || token == ANKRETH || token == LP);
    }

    function isValidTokenOut(address token) public pure override returns (bool) {
        return (token == STETH || token == WSTETH || token == ANKRETH || token == LP);
    }
}
