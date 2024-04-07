// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./base/PendleAuraBalancerStableLPSYV2.sol";
import "../../StEthHelper.sol";
import "./base/MetaStable/MetaStablePreview.sol";

contract PendleAuraWethWstethSYV2 is PendleAuraBalancerStableLPSYV2, StEthHelper {
    uint256 internal constant AURA_PID = 29;
    address internal constant LP = 0x32296969Ef14EB0c6d29669C550D4a0449130230;

    constructor(
        string memory _name,
        string memory _symbol,
        MetaStablePreview _previewHelper
    ) PendleAuraBalancerStableLPSYV2(_name, _symbol, LP, AURA_PID, _previewHelper) StEthHelper() {}

    function _deposit(address tokenIn, uint256 amount) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            IWETH(WETH).deposit{value: amount}();
            amountSharesOut = super._deposit(WETH, amount);
        } else if (tokenIn == STETH) {
            uint256 amountWstETH = _depositWstETH(STETH, amount);
            amountSharesOut = super._deposit(WSTETH, amountWstETH);
        } else {
            amountSharesOut = super._deposit(tokenIn, amount);
        }
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        if (tokenOut == NATIVE) {
            amountTokenOut = super._redeem(address(this), WETH, amountSharesToRedeem);
            IWETH(WETH).withdraw(amountTokenOut);
            _transferOut(NATIVE, receiver, amountTokenOut);
        } else if (tokenOut == STETH) {
            uint256 amountWstETH = super._redeem(address(this), WSTETH, amountSharesToRedeem);
            amountTokenOut = _redeemWstETH(receiver, amountWstETH);
        } else {
            amountTokenOut = super._redeem(receiver, tokenOut, amountSharesToRedeem);
        }
    }

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            amountSharesOut = super._previewDeposit(WETH, amountTokenToDeposit);
        } else if (tokenIn == STETH) {
            uint256 amountWstETH = _previewDepositWstETH(STETH, amountTokenToDeposit);
            amountSharesOut = super._previewDeposit(WSTETH, amountWstETH);
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
        } else if (tokenOut == STETH) {
            uint256 amountWstETH = super._previewRedeem(WSTETH, amountSharesToRedeem);
            amountTokenOut = _previewRedeemWstETH(amountWstETH);
        } else {
            amountTokenOut = super._previewRedeem(tokenOut, amountSharesToRedeem);
        }
    }

    function _getPoolTokenAddresses() internal view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = WSTETH;
        res[1] = WETH;
    }

    function _getRateProviders() internal view virtual returns (address[] memory res) {
        res = new address[](2);
        res[0] = 0x72D07D7DcA67b8A406aD1Ec34ce969c90bFEE768;
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
        res = new address[](5);
        res[0] = LP;
        res[1] = WSTETH;
        res[2] = WETH;
        res[3] = STETH;
        res[4] = NATIVE;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](5);
        res[0] = LP;
        res[1] = WSTETH;
        res[2] = WETH;
        res[3] = STETH;
        res[4] = NATIVE;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return (token == LP || token == WSTETH || token == WETH || token == STETH || token == NATIVE);
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return (token == LP || token == WSTETH || token == WETH || token == STETH || token == NATIVE);
    }
}
