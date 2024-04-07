// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBase.sol";
import "../../../../interfaces/IPOracleForSy.sol";

contract PendleMantleStakedEthSY is SYBase {
    using PMath for int256;

    address internal immutable underlyingAssetOnEthAddr;
    uint8 internal immutable underlyingAssetOnEthDecimals;
    address public immutable oracleAddress;

    constructor(
        string memory _name,
        string memory _symbol,
        address _token,
        address _underlyingAssetOnEthAddr,
        uint8 _underlyingAssetOnEthDecimals,
        address _oracleAddress
    ) SYBase(_name, _symbol, _token) {
        underlyingAssetOnEthAddr = _underlyingAssetOnEthAddr;
        underlyingAssetOnEthDecimals = _underlyingAssetOnEthDecimals;
        oracleAddress = _oracleAddress;
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
        return IPOracleForSy(oracleAddress).latestAnswer().Uint();
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
        res = new address[](1);
        res[0] = yieldToken;
    }

    function getTokensOut() public view override returns (address[] memory res) {
        res = new address[](1);
        res[0] = yieldToken;
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
