// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {RedstoneCoreOracle} from "src/adapter/redstone/RedstoneCoreOracle.sol";

contract RedstoneCoreOracleHarness is RedstoneCoreOracle {
    uint256 price;
    uint256 timestampMillis;

    constructor(address _base, address _quote, bytes32 _feedId, uint8 _feedDecimals, uint32 _maxStaleness)
        RedstoneCoreOracle(_base, _quote, _feedId, _feedDecimals, _maxStaleness)
    {}

    function setPrice(uint256 _price, uint256 _timestampMillis) external {
        price = _price;
        timestampMillis = _timestampMillis;
    }

    function getOracleNumericValueFromTxMsg(bytes32) internal view override returns (uint256) {
        validateTimestamp(timestampMillis);
        return price;
    }
}
