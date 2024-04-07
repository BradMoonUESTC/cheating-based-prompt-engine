// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../../SYBaseWithRewards.sol";
import "../../../../../interfaces/ConvexCurve/IBooster.sol";
import "../../../../../interfaces/ConvexCurve/IRewards.sol";
import "../../../../../interfaces/Curve/ICrvPool.sol";

abstract contract PendleConvexLPSY is SYBaseWithRewards {
    using SafeERC20 for IERC20;

    uint256 public immutable cvxPid;
    address public immutable cvxRewardManager;

    address public immutable crvPool;
    address public immutable crvLp;

    address public constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _cvxPid,
        address _crvLp,
        address _crvPool
    ) SYBaseWithRewards(_name, _symbol, _crvLp) {
        cvxPid = _cvxPid;
        crvPool = _crvPool;

        (crvLp, cvxRewardManager) = _getPoolInfo(cvxPid);
        if (crvLp != _crvLp) revert Errors.SYCurveInvalidPid();

        _safeApproveInf(crvLp, BOOSTER);
    }

    function _getPoolInfo(uint256 _cvxPid) internal view returns (address _crvLp, address _cvxRewardManager) {
        if (_cvxPid > IBooster(BOOSTER).poolLength()) revert Errors.SYCurveInvalidPid();

        (_crvLp, , , _cvxRewardManager, , ) = IBooster(BOOSTER).poolInfo(_cvxPid);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    /**
     * If any of the base pool tokens are deposited, it will first add liquidity to the curve pool and mint LP,
     * which will then be deposited into convex
     */
    function _deposit(address tokenIn, uint256 amount) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == crvLp) {
            amountSharesOut = amount;
        } else {
            amountSharesOut = _depositToCurve(tokenIn, amount);
        }

        IBooster(BOOSTER).deposit(cvxPid, amountSharesOut, true);
    }

    /**
     * If any of the base curve pool tokens is specified as 'tokenOut',
     * it will redeem the corresponding liquidity the LP token represents via the prevailing exchange rate.
     */
    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        IRewards(cvxRewardManager).withdrawAndUnwrap(amountSharesToRedeem, false);

        if (tokenOut == crvLp) {
            amountTokenOut = amountSharesToRedeem;
        } else {
            amountTokenOut = _redeemFromCurve(tokenOut, amountSharesToRedeem);
        }
        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    /**
     * The current price of the pool LP token relative to the underlying pool assets. Given as an integer with 1e18 precision.
     */
    function exchangeRate() public view virtual override returns (uint256) {
        return ICrvPool(crvPool).get_virtual_price();
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    /**
     * Refer to currentExtraRewards array of reward tokens specific to the curve pool.
     * @dev We are aware that Convex might add or remove reward tokens, but also agreed that it was
     * not worth the complexity
     **/
    function _getRewardTokens() internal view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = CRV;
        res[1] = CVX;
    }

    function _redeemExternalReward() internal virtual override {
        // Redeem all extra rewards from the curve pool
        IRewards(cvxRewardManager).getReward();
    }

    /*///////////////////////////////////////////////////////////////
                    MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == crvLp) {
            amountSharesOut = amountTokenToDeposit;
        } else {
            amountSharesOut = _previewDepositToCurve(tokenIn, amountTokenToDeposit);
        }
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view virtual override returns (uint256 amountTokenOut) {
        if (tokenOut == crvLp) {
            amountTokenOut = amountSharesToRedeem;
        } else {
            amountTokenOut = _previewRedeemFromCurve(tokenOut, amountSharesToRedeem);
        }
    }

    function getTokensIn() public view virtual override returns (address[] memory res);

    function getTokensOut() public view virtual override returns (address[] memory res);

    function isValidTokenIn(address token) public view virtual override returns (bool);

    function isValidTokenOut(address token) public view virtual override returns (bool);

    function _depositToCurve(address tokenIn, uint256 amountTokenToDeposit) internal virtual returns (uint256);

    function _redeemFromCurve(address tokenOut, uint256 amountLpToRedeem) internal virtual returns (uint256);

    function _previewDepositToCurve(
        address token,
        uint256 amountTokenToDeposit
    ) internal view virtual returns (uint256 amountLpOut);

    function _previewRedeemFromCurve(
        address token,
        uint256 amountLpToRedeem
    ) internal view virtual returns (uint256 amountTokenOut);

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.LIQUIDITY, crvLp, IERC20Metadata(crvLp).decimals());
    }
}
