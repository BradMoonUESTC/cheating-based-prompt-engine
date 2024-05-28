// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/StorageSlot.sol";

contract AdminWrapper {
	/// @dev return admin address from storage slot
	/// @return admin admin contract address
	function _getAdmin() internal view returns (address) {
		// bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1))
		bytes32 _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
		return StorageSlot.getAddressSlot(_ADMIN_SLOT).value;
	}

	modifier onlyAdmin() {
		require(msg.sender == _getAdmin(), "AdminWrapper: caller is not the admin");
		_;
	}
}
