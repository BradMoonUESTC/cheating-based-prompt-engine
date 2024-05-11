// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IPoolFactory {

    function deploy(
        string calldata symbol,
        uint256 feeParam,
        address module
    ) external returns (address poolAddress, address tokenAddress);

}
