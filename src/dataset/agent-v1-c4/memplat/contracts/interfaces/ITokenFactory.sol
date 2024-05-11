// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ITokenFactory {

    function deploy(
        string calldata symbol
    ) external returns (address tokenAddress);

}
