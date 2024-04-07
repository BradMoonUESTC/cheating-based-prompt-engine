// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../SYBase.sol";
import "../../../../interfaces/IPExchangeRateOracle.sol";
import "../../../../interfaces/KelpDAO/IKelpDepositPool.sol";
import "../../../../interfaces/KelpDAO/IKelpLRTConfig.sol";
import "../../../../interfaces/Stader/IStaderStakeManager.sol";

contract PendleRsETHSY is SYBase {
    using ArrayLib for address[];

    address public immutable rsETH;
    address public immutable depositPool;
    address public immutable staderStakeManager;
    address public lrtConfig;

    address public exchangeRateOracle;

    address public immutable ETHx; // gas saving purpose only
    address public immutable stETH; // gas saving purpose only

    event SetNewExchangeRateOracle(address oracle);

    constructor(
        address _rsETH,
        address _depositPool,
        address _staderStakeManager,
        address _exchangeRateOracle,
        address _ETHx,
        address _stETH
    ) SYBase("SY Kelp rsETH", "SY-rsETH", _rsETH) {
        rsETH = _rsETH;
        depositPool = _depositPool;
        staderStakeManager = _staderStakeManager;
        exchangeRateOracle = _exchangeRateOracle;
        ETHx = _ETHx;
        stETH = _stETH;

        updateLrtConfigAddress();
        safeApproveSupportedTokens();
    }

    function updateLrtConfigAddress() public {
        lrtConfig = IKelpDepositPool(depositPool).lrtConfig();
    }

    function safeApproveSupportedTokens() public {
        address[] memory assets = IKelpLRTConfig(lrtConfig).getSupportedAssetList();
        for (uint256 i = 0; i < assets.length; ) {
            _safeApproveInf(assets[i], depositPool);
            unchecked {
                i++;
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == rsETH) {
            amountSharesOut = amountDeposited;
        } else {
            if (tokenIn == NATIVE) {
                (tokenIn, amountDeposited) = (
                    ETHx,
                    IStaderStakeManager(staderStakeManager).deposit{value: amountDeposited}(address(this))
                );
            }
            uint256 preBalance = _selfBalance(rsETH);
            IKelpDepositPool(depositPool).depositAsset(
                tokenIn,
                amountDeposited,
                0,
                "c05f6902ec7c7434ceb666010c16a63a2e3995aad11f1280855b26402194346b"
            );
            amountSharesOut = _selfBalance(rsETH) - preBalance;
        }
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256) {
        _transferOut(rsETH, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return IPExchangeRateOracle(exchangeRateOracle).getExchangeRate();
    }

    function setExchangeRateOracle(address newOracle) external onlyOwner {
        exchangeRateOracle = newOracle;
        emit SetNewExchangeRateOracle(newOracle);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 amountSharesOut) {
        if (tokenIn == rsETH) {
            return amountTokenToDeposit;
        }
        if (tokenIn == NATIVE) {
            (tokenIn, amountTokenToDeposit) = (
                ETHx,
                IStaderStakeManager(staderStakeManager).previewDeposit(amountTokenToDeposit)
            );
        }
        return IKelpDepositPool(depositPool).getRsETHAmountToMint(tokenIn, amountTokenToDeposit);
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 amountTokenOut) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view virtual override returns (address[] memory) {
        return ArrayLib.create(rsETH, NATIVE).merge(IKelpLRTConfig(lrtConfig).getSupportedAssetList());
    }

    function getTokensOut() public view virtual override returns (address[] memory) {
        return ArrayLib.create(rsETH);
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == rsETH || token == NATIVE || token == ETHx || token == stETH || _isSupportedToken(token);
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == rsETH;
    }

    function _isSupportedToken(address token) internal view returns (bool) {
        return IKelpLRTConfig(lrtConfig).isSupportedAsset(token);
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
