// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../SYBase.sol";
import "../../../../interfaces/IPExchangeRateOracle.sol";
import "../../../../interfaces/Renzo/IRenzoRestakeManager.sol";
import "../../../../interfaces/Renzo/IRenzoOracle.sol";

contract PendleEzETHSY is SYBase {
    using ArrayLib for address[];

    address public immutable ezETH;
    address public immutable restakeManager;
    address public immutable renzoOracle;
    uint256 public immutable referralId;

    address public exchangeRateOracle;
    address[] public supportedCollateralTokens;

    event SetNewExchangeRateOracle(address oracle);

    constructor(
        address _ezETH,
        address _stakeManager,
        address _exchangeRateOracle,
        uint256 _referralId
    ) SYBase("SY Renzo ezETH", "SY-ezETH", _ezETH) {
        ezETH = _ezETH;
        restakeManager = _stakeManager;
        exchangeRateOracle = _exchangeRateOracle;
        renzoOracle = IRenzoRestakeManager(restakeManager).renzoOracle();
        referralId = _referralId;
    }

    // this way we dont have to check if length is accurate
    function refetchCollateralTokens(uint256 length) external onlyOwner {
        address[] memory newCollateralTokens = new address[](length);
        for (uint256 i = 0; i < length; ++i) {
            newCollateralTokens[i] = IRenzoRestakeManager(restakeManager).collateralTokens(i);

            // just a safety check, preventing human mistake from underlying protocol
            require(newCollateralTokens[i] != ezETH, "refetchCollateralTokens: should not approve ezETH");
            _safeApproveInf(newCollateralTokens[i], restakeManager);
        }
        supportedCollateralTokens = newCollateralTokens;
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address tokenIn, uint256 amountDeposited) internal virtual override returns (uint256) {
        if (tokenIn == ezETH) {
            return amountDeposited;
        }

        uint256 preBalance = _selfBalance(ezETH);
        if (tokenIn == NATIVE) {
            IRenzoRestakeManager(restakeManager).depositETH{value: amountDeposited}(referralId);
        } else {
            IRenzoRestakeManager(restakeManager).deposit(tokenIn, amountDeposited, referralId);
        }
        return _selfBalance(ezETH) - preBalance;
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256) {
        _transferOut(ezETH, receiver, amountSharesToRedeem);
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
    ) internal pure override returns (uint256 amountTokenOut) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view virtual override returns (address[] memory) {
        return ArrayLib.create(ezETH, NATIVE).merge(supportedCollateralTokens);
    }

    function getTokensOut() public view virtual override returns (address[] memory) {
        return ArrayLib.create(ezETH);
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == NATIVE || token == ezETH || supportedCollateralTokens.contains(token);
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == ezETH;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
