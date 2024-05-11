// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./DeliverOwnable.sol";
import "./Relayers.sol";
import "./Config.sol";

contract Controller is Relayers, Config, DeliverOwnable {

	constructor(ICore _core, Config_ memory _config) DeliverOwnable(_core) {
		_addRelayer(owner());
		_updateConfig(_config);
	}

	function addRelayer(address relayer) external onlyOwner {
		_addRelayer(relayer);
	}

	function removeRelayer(address relayer) external onlyOwner {
		_removeRelayer(relayer);
	}

	function updateConfig(Config_ memory _config) external onlyOwner {
		_updateConfig(_config);
	}

	function updateDepositBaseFee(uint128 _depositBaseFee) external onlyOwner {
		_updateDepositBaseFee(_depositBaseFee);
	}

	function updateDepositFeeRate(uint32 _depositFeeRate) external onlyOwner {
		_updateDepositFeeRate(_depositFeeRate);
	}

	function updateFinalizeTxGas(uint32 _finalizeTxGas) external onlyOwner {
		_updateFinalizeTxGas(_finalizeTxGas);
	}

}
