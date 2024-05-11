// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract BaseModule {

    bool immutable internal INIT_FLAG;
    bool immutable internal AFTER_ADD_FLAG;
    bool immutable internal AFTER_REMOVE_FLAG;
    bool immutable internal BEFORE_BUY_FLAG;
    bool immutable internal AFTER_BUY_FLAG;
    bool immutable internal BEFORE_SELL_FLAG;
    bool immutable internal AFTER_SELL_FLAG;

    /// @dev 00 00 00 00 00 00 00
    constructor(
        bytes32 flag_data
    ) {
        INIT_FLAG = uint8(uint256(flag_data >> 0)) > 0;
        AFTER_ADD_FLAG = uint8(uint256(flag_data >> 8)) > 0;
        AFTER_REMOVE_FLAG = uint8(uint256(flag_data >> 16)) > 0;
        BEFORE_BUY_FLAG = uint8(uint256(flag_data >> 24)) > 0;
        AFTER_BUY_FLAG = uint8(uint256(flag_data >> 32)) > 0;
        BEFORE_SELL_FLAG = uint8(uint256(flag_data >> 40)) > 0;
        AFTER_SELL_FLAG = uint8(uint256(flag_data >> 48)) > 0;
    }

    function getFlag() external view returns (bool, bool, bool, bool, bool, bool, bool) {
        return (INIT_FLAG, AFTER_ADD_FLAG, AFTER_REMOVE_FLAG, BEFORE_BUY_FLAG, AFTER_BUY_FLAG, BEFORE_SELL_FLAG, AFTER_SELL_FLAG);
    }

}
