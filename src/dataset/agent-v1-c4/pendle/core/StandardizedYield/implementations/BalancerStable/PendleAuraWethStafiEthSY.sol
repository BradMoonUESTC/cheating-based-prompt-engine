// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./base/PendleAuraBalancerStableLPSYV2.sol";
import "../../../../interfaces/IWETH.sol";
import "./base/MetaStable/MetaStablePreview.sol";

contract PendleAuraWethStafiEthSY is PendleAuraBalancerStableLPSYV2 {
    address internal constant STAFI_ETH = 0x9559Aaa82d9649C7A7b220E7c461d2E74c9a3593;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal constant AURA_PID = 63;
    address internal constant LP = 0xB08885e6026bab4333A80024Ec25a1a3e1FF2b8A;

    constructor(
        string memory _name,
        string memory _symbol,
        MetaStablePreview _previewHelper
    ) PendleAuraBalancerStableLPSYV2(_name, _symbol, LP, AURA_PID, _previewHelper) {}

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

    function _getPoolTokenAddresses() internal view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = STAFI_ETH;
        res[1] = WETH;
    }

    function _getRateProviders() internal view virtual returns (address[] memory res) {
        res = new address[](2);
        res[0] = 0x3D40f9dd83bd404fA4047c15da494E58C3c1f1ac;
        res[1] = 0x0000000000000000000000000000000000000000;
    }

    function _getRawScalingFactors() internal view virtual returns (uint256[] memory res) {
        res = new uint256[](2);
        res[0] = 1e18;
        res[1] = 1e18;
    }

    function _getImmutablePoolData() internal view virtual override returns (bytes memory) {
        MetaStablePreview.ImmutableData memory res;
        res.LP = LP;
        res.poolTokens = _getPoolTokenAddresses();
        res.rateProviders = _getRateProviders();
        res.rawScalingFactors = _getRawScalingFactors();

        return abi.encode(res);
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](4);
        res[0] = LP;
        res[1] = STAFI_ETH;
        res[2] = WETH;
        res[3] = NATIVE;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](4);
        res[0] = LP;
        res[1] = STAFI_ETH;
        res[2] = WETH;
        res[3] = NATIVE;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return (token == LP || token == STAFI_ETH || token == WETH || token == NATIVE);
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return (token == LP || token == STAFI_ETH || token == WETH || token == NATIVE);
    }
}
