// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../SYBase.sol";
import "../../../interfaces/Lybra/IEUSD.sol";

contract PendleEUSDSY is SYBase {
    address public immutable eUSD;

    constructor(string memory _name, string memory _symbol, address _eUSD) SYBase(_name, _symbol, _eUSD) {
        eUSD = _eUSD;
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address /*tokenIn*/,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        return IEUSD(eUSD).getSharesByMintedEUSD(amountDeposited);
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 /*amountTokenOut*/) {
        return IEUSD(eUSD).transferShares(receiver, amountSharesToRedeem);
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return IEUSD(eUSD).getMintedEUSDByShares(1e18);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address /*tokenIn*/,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        return IEUSD(eUSD).getSharesByMintedEUSD(amountTokenToDeposit);
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 /*amountTokenOut*/) {
        return IEUSD(eUSD).getMintedEUSDByShares(amountSharesToRedeem);
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](1);
        res[0] = eUSD;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](1);
        res[0] = eUSD;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == eUSD;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == eUSD;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        assetType = AssetType.TOKEN;
        assetAddress = eUSD;
        assetDecimals = 18;
    }
}
