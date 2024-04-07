// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseUpg.sol";
import "../../../../interfaces/IPExchangeRateOracle.sol";
import "../../../../interfaces/Renzo/IRenzoRestakeManager.sol";
import "../../../../interfaces/Renzo/IRenzoOracle.sol";
import "../../../../interfaces/Zircuit/IZircuitZtaking.sol";

contract PendleZtakeEzETHSY is SYBaseUpg {
    address public immutable zircuitStaking;
    address public immutable ezETH;
    address public immutable restakeManager;
    address public immutable renzoOracle;
    uint256 public immutable referralId;
    address public immutable exchangeRateOracle;

    event SetNewExchangeRateOracle(address oracle);

    constructor(
        address _zircuitStaking,
        address _ezETH,
        address _restakeManager,
        uint256 _referralId,
        address _exchangeRateOracle
    ) SYBaseUpg(_ezETH) {
        _disableInitializers();
        zircuitStaking = _zircuitStaking;
        ezETH = _ezETH;
        restakeManager = _restakeManager;
        renzoOracle = IRenzoRestakeManager(restakeManager).renzoOracle();
        referralId = _referralId;
        exchangeRateOracle = _exchangeRateOracle;
    }

    function initialize() external initializer {
        __SYBaseUpg_init("SY Zircuit Staking ezETH", "SY-zs-ezETH");
        _safeApproveInf(ezETH, zircuitStaking);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            IRenzoRestakeManager(restakeManager).depositETH{value: amountDeposited}(referralId);
            amountSharesOut = _selfBalance(ezETH);
        } else {
            amountSharesOut = amountDeposited;
        }
        IZircuitZtaking(zircuitStaking).depositFor(ezETH, address(this), amountSharesOut);
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256 /*amountTokenOut*/) {
        IZircuitZtaking(zircuitStaking).withdraw(ezETH, amountSharesToRedeem);
        _transferOut(ezETH, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return IPExchangeRateOracle(exchangeRateOracle).getExchangeRate();
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == ezETH) {
            return amountTokenToDeposit;
        }

        uint256 supply = IERC20(ezETH).totalSupply();
        (, , uint256 tvl) = IRenzoRestakeManager(restakeManager).calculateTVLs();

        uint256 value;
        if (tokenIn == NATIVE) {
            value = amountTokenToDeposit;
        } else {
            value = IRenzoOracle(renzoOracle).lookupTokenValue(tokenIn, amountTokenToDeposit);
        }

        return IRenzoOracle(renzoOracle).calculateMintAmount(tvl, value, supply);
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, yieldToken);
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(yieldToken);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == yieldToken;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == yieldToken;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        assetType = AssetType.TOKEN;
        assetAddress = NATIVE;
        assetDecimals = 18;
    }
}
