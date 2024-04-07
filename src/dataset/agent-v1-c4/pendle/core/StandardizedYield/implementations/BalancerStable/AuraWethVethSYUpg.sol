// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./base/PendleAuraBalancerStableLPSYV3Upg.sol";
import "./base/ComposableStable/ComposableStablePreview.sol";

contract AuraWethVethSYUpg is PendleAuraBalancerStableLPSYV3Upg {
    address internal constant VETH = 0x4Bc3263Eb5bb2Ef7Ad9aB6FB68be80E43b43801F;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal constant AURA_PID = 147;
    address internal constant LP = 0xB54E6AADBF1ac1a3EF2A56E358706F0f8E320a03;

    address internal constant COMPOSABLE_PREVIEW = 0x4239Ddd3c50463383670E86c119220849BFaF64a;

    bool internal constant NO_TOKENS_EXEMPT = true;
    bool internal constant ALL_TOKENS_EXEMPT = false;

    constructor()
        PendleAuraBalancerStableLPSYV3Upg(LP, AURA_PID, ComposableStablePreview(COMPOSABLE_PREVIEW))
        initializer
    //solhint-disable-next-line
    {

    }

    function initialize(string memory _name, string memory _symbol) external initializer {
        __PendleAuraBalancerStableLPSYV3Upg_init(_name, _symbol);
    }

    function _deposit(address tokenIn, uint256 amount) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            IWETH(WETH).deposit{value: amount}();
            amountSharesOut = super._deposit(WETH, amount);
        } else {
            amountSharesOut = super._deposit(tokenIn, amount);
        }
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256) {
        if (tokenOut == NATIVE) {
            uint256 amountTokenOut = super._redeem(address(this), WETH, amountSharesToRedeem);
            IWETH(WETH).withdraw(amountTokenOut);
            _transferOut(NATIVE, receiver, amountTokenOut);
            return amountTokenOut;
        } else {
            return super._redeem(receiver, tokenOut, amountSharesToRedeem);
        }
    }

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            amountSharesOut = super._previewDeposit(WETH, amountTokenToDeposit);
        } else {
            amountSharesOut = super._previewDeposit(tokenIn, amountTokenToDeposit);
        }
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view virtual override returns (uint256 amountTokenOut) {
        if (tokenOut == NATIVE) {
            amountTokenOut = super._previewRedeem(WETH, amountSharesToRedeem);
        } else {
            amountTokenOut = super._previewRedeem(tokenOut, amountSharesToRedeem);
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
        res[0] = VETH;
        res[1] = LP;
        res[2] = WETH;
    }

    function _getBPTIndex() internal pure override returns (uint256) {
        return 1;
    }

    function _getRateProviders() internal pure returns (address[] memory res) {
        res = new address[](3);
        res[0] = 0x12589A727aeFAc3fbE5025F890f1CB97c269BEc2;
        res[1] = 0x0000000000000000000000000000000000000000;
        res[2] = 0x0000000000000000000000000000000000000000;
    }

    function _getRawScalingFactors() internal pure returns (uint256[] memory res) {
        res = new uint256[](3);
        res[0] = res[1] = res[2] = 1e18;
    }

    function _getExemption() internal pure returns (bool[] memory res) {
        res = new bool[](3);
        res[0] = res[1] = res[2] = false;
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](4);
        res[0] = LP;
        res[1] = WETH;
        res[2] = VETH;
        res[3] = NATIVE;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        return getTokensIn();
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return (token == LP || token == WETH || token == VETH || token == NATIVE);
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return isValidTokenIn(token);
    }
}
