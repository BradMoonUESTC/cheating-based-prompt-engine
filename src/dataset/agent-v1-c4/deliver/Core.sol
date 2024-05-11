// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

contract Core {

	address public owner;
	address public pendingOwner;

	address public guardian;

	bool public paused;

	event NewOwnerCommitted(address owner, address pendingOwner);

	event NewOwnerAccepted(address oldOwner, address owner);

	event NewOwnerRevoked(address owner, address revokedOwner);

	event GuardianSet(address guardian);

	event Paused();

	event Unpaused();

	constructor(address _owner, address _guardian) {
		owner = _owner;
		guardian = _guardian;
		emit GuardianSet(_guardian);
	}

	modifier onlyOwner() {
		require(msg.sender == owner, "Only owner");
		_;
	}

	function setGuardian(address _guardian) external onlyOwner {
		guardian = _guardian;
		emit GuardianSet(_guardian);
	}

	function setPaused(bool _paused) external {
		require((_paused && msg.sender == guardian) || msg.sender == owner, "Unauthorized");
		paused = _paused;
		if (_paused) {
			emit Paused();
		} else {
			emit Unpaused();
		}
	}

	function commitTransferOwnership(address newOwner) external onlyOwner {
		pendingOwner = newOwner;
		emit NewOwnerCommitted(msg.sender, newOwner);
	}

	function acceptTransferOwnership() external {
		require(msg.sender == pendingOwner, "Only new owner");

		emit NewOwnerAccepted(owner, msg.sender);

		owner = pendingOwner;
		pendingOwner = address(0);
	}

	function revokeTransferOwnership() external onlyOwner {
		emit NewOwnerRevoked(msg.sender, pendingOwner);

		pendingOwner = address(0);
	}
}
