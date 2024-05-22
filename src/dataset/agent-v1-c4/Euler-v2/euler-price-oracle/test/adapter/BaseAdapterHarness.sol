// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {BaseAdapter} from "src/adapter/BaseAdapter.sol";

contract BaseAdapterHarness is BaseAdapter {
    string public constant name = "BaseAdapterHarness";

    function _getQuote(uint256, address, address) internal pure override returns (uint256) {
        return 0;
    }

    function getDecimals(address token) external view returns (uint8) {
        return _getDecimals(token);
    }
}
