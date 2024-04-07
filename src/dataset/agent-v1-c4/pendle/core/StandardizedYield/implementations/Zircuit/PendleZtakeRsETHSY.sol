// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseUpg.sol";
import "../../../../interfaces/Zircuit/IZircuitZtaking.sol";
import "../../../../interfaces/IPExchangeRateOracle.sol";
import "../../../../interfaces/KelpDAO/IKelpDepositPool.sol";
import "../../../../interfaces/KelpDAO/IKelpLRTConfig.sol";

contract PendleZtakeRsETHSY is SYBaseUpg {
    address public constant ETH_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // solhint-disable immutable-vars-naming
    address public immutable zircuitStaking;
    address public immutable rsETH;
    address public immutable depositPool;
    address public immutable exchangeRateOracle;

    constructor(
        address _zircuitStaking,
        address _rsETH,
        address _depositPool,
        address _exchangeRateOracle
    ) SYBaseUpg(_rsETH) {
        _disableInitializers();
        zircuitStaking = _zircuitStaking;
        rsETH = _rsETH;
        depositPool = _depositPool;
        exchangeRateOracle = _exchangeRateOracle;
    }

    function initialize() external initializer {
        __SYBaseUpg_init("SY Zircuit Staking rsETH", "SY-zs-rsETH");
        _safeApproveInf(rsETH, zircuitStaking);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            IKelpDepositPool(depositPool).depositETH{value: amountDeposited}(
                0,
                "c05f6902ec7c7434ceb666010c16a63a2e3995aad11f1280855b26402194346b"
            );
            amountSharesOut = _selfBalance(rsETH);
        } else {
            amountSharesOut = amountDeposited;
        }
        IZircuitZtaking(zircuitStaking).depositFor(rsETH, address(this), amountSharesOut);
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal override returns (uint256 /*amountTokenOut*/) {
        IZircuitZtaking(zircuitStaking).withdraw(rsETH, amountSharesToRedeem);
        _transferOut(rsETH, receiver, amountSharesToRedeem);
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
        if (tokenIn == rsETH) {
            return amountTokenToDeposit;
        }
        return IKelpDepositPool(depositPool).getRsETHAmountToMint(ETH_TOKEN, amountTokenToDeposit);
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, rsETH);
    }

    function getTokensOut() public view override returns (address[] memory res) {
        return ArrayLib.create(rsETH);
    }

    function isValidTokenIn(address token) public view override returns (bool) {
        return token == NATIVE || token == rsETH;
    }

    function isValidTokenOut(address token) public view override returns (bool) {
        return token == rsETH;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        assetType = AssetType.TOKEN;
        assetAddress = NATIVE;
        assetDecimals = 18;
    }
}
