// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

import {Operation, Request} from "./Common.sol";

contract FeeModel is Ownable {
    uint32 public constant FEE_RATE_BASE = 1_000_000;

    struct FeeConfig {
        bool active; // To distinguish between **Free** and **Unset**
        uint32 feeRate;
        uint256 minFee;
    }

    mapping(Operation op => FeeConfig cfg) public defaultFeeConfig;
    mapping(Operation op => mapping(bytes32 dstChain => FeeConfig cfg))
        public chainFeeConfig;

    event DefaultFeeConfigSet(Operation indexed _op, FeeConfig _config);
    event ChainFeeConfigSet(
        Operation indexed _op,
        bytes32 indexed _chain,
        FeeConfig _config
    );

    constructor(address _owner) Ownable(_owner) {}

    function _validateOp(Operation op) internal pure {
        require(
            op == Operation.Mint ||
                op == Operation.Burn ||
                op == Operation.CrosschainRequest,
            "Invalid op"
        );
    }

    function _getFee(
        uint256 _amount,
        FeeConfig memory _config
    ) internal pure returns (uint256 _fee) {
        _fee = ((uint256(_config.feeRate) * _amount) / FEE_RATE_BASE);

        if (_fee < _config.minFee) {
            // Minimal fee
            _fee = _config.minFee;
        }

        require(_fee < _amount, "amount lower than minimal fee");
    }

    function _validateConfig(FeeConfig calldata _config) internal pure {
        require(
            _config.feeRate <= FEE_RATE_BASE / 100,
            "Fee rate too high, > 1%"
        );
    }

    function setDefaultFeeConfig(
        Operation _op,
        FeeConfig calldata _config
    ) external onlyOwner {
        _validateOp(_op);
        _validateConfig(_config);
        defaultFeeConfig[_op] = _config;
        emit DefaultFeeConfigSet(_op, _config);
    }

    function setChainFeeConfig(
        Operation _op,
        bytes32 _dstChain,
        FeeConfig calldata _config
    ) external onlyOwner {
        _validateOp(_op);
        _validateConfig(_config);
        chainFeeConfig[_op][_dstChain] = _config;
        emit ChainFeeConfigSet(_op, _dstChain, _config);
    }

    function getFee(Request calldata r) external view returns (uint256 _fee) {
        _validateOp(r.op);
        FeeConfig memory _config = chainFeeConfig[r.op][r.dstChain];
        if (_config.active) return _getFee(r.amount, _config);
        _config = defaultFeeConfig[r.op];
        if (_config.active) return _getFee(r.amount, _config);
        return 0;
    }
}
