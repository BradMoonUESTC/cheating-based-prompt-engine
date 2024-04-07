// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "../../SYBase.sol";
import "../../../../interfaces/EtherFi/IEtherFiLiquidityPool.sol";
import "../../../../interfaces/EtherFi/IEtherFiWEEth.sol";

contract PendleWEEthSY is SYBase {
    using PMath for int256;

    address public immutable weETH;
    address public immutable liquidityPool;
    address public immutable eETH;
    address public immutable referee;

    constructor(address _weETH, address _referee) SYBase("SY ether.fi weETH", "SY-weETH", _weETH) {
        weETH = _weETH;
        liquidityPool = IEtherFiWEEth(_weETH).liquidityPool();
        eETH = IEtherFiWEEth(_weETH).eETH();
        referee = _referee;

        _safeApproveInf(eETH, weETH);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            IEtherFiLiquidityPool(liquidityPool).deposit{value: amountDeposited}(referee);
        }
        if (tokenIn != weETH) {
            amountSharesOut = IEtherFiWEEth(weETH).wrap(_selfBalance(eETH));
        } else {
            amountSharesOut = amountDeposited;
        }
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256 amountTokenOut) {
        if (tokenOut == weETH) {
            amountTokenOut = amountSharesToRedeem;
        } else {
            amountTokenOut = IEtherFiWEEth(weETH).unwrap(amountSharesToRedeem);
        }
        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view override returns (uint256) {
        return IEtherFiLiquidityPool(liquidityPool).amountForShare(1 ether);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        if (tokenIn == weETH) {
            return amountTokenToDeposit;
        } else {
            return IEtherFiLiquidityPool(liquidityPool).sharesForAmount(amountTokenToDeposit);
        }
    }

    function _previewRedeem(address tokenOut, uint256 amountSharesToRedeem) internal view override returns (uint256) {
        if (tokenOut == weETH) {
            return amountSharesToRedeem;
        } else {
            return IEtherFiLiquidityPool(liquidityPool).amountForShare(amountSharesToRedeem);
        }
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(weETH, eETH, NATIVE);
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(weETH, eETH);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == eETH || token == weETH;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == eETH || token == weETH;
    }

    function assetInfo() external view override returns (AssetType, address, uint8) {
        return (AssetType.TOKEN, eETH, 18);
    }
}
