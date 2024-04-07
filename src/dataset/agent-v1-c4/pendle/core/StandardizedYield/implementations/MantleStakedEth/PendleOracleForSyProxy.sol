// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBase.sol";
import "../../../../interfaces/IPOracleForSy.sol";

// the Owner of this will be a timelock
contract PendleOracleForSyProxy is BoringOwnableUpgradeable, IPOracleForSy {
    address public oracleAddress;

    constructor(address _oracleAddress) initializer {
        __BoringOwnable_init();
        oracleAddress = _oracleAddress;
    }

    function latestAnswer() external view override returns (int256) {
        return IPOracleForSy(oracleAddress).latestAnswer();
    }

    function setOracleAddress(address _oracleAddress) external onlyOwner {
        oracleAddress = _oracleAddress;
    }
}
