// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./FluxTokenLib.sol";
import "../../SYBase.sol";
import "../../../../interfaces/Flux/IFluxErc20.sol";

contract PendleFluxLendingSY is SYBase {
    using PMath for uint256;

    error FluxLendingError(uint256 errCode);

    address public immutable fToken;
    address public immutable underlying;

    constructor(string memory _name, string memory _symbol, address _fToken) SYBase(_name, _symbol, _fToken) {
        // underlying
        fToken = _fToken;
        underlying = IFluxErc20(_fToken).underlying();

        _safeApproveInf(underlying, fToken);
    }

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == fToken) {
            return amountDeposited;
        } else {
            uint256 preBalance = _selfBalance(fToken);
            uint256 errCode = IFluxErc20(fToken).mint(amountDeposited);
            if (errCode != 0) revert FluxLendingError(errCode);
            return _selfBalance(fToken) - preBalance;
        }
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        if (tokenOut == fToken) {
            amountTokenOut = amountSharesToRedeem;
        } else {
            uint256 preBalance = _selfBalance(tokenOut);
            uint256 errCode = IFluxErc20(fToken).redeem(amountSharesToRedeem);
            if (errCode != 0) revert FluxLendingError(errCode);
            amountTokenOut = _selfBalance(tokenOut) - preBalance;
        }
        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    function exchangeRate() public view virtual override returns (uint256) {
        return FluxTokenLib.exchangeRateCurrentView(fToken);
    }

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == fToken) {
            return amountTokenToDeposit;
        } else {
            return amountTokenToDeposit.divDown(exchangeRate());
        }
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 /*amountTokenOut*/) {
        if (tokenOut == fToken) {
            return amountSharesToRedeem;
        } else {
            return amountSharesToRedeem.mulDown(exchangeRate());
        }
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = fToken;
        res[1] = underlying;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = fToken;
        res[1] = underlying;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == fToken || token == underlying;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == fToken || token == underlying;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, underlying, IERC20Metadata(underlying).decimals());
    }
}
