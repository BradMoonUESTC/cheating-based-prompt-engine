// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../SYBase.sol";
import "../../../interfaces/IWstETH.sol";
import "../../../interfaces/IWETH.sol";
import "../../../interfaces/IStETH.sol";

contract PendleWstEthSY is SYBase {
    address public immutable wETH;
    address public immutable stETH;
    address public immutable wstETH;

    constructor(
        string memory _name,
        string memory _symbol,
        address _wETH,
        address _wstETH
    ) SYBase(_name, _symbol, _wstETH) {
        wETH = _wETH;
        wstETH = _wstETH;
        stETH = IWstETH(wstETH).stETH();
        _safeApproveInf(stETH, wstETH);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {SYBase-_deposit}
     *
     * The underlying yield token is wstETH. If the base token deposited is stETH, the function wraps
     * it into wstETH first. Then the corresponding amount of shares is returned.
     *
     * The exchange rate of wstETH to shares is 1:1
     */
    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == wstETH) {
            amountSharesOut = amountDeposited;
        } else {
            uint256 amountStETH;
            if (tokenIn == stETH) {
                amountStETH = amountDeposited;
            } else {
                if (tokenIn == wETH) IWETH(wETH).withdraw(amountDeposited);

                uint256 amountStEthSharesOut = IStETH(stETH).submit{value: amountDeposited}(address(0));
                amountStETH = IStETH(stETH).getPooledEthByShares(amountStEthSharesOut);
            }
            amountSharesOut = IWstETH(wstETH).wrap(amountStETH);
        }
    }

    /**
     * @dev See {SYBase-_redeem}
     *
     * The shares are redeemed into the same amount of wstETH. If `tokenOut` is stETH, the function also
     * unwraps said amount of wstETH into stETH for redemption.
     */
    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        if (tokenOut == wstETH) {
            amountTokenOut = amountSharesToRedeem;
        } else {
            amountTokenOut = IWstETH(wstETH).unwrap(amountSharesToRedeem);
        }
        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates and updates the exchange rate of shares to underlying asset token
     * @dev It is the exchange rate of wstETH to stETH
     */
    function exchangeRate() public view virtual override returns (uint256) {
        return IStETH(stETH).getPooledEthByShares(1 ether);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 amountSharesOut) {
        if (tokenIn == wstETH) amountSharesOut = amountTokenToDeposit;
        else {
            if (tokenIn != stETH) {
                uint256 totalShares = IStETH(stETH).getTotalShares();
                uint256 totalPooledEth = IStETH(stETH).getTotalPooledEther();
                uint256 amountStEthSharesOut = IStETH(stETH).getSharesByPooledEth(amountTokenToDeposit);

                totalShares += amountStEthSharesOut;
                totalPooledEth += amountTokenToDeposit;

                uint256 stEthBalance = (amountStEthSharesOut * totalPooledEth) / totalShares;
                amountSharesOut = (stEthBalance * totalShares) / totalPooledEth;
            } else {
                amountSharesOut = IStETH(stETH).getSharesByPooledEth(amountTokenToDeposit);
            }
        }
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 amountTokenOut) {
        if (tokenOut == wstETH) amountTokenOut = amountSharesToRedeem;
        else amountTokenOut = IStETH(stETH).getPooledEthByShares(amountSharesToRedeem);
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](4);
        res[0] = NATIVE;
        res[1] = wETH;
        res[2] = stETH;
        res[3] = wstETH;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = stETH;
        res[1] = wstETH;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == stETH || token == wstETH || token == NATIVE || token == wETH;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == stETH || token == wstETH;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, stETH, IERC20Metadata(stETH).decimals());
    }
}
