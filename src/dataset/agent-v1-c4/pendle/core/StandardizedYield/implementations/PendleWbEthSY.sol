// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../SYBase.sol";
import "../../../interfaces/BinanceEth/IWBETH.sol";

contract PendleWbEthSY is SYBase {
    using PMath for uint256;

    address public immutable eth;
    address public immutable wbETH;

    constructor(
        string memory _name,
        string memory _symbol,
        address _eth,
        address _wbETH
    ) SYBase(_name, _symbol, _wbETH) {
        eth = _eth;
        wbETH = _wbETH;
        _safeApproveInf(eth, wbETH);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == eth) {
            uint256 previousBalance = _selfBalance(wbETH);
            IWBETH(wbETH).deposit(amountDeposited, address(this));
            amountSharesOut = _selfBalance(wbETH) - previousBalance;
        } else {
            // wbETH
            amountSharesOut = amountDeposited;
        }
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
        // exchangeRate is set by wbETH's oracle
        return IWBETH(wbETH).exchangeRate();
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == eth) {
            return amountTokenToDeposit.divDown(exchangeRate());
        } else {
            return amountTokenToDeposit;
        }
    }

    function _previewRedeem(
        address,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        res = new address[](2);
        res[0] = wbETH;
        res[1] = eth;
    }

    function getTokensOut() public view override returns (address[] memory res) {
        res = new address[](1);
        res[0] = wbETH;
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == eth || token == wbETH;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == wbETH;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, eth, 18);
    }
}
