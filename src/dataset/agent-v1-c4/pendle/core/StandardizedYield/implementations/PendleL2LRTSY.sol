// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../SYBase.sol";
import "../../../interfaces/IPExchangeRateOracle.sol";

contract PendleL2LRTSY is SYBase {
    using PMath for int256;

    address public exchangeRateOracle;
    address internal immutable underlyingAssetOnEthAddr;
    uint8 internal immutable underlyingAssetOnEthDecimals;

    constructor(
        string memory _name,
        string memory _symbol,
        address _token,
        address _exchangeRateOracle,
        address _underlyingAssetOnEthAddr,
        uint8 _underlyingAssetOnEthDecimals
    ) SYBase(_name, _symbol, _token) {
        exchangeRateOracle = _exchangeRateOracle;
        underlyingAssetOnEthAddr = _underlyingAssetOnEthAddr;
        underlyingAssetOnEthDecimals = _underlyingAssetOnEthDecimals;
    }

    function setExchangeRateOracle(address newOracle) external onlyOwner {
        exchangeRateOracle = newOracle;
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address, uint256 amountDeposited) internal pure override returns (uint256 /*amountSharesOut*/) {
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256 /*amountTokenOut*/) {
        _transferOut(tokenOut, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view override returns (uint256) {
        return IPExchangeRateOracle(exchangeRateOracle).getExchangeRate();
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address,
        uint256 amountTokenToDeposit
    ) internal pure override returns (uint256 /*amountSharesOut*/) {
        return amountTokenToDeposit;
    }

    function _previewRedeem(
        address,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
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
        return (AssetType.TOKEN, underlyingAssetOnEthAddr, underlyingAssetOnEthDecimals);
    }
}
