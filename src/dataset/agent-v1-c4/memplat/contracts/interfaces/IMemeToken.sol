// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMemeToken is IERC20 {

    function initialize(address pool) external;

    function transferByPool(
        address user,
        uint256 amount
    ) external;

}
