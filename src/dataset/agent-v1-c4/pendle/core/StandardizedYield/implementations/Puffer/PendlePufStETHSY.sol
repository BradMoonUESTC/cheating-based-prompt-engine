// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseUpg.sol";
import "../../StEthNativeLib.sol";
import "../../../../interfaces/IERC4626.sol";

contract PendlePufStETHSY is SYBaseUpg {
    using PMath for uint256;
    address public immutable asset;

    constructor(address _erc4626) SYBaseUpg(_erc4626) {
        asset = IERC4626(_erc4626).asset();
    }

    function initialize() external initializer {
        __SYBaseUpg_init("SY Puffer ETH", "SY pufETH");
        approveAssetForDeposit();
    }

    function approveAssetForDeposit() public {
        _safeApproveInf(asset, yieldToken);
    }

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == yieldToken) {
            return amountDeposited;
        } else {
            if (tokenIn == NATIVE) {
                amountDeposited = StETHNativeLib._depositStETH(amountDeposited);
            }
            return IERC4626(yieldToken).deposit(amountDeposited, address(this));
        }
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256) {
        _transferOut(yieldToken, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
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
        // tokenIn is either NATIVE or stETH, we treat 1 NATIVE == 1 stETH
        else return IERC4626(yieldToken).previewDeposit(amountTokenToDeposit);
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldToken, asset, NATIVE);
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldToken);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldToken || token == asset || token == NATIVE;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldToken;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        // Puffer team clarified that their 4626 will be changed to WETH when they are fully launched
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
