// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.17;

import "../../../../interfaces/IPPreviewHelper.sol";
import "../../../../interfaces/Connext/IConnext.sol";
import "../../../../interfaces/Renzo/IRenzoDepositL2.sol";

import "../../../libraries/math/PMath.sol";
import "../../../libraries/BoringOwnableUpgradeable.sol";

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract PendleRenzoPreviewHelper is IPPreviewHelper, UUPSUpgradeable, BoringOwnableUpgradeable {
    using PMath for uint256;

    address public immutable renzoDeposit;
    address public immutable wETH;

    address public immutable connext;
    bytes32 public immutable swapKey;
    uint8 public immutable depositTokenId;
    uint8 public immutable collateralTokenId;

    constructor(address _renzoDeposit, address _wETH, uint8 _depositTokenId, uint8 _collateralTokenId) {
        renzoDeposit = _renzoDeposit;
        wETH = _wETH;

        depositTokenId = _depositTokenId;
        collateralTokenId = _collateralTokenId;
        connext = IRenzoDepositL2(renzoDeposit).connext();
        swapKey = IRenzoDepositL2(renzoDeposit).swapKey();
    }

    function initialize() external initializer {
        __BoringOwnable_init();
    }

    function previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) external view returns (uint256 amountSharesOut) {
        if (tokenIn == wETH) {
            uint256 amountWETHBridged = IConnext(connext).calculateSwap(
                swapKey,
                depositTokenId,
                collateralTokenId,
                amountTokenToDeposit
            );

            uint256 feeBps = IRenzoDepositL2(renzoDeposit).bridgeRouterFeeBps();
            amountWETHBridged -= (amountWETHBridged * feeBps) / 10_000;

            uint256 lastPrice = IRenzoDepositL2(renzoDeposit).lastPrice();
            return amountWETHBridged.divDown(lastPrice);
        }
        return amountTokenToDeposit;
    }

    function previewRedeem(
        address /*tokenOut*/,
        uint256 /*amountSharesToBurn*/
    ) external pure returns (uint256 /*amountTokenOut*/) {
        revert("not implemented");
    }

    // solhint-disable-next-line
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
