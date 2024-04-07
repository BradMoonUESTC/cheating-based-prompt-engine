// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../SYBaseUpg.sol";
import "../../../interfaces/IERC4626.sol";

contract PendleERC4626SYUpg is SYBaseUpg {
    using PMath for uint256;
    address public immutable asset;

    constructor(address _erc4626) SYBaseUpg(_erc4626) {
        asset = IERC4626(_erc4626).asset();
        _safeApproveInf(asset, _erc4626);
    }

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == yieldToken) {
            return amountDeposited;
        } else {
            return IERC4626(yieldToken).deposit(amountDeposited, address(this));
        }
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256 amountTokenOut) {
        if (tokenOut == yieldToken) {
            amountTokenOut = amountSharesToRedeem;
            _transferOut(yieldToken, receiver, amountTokenOut);
        } else {
            amountTokenOut = IERC4626(yieldToken).redeem(amountSharesToRedeem, receiver, address(this));
        }
    }

    function exchangeRate() public view virtual override returns (uint256) {
        uint256 totalAssets = IERC4626(yieldToken).totalAssets();
        uint256 totalSupply = IERC4626(yieldToken).totalSupply();
        return totalAssets.divDown(totalSupply);
    }

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == yieldToken) return amountTokenToDeposit;
        else return IERC4626(yieldToken).previewDeposit(amountTokenToDeposit);
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 /*amountTokenOut*/) {
        if (tokenOut == yieldToken) return amountSharesToRedeem;
        else return IERC4626(yieldToken).previewRedeem(amountSharesToRedeem);
    }

    function getTokensIn() public view override returns (address[] memory res) {
        res = new address[](2);
        res[0] = asset;
        res[1] = yieldToken;
    }

    function getTokensOut() public view override returns (address[] memory res) {
        res = new address[](2);
        res[0] = asset;
        res[1] = yieldToken;
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldToken || token == asset;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldToken || token == asset;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, asset, IERC20Metadata(asset).decimals());
    }
}
