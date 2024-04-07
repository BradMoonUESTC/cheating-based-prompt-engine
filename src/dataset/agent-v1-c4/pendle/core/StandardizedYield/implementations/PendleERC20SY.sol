// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../SYBase.sol";

contract PendleERC20SY is SYBase {
    using PMath for uint256;

    constructor(string memory _name, string memory _symbol, address _erc20) SYBase(_name, _symbol, _erc20) {}

    function _deposit(
        address /*tokenIn*/,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256) {
        _transferOut(yieldToken, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    function exchangeRate() public view virtual override returns (uint256 res) {
        return PMath.ONE;
    }

    function _previewDeposit(
        address /*tokenIn*/,
        uint256 amountTokenToDeposit
    ) internal view virtual override returns (uint256 /*amountSharesOut*/) {
        return amountTokenToDeposit;
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal view virtual override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldToken);
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldToken);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == yieldToken;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldToken;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, yieldToken, IERC20Metadata(yieldToken).decimals());
    }
}
