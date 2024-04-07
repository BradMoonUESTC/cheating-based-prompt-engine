// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBase.sol";
import "../../../../interfaces/Ankr/IAnkrLiquidStaking.sol";
import "../../../../interfaces/Ankr/IAnkrBNB.sol";

contract PendleAnkrBNBSY is SYBase {
    error MinimumStakeAmountNotReached(uint256 amountToStake, uint256 minimumStakeAmount);

    error MinimumRedeemAmountNotReached(uint256 amountToRedeem, uint256 minimumRedeemAmount);

    error UnstakeCapacityTooLow(uint256 amountBondToRedeem, uint256 unstakeCapacity);

    using PMath for uint256;

    uint256 internal constant FEE_MAX = 10000;

    address public immutable ankrLiquidStaking;
    address public immutable ankrBNB; // certificate token

    constructor(
        string memory _name,
        string memory _symbol,
        address _ankrLiquidStaking,
        address _ankrBNB
    ) SYBase(_name, _symbol, _ankrBNB) {
        ankrLiquidStaking = _ankrLiquidStaking;
        ankrBNB = _ankrBNB;
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == NATIVE) {
            uint256 preBalance = _selfBalance(ankrBNB);
            IAnkrLiquidStaking(ankrLiquidStaking).stakeCerts{value: amountDeposited}();
            amountSharesOut = _selfBalance(ankrBNB) - preBalance;
        } else {
            amountSharesOut = amountDeposited;
        }
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        if (tokenOut == NATIVE) {
            // Tho we can use previewRedeem here to get the accurate result
            // There's risk that ankr upgrade their contract logic or immutable/constant variables for MATH
            // Thus, redeeming back to this contract first to account for amountTokenOut is required
            uint256 preBalance = _selfBalance(NATIVE);
            IAnkrLiquidStaking(ankrLiquidStaking).swap(amountSharesToRedeem, address(this));
            amountTokenOut = _selfBalance(NATIVE) - preBalance;
        } else {
            amountTokenOut = amountSharesToRedeem;
        }
        _transferOut(tokenOut, receiver, amountTokenOut);
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        // ankr uses inversed exchangeRate
        return PMath.ONE.divDown(IAnkrBNB(ankrBNB).ratio());
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 amountSharesOut) {
        if (tokenIn == ankrBNB) {
            amountSharesOut = amountTokenToDeposit;
        } else {
            uint256 minStakeAmount = IAnkrLiquidStaking(ankrLiquidStaking).getMinStake();
            if (amountTokenToDeposit < minStakeAmount) {
                revert MinimumStakeAmountNotReached(amountTokenToDeposit, minStakeAmount);
            }
            return IAnkrBNB(ankrBNB).bondsToShares(amountTokenToDeposit);
        }
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 amountTokenOut) {
        if (tokenOut == ankrBNB) {
            amountTokenOut = amountSharesToRedeem;
        } else {
            uint256 amountBondToRedeem = IAnkrBNB(ankrBNB).sharesToBonds(amountSharesToRedeem);
            (uint256 minUnstakeAmount, uint256 unstakeCapacity, uint256 unstakeFee) = _getAnkrRedeemInfo();

            if (amountBondToRedeem < minUnstakeAmount) {
                revert MinimumRedeemAmountNotReached(amountBondToRedeem, minUnstakeAmount);
            }

            amountSharesToRedeem = IAnkrBNB(ankrBNB).bondsToShares(amountBondToRedeem);

            // Note that ankr may update their contract to change FEE_MAX?
            uint256 unstakeFeeAmount = (amountBondToRedeem * unstakeFee) / FEE_MAX;
            amountBondToRedeem -= unstakeFeeAmount;

            if (amountBondToRedeem > unstakeCapacity) {
                revert UnstakeCapacityTooLow(amountBondToRedeem, unstakeCapacity);
            }
            return amountBondToRedeem;
        }
    }

    function _getAnkrRedeemInfo()
        internal
        view
        returns (uint256 minUnstakeAmount, uint256 unstakeCapacity, uint256 unstakeFee)
    {
        minUnstakeAmount = IAnkrLiquidStaking(ankrLiquidStaking).getMinUnstake();
        unstakeCapacity = IAnkrLiquidStaking(ankrLiquidStaking).flashPoolCapacity();
        unstakeFee = IAnkrLiquidStaking(ankrLiquidStaking).getFlashUnstakeFee();
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = ankrBNB;
        res[1] = NATIVE;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = ankrBNB;
        res[1] = NATIVE;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == ankrBNB || token == NATIVE;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == ankrBNB || token == NATIVE;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
