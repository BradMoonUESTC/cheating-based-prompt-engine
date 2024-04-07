// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBase.sol";
import "../../../../interfaces/Bedrock/IBedrockStaking.sol";

contract PendleUniETHSY is SYBase {
    using PMath for uint256;

    address public immutable bedrockStaking;
    address public immutable uniETH;

    constructor(address _bedrockStaking, address _uniETH) SYBase("SY Bedrock UniETH", "SY-uniETH", _uniETH) {
        bedrockStaking = _bedrockStaking;
        uniETH = _uniETH;
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address tokenIn, uint256 amountDeposited) internal override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            amountSharesOut = IBedrockStaking(bedrockStaking).mint{value: amountDeposited}(0, type(uint256).max);
        } else {
            amountSharesOut = amountDeposited;
        }
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256) {
        _transferOut(uniETH, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view override returns (uint256) {
        return IBedrockStaking(bedrockStaking).exchangeRatio();
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        if (tokenIn == NATIVE) {
            uint256 reserve = IBedrockStaking(bedrockStaking).currentReserve();
            uint256 supply = IERC20(uniETH).totalSupply();
            return (amountTokenToDeposit * supply) / reserve;
        }
        return amountTokenToDeposit;
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(uniETH, NATIVE);
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(uniETH);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == uniETH;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == uniETH;
    }

    function assetInfo() external pure override returns (AssetType, address, uint8) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
