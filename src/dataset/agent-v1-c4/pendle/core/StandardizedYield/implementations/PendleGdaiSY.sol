// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../SYBase.sol";
import "../../../interfaces/IERC4626.sol";

contract PendleGDaiSY is SYBase {
    address public immutable DAI;
    address public immutable gDAI;

    constructor(string memory _name, string memory _symbol, address _gDAI) SYBase(_name, _symbol, _gDAI) {
        gDAI = _gDAI;
        DAI = IERC4626(gDAI).asset();
        _safeApproveInf(DAI, gDAI);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    /**
     * The underlying yield token is gDAI. If the base token deposited is DAI, the function
     * deposits received DAI into the gDAI contract.
     */
    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == gDAI) {
            return amountDeposited;
        } else {
            return IERC4626(gDAI).deposit(amountDeposited, address(this));
        }
    }

    /**
     * Only withdrawal to gDAI is supported.
     */
    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 /*amountTokenOut*/) {
        _transferOut(tokenOut, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates and updates the exchange rate of shares to underlying asset token
     * @dev It is the exchange rate of gDAI to DAI
     */
    function exchangeRate() public view virtual override returns (uint256) {
        return IERC4626(gDAI).convertToAssets(1e18);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == gDAI) {
            return amountTokenToDeposit;
        } else {
            return IERC4626(gDAI).previewDeposit(amountTokenToDeposit);
        }
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = DAI;
        res[1] = gDAI;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](1);
        res[0] = gDAI;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == DAI || token == gDAI;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == gDAI;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, DAI, 18);
    }
}
