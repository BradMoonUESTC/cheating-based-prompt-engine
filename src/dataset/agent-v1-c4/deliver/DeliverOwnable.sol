// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./ICore.sol";

contract DeliverOwnable {
	ICore public immutable core;

	constructor(ICore _core) {
		core = _core;
	}

	modifier wherNotPaused() {
		require(!paused(), "paused!");
		_;
	}

	modifier onlyOwner() {
		require(msg.sender == core.owner(), "Only owner");
		_;
	}

	modifier onlyGuardian() {
		require(msg.sender == core.guardian(), "Only guardian");
		_;
	}

	function paused() public view returns (bool) {
		return core.paused();
	}

	function owner() public view returns (address) {
		return core.owner();
	}

	function guardian() public view returns (address) {
		return core.guardian();
	}
}
