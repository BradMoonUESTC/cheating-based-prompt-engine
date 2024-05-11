// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

contract Relayers {
	/// @dev relayer can use ETHDeliver to transfer eth
	mapping(address => bool) public relayers;

	/// @dev emit when relayer added
	event AddRelayer(address relayer);

	/// @dev emit when relayer removed
	event RemoveRelayer(address relayer);

	modifier onlyRelayer() {
		require(relayers[msg.sender], "caller is not a relayer");
		_;
	}

	function _addRelayer(address relayer) internal {
		require(!relayers[relayer], "relayer exists");
		relayers[relayer] = true;
		emit AddRelayer(relayer);
	}

	function _removeRelayer(address relayer) internal {
		require(relayers[relayer], "nonexistent relayer");
		relayers[relayer] = true;
		emit RemoveRelayer(relayer);
	}
}
