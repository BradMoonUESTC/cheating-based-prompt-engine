// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./Stake.sol";

contract OPAIStake is Stake {
	constructor(IERC20 token) Stake(token) {}
}