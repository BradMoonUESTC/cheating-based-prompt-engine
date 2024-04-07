// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./base/PendleConvexLPSY.sol";
import "./base/CurveFraxUsdcPoolHelper.sol";
import "../../../libraries/ArrayLib.sol";

contract PendleCurveFraxUsdcSY is PendleConvexLPSY {
    using ArrayLib for address[];

    uint256 public constant PID = 100;

    address public constant FRAX = CurveFraxUsdcPoolHelper.FRAX;
    address public constant USDC = CurveFraxUsdcPoolHelper.USDC;

    constructor(
        string memory _name,
        string memory _symbol
    ) PendleConvexLPSY(_name, _symbol, PID, CurveFraxUsdcPoolHelper.LP, CurveFraxUsdcPoolHelper.POOL) {
        _safeApproveInf(FRAX, crvPool);
        _safeApproveInf(USDC, crvPool);
    }

    function _depositToCurve(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal virtual override returns (uint256 amountLpOut) {
        uint256[2] memory amounts;
        amounts[_getIndex(tokenIn)] = amountTokenToDeposit;
        amountLpOut = ICrvPool(crvPool).add_liquidity(amounts, 0);
    }

    function _redeemFromCurve(
        address tokenOut,
        uint256 amountLpToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        amountTokenOut = ICrvPool(crvPool).remove_liquidity_one_coin(
            amountLpToRedeem,
            PMath.Int128(_getIndex(tokenOut)),
            0
        );
    }

    function _previewDepositToCurve(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual override returns (uint256) {
        return CurveFraxUsdcPoolHelper.previewAddLiquidity(tokenIn, amountTokenToDeposit);
    }

    function _previewRedeemFromCurve(
        address tokenOut,
        uint256 amountLpToRedeem
    ) internal view virtual override returns (uint256) {
        return ICrvPool(crvPool).calc_withdraw_one_coin(amountLpToRedeem, PMath.Int128(_getIndex(tokenOut)));
    }

    function _getIndex(address token) internal pure returns (uint256) {
        return (token == FRAX ? 0 : 1);
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](3);
        res[0] = crvLp;
        res[1] = FRAX;
        res[2] = USDC;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](3);
        res[0] = crvLp;
        res[1] = FRAX;
        res[2] = USDC;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool res) {
        res = (token == crvLp || token == FRAX || token == USDC);
    }

    function isValidTokenOut(address token) public view override returns (bool res) {
        res = (token == crvLp || token == FRAX || token == USDC);
    }
}
