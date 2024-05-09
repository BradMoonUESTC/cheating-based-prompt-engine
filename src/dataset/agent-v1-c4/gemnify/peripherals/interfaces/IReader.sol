// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IVault} from "../../core/interfaces/IVault.sol";

interface IReader {
    function vault() external view returns (IVault);

    function setVault(address _vault) external;

    function getDepositOrWithdrawFeeBasisPoints(
        address _token,
        uint256 _amountIn,
        bool _isDeposit
    ) external view returns (uint256);

    function getSwapFeeBasisPoints(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view returns (uint256);
}
