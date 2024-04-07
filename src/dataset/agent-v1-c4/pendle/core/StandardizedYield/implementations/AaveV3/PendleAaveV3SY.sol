// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "../../SYBase.sol";
import "./libraries/AaveAdapterLib.sol";
import "../../../../interfaces/AaveV3/IAaveV3AToken.sol";
import "../../../../interfaces/AaveV3/IAaveV3Pool.sol";

// @NOTE: In this contract, we denote the "scaled balance" term as "share"
contract PendleAaveV3SY is SYBase {
    using PMath for uint256;

    address public immutable aToken;
    address public immutable aavePool;
    address public immutable underlying;

    constructor(
        string memory _name,
        string memory _symbol,
        address _aavePool,
        address _aToken
    ) SYBase(_name, _symbol, _aToken) {
        aToken = _aToken;
        aavePool = _aavePool;
        underlying = IAaveV3AToken(aToken).UNDERLYING_ASSET_ADDRESS();

        _safeApproveInf(underlying, _aavePool);
    }

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == underlying) {
            IAaveV3Pool(aavePool).supply(underlying, amountDeposited, address(this), 0);
        }
        amountSharesOut = AaveAdapterLib.calcSharesFromAssetUp(amountDeposited, _getNormalizedIncome());
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256 amountTokenOut) {
        amountTokenOut = AaveAdapterLib.calcSharesToAssetDown(amountSharesToRedeem, _getNormalizedIncome());
        if (tokenOut == underlying) {
            IAaveV3Pool(aavePool).withdraw(underlying, amountTokenOut, receiver);
        } else {
            _transferOut(aToken, receiver, amountTokenOut);
        }
    }

    function exchangeRate() public view virtual override returns (uint256) {
        return _getNormalizedIncome() / 1e9;
    }

    function _previewDeposit(
        address,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        return AaveAdapterLib.calcSharesFromAssetUp(amountTokenToDeposit, _getNormalizedIncome());
    }

    function _previewRedeem(
        address,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 /*amountTokenOut*/) {
        return AaveAdapterLib.calcSharesToAssetDown(amountSharesToRedeem, _getNormalizedIncome());
    }

    function _getNormalizedIncome() internal view returns (uint256) {
        return IAaveV3Pool(aavePool).getReserveNormalizedIncome(underlying);
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(underlying, aToken);
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(underlying, aToken);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == aToken || token == underlying;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == aToken || token == underlying;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, underlying, IERC20Metadata(underlying).decimals());
    }
}
