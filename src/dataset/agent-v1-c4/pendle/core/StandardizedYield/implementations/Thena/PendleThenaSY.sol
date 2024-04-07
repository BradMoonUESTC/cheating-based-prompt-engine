// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.17;

import "../../SYBaseWithRewards.sol";
import "./ThenaLpHelper.sol";
import "../../../../interfaces/IPPreviewHelper.sol";
import "../../../../interfaces/Thena/IThenaGaugeV2.sol";
import "../../../libraries/ArrayLib.sol";

contract PendleThenaSY is ThenaLpHelper, SYBaseWithRewards {
    event SetNewBinarySearchEps(uint256 newEps);
    event AddExternalRewardToken(address indexed token);

    using PMath for uint256;
    using ArrayLib for address[];

    address[] public externalRewardTokens;
    address public immutable gauge;
    address public immutable THENA;
    IPPreviewHelper public immutable previewHelper;

    constructor(
        string memory _name,
        string memory _symbol,
        address _pair,
        address _factory,
        address _router,
        address _gauge,
        address _THENA,
        IPPreviewHelper _previewHelper
    ) SYBaseWithRewards(_name, _symbol, _pair) ThenaLpHelper(_pair, _factory, _router) {
        THENA = _THENA;
        gauge = _gauge;
        previewHelper = _previewHelper;
        _safeApproveInf(_pair, _gauge);
    }

    /**
     * @dev See {SYBase-_deposit}
     */
    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 amountLpDeposited) {
        _withdrawAllFromGauge();
        if (tokenIn == pair) {
            amountLpDeposited = amountDeposited;
        } else {
            amountLpDeposited = _zapIn(tokenIn, amountDeposited);
        }
        _depositToGaugeIfNotEmergency();
    }

    /**
     * @dev See {SYBase-_redeem}
     */
    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        _withdrawAllFromGauge();
        if (tokenOut == pair) {
            amountTokenOut = amountSharesToRedeem;
        } else {
            amountTokenOut = _zapOut(tokenOut, amountSharesToRedeem);
        }
        _transferOut(tokenOut, receiver, amountTokenOut);
        _depositToGaugeIfNotEmergency();
    }

    function exchangeRate() public view virtual override returns (uint256) {
        return PMath.ONE;
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-getRewardTokens}
     */
    function _getRewardTokens() internal view virtual override returns (address[] memory res) {
        res = new address[](1 + externalRewardTokens.length);
        res[0] = THENA;
        for (uint256 i = 1; i < res.length; ++i) {
            res[i] = externalRewardTokens[i - 1];
        }
    }

    function _redeemExternalReward() internal override {
        IThenaGaugeV2(gauge).getReward();
    }

    /*///////////////////////////////////////////////////////////////
                    PREVIEW-RELATED
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        if (tokenIn == pair) {
            return amountTokenToDeposit;
        } else {
            return previewHelper.previewDeposit(tokenIn, amountTokenToDeposit);
        }
    }

    function _previewRedeem(address tokenOut, uint256 amountSharesToRedeem) internal view override returns (uint256) {
        if (tokenOut == pair) {
            return amountSharesToRedeem;
        } else {
            return previewHelper.previewRedeem(tokenOut, amountSharesToRedeem);
        }
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](3);
        res[0] = token0;
        res[1] = token1;
        res[2] = pair;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](3);
        res[0] = token0;
        res[1] = token1;
        res[2] = pair;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == token0 || token == token1 || token == pair;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == token0 || token == token1 || token == pair;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.LIQUIDITY, pair, IERC20Metadata(pair).decimals());
    }

    /*///////////////////////////////////////////////////////////////
                        REWARD RELATED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _withdrawAllFromGauge() internal {
        if (IThenaGaugeV2(gauge).balanceOf(address(this)) == 0) {
            return;
        }

        if (IThenaGaugeV2(gauge).emergency()) {
            IThenaGaugeV2(gauge).emergencyWithdraw();
        } else {
            IThenaGaugeV2(gauge).withdrawAll();
        }
    }

    function _depositToGaugeIfNotEmergency() internal {
        if (!IThenaGaugeV2(gauge).emergency()) {
            IThenaGaugeV2(gauge).depositAll();
        }
    }

    function setBinarySearchEps(uint256 newEps) external onlyOwner {
        require(newEps > 0 && newEps < 1e18, "invalid newEps");
        binarySearchEps = newEps;

        emit SetNewBinarySearchEps(newEps);
    }

    function addExternalRewardToken(address token) external onlyOwner {
        // prevent adding THE as well
        require(!_getRewardTokens().contains(token), "rewardToken existed");
        externalRewardTokens.push(token);

        emit AddExternalRewardToken(token);
    }
}
