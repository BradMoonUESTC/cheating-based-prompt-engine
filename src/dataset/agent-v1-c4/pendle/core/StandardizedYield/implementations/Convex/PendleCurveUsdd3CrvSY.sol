// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./base/PendleConvexLPSY.sol";
import "./base/CurveUsdd3CrvPoolHelper.sol";
import "../../../libraries/ArrayLib.sol";

contract PendleCurveUsdd3CrvSY is PendleConvexLPSY {
    using ArrayLib for address[];

    uint256 public constant PID = 96;
    address public constant USDD = CurveUsdd3CrvPoolHelper.USDD;
    address public constant LP_3CRV = Curve3CrvPoolHelper.LP;
    address public constant DAI = Curve3CrvPoolHelper.DAI;
    address public constant USDC = Curve3CrvPoolHelper.USDC;
    address public constant USDT = Curve3CrvPoolHelper.USDT;
    address public constant POOL_3CRV = Curve3CrvPoolHelper.POOL;
    uint256 public constant INDEX_OF_3CRV = 1;

    constructor(
        string memory _name,
        string memory _symbol
    ) PendleConvexLPSY(_name, _symbol, PID, CurveUsdd3CrvPoolHelper.POOL, CurveUsdd3CrvPoolHelper.POOL) {
        _safeApproveInf(USDD, crvPool);
        _safeApproveInf(LP_3CRV, crvPool);
        _safeApproveInf(DAI, POOL_3CRV);
        _safeApproveInf(USDC, POOL_3CRV);
        _safeApproveInf(USDT, POOL_3CRV);
    }

    function _depositToCurve(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal virtual override returns (uint256 amountLpOut) {
        uint256 preBalanceLp = _selfBalance(crvLp);

        uint256[2] memory amounts;

        if (Curve3CrvPoolHelper.is3CrvToken(tokenIn)) {
            uint256 amount3CrvLp = Curve3CrvPoolHelper.deposit3Crv(tokenIn, amountTokenToDeposit);
            amounts[INDEX_OF_3CRV] = amount3CrvLp;
        } else {
            // one of the 2 LP
            amounts[_getIndex(tokenIn)] = amountTokenToDeposit;
        }

        ICrvPool(crvPool).add_liquidity(amounts, 0);

        amountLpOut = _selfBalance(crvLp) - preBalanceLp;
    }

    function _redeemFromCurve(
        address tokenOut,
        uint256 amountLpToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        address tokenToRemove = (tokenOut == USDD) ? USDD : LP_3CRV;

        uint256 preBalanceToken = _selfBalance(tokenToRemove);

        ICrvPool(crvPool).remove_liquidity_one_coin(amountLpToRedeem, PMath.Int128(_getIndex(tokenToRemove)), 0);

        uint256 amountTokenRemoved = _selfBalance(tokenToRemove) - preBalanceToken;

        if (Curve3CrvPoolHelper.is3CrvToken(tokenOut)) {
            amountTokenOut = Curve3CrvPoolHelper.redeem3Crv(tokenOut, amountTokenRemoved);
        } else {
            // one of the 2 LP
            amountTokenOut = amountTokenRemoved;
        }
    }

    function _previewDepositToCurve(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual override returns (uint256) {
        return CurveUsdd3CrvPoolHelper.previewAddLiquidity(tokenIn, amountTokenToDeposit);
    }

    function _previewRedeemFromCurve(
        address tokenOut,
        uint256 amountLpToRedeem
    ) internal view virtual override returns (uint256) {
        address tokenToRemove = tokenOut == USDD ? USDD : LP_3CRV;
        uint256 amountTokenRemoved = ICrvPool(crvPool).calc_withdraw_one_coin(
            amountLpToRedeem,
            PMath.Int128(_getIndex(tokenToRemove))
        );

        if (Curve3CrvPoolHelper.is3CrvToken(tokenOut)) {
            return Curve3CrvPoolHelper.preview3CrvRedeem(tokenOut, amountTokenRemoved);
        } else {
            // one of the 2 LP
            return amountTokenRemoved;
        }
    }

    function _getIndex(address token) internal pure returns (uint256) {
        return (token == USDD ? 0 : 1);
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](6);
        res[0] = crvLp;
        res[1] = USDD;
        res[2] = LP_3CRV;
        res[3] = DAI;
        res[4] = USDC;
        res[5] = USDT;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](6);
        res[0] = crvLp;
        res[1] = USDD;
        res[2] = LP_3CRV;
        res[3] = DAI;
        res[4] = USDC;
        res[5] = USDT;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool res) {
        res = (token == crvLp || token == USDD || token == LP_3CRV || Curve3CrvPoolHelper.is3CrvToken(token));
    }

    function isValidTokenOut(address token) public view override returns (bool res) {
        res = (token == crvLp || token == USDD || token == LP_3CRV || Curve3CrvPoolHelper.is3CrvToken(token));
    }

    function _getRewardTokens() internal pure override returns (address[] memory rewardTokens) {
        rewardTokens = new address[](3);
        rewardTokens[0] = USDD;
        rewardTokens[1] = CRV;
        rewardTokens[2] = CVX;
    }
}
