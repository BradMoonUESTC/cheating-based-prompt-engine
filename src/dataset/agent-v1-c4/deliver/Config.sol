// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

contract Config {

	struct Config_ {
		uint128 depositBaseFee;
		uint32 depositFeeRate;
		uint32 finalizeTxGas;
	}

	Config_ public config;

	uint32 public constant MAXPCT = 1000000;

	event UpdateConfig(Config_ config);

	function _updateConfig(Config_ memory _config) internal {
		config = _config;
		emit UpdateConfig(config);
	}

	function _updateDepositBaseFee(uint128 _depositBaseFee) internal {
		config.depositBaseFee = _depositBaseFee;
 		emit UpdateConfig(config);
	}

	function _updateDepositFeeRate(uint32 _depositFeeRate) internal {
		require(_depositFeeRate <= MAXPCT / 20, "fee rate must be less or equal than 5%");
		config.depositFeeRate = _depositFeeRate;
 		emit UpdateConfig(config);
	}

	function _updateFinalizeTxGas(uint32 _finalizeTxGas) internal {
		config.finalizeTxGas = _finalizeTxGas;
 		emit UpdateConfig(config);
	}

}
