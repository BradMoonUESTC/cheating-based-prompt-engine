// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../SYBase.sol";
import "../../../interfaces/Frax/IFrxEthMinter.sol";
import "../../../interfaces/IERC4626.sol";

/// @dev deposit through weth is not neccessary to be done on this contract's level
/// as we already supported this with our router
contract PendleSfrxEthSY is SYBase {
    address public immutable minter;
    address public immutable frxETH;
    address public immutable sfrxETH;

    constructor(
        string memory _name,
        string memory _symbol,
        address _minter
    ) SYBase(_name, _symbol, IFrxEthMinter(_minter).sfrxETHToken()) {
        minter = _minter;
        sfrxETH = IFrxEthMinter(minter).sfrxETHToken();
        frxETH = IFrxEthMinter(minter).frxETHToken();

        _safeApproveInf(frxETH, sfrxETH);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    /**
     * The underlying yield token is frxETH. If the base token deposited is ETH, the function
     * deposits through fraxMinterContract - the most efficient way to get frxETH and deposit
     * directly to sfrxETH.
     */
    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == NATIVE) {
            return IFrxEthMinter(minter).submitAndDeposit{value: amountDeposited}(address(this));
        } else if (tokenIn == frxETH) {
            return IERC4626(sfrxETH).deposit(amountDeposited, address(this));
        } else {
            return amountDeposited;
        }
    }

    /**
     * Withdrawal to sfrxETH and frxETH is done normally as other ERC4626.
     * Withdrawal to ETH is on the other hand not possible
     */
    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 /*amountTokenOut*/) {
        if (tokenOut == sfrxETH) {
            _transferOut(sfrxETH, receiver, amountSharesToRedeem);
            return amountSharesToRedeem;
        } else {
            return IERC4626(sfrxETH).redeem(amountSharesToRedeem, receiver, address(this));
        }
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates and updates the exchange rate of shares to underlying asset token
     * @dev It is the exchange rate of sfrxETH to frxETH
     */
    function exchangeRate() public view virtual override returns (uint256) {
        return IERC4626(sfrxETH).convertToAssets(1 ether);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == sfrxETH) {
            return amountTokenToDeposit;
        } else {
            return IERC4626(sfrxETH).previewDeposit(amountTokenToDeposit);
        }
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 /*amountTokenOut*/) {
        if (tokenOut == sfrxETH) {
            return amountSharesToRedeem;
        } else {
            return IERC4626(sfrxETH).convertToAssets(amountSharesToRedeem);
        }
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](3);
        res[0] = frxETH;
        res[1] = sfrxETH;
        res[2] = NATIVE;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = frxETH;
        res[1] = sfrxETH;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == frxETH || token == sfrxETH || token == NATIVE;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == frxETH || token == sfrxETH;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, frxETH, 18);
    }
}
