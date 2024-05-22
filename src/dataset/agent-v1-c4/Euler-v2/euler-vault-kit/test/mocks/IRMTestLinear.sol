// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../src/InterestRateModels/IIRM.sol";
import "../../src/EVault/shared/Constants.sol";

contract IRMTestLinear is IIRM {
    uint256 internal constant MAX_IR = uint256(1e27 * 0.1) / SECONDS_PER_YEAR;

    function computeInterestRate(address vault, uint256 cash, uint256 borrows) public view returns (uint256) {
        if (msg.sender != vault) revert E_IRMUpdateUnauthorized();
        uint256 totalAssets = cash + borrows;

        uint32 utilisation = totalAssets == 0
            ? 0 // empty pool arbitrarily given utilisation of 0
            : uint32(borrows * type(uint32).max / totalAssets);

        return MAX_IR * utilisation / type(uint32).max;
    }

    function computeInterestRateView(address vault, uint256 cash, uint256 borrows) external view returns (uint256) {
        return computeInterestRate(vault, cash, borrows);
    }
}
