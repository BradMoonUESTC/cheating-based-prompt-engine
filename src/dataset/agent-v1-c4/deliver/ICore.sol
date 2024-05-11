// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./ICore.sol";

interface ICore {

	function acceptTransferOwnership() external;

	function commitTransferOwnership(address newOwner) external;

	function revokeTransferOwnership() external;

	function setFeeReceiver(address _feeReceiver) external;

	function setGuardian(address _guardian) external;

	function setPaused(bool _paused) external;

	function guardian() external view returns (address);

	function owner() external view returns (address);

	function paused() external view returns (bool);

	function pendingOwner() external view returns (address);

}
