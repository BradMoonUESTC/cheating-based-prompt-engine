// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {BaseAdapter, Errors, IPriceOracle} from "src/adapter/BaseAdapter.sol";
import {IStEth} from "src/adapter/lido/IStEth.sol";

/// @title LidoOracle
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Adapter for pricing Lido stEth <-> wstEth via the stEth contract.
contract LidoOracle is BaseAdapter {
    /// @inheritdoc IPriceOracle
    string public constant name = "LidoOracle";
    /// @notice The address of Lido staked Ether.
    /// @dev This address will not change.
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    /// @notice The address of Lido wrapped staked Ether
    /// @dev This address will not change.
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @notice Get a quote by querying the exchange rate from the stEth contract.
    /// @dev Calls `getSharesByPooledEth` for stEth/wstEth and `getPooledEthByShares` for wstEth/stEth.
    /// @param inAmount The amount of `base` to convert.
    /// @param base The token that is being priced. Either `stEth` or `wstEth`.
    /// @param quote The token that is the unit of account. Either `wstEth` or `stEth`.
    /// @return The converted amount.
    function _getQuote(uint256 inAmount, address base, address quote) internal view override returns (uint256) {
        if (base == STETH && quote == WSTETH) {
            return IStEth(STETH).getSharesByPooledEth(inAmount);
        } else if (base == WSTETH && quote == STETH) {
            return IStEth(STETH).getPooledEthByShares(inAmount);
        }
        revert Errors.PriceOracle_NotSupported(base, quote);
    }
}
