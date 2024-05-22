// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

/// @title IStEth
/// @author Lido (https://github.com/lidofinance/lido-dao/blob/5fcedc6e9a9f3ec154e69cff47c2b9e25503a78a/contracts/0.6.12/interfaces/IStETH.sol)
/// @notice Partial interface for Lido Staked Ether.
interface IStEth {
    /// @notice Get the amount of stEth equivalent to `sharesAmount` of wstEth.
    /// @param sharesAmount The amount of wstEth to convert.
    /// @return The amount of stEth equivalent to `sharesAmount` of wstEth.
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
    /// @notice Get the amount of wstEth equivalent to `ethAmount` of stEth.
    /// @param ethAmount The amount of stEth to convert.
    /// @return The amount of wstEth equivalent to `ethAmount` of stEth.
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256);
}
