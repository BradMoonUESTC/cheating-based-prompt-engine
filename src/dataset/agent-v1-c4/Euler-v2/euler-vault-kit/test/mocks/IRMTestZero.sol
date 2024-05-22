// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../src/InterestRateModels/IIRM.sol";

contract IRMTestZero is IIRM {
    constructor() {}

    function computeInterestRate(address vault, uint256, uint256) public view returns (uint256) {
        if (msg.sender != vault) revert E_IRMUpdateUnauthorized();
        return 0;
    }

    function computeInterestRateView(address vault, uint256 cash, uint256 borrows) external view returns (uint256) {
        return computeInterestRate(vault, cash, borrows);
    }
}
