// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseWithRewardsUpg.sol";
import "./GLPPreviewHelper.sol";
import "../../../libraries/ArrayLib.sol";
import "../../../../interfaces/GMX/IRewardRouterV2.sol";
import "../../../../interfaces/GMX/IGlpManager.sol";
import "../../../../interfaces/GMX/IGMXVault.sol";

contract PendleGlpSY is SYBaseWithRewardsUpg, GLPPreviewHelper {
    using ArrayLib for address[];

    address public immutable glp;
    address public immutable stakedGlp;
    address public immutable rewardRouter;
    address public immutable glpRouter;
    address public immutable glpManager;
    address public immutable weth;

    constructor(
        address _glp,
        address _fsGlp,
        address _stakedGlp,
        address _rewardRouter,
        address _glpRouter,
        address _vault
    ) SYBaseUpg(_fsGlp) GLPPreviewHelper(_vault) {
        _disableInitializers();
        glp = _glp;
        stakedGlp = _stakedGlp;
        rewardRouter = _rewardRouter;
        glpRouter = _glpRouter;
        glpManager = IRewardRouterV2(glpRouter).glpManager();
        weth = IRewardRouterV2(glpRouter).weth();
    }

    function initialize() external initializer {
        __SYBaseUpg_init("SY GLP", "SY-GLP");
        approveAllWhitelisted();
    }

    function approveAllWhitelisted() public {
        uint256 length = vault.allWhitelistedTokensLength();
        for (uint256 i = 0; i < length; ++i) {
            address token = vault.allWhitelistedTokens(i);
            if (vault.whitelistedTokens(token)) {
                _safeApproveInf(token, glpManager);
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {SYBase-_deposit}
     */
    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == stakedGlp) {
            // GLP is already staked in stakedGlp's transferFrom, called in _transferIn()
            amountSharesOut = amountDeposited;
        } else if (tokenIn == NATIVE) {
            amountSharesOut = IRewardRouterV2(glpRouter).mintAndStakeGlpETH{value: msg.value}(0, 0);
        } else {
            amountSharesOut = IRewardRouterV2(glpRouter).mintAndStakeGlp(tokenIn, amountDeposited, 0, 0);
        }
    }

    /**
     * @dev See {SYBase-_redeem}
     */
    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        if (tokenOut == stakedGlp) {
            amountTokenOut = amountSharesToRedeem;
            _transferOut(tokenOut, receiver, amountTokenOut);
        } else if (tokenOut == NATIVE) {
            amountTokenOut = IRewardRouterV2(glpRouter).unstakeAndRedeemGlpETH(
                amountSharesToRedeem,
                0,
                payable(receiver)
            );
        } else {
            amountTokenOut = IRewardRouterV2(glpRouter).unstakeAndRedeemGlp(
                tokenOut,
                amountSharesToRedeem,
                0,
                receiver
            );
        }
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates and updates the exchange rate of shares to underlying asset token
     * @dev 1 SY = 1 GLP
     */
    function exchangeRate() public view virtual override returns (uint256) {
        return PMath.ONE;
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-getRewardTokens}
     */
    function _getRewardTokens() internal view override returns (address[] memory res) {
        res = new address[](1);
        res[0] = weth;
    }

    function _redeemExternalReward() internal override {
        IRewardRouterV2(rewardRouter).handleRewards(false, false, true, true, false, true, false);
    }

    /*///////////////////////////////////////////////////////////////
                    MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 amountSharesOut) {
        if (tokenIn == stakedGlp) amountSharesOut = amountTokenToDeposit;
        else {
            if (tokenIn == NATIVE) tokenIn = weth;

            // Based on GlpManager's _addLiquidity
            uint256 aumInUsdg = IGlpManager(glpManager).getAumInUsdg(true);
            uint256 glpSupply = IERC20(glp).totalSupply();
            uint256 usdgAmount = super._buyUSDG(tokenIn, amountTokenToDeposit);

            uint256 mintAmount = aumInUsdg == 0 ? usdgAmount : (usdgAmount * glpSupply) / aumInUsdg;
            amountSharesOut = mintAmount;
        }
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 amountTokenOut) {
        if (tokenOut == stakedGlp) amountTokenOut = amountSharesToRedeem;
        else {
            if (tokenOut == NATIVE) tokenOut = weth;

            // Based on GlpManager's _removeLiquidity
            uint256 aumInUsdg = IGlpManager(glpManager).getAumInUsdg(false);
            uint256 glpSupply = IERC20(glp).totalSupply();

            uint256 usdgAmount = (amountSharesToRedeem * aumInUsdg) / glpSupply;
            uint256 amountOut = super._sellUSDG(tokenOut, usdgAmount);

            amountTokenOut = amountOut;
        }
    }

    function _getGlpTokens() internal view returns (address[] memory res) {
        res = new address[](0);
        uint256 length = vault.allWhitelistedTokensLength();
        for (uint256 i = 0; i < length; ++i) {
            address token = vault.allWhitelistedTokens(i);
            if (vault.whitelistedTokens(token) && !res.contains(token)) {
                res = res.append(token);
            }
        }
        res = res.append(stakedGlp);
        res = res.append(NATIVE);
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        return _getGlpTokens();
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        return _getGlpTokens();
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == stakedGlp || token == NATIVE || vault.whitelistedTokens(token);
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == stakedGlp || token == NATIVE || vault.whitelistedTokens(token);
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.LIQUIDITY, glp, IERC20Metadata(glp).decimals());
    }
}
