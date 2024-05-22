// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "evc/interfaces/IVault.sol";

contract MockController {
    IEVC public immutable evc;

    constructor(IEVC _evc) {
        evc = _evc;
    }

    function checkAccountStatus(address, address[] calldata) external pure returns (bytes4) {
        return IVault.checkAccountStatus.selector;
    }

    function liquidateCollateralShares(
        address vault,
        address liquidated,
        address liquidator,
        uint256 shares
    ) external {
        // Control the collateral in order to transfer shares from the violator's vault to the liquidator.
        bytes memory result =
            evc.controlCollateral(vault, liquidated, 0, abi.encodeCall(ERC20.transfer, (liquidator, shares)));

        require(result.length == 0 || abi.decode(result, (bool)), "MockController: liquidateCollateralShares failed");
    }
}
