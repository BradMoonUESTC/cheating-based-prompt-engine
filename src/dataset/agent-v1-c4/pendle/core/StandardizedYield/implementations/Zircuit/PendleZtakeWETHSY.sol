// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseUpg.sol";
import "../../../../interfaces/Zircuit/IZircuitZtaking.sol";

contract PendleZtakeWETHSY is SYBaseUpg {
    // solhint-disable immutable-vars-naming
    address public immutable zircuitStaking;
    address public immutable wETH;

    constructor(address _zircuitStaking, address _wETH) SYBaseUpg(_wETH) {
        _disableInitializers();
        zircuitStaking = _zircuitStaking;
        wETH = _wETH;
    }

    function initialize() external initializer {
        __SYBaseUpg_init("SY Zircuit Staking wETH", "SY-zs-wETH");
        _safeApproveInf(wETH, zircuitStaking);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address /*tokenIn*/, uint256 amountDeposited) internal virtual override returns (uint256) {
        IZircuitZtaking(zircuitStaking).depositFor(wETH, address(this), amountDeposited);
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256 /*amountTokenOut*/) {
        IZircuitZtaking(zircuitStaking).withdraw(wETH, amountSharesToRedeem);
        _transferOut(wETH, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return PMath.ONE;
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address /*tokenIn*/,
        uint256 amountTokenToDeposit
    ) internal pure override returns (uint256 /*amountSharesOut*/) {
        return amountTokenToDeposit;
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(wETH);
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(wETH);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == wETH;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == wETH;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        assetType = AssetType.TOKEN;
        assetAddress = wETH;
        assetDecimals = 18;
    }
}
