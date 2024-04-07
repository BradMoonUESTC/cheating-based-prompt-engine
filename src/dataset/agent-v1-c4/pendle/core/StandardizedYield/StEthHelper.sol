// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../interfaces/IWstETH.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/IStETH.sol";
import "../libraries/TokenHelper.sol";

abstract contract StEthHelper is TokenHelper {
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    constructor() {
        _safeApproveInf(STETH, WSTETH);
    }

    /// @dev tokenIn must be either ETH, WETH or STETH
    function _depositWstETH(address tokenIn, uint256 amountDep) internal virtual returns (uint256 amountOut) {
        uint256 amountStETH;
        if (tokenIn == STETH) {
            amountStETH = amountDep;
        } else {
            if (tokenIn == WETH) IWETH(WETH).withdraw(amountDep);

            uint256 amountStEthSharesOut = IStETH(STETH).submit{value: amountDep}(address(0));
            amountStETH = IStETH(STETH).getPooledEthByShares(amountStEthSharesOut);
        }
        amountOut = IWstETH(WSTETH).wrap(amountStETH);
    }

    function _redeemWstETH(address receiver, uint256 amountRedeem) internal virtual returns (uint256 amountTokenOut) {
        amountTokenOut = IWstETH(WSTETH).unwrap(amountRedeem);
        if (receiver != address(this)) _transferOut(STETH, receiver, amountTokenOut);
    }

    /// @dev tokenIn must be either ETH, WETH or STETH
    function _previewDepositWstETH(
        address tokenIn,
        uint256 amountDep
    ) internal view virtual returns (uint256 amountOut) {
        if (tokenIn != STETH) {
            assert(tokenIn == WETH || tokenIn == NATIVE);
            uint256 totalShares = IStETH(STETH).getTotalShares();
            uint256 totalPooledEth = IStETH(STETH).getTotalPooledEther();
            uint256 amountStEthSharesOut = IStETH(STETH).getSharesByPooledEth(amountDep);

            totalShares += amountStEthSharesOut;
            totalPooledEth += amountDep;

            uint256 stEthBalance = (amountStEthSharesOut * totalPooledEth) / totalShares;
            amountOut = (stEthBalance * totalShares) / totalPooledEth;
        } else {
            amountOut = IStETH(STETH).getSharesByPooledEth(amountDep);
        }
    }

    function _previewRedeemWstETH(uint256 amountRedeem) internal view returns (uint256 amountOut) {
        amountOut = IStETH(STETH).getPooledEthByShares(amountRedeem);
    }
}
